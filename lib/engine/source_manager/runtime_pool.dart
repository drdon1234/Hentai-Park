part of '../source_manager.dart';

const _maxRuntimes = 6;
const _runtimeIdle = Duration(minutes: 5);
const _accountTtl = Duration(minutes: 10);

/// Reads manifests, starts runtimes on first use, releases idle ones and routes every call.
mixin _RuntimePool on _SourceRegistry {
  /// Reads a source's manifest without starting it: from the cache when the script and runtime
  /// are unchanged, otherwise by evaluating the script in a sandbox. Any running runtime for the
  /// key is discarded. [waitForInit] (installation) starts the runtime and waits for its `init`.
  @override
  Future<void> _load(InstalledSource s, {bool waitForInit = false}) async {
    try {
      final code = decodeSourceScript(await _scriptFile(s.key).readAsBytes());
      if (loader != null) {
        s.manifest = await loader!(s.key, code, await _loadState(s.key));
      } else {
        _activations.remove(s.key)?.ignore();
        await JsEngine.instance.disposeRuntime(s.key);
        final hash = sha256Hex(code);
        final runtimeHash = await JsEngine.instance.runtimeHash();
        final cached = _manifestCache[s.key];
        if (waitForInit) {
          final activation = _start(s, code, waitForInit: true);
          _activations[s.key] = activation;
          await activation;
        } else if (cached is Map &&
            cached['sha256'] == hash &&
            cached['runtime'] == runtimeHash &&
            cached['manifest'] is Map) {
          s.manifest = SourceManifest(
            (cached['manifest'] as Map).cast<String, dynamic>(),
          );
        } else {
          final info = await JsEngine.instance.probe(code);
          if (info.key != s.key) {
            throw SourceError(
              'CONFIG',
              '脚本注册的标识（{script}）与安装记录（{installed}）不一致',
              params: {'script': info.key, 'installed': s.key},
            );
          }
          s.manifest = SourceManifest(info.manifest);
        }
        _cacheManifest(s, hash: hash, runtime: runtimeHash);
        final account = cached is Map ? cached['account'] : null;
        if (s.account == null && account is Map) {
          s.accountListenable.value = AccountStatus(
            account['loggedIn'] == true,
            (account['name'] ?? '').toString(),
            configured: account['configured'] == true,
          );
        }
      }
      s.version = s.manifest!.version;
      s.loadFailure = null;
    } catch (e) {
      _activations.remove(s.key)?.ignore();
      s.loadFailure = e is SourceError ? e : SourceError('CONFIG', '$e');
      debugPrint(Diagnostics.error(e));
    }
    _manifestChanges.add({s.key});
  }

  @override
  void _cacheManifest(InstalledSource s, {String? hash, String? runtime}) {
    final entry = {
      ...?(_manifestCache[s.key] as Map?)?.cast<String, dynamic>(),
    };
    if (hash != null) entry['sha256'] = hash;
    if (runtime != null) entry['runtime'] = runtime;
    if (s.manifest != null) entry['manifest'] = s.manifest!.json;
    final account = s.account;
    if (account != null) {
      entry['account'] = {
        'loggedIn': account.loggedIn,
        'name': account.name,
        'configured': account.configured,
      };
    }
    _manifestCache[s.key] = entry;
    _manifestStore.save(_manifestCache);
  }

  /// Starts the runtime of an enabled source: evaluate, attach private state, run `init`.
  Future<void> _start(
    InstalledSource s,
    String code, {
    bool waitForInit = false,
  }) async {
    if (!s.enabled) throw SourceError('CONFIG', '该站点已停用');
    final state = await _loadState(s.key);
    final runtime = JsEngine.instance.runtime(s.key);
    final info = await runtime.loadScript(code);
    // Publish the installed script's verified declaration before its init
    // uses cookies; setup may wait for those browser operations to finish.
    final before = s.manifest?.json;
    s.manifest = SourceManifest(info.manifest);
    s.manifest = SourceManifest(
      await runtime.setup(state, waitForInit: waitForInit),
    );
    _lastUsed[s.key] = DateTime.now();
    _scheduleTrim();
    if (jsonEncode(before) != jsonEncode(s.manifest!.json)) {
      s.version = s.manifest!.version;
      _cacheManifest(s);
      _manifestChanges.add({s.key});
      notifyListeners();
    }
  }

  /// Makes sure the source's runtime is running before a call.
  Future<void> _ensureRuntime(String key) {
    if (loader != null) return Future.value();
    final running = _activations[key];
    if (running != null) return running;
    final s = _sources[key];
    if (s == null) return Future.error(SourceError('CONFIG', '站点未安装'));
    late final Future<void> activation;
    activation = () async {
      final code = decodeSourceScript(await _scriptFile(key).readAsBytes());
      await _start(s, code);
      if (_backgroundKeys == null && s.manifest?.can('status') == true) {
        // First use after launch: refresh the account once the runtime is up.
        unawaited(refreshAccount(key));
      }
    }();
    _activations[key] = activation;
    activation.catchError((Object _) {
      if (identical(_activations[key], activation)) _activations.remove(key);
      unawaited(JsEngine.instance.disposeRuntime(key));
    });
    return activation;
  }

  void _scheduleTrim() {
    _trimTimer ??= Timer.periodic(const Duration(seconds: 30), (_) {
      _trimRuntimes();
      if (_activations.isEmpty) {
        _trimTimer?.cancel();
        _trimTimer = null;
      }
    });
  }

  /// Releases runtimes that have been idle for a while, and the least recently used ones beyond
  /// [_maxRuntimes]. A runtime with calls in flight is never released.
  void _trimRuntimes({DateTime? now}) {
    now ??= DateTime.now();
    bool idle(String key) =>
        !_changingSources.contains(key) &&
        (_activeBySource[key]?.isEmpty ?? true);
    final running = _activations.keys.where(idle).toList()
      ..sort(
        (a, b) => (_lastUsed[a] ?? DateTime(0)).compareTo(
          _lastUsed[b] ?? DateTime(0),
        ),
      );
    var excess = _activations.length - _maxRuntimes;
    for (final key in running) {
      final last = _lastUsed[key] ?? DateTime(0);
      final stale = now.difference(last) > _runtimeIdle;
      final over =
          excess > 0 && now.difference(last) > const Duration(seconds: 20);
      if (!stale && !over) continue;
      excess--;
      // Removing the activation synchronously means a call that starts now builds a new runtime.
      _activations.remove(key)?.ignore();
      unawaited(JsEngine.instance.disposeRuntime(key));
    }
  }

  /// Number of runtimes currently started (diagnostics and tests).
  int get runningRuntimes => _activations.length;

  @override
  Future<Object?> _call(
    String key,
    String method,
    List<Object?> args, {
    CancelToken? cancelToken,
  }) async {
    if (cancelToken?.cancelError case final error?) throw error;
    await awaitCancelled(ready, cancelToken);
    while (true) {
      final pending = _mutations.settled;
      final local = _sourceMutations[key]?.settled;
      await awaitCancelled(pending, cancelToken);
      if (local != null) await awaitCancelled(local, cancelToken);
      if (identical(pending, _mutations.settled) &&
          identical(local, _sourceMutations[key]?.settled)) {
        break;
      }
    }
    final finished = Completer<void>();
    if (cancelToken?.cancelError case final error?) throw error;
    // Registered before the runtime starts so an idle trim never releases it mid-call.
    _activeCalls.add(finished.future);
    (_activeBySource[key] ??= {}).add(finished.future);
    try {
      await _ensureRuntime(key);
    } catch (_) {
      _activeCalls.remove(finished.future);
      _activeBySource[key]?.remove(finished.future);
      finished.complete();
      rethrow;
    }
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
    try {
      return await JsEngine.instance.invoke(
        key,
        method,
        args,
        cancelToken: readToken,
      );
    } on SourceError catch (error) {
      // Errors raised by the plugin are worded in its own copy.
      final copy = manifest(key)?.copy;
      if (copy == null) rethrow;
      throw error.withCopy(copy);
    } finally {
      _activeCalls.remove(finished.future);
      _activeBySource[key]?.remove(finished.future);
      finished.complete();
      await cancellation?.cancel();
      if (isRead) _readRequests[key]?.remove(readToken);
      _lastUsed[key] = DateTime.now();
      final checked = _accountCheckedAt[key];
      if (readToken?.isCancelled != true &&
          _backgroundKeys == null &&
          !method.startsWith('account.') &&
          checked != null &&
          DateTime.now().difference(checked) > _accountTtl) {
        unawaited(refreshAccount(key));
      }
    }
  }
}
