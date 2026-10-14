part of '../source_manager.dart';

/// Previews, installs, updates, restores and removes source scripts, with crash recovery.
mixin _SourceInstaller on _SourceRegistry {
  Future<List<RepoEntry>> fetchRepository(String url) async {
    final res = await HttpService.instance.send(method: 'GET', url: url);
    if (!res.ok) {
      throw SourceError(
        'HTTP',
        '仓库返回 HTTP {status}',
        params: {'status': res.status},
      );
    }
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
    if (!res.ok) {
      throw SourceError(
        'HTTP',
        '下载失败：HTTP {status}',
        params: {'status': res.status},
      );
    }
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
      throw SourceError('CONFIG', '脚本校验失败：内容与站点仓库公布的 SHA-256 不一致，可能被篡改');
    }
    final info = await JsEngine.instance.probe(code);
    final manifest = SourceManifest(info.manifest);
    final domains = declaredDomains(info.manifest);
    final warnings = <String>[];
    final existing = _sources[info.key];
    if (_builtinKeys.contains(info.key) && existing?.origin == 'builtin') {
      warnings.add(
        tr('将替换内置站点「{name}」，并保留它的登录状态与设置', {'name': existing!.name}),
      );
    } else if (existing != null) {
      warnings.add(
        tr('将更新已安装的「{name}」（v{from} → v{to}），并保留它的登录状态', {
          'name': existing.name,
          'from': existing.version,
          'to': manifest.version,
        }),
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
        warnings.add(
          tr('声明的站点与「{site}」重叠：{domains}', {
            'site': other.name,
            'domains': shared.join(tr('、')),
          }),
        );
      }
    }
    if (domains.isEmpty) warnings.add(tr('没有声明所属站点，无法使用 Cookie 同步与浏览器模式'));
    if (manifest.usesBrowserNetwork) {
      warnings.add(tr('使用浏览器模式联网（在内置浏览器中发出请求）'));
    }
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
      throw SourceError('CONFIG', '上次站点更新尚未恢复，请重启应用后重试');
    }
    final key = preview.key;
    if (!isSourceKey(key) || sha256Hex(preview.code) != preview.sha256) {
      throw SourceError('CONFIG', '站点脚本的标识或校验值无效');
    }
    final existing = _sources[key];
    if (official &&
        (existing == null ||
            (expectedSource != null &&
                (!identical(existing, expectedSource) ||
                    existing.version != expectedVersion ||
                    existing.origin != expectedOrigin)) ||
            !{'builtin', 'official'}.contains(existing.origin) ||
            !SourceManager.isNewer(
              preview.manifest.version,
              existing.version,
            ))) {
      throw SourceError('CONFIG', '站点已变化，请重新检查更新');
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
      if (s.loadFailure case final failure?) throw failure;
      if (s.manifest?.json['key'] != key ||
          s.version != preview.manifest.version ||
          s.manifest?.json['apiVersion'] !=
              preview.manifest.json['apiVersion']) {
        throw SourceError('CONFIG', '站点加载结果与更新信息不一致');
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
      throw SourceError('CONFIG', '站点脚本的标识或校验值无效');
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

  @override
  Future<void> _recoverInstall() async {
    final file = AppPaths.dataFile('source_install.json');
    if (!await file.exists()) return;
    final journal = (jsonDecode(await file.readAsString()) as Map)
        .cast<String, dynamic>();
    await _restoreInstall(journal);
    await file.delete();
  }

  /// Removes a source together with everything it stored: runtime, settings, private store and cookies.
  Future<void> uninstall(String key) => _mutate(() async {
    _activations.remove(key)?.ignore();
    _manifestCache.remove(key);
    _manifestStore.save(_manifestCache);
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
    _manifestChanges.add({key});
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
}
