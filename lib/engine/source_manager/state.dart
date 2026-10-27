part of '../source_manager.dart';

/// Per-source settings and private store, and their part of backups.
mixin _SourceState on _SourceRegistry {
  @override
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

  @override
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

  @override
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
        if (_activations.containsKey(key)) {
          await JsEngine.instance.updateSettings(key, settings);
        }
        notifyListeners();
      }, key: key);

  /// Installed sources and their settings; [credentials] also includes each source's private
  /// store (tokens, account ids) and partitioned cookies, which may contain secrets.
  Future<Map<String, dynamic>> exportJson({bool credentials = false}) =>
      _mutate(() async {
        final cookies = <String, Map<String, String>>{};
        if (credentials) {
          await _stopStateWriters(_sources.keys);
          for (final key in {..._sources.keys, ..._state.keys}) {
            final pending = _state[key]?['restoreCookies'];
            cookies[key] = pending is Map
                ? pending.cast<String, String>()
                : await CookieStore.instance.snapshotPartition(key);
          }
        }
        return (jsonDecode(
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
            if (credentials) 'cookies': cookies,
          }),
        ) as Map).cast<String, dynamic>();
      }, invalidate: false);

  Future<
    ({
      Map<String, Object?> files,
      List<({String key, String url})> missing,
      Map<String, ({Map<String, String> snapshot, List<String> domains})>
      cookies,
    })
  >
  prepareImport(Map<String, dynamic> json) async {
    _validateImport(json);
    await _stopStateWriters({
      for (final name in ['settings', 'data', 'cookies'])
        ...(json[name] as Map? ?? {}).keys.cast<String>(),
    });
    final missing = <({String key, String url})>[];
    final files = <String, Object?>{};
    final records = {for (final s in all) s.key: s.toJson()};
    final settings = (json['settings'] as Map?)?.cast<String, dynamic>() ?? {};
    final data = (json['data'] as Map?)?.cast<String, dynamic>() ?? {};
    final cookieData = (json['cookies'] as Map?)?.cast<String, dynamic>() ?? {};
    final cookies =
        <String, ({Map<String, String> snapshot, List<String> domains})>{};
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
    for (final key in {
      ...settings.keys,
      ...data.keys,
      ...metadata.keys,
      ...cookieData.keys,
    }) {
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
        state['data'] = cookieData.containsKey(key)
            ? d.cast<String, dynamic>()
            : {
                ...(state['data'] as Map).cast<String, dynamic>(),
                ...d.cast<String, dynamic>(),
              };
      }
      if (cookieData[key] case final Map snapshot) {
        final installed = manifest(key);
        if (installed == null) {
          state['restoreCookies'] = snapshot;
        } else {
          final domains = declaredDomains(installed.json);
          CookieStore.validateSnapshot(snapshot, domains: domains);
          cookies[key] = (
            snapshot: snapshot.cast<String, String>(),
            domains: domains,
          );
          state.remove('restoreCookies');
        }
      }
      if (!_sources.containsKey(key) && metadata[key] != null) {
        state['restoreMetadata'] = metadata[key];
      }
      files['source_state_$key.json'] = state;
    }
    files['sources.json'] = {'sources': records.values.toList()};
    return (files: files, missing: missing, cookies: cookies);
  }

  Future<void> reloadFromDisk({
    Set<String> credentialsChanged = const {},
  }) async {
    for (final key in credentialsChanged) {
      (_manifestCache[key] as Map?)?.remove('account');
      _accountCheckedAt.remove(key);
    }
    if (credentialsChanged.isNotEmpty) {
      _manifestStore.save(_manifestCache);
      await _manifestStore.flush();
    }
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
    for (final key in credentialsChanged) {
      authenticationChanged(key);
    }
    notifyListeners();
  }

  @override
  Future<void> _restorePendingCookies(
    String key,
    SourceManifest manifest,
  ) async {
    final state = await _loadState(key);
    if (state['restoreCookies'] case final Map snapshot) {
      final domains = declaredDomains(manifest.json);
      CookieStore.validateSnapshot(snapshot, domains: domains);
      await CookieStore.instance.restorePartition(
        key,
        snapshot.cast<String, String>(),
        domains: domains,
        browserSnapshot: const {},
      );
      state.remove('restoreCookies');
      final store = _stateStores[key] ??= JsonStore('source_state_$key.json');
      store.save(state);
      await store.flush();
    }
  }

  /// 后台 init 也能持久化凭据；先释放并排空桥接写入，快照和恢复才不会被旧状态覆盖。
  Future<void> _stopStateWriters(Iterable<String> keys) async {
    for (final key in keys) {
      _activations.remove(key)?.ignore();
      if (loader == null) await JsEngine.instance.disposeRuntime(key);
      await _stateStores[key]?.flush();
    }
  }

  @override
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
    for (final entry in plan.cookies.entries) {
      await CookieStore.instance.restorePartition(
        entry.key,
        entry.value.snapshot,
        domains: entry.value.domains,
      );
    }
    for (final e in plan.files.entries) {
      await writeFileAtomic(
        AppPaths.dataFile(e.key),
        utf8.encode(jsonEncode(e.value)),
      );
    }
    await reloadFromDisk(
      credentialsChanged: {
        ...plan.cookies.keys,
        ...(json['data'] as Map? ?? {}).keys.cast<String>(),
      },
    );
    return plan.missing;
  });
}

/// Rejects malformed source data in a backup before anything is written.
void _validateImport(Map<String, dynamic> json) {
  final cookies = json['cookies'];
  if (cookies != null) {
    if (cookies is! Map) throw const FormatException('备份数据无效');
    for (final entry in cookies.entries) {
      if (!isSourceKey(entry.key)) throw const FormatException('备份数据无效');
      CookieStore.validateSnapshot(entry.value);
    }
  }
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
        (raw['order'] != null && (raw['order'] is! int || raw['order'] < 0)) ||
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
