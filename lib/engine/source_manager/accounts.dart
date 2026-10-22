part of '../source_manager.dart';

/// Login, logout, managed accounts and the cached account state.
mixin _SourceAccounts on _SourceRegistry {
  @override
  Future<void> _requireAccount(String key, {CancelToken? cancelToken}) async {
    await awaitCancelled(ready, cancelToken);
    if (manifest(key)?.account?.required != true) return;
    // 首次恢复登录态先完成账号检查；已知游客不启动内容请求或读取旧缓存。
    final account = accountListenable(key)?.value;
    final checked = _accountCheckedAt[key];
    if (_accountRefreshes.containsKey(key) ||
        account == null ||
        checked == null ||
        DateTime.now().difference(checked) > _accountTtl) {
      await awaitCancelled(refreshAccount(key), cancelToken);
    }
    if (cancelToken?.cancelError case final error?) throw error;
    if (accountListenable(key)?.value?.loggedIn != true) {
      throw SourceError('LOGIN_REQUIRED', '这个站点需要登录后才能浏览');
    }
  }

  /// Only called after the user confirmed registration. The preference is durable before JS runs.
  Future<void> setManagedAccount(String key, bool enabled) async {
    await ready;
    await _mutate(() async {
      if (manifest(key)?.account?.managedAccount != true) {
        throw SourceError('UNSUPPORTED', '这个站点不支持自动维护的专用账号');
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
      if (_activations.containsKey(key)) {
        await JsEngine.instance.updateSettings(key, settings);
      }
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

  Future<String> login(String key, Map<String, String> values) async {
    _displayOrder?.invalidate(key);
    // 登录前已启动的状态检查不能代替这次凭证的验证。
    try {
      await _accountRefreshes[key];
    } catch (_) {
      // 旧凭证的网络失败不阻止用户重新登录。
    }
    final wasLoggedIn = accountListenable(key)?.value?.loggedIn;
    AppLog.record({
      'event': 'login',
      'site': key,
      'action': 'account.login',
      'stage': 'verify',
      'outcome': 'started',
    });
    final res = await _call(key, 'account.login', [values]);
    // 登录过程中内容请求也可能触发检查；等它结束后再验证这次登录。
    try {
      await _accountRefreshes[key];
    } catch (_) {
      // 并发旧检查失败时，仍以接下来的新检查为准。
    }
    await refreshAccount(key);
    if (manifest(key)?.can('status') == true &&
        accountListenable(key)?.value?.loggedIn != true) {
      AppLog.record({
        'event': 'login',
        'site': key,
        'action': 'account.login',
        'stage': 'verify',
        'outcome': 'failure',
      });
      throw SourceError(
        'LOGIN_REQUIRED',
        '尚未识别到登录，请确认网页显示账号后点击完成；如有验证提示，请先完成验证',
      );
    }
    if (wasLoggedIn == accountListenable(key)?.value?.loggedIn) {
      authenticationChanged(key);
    }
    AppLog.record({
      'event': 'login',
      'site': key,
      'action': 'account.login',
      'stage': 'complete',
      'outcome': 'success',
    });
    return res is Map ? (res['name'] ?? '').toString() : '';
  }

  Future<void> logout(String key) async {
    _displayOrder?.invalidate(key);
    // 先收束旧状态检查，防止其在退出后重新发布已登录状态。
    try {
      await _accountRefreshes[key];
    } catch (_) {}
    final wasLoggedIn = accountListenable(key)?.value?.loggedIn;
    await _call(key, 'account.logout', []);
    _accountEpochs[key] = (_accountEpochs[key] ?? 0) + 1;
    final source = _sources[key];
    if (source != null) _publishAccountStatus(source, AccountStatus(false, ''));
    _accountCheckedAt.remove(key);
    await CookieStore.instance.clearPartition(key);
    try {
      await _accountRefreshes[key];
    } catch (_) {}
    if (source != null) _publishAccountStatus(source, AccountStatus(false, ''));
    _accountCheckedAt.remove(key);
    if (manifest(key)?.account?.managedAccount == true &&
        settingsOf(key)['managedAccount'] == true) {
      await setManagedAccount(key, false);
    }
    await refreshAccount(key);
    if (wasLoggedIn == accountListenable(key)?.value?.loggedIn) {
      authenticationChanged(key);
    }
  }

  /// Checks the account. Runs after login, logout, web login, on a source's first use after
  /// launch and when the last check is older than [_accountTtl]. Required-account reads wait
  /// for confirmation before they access content or caches.
  @override
  Future<void> refreshAccount(String key) {
    final pending = _accountRefreshes[key];
    if (pending != null) return pending;
    late final Future<void> refresh;
    refresh = _refreshAccount(key).whenComplete(() {
      if (identical(_accountRefreshes[key], refresh)) {
        _accountRefreshes.remove(key);
      }
    });
    _accountRefreshes[key] = refresh;
    return refresh;
  }

  Future<void> _refreshAccount(String key) async {
    final epoch = _accountEpochs[key] ?? 0;
    final s = _sources[key];
    if (s?.manifest?.can('status') != true) return;
    AccountStatus status;
    try {
      final res = (await _call(key, 'account.status', []) as Map?) ?? {};
      status = AccountStatus(
        res['loggedIn'] == true,
        (res['name'] ?? '').toString(),
        configured: res['configured'] == true || res['loggedIn'] == true,
      );
    } catch (_) {
      // 检查失败不代表退出登录；让下一次内容重试重新确认账号。
      _accountCheckedAt.remove(key);
      rethrow;
    }
    if (epoch != (_accountEpochs[key] ?? 0)) return;
    _accountCheckedAt[key] = DateTime.now();
    _publishAccountStatus(s!, status);
  }

  void _publishAccountStatus(InstalledSource source, AccountStatus status) {
    final old = source.account;
    if (old?.loggedIn == status.loggedIn &&
        old?.name == status.name &&
        old?.configured == status.configured) {
      return;
    }
    source.accountListenable.value = status;
    if (old?.loggedIn != status.loggedIn) {
      authenticationChanged(source.key, initial: old == null);
    }
    if (loader == null) _cacheManifest(source);
  }
}
