part of '../source_manager.dart';

/// Login, logout, managed accounts and the cached account state.
mixin _SourceAccounts on _SourceRegistry {
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
    final wasLoggedIn = accountListenable(key)?.value?.loggedIn;
    final res = await _call(key, 'account.login', [values]);
    await refreshAccount(key);
    if (wasLoggedIn == accountListenable(key)?.value?.loggedIn) {
      authenticationChanged(key);
    }
    return res is Map ? (res['name'] ?? '').toString() : '';
  }

  Future<void> logout(String key) async {
    final wasLoggedIn = accountListenable(key)?.value?.loggedIn;
    await _call(key, 'account.logout', []);
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
  /// launch and when the last check is older than [_accountTtl]; ordinary calls never trigger it.
  @override
  Future<void> refreshAccount(String key) async {
    final s = _sources[key];
    if (s?.manifest?.can('status') != true) return;
    _accountCheckedAt[key] = DateTime.now();
    AccountStatus status;
    try {
      final res = (await _call(key, 'account.status', []) as Map?) ?? {};
      status = AccountStatus(
        res['loggedIn'] == true,
        (res['name'] ?? '').toString(),
        configured: res['configured'] == true || res['loggedIn'] == true,
      );
    } catch (_) {
      status = AccountStatus(false, '');
    }
    final old = s!.account;
    if (old?.loggedIn == status.loggedIn &&
        old?.name == status.name &&
        old?.configured == status.configured) {
      return;
    }
    s.accountListenable.value = status;
    if (old?.loggedIn != status.loggedIn) authenticationChanged(key);
    if (loader == null) _cacheManifest(s);
  }
}
