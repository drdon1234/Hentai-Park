import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../core/app_log.dart';
import '../core/async_tasks.dart';
import '../core/localization.dart';
import '../core/models.dart';
import '../core/settings.dart';
import '../core/storage.dart';
import '../core/versions.dart';
import '../images/image_store.dart';
import '../images/subscription_cache.dart';
import '../subscriptions/context_identity.dart';
import '../subscriptions/models.dart';
import '../video/hls_sources.dart';
import 'cancellation.dart';
import 'cookie_store.dart';
import 'domains.dart';
import 'home_cache.dart';
import 'home_metadata.dart';
import 'http_service.dart';
import 'js_engine.dart';
import 'media_transport_factory.dart';
import 'source_identity.dart';

part 'source_manager/accounts.dart';
part 'source_manager/api.dart';
part 'source_manager/installer.dart';
part 'source_manager/records.dart';
part 'source_manager/runtime_pool.dart';
part 'source_manager/state.dart';
part 'source_manager/subscriptions.dart';

/// Loads a script without the JS engine (tests); returns its manifest.
typedef SourceLoader = Future<SourceManifest> Function(
  String key,
  String code,
  Map<String, dynamic> state,
);

/// Installs, updates, orders and loads source plugins, and exposes a typed API over them.
///
/// One facade over concerns kept in this library's parts: the registry and mutation queue
/// (here), lazily started runtimes, private state and backup, accounts, installation, the typed
/// source API and update subscriptions.
class SourceManager extends _SourceRegistry
    with
        _SourceState,
        _RuntimePool,
        _SourceAccounts,
        _SourceInstaller,
        _SourceApi,
        _SubscriptionApi {
  SourceManager({super.loader});
  static final SourceManager instance = SourceManager();

  static bool isNewer(String candidate, String installed) =>
      compareReleaseVersions(candidate, installed) > 0;

  static void validateImport(Map<String, dynamic> json) =>
      _validateImport(json);
}

/// Installed sources, their order, launch and the queue that serializes changes against calls.
abstract class _SourceRegistry extends ChangeNotifier {
  _SourceRegistry({this.loader});

  final SourceLoader? loader;
  final _mutations = SerialExecutor();
  final Set<Future<void>> _activeCalls = {};
  final _activeBySource = <String, Set<Future<void>>>{};
  final _readRequests = <String, Set<CancelToken>>{};
  final _backgroundFeeds = <String, Set<CancelToken>>{};
  final _sourceMutations = <String, SerialExecutor>{};
  final _changingSources = <String>{};
  final _attachmentWrites = <String, SerialExecutor>{};

  final _registry = JsonStore('sources.json');

  /// Manifests and last known account states keyed by script and runtime hash, so launch reads
  /// them instead of starting a WebView for every source.
  final _manifestStore = JsonStore('source_manifests.json');
  Map<String, dynamic> _manifestCache = {};

  /// Runtimes are started on first use and released when idle (see [_trimRuntimes]).
  final _activations = <String, Future<void>>{};
  final _lastUsed = <String, DateTime>{};
  final _accountCheckedAt = <String, DateTime>{};
  Timer? _trimTimer;

  /// Keys whose manifests were loaded, replaced or removed.
  final _manifestChanges = StreamController<Set<String>>.broadcast(sync: true);
  Stream<Set<String>> get manifestChanges => _manifestChanges.stream;

  ValueListenable<AccountStatus?>? accountListenable(String key) =>
      _sources[key]?.accountListenable;
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
      final cache = await _manifestStore.load();
      _manifestCache = cache is Map ? cache.cast<String, dynamic>() : {};
      JsEngine.instance.onPersist = _persistData;
      // A crashed or timed-out runtime is discarded; the next call starts a fresh one.
      JsEngine.instance.onRestarted = (key) => unawaited(
        _mutate(() async {
          _activations.remove(key)?.ignore();
          await JsEngine.instance.disposeRuntime(key);
        }, key: key),
      );
      await loadAll();
    } catch (_) {
      initializationError = SourceError('CONFIG', '站点加载失败，请重试');
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
    _manifestChanges.add(_sources.keys.toSet());
    notifyListeners();
  }

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
        _changingSources.add(key);
        try {
          return await action();
        } finally {
          _changingSources.remove(key);
        }
      });
    }
    final pendingLocal = _sourceMutations.values.map((q) => q.settled).toList();
    return _mutations.run(() async {
      await Future.wait(pendingLocal);
      await Future.wait(_activeCalls.toList());
      return action();
    });
  }

  // Implemented by the part mixins.
  Future<void> _recoverInstall();
  Future<void> _loadSavedStates();
  Future<Map<String, dynamic>> _loadState(String key);
  Future<void> _persistData(
    String key,
    Map<String, dynamic> data, {
    bool flush = false,
  });
  Map<String, dynamic> settingsOf(String key);
  Future<void> _load(InstalledSource s, {bool waitForInit = false});
  void _cacheManifest(InstalledSource s);
  Future<Object?> _call(
    String key,
    String method,
    List<Object?> args, {
    CancelToken? cancelToken,
  });
  Future<void> refreshAccount(String key);
}
