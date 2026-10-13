import '../core/diagnostics.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'source_identity.dart';
import 'home_cache.dart';
import 'home_metadata.dart';
import '../core/settings.dart';
import '../core/versions.dart';
import '../core/async_tasks.dart';

import 'package:crypto/crypto.dart' as crypto;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../core/localization.dart';
import '../core/models.dart';
import '../core/storage.dart';
import '../subscriptions/models.dart';
import '../subscriptions/context_identity.dart';
import '../images/subscription_cache.dart';
import '../images/image_store.dart';
import 'cookie_store.dart';
import 'domains.dart';
import 'http_service.dart';
import 'media_transport_factory.dart';
import 'js_engine.dart';
import '../video/hls_sources.dart';

/// Installed source plugin and its runtime state.
class InstalledSource {
  InstalledSource({
    required this.key,
    required this.origin,
    required this.version,
    this.url = '',
    this.enabled = true,
    this.order = 0,
    this.sha256 = '',
  });

  final String key;
  String origin; // builtin | official | url
  String version;
  String url;
  bool enabled;
  int order;

  /// SHA-256 of the installed script (shown to the user; empty for sources installed by older versions).
  String sha256;
  SourceManifest? manifest;
  String? _loadError;
  String? get loadError => _loadError == null ? null : tr(_loadError!);
  set loadError(String? value) => _loadError = value;
  AccountStatus? account;

  Map<String, dynamic> toJson() => {
    'key': key,
    'origin': origin,
    'version': version,
    'url': url,
    'enabled': enabled,
    'order': order,
    'sha256': sha256,
  };

  factory InstalledSource.fromJson(Map<String, dynamic> j) => InstalledSource(
    key: j['key'].toString(),
    origin: (j['origin'] ?? 'builtin').toString(),
    version: (j['version'] ?? '0.0.0').toString(),
    url: (j['url'] ?? '').toString(),
    enabled: j['enabled'] != false,
    order: (j['order'] as num?)?.toInt() ?? 0,
    sha256: (j['sha256'] ?? '').toString(),
  );

  String get name => manifest?.name ?? key;
  bool get ready => manifest != null && loadError == null;
}

class RepoEntry {
  RepoEntry(this.json, this.baseUrl);
  final Map<String, dynamic> json;
  final String baseUrl;
  String get key => json['key'].toString();
  String get name => (json['name'] ?? key).toString();
  String get version => (json['version'] ?? '0.0.0').toString();
  String get description => (json['description'] ?? '').toString();

  /// Optional checksum published by the repository; when present the download must match it.
  String? get sha256 => (json['sha256'] as String?)?.toLowerCase();
  String get url {
    final u = (json['url'] ?? json['file'] ?? '').toString();
    return u.startsWith('http') ? u : Uri.parse(baseUrl).resolve(u).toString();
  }
}

String sha256Hex(String text) =>
    crypto.sha256.convert(utf8.encode(text)).toString();

/// UTF-8 decoding normally drops a BOM; scripts must round-trip to their published bytes.
String decodeSourceScript(List<int> bytes) {
  final text = utf8.decode(bytes);
  final hasBom =
      bytes.length >= 3 &&
      bytes[0] == 0xef &&
      bytes[1] == 0xbb &&
      bytes[2] == 0xbf;
  return hasBom ? '\uFEFF$text' : text;
}

/// What installing a script would do, shown to the user before anything is written.
class InstallPreview {
  InstallPreview({
    required this.code,
    required this.url,
    required this.key,
    required this.manifest,
    required this.sha256,
    required this.domains,
    required this.warnings,
    this.existing,
  });
  final String code;
  final String url;
  final String key;
  final SourceManifest manifest;
  final String sha256;
  final List<String> domains;
  final List<String> warnings;
  final InstalledSource? existing;
}

/// Installs, updates, orders and loads source plugins, and exposes a typed API over them.
typedef SourceLoader = Future<SourceManifest> Function(
  String key,
  String code,
  Map<String, dynamic> state,
);

class SourceManager extends ChangeNotifier {
  SourceManager({this.loader});
  static final SourceManager instance = SourceManager();

  final SourceLoader? loader;
  final _mutations = SerialExecutor();
  final Set<Future<void>> _activeCalls = {};
  final _activeBySource = <String, Set<Future<void>>>{};
  final _readRequests = <String, Set<CancelToken>>{};
  final _backgroundFeeds = <String, Set<CancelToken>>{};
  final _sourceMutations = <String, SerialExecutor>{};
  final _attachmentWrites = <String, SerialExecutor>{};

  final _registry = JsonStore('sources.json');
  final Map<String, InstalledSource> _sources = {};
  final Map<String, Map<String, dynamic>> _state = {}; // key → {settings, data}
  final Map<String, JsonStore> _stateStores = {};
  bool loaded = false;
  var _ready = Completer<void>();
  SourceError? initializationError;
  Future<void>? _initializing;
  Set<String>? _backgroundKeys;
  final Set<String> _builtinKeys = {};

  /// Completes once installed sources have been loaded the first time; every source call waits on it
  /// so work started at launch (resumed downloads, deep links) never races the plugin loader.
  Future<void> get ready async {
    await _ready.future;
    if (initializationError case final error?) throw error;
  }

  Directory get _dir => Directory(p.join(AppPaths.data.path, 'sources'));
  File _scriptFile(String key) => File(p.join(_dir.path, '$key.js'));

  List<InstalledSource> get all =>
      _sources.values.toList()..sort((a, b) => a.order.compareTo(b.order));
  List<InstalledSource> get enabled =>
      all.where((s) => s.enabled && s.ready).toList();
  InstalledSource? operator [](String key) => _sources[key];
  SourceManifest? manifest(String key) => _sources[key]?.manifest;
  bool isBuiltin(String key) => _builtinKeys.contains(key);

  Future<void> init({Set<String>? backgroundKeys}) {
    if (_initializing != null) return _initializing!;
    if (loaded) return Future.value();
    if (_ready.isCompleted) _ready = Completer<void>();
    initializationError = null;
    _backgroundKeys = backgroundKeys;
    final run = _initialize();
    _initializing = run.whenComplete(() {
      _initializing = null;
    });
    return _initializing!;
  }

  Future<void> _initialize() async {
    try {
      CookieStore.instance.domainsForPartition = (key) {
        final installed = manifest(key);
        return installed == null ? null : declaredDomains(installed.json);
      };
      await _dir.create(recursive: true);
      final data = await _registry.load();
      if (data is Map && data['sources'] is List) {
        for (final j in (data['sources'] as List).whereType<Map>()) {
          final s = InstalledSource.fromJson(j.cast<String, dynamic>());
          _sources[s.key] = s;
        }
      }
      await _recoverInstall();
      await _loadSavedStates();
      await _syncBuiltins();
      JsEngine.instance.onPersist = _persistData;
      JsEngine.instance.onRestarted = (key) => unawaited(
        _mutate(() async {
          final s = _sources[key];
          if (s == null) return;
          await _load(s);
          notifyListeners();
        }),
      );
      await loadAll();
    } catch (_) {
      initializationError = SourceError('CONFIG', '源初始化失败，请重试');
      rethrow;
    } finally {
      // Never leave callers waiting forever if the engine failed to start; they get the error instead.
      if (!_ready.isCompleted) _ready.complete();
      notifyListeners();
    }
  }

  /// Installs bundled sources once; existing records change only after confirmation.
  Future<void> _syncBuiltins() async {
    final index = jsonDecode(
      await rootBundle.loadString('assets/sources/index.json'),
    ) as Map;
    var order = _sources.length;
    for (final e in (index['sources'] as List).cast<Map>()) {
      final key = e['key'].toString();
      final version = e['version'].toString();
      _builtinKeys.add(key);
      // A missing installed script may require a different version from the bundle.
      // Keep its record intact until the user explicitly restores or updates it.
      if (_sources.containsKey(key)) continue;
      final file = _scriptFile(key);
      final code = await rootBundle.loadString('assets/sources/${e['file']}');
      final hash = sha256Hex(code);
      await file.writeAsString(code);
      _sources[key] = InstalledSource(
        key: key,
        origin: 'builtin',
        version: version,
        order: order++,
        sha256: hash,
      );
    }
    _saveRegistry();
  }

  Future<void> loadAll() async {
    await forEachConcurrent(
      all
          .where(
            (s) =>
                _backgroundKeys == null ||
                (_backgroundKeys!.contains(s.key) && s.enabled),
          )
          .toList(),
      3,
      (s) => _load(s),
    );
    loaded = true;
    if (!_ready.isCompleted) _ready.complete();
    notifyListeners();
    if (_backgroundKeys == null) {
      for (final s in enabled) {
        refreshAccount(s.key);
      }
    }
  }

  /// Loads a source into a fresh runtime of its own (any previous runtime for the key is discarded).
  Future<void> _load(InstalledSource s, {bool waitForInit = false}) async {
    try {
      final state = await _loadState(s.key);
      final code = decodeSourceScript(await _scriptFile(s.key).readAsBytes());
      if (loader != null) {
        s.manifest = await loader!(s.key, code, state);
      } else {
        await JsEngine.instance.disposeRuntime(s.key);
        if (!s.enabled) {
          final info = await JsEngine.instance.probe(code);
          s.manifest = SourceManifest(info.manifest);
          s.version = s.manifest!.version;
          s.loadError = null;
          return;
        }
        final runtime = JsEngine.instance.runtime(s.key);
        final info = await runtime.loadScript(code);
        // Publish the installed script's verified declaration before its init
        // uses cookies; setup may wait for those browser operations to finish.
        s.manifest = SourceManifest(info.manifest);
        s.manifest = SourceManifest(
          await runtime.setup(state, waitForInit: waitForInit),
        );
      }
      s.version = s.manifest!.version;
      s.loadError = null;
    } catch (e) {
      s.loadError = e is SourceError ? e.rawMessage : e.toString();
      debugPrint(Diagnostics.error(e));
    }
  }

  Future<Map<String, dynamic>> _loadState(String key) async {
    if (_state[key] != null) return _state[key]!;
    final store = _stateStores[key] ??= JsonStore('source_state_$key.json');
    final data = await store.load();
    final state = data is Map
        ? data.cast<String, dynamic>()
        : <String, dynamic>{};
    state['settings'] ??= <String, dynamic>{};
    state['data'] ??= <String, dynamic>{};
    return _state[key] = state;
  }

  Future<void> _persistData(
    String key,
    Map<String, dynamic> data, {
    bool flush = false,
  }) async {
    final state = _state[key] ??= {
      'settings': <String, dynamic>{},
      'data': <String, dynamic>{},
    };
    state['data'] = data;
    final store = _stateStores[key] ??= JsonStore('source_state_$key.json');
    store.save(state);
    if (flush) await store.flush();
  }

  Map<String, dynamic> settingsOf(String key) =>
      ((_state[key]?['settings'] as Map?) ?? {}).cast<String, dynamic>();

  Object? settingValue(String key, OptionDef def) =>
      settingsOf(key)[def.key] ?? def.defaultValue;

  Future<void> setSetting(String key, String settingKey, Object? value) =>
      _mutate(() async {
        final state = await _loadState(key);
        final settings = (state['settings'] as Map).cast<String, dynamic>()
          ..[settingKey] = value;
        state['settings'] = settings;
        (_stateStores[key] ??= JsonStore('source_state_$key.json')).save(state);
        await JsEngine.instance.updateSettings(key, settings);
        notifyListeners();
      }, key: key);

  /// Only called after the user confirmed registration. The preference is durable before JS runs.
  Future<void> setManagedAccount(String key, bool enabled) async {
    await ready;
    await _mutate(() async {
      if (manifest(key)?.account?.managedAccount != true) {
        throw SourceError('UNSUPPORTED', '该源不支持专用自动维护账号');
      }
      final state = await _loadState(key);
      if (enabled && (state['data'] as Map?)?['credentials'] != null) {
        throw SourceError('CONFIG', '已有手动账号，请先退出登录再启用专用账号');
      }
      final settings = {
        ...(state['settings'] as Map).cast<String, dynamic>(),
        'managedAccount': enabled,
      };
      final next = {...state, 'settings': settings};
      final store = _stateStores[key] ??= JsonStore('source_state_$key.json');
      store.save(next);
      await store.flush();
      _state[key] = next;
      await JsEngine.instance.updateSettings(key, settings);
      notifyListeners();
    }, key: key);
    try {
      if (enabled) await _call(key, 'account.enableManaged', []);
    } finally {
      await refreshAccount(key);
    }
  }

  Future<void> retryManagedAccount(String key) async {
    try {
      await _call(key, 'account.enableManaged', []);
    } finally {
      await refreshAccount(key);
    }
  }

  // ── Backup ──

  /// Installed sources and their settings; [credentials] also includes each source's private
  /// store (tokens, account ids), which may contain secrets.
  Future<Map<String, dynamic>> exportJson({bool credentials = false}) =>
      _mutate(
        () async => (jsonDecode(
          jsonEncode({
            'sources': [
              for (final s in all)
                {
                  'key': s.key,
                  'origin': s.origin,
                  'url': s.url,
                  'enabled': s.enabled,
                  'order': s.order,
                },
              for (final e in _state.entries)
                if (!_sources.containsKey(e.key) &&
                    e.value['restoreMetadata'] is Map)
                  e.value['restoreMetadata'],
            ],
            'settings': {
              for (final key in {..._sources.keys, ..._state.keys})
                key: settingsOf(key),
            },
            if (credentials)
              'data': {
                for (final key in {..._sources.keys, ..._state.keys})
                  key: ((_state[key]?['data'] as Map?) ?? {})
                      .cast<String, dynamic>(),
              },
          }),
        ) as Map).cast<String, dynamic>(),
      );

  /// Applies settings (and private stores, when present) to sources that are installed, reloading
  /// them so the runtime sees the restored values. Returns URL-installed sources that are missing here.
  static void validateImport(Map<String, dynamic> json) {
    for (final name in ['settings', 'data']) {
      final value = json[name];
      if (value == null) continue;
      if (value is! Map ||
          value.entries.any(
            (e) =>
                !isSourceKey(e.key) ||
                e.value is! Map ||
                (e.value as Map).keys.any((k) => k is! String),
          )) {
        throw const FormatException('备份数据无效');
      }
    }
    final sources = json['sources'];
    if (sources != null && sources is! List) {
      throw const FormatException('备份数据无效');
    }
    for (final raw in sources is List ? sources : const []) {
      if (raw is! Map ||
          !isSourceKey(raw['key']) ||
          (raw['order'] != null &&
              (raw['order'] is! int || raw['order'] < 0)) ||
          (raw['enabled'] != null && raw['enabled'] is! bool) ||
          (raw['url'] != null && raw['url'] is! String)) {
        throw const FormatException('备份数据无效');
      }
      if (raw['origin'] == 'url') {
        final uri = Uri.tryParse(raw['url']?.toString() ?? '');
        if (uri == null ||
            !{'http', 'https'}.contains(uri.scheme) ||
            uri.host.isEmpty ||
            uri.userInfo.isNotEmpty) {
          throw const FormatException('备份数据无效');
        }
      }
    }
  }

  Future<
    ({Map<String, Object?> files, List<({String key, String url})> missing})
  >
  prepareImport(Map<String, dynamic> json) async {
    validateImport(json);
    final missing = <({String key, String url})>[];
    final files = <String, Object?>{};
    final records = {for (final s in all) s.key: s.toJson()};
    final settings = (json['settings'] as Map?)?.cast<String, dynamic>() ?? {};
    final data = (json['data'] as Map?)?.cast<String, dynamic>() ?? {};
    final metadata = <String, Map>{};
    for (final e in ((json['sources'] as List?) ?? const []).whereType<Map>()) {
      final key = e['key'].toString();
      metadata[key] = e;
      final s = _sources[key];
      if (s == null) {
        final url = (e['url'] ?? '').toString();
        if (e['origin'] == 'url' && url.isNotEmpty) {
          missing.add((key: key, url: url));
        }
        continue;
      }
      records[key] = {
        ...s.toJson(),
        'enabled': e['enabled'] != false,
        'order': e['order'] ?? s.order,
      };
    }
    for (final key in {...settings.keys, ...data.keys, ...metadata.keys}) {
      final st = settings[key];
      final d = data[key];
      final state =
          jsonDecode(jsonEncode(await _loadState(key))) as Map<String, dynamic>;
      if (st is Map) {
        state['settings'] = {
          ...(state['settings'] as Map).cast<String, dynamic>(),
          ...st.cast<String, dynamic>(),
        };
      }
      if (d is Map) {
        state['data'] = {
          ...(state['data'] as Map).cast<String, dynamic>(),
          ...d.cast<String, dynamic>(),
        };
      }
      if (!_sources.containsKey(key) && metadata[key] != null) {
        state['restoreMetadata'] = metadata[key];
      }
      files['source_state_$key.json'] = state;
    }
    files['sources.json'] = {'sources': records.values.toList()};
    return (files: files, missing: missing);
  }

  Future<void> reloadFromDisk() async {
    final registry = await _registry.load();
    _sources.clear();
    if (registry is Map) {
      for (final raw in (registry['sources'] as List? ?? const [])) {
        final s = InstalledSource.fromJson(
          (raw as Map).cast<String, dynamic>(),
        );
        _sources[s.key] = s;
      }
    }
    _state.clear();
    _stateStores.clear();
    await _loadSavedStates();
    if (loaded) await loadAll();
    notifyListeners();
  }

  Future<void> _loadSavedStates() async {
    await for (final file in AppPaths.data.list()) {
      final name = p.basename(file.path);
      if (file is File &&
          name.startsWith('source_state_') &&
          name.endsWith('.json')) {
        final key = name.substring(13, name.length - 5);
        if (isSourceKey(key)) await _loadState(key);
      }
    }
  }

  Future<void> flush() async {
    if (_sources.isNotEmpty) await _registry.flush();
    for (final store in _stateStores.values) {
      await store.flush();
    }
  }

  Future<T> exclusively<T>(Future<T> Function() action) => _mutate(action);

  Future<List<({String key, String url})>> importJson(
    Map<String, dynamic> json,
  ) => _mutate(() async {
    final plan = await prepareImport(json);
    for (final e in plan.files.entries) {
      await writeFileAtomic(
        AppPaths.dataFile(e.key),
        utf8.encode(jsonEncode(e.value)),
      );
    }
    await reloadFromDisk();
    return plan.missing;
  });

  Future<void> setEnabled(String key, bool enabled) => _mutate(() async {
    final source = _sources[key];
    if (source == null || source.enabled == enabled) return;
    source.enabled = enabled;
    await _load(source);
    _saveRegistry();
    notifyListeners();
  }, key: key);

  void reorder(int oldIndex, int newIndex) {
    final list = all;
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    _saveOrder(list);
  }

  /// The bundled index is the sole source of official default ordering.
  /// Third-party sources retain their relative order after the official sources.
  void resetOrderToDefault() {
    final list = all;
    final byKey = {for (final source in list) source.key: source};
    _saveOrder([
      for (final key in _builtinKeys)
        if (byKey.containsKey(key)) byKey[key]!,
      ...list.where((source) => !_builtinKeys.contains(source.key)),
    ]);
  }

  void _saveOrder(List<InstalledSource> list) {
    for (var i = 0; i < list.length; i++) {
      list[i].order = i;
    }
    _saveRegistry();
    notifyListeners();
  }

  void _saveRegistry() => _registry.save({
    'sources': _sources.values.map((s) => s.toJson()).toList(),
  });

  // ── Install / update from URL or repository ─────────────

  Future<List<RepoEntry>> fetchRepository(String url) async {
    final res = await HttpService.instance.send(method: 'GET', url: url);
    if (!res.ok) throw SourceError('HTTP', '仓库返回 HTTP ${res.status}');
    final data = jsonDecode(res.text);
    final list = data is Map ? data['sources'] as List? ?? [] : data as List;
    return list
        .whereType<Map>()
        .map((e) => RepoEntry(e.cast<String, dynamic>(), url))
        .toList();
  }

  /// Downloads a script and inspects it in a sandboxed runtime, without installing anything.
  /// [expectedSha256] (from a repository index) must match when given.
  Future<InstallPreview> previewFromUrl(
    String url, {
    String? expectedSha256,
  }) async {
    final res = await HttpService.instance.send(method: 'GET', url: url);
    if (!res.ok) throw SourceError('HTTP', '下载失败：HTTP ${res.status}');
    return previewScript(
      decodeSourceScript(res.bytes),
      url: url,
      expectedSha256: expectedSha256,
    );
  }

  Future<InstallPreview> previewScript(
    String code, {
    String url = '',
    String? expectedSha256,
  }) async {
    final hash = sha256Hex(code);
    if (expectedSha256 != null &&
        expectedSha256.isNotEmpty &&
        expectedSha256 != hash) {
      throw SourceError('CONFIG', '脚本校验失败：内容与源仓库公布的 SHA-256 不一致，可能被篡改');
    }
    final info = await JsEngine.instance.probe(code);
    final manifest = SourceManifest(info.manifest);
    final domains = declaredDomains(info.manifest);
    final warnings = <String>[];
    final existing = _sources[info.key];
    if (_builtinKeys.contains(info.key) && existing?.origin == 'builtin') {
      warnings.add('将替换内置源「${existing!.name}」，并继承它的登录状态与设置');
    } else if (existing != null) {
      warnings.add(
        '将更新已安装的「${existing.name}」（v${existing.version} → v${manifest.version}），并继承它的登录状态',
      );
    }
    for (final other in all) {
      if (other.key == info.key || other.manifest == null) continue;
      final theirs = declaredDomains(other.manifest!.json);
      final shared = domains
          .where(
            (d) => theirs.any(
              (o) => hostInDomains(d, [o]) || hostInDomains(o, [d]),
            ),
          )
          .toList();
      if (shared.isNotEmpty) {
        warnings.add('声明的站点与「${other.name}」重叠：${shared.join('、')}');
      }
    }
    if (domains.isEmpty) warnings.add('没有声明所属站点，无法使用 Cookie 同步与浏览器模式');
    if (manifest.usesBrowserNetwork) warnings.add('使用浏览器模式联网（在内置浏览器中发出请求）');
    return InstallPreview(
      code: code,
      url: url,
      key: info.key,
      manifest: manifest,
      sha256: hash,
      domains: domains,
      warnings: warnings,
      existing: existing,
    );
  }

  /// Installs a previewed script (after the user confirmed it); returns its key.
  Future<String> install(InstallPreview preview, {bool official = false}) {
    // Capture mutable source metadata before entering the mutation queue.
    final expectedSource = preview.existing;
    final expectedVersion = expectedSource?.version;
    final expectedOrigin = expectedSource?.origin;
    return _mutate(
      () => _install(
        preview,
        official: official,
        expectedSource: expectedSource,
        expectedVersion: expectedVersion,
        expectedOrigin: expectedOrigin,
      ),
    );
  }

  Future<String> _install(
    InstallPreview preview, {
    required bool official,
    required InstalledSource? expectedSource,
    required String? expectedVersion,
    required String? expectedOrigin,
  }) async {
    final journalFile = AppPaths.dataFile('source_install.json');
    if (await journalFile.exists()) {
      throw SourceError('CONFIG', '上次源更新尚未恢复，请重启应用后重试');
    }
    final key = preview.key;
    if (!isSourceKey(key) || sha256Hex(preview.code) != preview.sha256) {
      throw SourceError('CONFIG', '源脚本身份或校验值无效');
    }
    final existing = _sources[key];
    if (official &&
        (existing == null ||
            (expectedSource != null &&
                (!identical(existing, expectedSource) ||
                    existing.version != expectedVersion ||
                    existing.origin != expectedOrigin)) ||
            !{'builtin', 'official'}.contains(existing.origin) ||
            !isNewer(preview.manifest.version, existing.version))) {
      throw SourceError('CONFIG', '源已发生变化，请重新检查更新');
    }
    final file = _scriptFile(key);
    Map<String, dynamic>? journal;
    try {
      // Stop old initialization and bridge requests before taking a consistent snapshot.
      if (loader == null) await JsEngine.instance.disposeRuntime(key);
      final state = await _loadState(key);
      journal = {
        'key': key,
        'source': existing?.toJson(),
        'code': await file.exists()
            ? decodeSourceScript(await file.readAsBytes())
            : null,
        'state': jsonDecode(jsonEncode(state)),
        'cookies': await CookieStore.instance.snapshotPartition(key),
        'domains': <String>{
          if (existing?.manifest != null)
            ...declaredDomains(existing!.manifest!.json),
          ...preview.domains,
        }.toList(),
      };
      // One temporary recovery record covers only the source being changed. A crash
      // before the commit point restores its script, registry and private state on launch.
      await writeFileAtomic(journalFile, utf8.encode(jsonEncode(journal)));
      await writeFileAtomic(file, utf8.encode(preview.code));
      final s =
          existing ??
          InstalledSource(
            key: key,
            origin: 'url',
            version: '0.0.0',
            order: _sources.length,
          );
      _sources[key] = s;
      if (state.remove('restoreMetadata') case final Map metadata) {
        s.enabled = metadata['enabled'] != false;
        s.order = (metadata['order'] as num?)?.toInt() ?? s.order;
        (_stateStores[key] ??= JsonStore('source_state_$key.json')).save(state);
      }
      await _load(s, waitForInit: true);
      if (s._loadError != null) throw SourceError('CONFIG', s._loadError!);
      if (s.manifest?.json['key'] != key ||
          s.version != preview.manifest.version ||
          s.manifest?.json['apiVersion'] !=
              preview.manifest.json['apiVersion']) {
        throw SourceError('CONFIG', '源加载结果与更新信息不一致');
      }
      s
        ..origin = official ? 'official' : 'url'
        ..url = preview.url
        ..sha256 = preview.sha256;
      _sources[key] = s;
      await _stateStores[key]?.flush();
      _saveRegistry();
      await _registry.flush();
      await journalFile.delete();
      notifyListeners();
      return key;
    } catch (error) {
      if (loader == null) await JsEngine.instance.disposeRuntime(key);
      if (journal != null && await journalFile.exists()) {
        await _restoreInstall(journal);
        await journalFile.delete();
      }
      final restored = _sources[key];
      if (restored != null) await _load(restored);
      notifyListeners();
      if (error is SourceError) rethrow;
      throw SourceError('CONFIG', error.toString());
    }
  }

  Future<void> _restoreInstall(Map<String, dynamic> journal) async {
    final key = journal['key'] as String;
    if (!isSourceKey(key)) {
      throw SourceError('CONFIG', '源脚本身份或校验值无效');
    }
    final file = _scriptFile(key);
    final code = journal['code'] as String?;
    if (code != null) {
      await writeFileAtomic(file, utf8.encode(code));
    } else if (await file.exists()) {
      await file.delete();
    }
    final old = journal['source'];
    if (old is Map) {
      final current = _sources[key];
      _sources[key] = InstalledSource.fromJson(old.cast<String, dynamic>())
        ..enabled = current?.enabled ?? old['enabled'] != false
        ..order = current?.order ?? (old['order'] as num?)?.toInt() ?? 0;
    } else {
      _sources.remove(key);
    }
    final state = (journal['state'] as Map).cast<String, dynamic>();
    _state[key] = state;
    final store = _stateStores[key] ??= JsonStore('source_state_$key.json');
    store.save(state);
    await store.flush();
    await CookieStore.instance.restorePartition(
      key,
      (journal['cookies'] as Map).cast<String, String>(),
      domains: (journal['domains'] as List).cast<String>(),
    );
    _saveRegistry();
    await _registry.flush();
  }

  Future<void> _recoverInstall() async {
    final file = AppPaths.dataFile('source_install.json');
    if (!await file.exists()) return;
    final journal = (jsonDecode(await file.readAsString()) as Map)
        .cast<String, dynamic>();
    await _restoreInstall(journal);
    await file.delete();
  }

  /// Mutations wait for existing calls; new calls wait for the queued mutations.
  Future<T> _mutate<T>(Future<T> Function() action, {String? key}) {
    if (key != null) {
      // 新设置不能等待旧分流或后台海报的网络超时；账号写入仍正常串行。
      for (final token in _readRequests[key]?.toList() ?? <CancelToken>[]) {
        token.cancel('source configuration changed');
      }
      final pendingGlobal = _mutations.settled;
      final queue = _sourceMutations[key] ??= SerialExecutor();
      return queue.run(() async {
        await pendingGlobal;
        await Future.wait(
          _activeBySource[key]?.toList() ?? const <Future<void>>[],
        );
        return action();
      });
    }
    final pendingLocal = _sourceMutations.values.map((q) => q.settled).toList();
    return _mutations.run(() async {
      await Future.wait(pendingLocal);
      await Future.wait(_activeCalls.toList());
      return action();
    });
  }

  /// Removes a source together with everything it stored: runtime, settings, private store and cookies.
  Future<void> uninstall(String key) => _mutate(() async {
    await JsEngine.instance.disposeRuntime(key);
    await CookieStore.instance.clearPartition(key);
    _sources.remove(key);
    try {
      await _scriptFile(key).delete();
    } catch (_) {}
    _state.remove(key);
    _stateStores.remove(key);
    try {
      await AppPaths.dataFile('source_state_$key.json').delete();
    } catch (_) {}
    _saveRegistry();
    notifyListeners();
  });

  /// Restores a built-in source to the bundled version.
  Future<void> resetBuiltin(String key) => _mutate(() async {
    final s = _sources[key];
    if (s == null || !_builtinKeys.contains(key)) return;
    final index = jsonDecode(
      await rootBundle.loadString('assets/sources/index.json'),
    ) as Map;
    final entry = (index['sources'] as List).cast<Map>().firstWhere(
      (entry) => entry['key'] == key,
    );
    final code = await rootBundle.loadString('assets/sources/${entry['file']}');
    // Reuse installation recovery so an explicit reset preserves private state on failure.
    await _install(
      InstallPreview(
        code: code,
        url: '',
        key: key,
        manifest: SourceManifest({
          'key': key,
          'version': entry['version'],
          'apiVersion': 1,
        }),
        sha256: sha256Hex(code),
        domains: s.manifest == null
            ? const []
            : declaredDomains(s.manifest!.json),
        warnings: const [],
        existing: s,
      ),
      official: false,
      expectedSource: s,
      expectedVersion: s.version,
      expectedOrigin: s.origin,
    );
    s
      ..origin = 'builtin'
      ..url = '';
    _saveRegistry();
    await _registry.flush();
    notifyListeners();
  });

  static bool isNewer(String candidate, String installed) =>
      compareReleaseVersions(candidate, installed) > 0;

  // ── Typed source API ────────────────────────────────────
  Future<String> subscriptionContext(String key) async => sha256Hex(
    jsonEncode([
      manifest(key)?.version,
      settingsOf(key),
      (_state[key]?['data'] as Map?)?.entries
          .where(
            (e) => RegExp(
              'credential|account|user|session',
              caseSensitive: false,
            ).hasMatch(e.key),
          )
          .map((e) => [e.key, subscriptionAccountIdentity(e.value)])
          .toList(),
      await CookieStore.instance.authenticationValues(
        key,
        ((manifest(key)?.json['account'] as Map?)?['requiredCookies']
                    as List? ??
                [])
            .map((v) => v.toString())
            .toList(),
      ),
      AppSettings.instance.proxy,
    ]),
  );

  Future<Object?> _call(
    String key,
    String method,
    List<Object?> args, {
    CancelToken? cancelToken,
  }) async {
    if (cancelToken?.cancelError case final error?) throw error;
    await ready;
    while (true) {
      final pending = _mutations.settled;
      final local = _sourceMutations[key]?.settled;
      await pending;
      await local;
      if (identical(pending, _mutations.settled) &&
          identical(local, _sourceMutations[key]?.settled)) {
        break;
      }
    }
    final finished = Completer<void>();
    if (cancelToken?.cancelError case final error?) throw error;
    final isRead = const {
      'feed',
      'search',
      'detail',
      'chapters',
      'pages',
      'videos',
    }.contains(method);
    final readToken = isRead ? CancelToken() : cancelToken;
    final cancellation = isRead
        ? cancelToken?.whenCancel.asStream().listen(readToken!.cancel)
        : null;
    if (isRead) (_readRequests[key] ??= {}).add(readToken!);
    _activeCalls.add(finished.future);
    (_activeBySource[key] ??= {}).add(finished.future);
    try {
      return await JsEngine.instance.invoke(
        key,
        method,
        args,
        cancelToken: readToken,
      );
    } finally {
      _activeCalls.remove(finished.future);
      _activeBySource[key]?.remove(finished.future);
      finished.complete();
      await cancellation?.cancel();
      if (isRead) _readRequests[key]?.remove(readToken);
      if (readToken?.isCancelled != true &&
          _backgroundKeys == null &&
          !method.startsWith('account.') &&
          manifest(key)?.can('status') == true) {
        unawaited(refreshAccount(key));
      }
    }
  }

  Future<WorkPage> feed(
    String key,
    String feedKey, {
    int page = 1,
    String? cursor,
    Map<String, Object?> options = const {},
    bool refresh = false,
    bool background = false,
    CancelToken? cancelToken,
  }) async {
    await ready;
    if (!background) cancelBackgroundFeeds(key);
    final token = cancelToken ?? CancelToken();
    if (background) (_backgroundFeeds[key] ??= {}).add(token);
    try {
      final source = manifest(key);
      // 每次读取摘要，登录、退出及网页登录改变身份后不能命中旧账号主页。
      final cookies = await CookieStore.instance.snapshotPartition(key);
      final result = await HomeCache.instance.request(
        [
          key,
          source?.version,
          cookies,
          settingsOf(key),
          _state[key]?['data'],
          AppSettings.instance.proxy,
          source?.json['domains'],
          feedKey,
          page,
          cursor,
          options,
          HomeMetadata.fields.toList(),
        ],
        () async {
          return (await _call(key, 'feed', [
            feedKey,
            {'page': page, 'cursor': cursor, 'options': options},
          ], cancelToken: token) as Map).cast<String, dynamic>();
        },
        refresh: refresh,
        requestGroup: background ? 'background' : 'foreground',
        shouldCache: HomeMetadata.cacheable,
        serialize: HomeMetadata.serialize,
      );
      return WorkPage.fromJson({
        ...result.data,
        '_staleCache': result.stale,
      }, key);
    } finally {
      if (background) _backgroundFeeds[key]?.remove(token);
    }
  }

  void cancelBackgroundFeeds(String key) {
    for (final token in _backgroundFeeds[key]?.toList() ?? <CancelToken>[]) {
      token.cancel('foreground browsing takes priority');
    }
  }

  Future<WorkPage> search(
    String key, {
    required String keyword,
    int page = 1,
    String? cursor,
    Map<String, Object?> filters = const {},
    CancelToken? cancelToken,
  }) async {
    final res = await _call(key, 'search', [
      {'keyword': keyword, 'page': page, 'cursor': cursor, 'filters': filters},
    ], cancelToken: cancelToken);
    return WorkPage.fromJson((res as Map).cast<String, dynamic>(), key);
  }

  Future<WorkDetail> detail(String key, String id, {WorkItem? preview}) async {
    final res = await _call(key, 'detail', [
      id,
      if (preview?.source == key && preview?.id == id) preview!.toJson(),
    ]);
    return WorkDetail((res as Map).cast<String, dynamic>(), key);
  }

  Future<String> random(String key) async =>
      (await _call(key, 'random', [{}])).toString();

  Future<List<GameResource>> gameResources(String key, String id) async {
    final result = await _call(key, 'gameResources', [id]);
    if (result is! List) throw SourceError('PARSE', '游戏资源格式无效');
    return result
        .map(
          (value) =>
              GameResource.fromJson((value as Map).cast<String, dynamic>()),
        )
        .toList();
  }

  Future<GameResourceLink> resolveGameResource(
    String key,
    String id,
    String resourceId,
    String channelId, {
    CancelToken? cancelToken,
  }) async {
    final result = await _call(key, 'resolveGameResource', [
      id,
      resourceId,
      channelId,
    ], cancelToken: cancelToken);
    return GameResourceLink.fromJson((result as Map).cast<String, dynamic>());
  }

  Future<ChapterImages> chapter(
    String key,
    String id,
    String? chapterId, {
    CancelToken? cancelToken,
  }) async {
    final res = await _call(key, 'chapter', [
      id,
      chapterId,
    ], cancelToken: cancelToken);
    return ChapterImages.fromJson((res as Map).cast<String, dynamic>());
  }

  Future<TextChapter> textChapter(
    String key,
    String id,
    String? chapterId, {
    CancelToken? cancelToken,
  }) async {
    final res = await _call(key, 'textChapter', [
      id,
      chapterId,
    ], cancelToken: cancelToken);
    return TextChapter.fromJson((res as Map).cast<String, dynamic>());
  }

  Future<PageImage> resolveImage(
    String key, {
    required String id,
    String? chapterId,
    required int index,
    String? token,
    int retry = 0,
    CancelToken? cancelToken,
  }) async {
    final res = await _call(key, 'resolveImage', [
      {
        'id': id,
        'chapterId': chapterId,
        'index': index,
        'token': token,
        'retry': retry,
      },
    ], cancelToken: cancelToken);
    return PageImage((res as Map).cast<String, dynamic>());
  }

  Future<({List<PreviewThumb> thumbs, bool hasNext})> thumbnails(
    String key,
    String id,
    int page,
  ) async {
    final res = (await _call(key, 'thumbnails', [id, page]) as Map)
        .cast<String, dynamic>();
    return (
      thumbs: (res['thumbnails'] as List? ?? [])
          .whereType<Map>()
          .map((t) => PreviewThumb(t.cast<String, dynamic>()))
          .toList(),
      hasNext: res['hasNext'] == true,
    );
  }

  Future<List<VideoSource>> videos(
    String key,
    String id, {
    String? episodeId,
    CancelToken? cancelToken,
  }) async {
    final res = await _call(key, 'videos', [
      id,
      episodeId ?? '_',
    ], cancelToken: cancelToken);
    final sources = (res as List)
        .whereType<Map>()
        .map((e) => VideoSource(e.cast<String, dynamic>()))
        .toList();
    if (!sources.any((s) => s.format == 'hls')) return sources;
    final sourceManifest = manifest(key);
    if (sourceManifest == null) throw SourceError('CONFIG', '视频源未加载');
    final resolved = <VideoSource>[];
    for (final source in sources) {
      if (source.format != 'hls') {
        resolved.add(source);
        continue;
      }
      resolved.addAll(
        await HlsSources(
          createMediaTransport(sourceManifest, headers: source.headers),
        ).resolve([source], cancelToken: cancelToken),
      );
    }
    return resolved;
  }

  Future<String> login(String key, Map<String, String> values) async {
    final res = await _call(key, 'account.login', [values]);
    await refreshAccount(key);
    return res is Map ? (res['name'] ?? '').toString() : '';
  }

  Future<SubscriptionTarget> normalizeSubscription(
    String key,
    String input, {
    String dimension = 'posts',
  }) async {
    final result = await _call(key, 'updateSubscriptions.normalize', [
      dimension,
      input,
    ]);
    final target = SubscriptionTarget(result as Map);
    if (target.id.isEmpty) throw SourceError('CONFIG', '订阅目标无效');
    return target;
  }

  Future<Map<String, dynamic>> checkSubscription(
    String key,
    String dimension,
    String target, {
    String? cursor,
    CancelToken? cancelToken,
  }) async => (await _call(key, 'updateSubscriptions.check', [
    {'dimension': dimension, 'target': target},
    {'cursor': cursor},
  ], cancelToken: cancelToken) as Map).cast<String, dynamic>();

  Future<List<SubscriptionTarget>> subscriptionTargets(String key) async =>
      ((await _call(key, 'subscription.targets', [])) as List)
          .whereType<Map>()
          .map(SubscriptionTarget.new)
          .toList();

  Future<SubscriptionPage> subscriptionPosts(
    String key,
    String target, {
    String? cursor,
    CancelToken? cancelToken,
  }) async => SubscriptionPage(
    (await _call(key, 'subscription.posts', [
      target,
      {'cursor': cursor},
    ], cancelToken: cancelToken)) as Map,
  );

  /// 源插件只返回附件块；由框架控制本地路径、大小与原子完成，取消不会留下假完整文件。
  Future<File> subscriptionMediaFile(
    String key,
    SubscriptionMedia media, {
    CancelToken? cancelToken,
    void Function(int, int)? onProgress,
  }) async {
    final resource = media.json['resource'];
    final size = resource is Map ? resource['size'] : null;
    if (resource is! Map || size is! int || size < 1 || size > 536870912) {
      throw SourceError('UNSUPPORTED', '该媒体暂不支持，请在原站打开');
    }
    final directory = SubscriptionCache.instance.directory;
    await directory.create(recursive: true);
    // 可变授权信息不应进入身份；稳定标识由插件提供，框架不识别站点私有字段。
    final cacheKey = resource['cacheKey'];
    if (cacheKey is! String || cacheKey.isEmpty || cacheKey.length > 512) {
      throw SourceError('CONFIG', '媒体数据无效');
    }
    final identity = safeFileName('$key:$cacheKey');
    final file = File(
      p.join(
        directory.path,
        '$identity.${media.type == 'video' ? 'mp4' : 'jpg'}',
      ),
    );
    SubscriptionCache.instance.retain(file);
    final queue = _attachmentWrites[file.path] ??= SerialExecutor();
    final result = queue.run(
      () => _downloadSubscriptionMedia(
        key,
        resource,
        size,
        file,
        cancelToken,
        onProgress,
      ),
    );
    final tail = queue.settled;
    try {
      return await result;
    } catch (_) {
      SubscriptionCache.instance.release(file);
      rethrow;
    } finally {
      if (identical(queue.settled, tail)) _attachmentWrites.remove(file.path);
    }
  }

  Future<File> _downloadSubscriptionMedia(
    String key,
    Map resource,
    int size,
    File file,
    CancelToken? cancelToken,
    void Function(int, int)? onProgress,
  ) async {
    final temporary = File(
      '${file.path}.part-${DateTime.now().microsecondsSinceEpoch}',
    );
    var offset = 0;
    SubscriptionCache.instance.retain(temporary);
    try {
      if (cancelToken?.cancelError case final error?) throw error;
      if (await file.exists() && await file.length() == size) {
        await file.setLastModified(DateTime.now());
        return file;
      }
      final output = await temporary.open(mode: FileMode.write);
      try {
        while (offset < size) {
          if (cancelToken?.cancelError case final error?) throw error;
          final chunk = await _call(key, 'subscription.mediaChunk', [
            resource,
            offset,
          ], cancelToken: cancelToken) as Map;
          final encoded = chunk['base64'];
          if (encoded is! String || encoded.length > 174764) {
            throw SourceError('PARSE', '媒体数据无效');
          }
          final bytes = base64Decode(encoded);
          if (bytes.isEmpty ||
              bytes.length > 131072 ||
              offset + bytes.length > size ||
              (offset + bytes.length < size && bytes.length != 131072)) {
            throw SourceError('PARSE', '媒体数据无效');
          }
          await output.writeFrom(bytes);
          offset += bytes.length;
          onProgress?.call(offset, size);
        }
        await output.flush();
      } finally {
        await output.close();
      }
      if (cancelToken?.cancelError case final error?) throw error;
      await temporary.rename(file.path);
      await ImageStore.instance.trim();
      return file;
    } finally {
      SubscriptionCache.instance.release(temporary);
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Future<void> logout(String key) async {
    await _call(key, 'account.logout', []);
    if (manifest(key)?.account?.managedAccount == true &&
        settingsOf(key)['managedAccount'] == true) {
      await setManagedAccount(key, false);
    }
    await refreshAccount(key);
  }

  Future<void> refreshAccount(String key) async {
    final s = _sources[key];
    if (s?.manifest?.can('status') != true) return;
    try {
      final res = (await _call(key, 'account.status', []) as Map?) ?? {};
      s!.account = AccountStatus(
        res['loggedIn'] == true,
        (res['name'] ?? '').toString(),
        configured: res['configured'] == true || res['loggedIn'] == true,
      );
    } catch (_) {
      s!.account = AccountStatus(false, '');
    }
    notifyListeners();
  }

  /// Finds (source, id) references in free text: links from any source, or "JM123456"-style codes.
  List<({String source, String id})> extractRefs(String text) {
    final refs = <({String source, String id})>[];
    for (final s in enabled) {
      for (final id in s.manifest!.extractIds(text)) {
        refs.add((source: s.key, id: id));
      }
    }
    return refs;
  }
}
