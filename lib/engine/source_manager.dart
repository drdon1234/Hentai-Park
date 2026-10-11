import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../core/localization.dart';
import '../core/models.dart';
import '../core/storage.dart';
import 'cookie_store.dart';
import 'domains.dart';
import 'http_service.dart';
import 'browser_media.dart';
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
  Future<void> _mutations = Future<void>.value();
  final Set<Future<void>> _activeCalls = {};

  final _registry = JsonStore('sources.json');
  final Map<String, InstalledSource> _sources = {};
  final Map<String, Map<String, dynamic>> _state = {}; // key → {settings, data}
  final Map<String, JsonStore> _stateStores = {};
  bool loaded = false;
  final _ready = Completer<void>();
  final Set<String> _builtinKeys = {};

  /// Completes once installed sources have been loaded the first time; every source call waits on it
  /// so work started at launch (resumed downloads, deep links) never races the plugin loader.
  Future<void> get ready => _ready.future;

  Directory get _dir => Directory(p.join(AppPaths.data.path, 'sources'));
  File _scriptFile(String key) => File(p.join(_dir.path, '$key.js'));

  List<InstalledSource> get all =>
      _sources.values.toList()..sort((a, b) => a.order.compareTo(b.order));
  List<InstalledSource> get enabled =>
      all.where((s) => s.enabled && s.ready).toList();
  InstalledSource? operator [](String key) => _sources[key];
  SourceManifest? manifest(String key) => _sources[key]?.manifest;
  bool isBuiltin(String key) => _builtinKeys.contains(key);

  Future<void> init() async {
    await _dir.create(recursive: true);
    final data = await _registry.load();
    if (data is Map && data['sources'] is List) {
      for (final j in (data['sources'] as List).whereType<Map>()) {
        final s = InstalledSource.fromJson(j.cast<String, dynamic>());
        _sources[s.key] = s;
      }
    }
    await _recoverInstall();
    await _syncBuiltins();
    await CookieStore.instance.migrateLegacy(_sources.keys);
    JsEngine.instance.onPersist = _persistData;
    JsEngine.instance.onRestarted = (key) => unawaited(
      _mutate(() async {
        final s = _sources[key];
        if (s == null) return;
        await _load(s);
        notifyListeners();
      }),
    );
    try {
      await loadAll();
    } finally {
      // Never leave callers waiting forever if the engine failed to start; they get the error instead.
      if (!_ready.isCompleted) _ready.complete();
    }
  }

  /// Installs bundled sources on first run and upgrades them when the app ships newer versions.
  Future<void> _syncBuiltins() async {
    final index = jsonDecode(
      await rootBundle.loadString('assets/sources/index.json'),
    ) as Map;
    var order = _sources.length;
    for (final e in (index['sources'] as List).cast<Map>()) {
      final key = e['key'].toString();
      final version = e['version'].toString();
      _builtinKeys.add(key);
      final existing = _sources[key];
      // User-installed sources remain independent. An online official update wins over
      // an equal/older bundle, but a newer app bundle can upgrade it again.
      if (existing != null && existing.origin == 'url') continue;
      if (existing != null &&
          existing.origin == 'official' &&
          !isNewer(version, existing.version) &&
          await _scriptFile(key).exists()) {
        continue;
      }
      // Built-in sources follow the bundled script exactly, so fixes shipped with an app update apply
      // even when the script's version string was not bumped.
      final code = await rootBundle.loadString('assets/sources/${e['file']}');
      final file = _scriptFile(key);
      final hash = sha256Hex(code);
      if (existing != null &&
          await file.exists() &&
          decodeSourceScript(await file.readAsBytes()) == code) {
        existing.version = version;
        existing.sha256 = hash;
        continue;
      }
      await file.writeAsString(code);
      if (existing == null) {
        _sources[key] = InstalledSource(
          key: key,
          origin: 'builtin',
          version: version,
          order: order++,
          sha256: hash,
        );
      } else {
        existing
          ..version = version
          ..origin = 'builtin'
          ..sha256 = hash;
      }
    }
    _saveRegistry();
  }

  Future<void> loadAll() async {
    await Future.wait(all.map(_load));
    loaded = true;
    if (!_ready.isCompleted) _ready.complete();
    notifyListeners();
    for (final s in enabled) {
      refreshAccount(s.key);
    }
  }

  /// Loads a source into a fresh runtime of its own (any previous runtime for the key is discarded).
  Future<void> _load(InstalledSource s, {bool waitForInit = false}) async {
    try {
      final code = decodeSourceScript(await _scriptFile(s.key).readAsBytes());
      final state = await _loadState(s.key);
      if (loader != null) {
        s.manifest = await loader!(s.key, code, state);
      } else {
        await JsEngine.instance.disposeRuntime(s.key);
        final runtime = JsEngine.instance.runtime(s.key);
        await runtime.loadScript(code);
        s.manifest = SourceManifest(
          await runtime.setup(state, waitForInit: waitForInit),
        );
      }
      s.version = s.manifest!.version;
      s.loadError = null;
    } catch (e) {
      s.loadError = e is SourceError ? e.rawMessage : e.toString();
      debugPrint('load ${s.key} failed: $e');
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
      });

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
    });
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
            ],
            'settings': {for (final s in all) s.key: settingsOf(s.key)},
            if (credentials)
              'data': {
                for (final s in all)
                  s.key: ((_state[s.key]?['data'] as Map?) ?? {})
                      .cast<String, dynamic>(),
              },
          }),
        ) as Map).cast<String, dynamic>(),
      );

  /// Applies settings (and private stores, when present) to sources that are installed, reloading
  /// them so the runtime sees the restored values. Returns URL-installed sources that are missing here.
  Future<List<({String key, String url})>> importJson(
    Map<String, dynamic> json,
  ) => _mutate(() async {
    final missing = <({String key, String url})>[];
    final settings = (json['settings'] as Map?)?.cast<String, dynamic>() ?? {};
    final data = (json['data'] as Map?)?.cast<String, dynamic>() ?? {};
    for (final e in ((json['sources'] as List?) ?? const []).whereType<Map>()) {
      final key = e['key'].toString();
      final s = _sources[key];
      if (s == null) {
        final url = (e['url'] ?? '').toString();
        if (e['origin'] == 'url' && url.isNotEmpty) {
          missing.add((key: key, url: url));
        }
        continue;
      }
      s
        ..enabled = e['enabled'] != false
        ..order = (e['order'] as num?)?.toInt() ?? s.order;
    }
    for (final s in all) {
      final st = settings[s.key];
      final d = data[s.key];
      if (st is! Map && d is! Map) continue;
      final state = await _loadState(s.key);
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
      final store = _stateStores[s.key] ??= JsonStore(
        'source_state_${s.key}.json',
      );
      store.save(state);
      await store.flush();
      await _load(s);
    }
    _saveRegistry();
    notifyListeners();
    return missing;
  });

  void setEnabled(String key, bool enabled) {
    _sources[key]?.enabled = enabled;
    _saveRegistry();
    notifyListeners();
  }

  void reorder(int oldIndex, int newIndex) {
    final list = all;
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
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
  Future<String> install(InstallPreview preview, {bool official = false}) =>
      _mutate(() => _install(preview, official: official));

  Future<String> _install(
    InstallPreview preview, {
    required bool official,
  }) async {
    final journalFile = AppPaths.dataFile('source_install.json');
    if (await journalFile.exists()) {
      throw SourceError('CONFIG', '上次源更新尚未恢复，请重启应用后重试');
    }
    final key = preview.key;
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(key) ||
        sha256Hex(preview.code) != preview.sha256) {
      throw SourceError('CONFIG', '源脚本身份或校验值无效');
    }
    final existing = _sources[key];
    if (official &&
        (existing == null ||
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
      await _writeAtomic(journalFile, jsonEncode(journal));
      await _writeAtomic(file, preview.code);
      final s =
          existing ??
          InstalledSource(
            key: key,
            origin: 'url',
            version: '0.0.0',
            order: _sources.length,
          );
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

  static Future<void> _writeAtomic(File file, String content) async {
    final temporary = File('${file.path}.pending');
    await temporary.writeAsString(content, flush: true);
    await temporary.rename(file.path);
  }

  Future<void> _restoreInstall(Map<String, dynamic> journal) async {
    final key = journal['key'] as String;
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(key)) {
      throw SourceError('CONFIG', '源脚本身份或校验值无效');
    }
    final file = _scriptFile(key);
    final code = journal['code'] as String?;
    if (code != null) {
      await _writeAtomic(file, code);
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
  Future<T> _mutate<T>(Future<T> Function() action) {
    final result = _mutations.then((_) async {
      await Future.wait(_activeCalls.toList());
      return action();
    });
    _mutations = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  /// Removes a source together with everything it stored: runtime, settings, private store and cookies.
  Future<void> uninstall(String key) => _mutate(() async {
    _sources.remove(key);
    await JsEngine.instance.disposeRuntime(key);
    try {
      await _scriptFile(key).delete();
    } catch (_) {}
    _state.remove(key);
    _stateStores.remove(key);
    try {
      await AppPaths.dataFile('source_state_$key.json').delete();
    } catch (_) {}
    await CookieStore.instance.clearPartition(key);
    _saveRegistry();
    notifyListeners();
  });

  /// Restores a built-in source to the bundled version.
  Future<void> resetBuiltin(String key) => _mutate(() async {
    final s = _sources[key];
    if (s == null) return;
    s.origin = 'builtin';
    await _syncBuiltins();
    await _load(s);
    notifyListeners();
  });

  static int _compareVersion(String a, String b) {
    final pa = a.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final pb = b.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    for (var i = 0; i < 3; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x.compareTo(y);
    }
    return 0;
  }

  static bool isNewer(String candidate, String installed) =>
      _compareVersion(candidate, installed) > 0;

  // ── Typed source API ────────────────────────────────────

  Future<Object?> _call(
    String key,
    String method,
    List<Object?> args, {
    CancelToken? cancelToken,
  }) async {
    if (cancelToken?.cancelError case final error?) throw error;
    await ready;
    while (true) {
      final pending = _mutations;
      await pending;
      if (identical(pending, _mutations)) break;
    }
    final finished = Completer<void>();
    if (cancelToken?.cancelError case final error?) throw error;
    _activeCalls.add(finished.future);
    try {
      return await JsEngine.instance.invoke(
        key,
        method,
        args,
        cancelToken: cancelToken,
      );
    } finally {
      _activeCalls.remove(finished.future);
      finished.complete();
      if (cancelToken?.isCancelled != true &&
          !method.startsWith('account.') &&
          manifest(key)?.can('status') == true) {
        await refreshAccount(key);
      }
    }
  }

  Future<WorkPage> feed(
    String key,
    String feedKey, {
    int page = 1,
    String? cursor,
    Map<String, Object?> options = const {},
  }) async {
    final res = await _call(key, 'feed', [
      feedKey,
      {'page': page, 'cursor': cursor, 'options': options},
    ]);
    return WorkPage.fromJson((res as Map).cast<String, dynamic>(), key);
  }

  Future<WorkPage> search(
    String key, {
    required String keyword,
    int page = 1,
    String? cursor,
    Map<String, Object?> filters = const {},
  }) async {
    final res = await _call(key, 'search', [
      {'keyword': keyword, 'page': page, 'cursor': cursor, 'filters': filters},
    ]);
    return WorkPage.fromJson((res as Map).cast<String, dynamic>(), key);
  }

  Future<WorkDetail> detail(String key, String id) async {
    final res = await _call(key, 'detail', [id]);
    return WorkDetail((res as Map).cast<String, dynamic>(), key);
  }

  Future<String> random(String key) async =>
      (await _call(key, 'random', [{}])).toString();

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
    CancelToken? cancelToken,
  }) async {
    final res = await _call(key, 'videos', [id], cancelToken: cancelToken);
    final sources = (res as List)
        .whereType<Map>()
        .map((e) => VideoSource(e.cast<String, dynamic>()))
        .toList();
    if (!sources.any((s) => s.format == 'hls')) return sources;
    final sourceManifest = manifest(key);
    if (sourceManifest == null) throw SourceError('CONFIG', '视频源未加载');
    return HlsSources(BrowserMedia(BrowserMediaPolicy.fromManifest(sourceManifest)))
      .resolve(sources, cancelToken: cancelToken);
  }

  Future<String> login(String key, Map<String, String> values) async {
    final res = await _call(key, 'account.login', [values]);
    await refreshAccount(key);
    return res is Map ? (res['name'] ?? '').toString() : '';
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
        refs.add((source: s.key, id: id.replaceAll('_', '/')));
      }
    }
    return refs;
  }
}
