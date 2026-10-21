import 'dart:convert';
import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart' as wv;
import 'package:path/path.dart' as p;

import '../core/app_log.dart';
import '../core/models.dart';
import '../core/storage.dart';
import 'browser_fetcher.dart';
import 'cookie_snapshot.dart';
import 'domains.dart';
import 'source_identity.dart' as identity;

/// Persistent cookies for native requests, partitioned per source: every source has its own jar,
/// so one source can never send or read another source's login cookies. App-level requests
/// (repository downloads etc.) use [appPartition].
///
/// The WebView cookie store is process-wide; cookies are mirrored into it only for a source's own
/// domains (browser-mode sources, Cloudflare verification and web logins rely on it).
class CookieStore {
  CookieStore._();
  static final CookieStore instance = CookieStore._();

  static const appPartition = identity.appPartition;

  final Map<String, PersistCookieJar> _jars = {};
  final Map<String, Set<Uri>> _browserUris = {};
  final Map<String, int> _generations = {};
  final Map<String, Future<void>> _operations = {};
  final _browserSessions = <Future<void> Function(String)>{};

  /// 权限来自已安装源，不能采用调用脚本提供的域名列表。
  List<String>? Function(String partition)? domainsForPartition;
  void Function() registerBrowserSession(Future<void> Function(String) close) {
    _browserSessions.add(close);
    return () => _browserSessions.remove(close);
  }

  Future<T> _serialize<T>(String partition, Future<T> Function() action) {
    partition = partition.isEmpty ? appPartition : partition;
    final operation = (_operations[partition] ?? Future<void>.value()).then(
      (_) => action(),
    );
    _operations[partition] = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  int generation(String partition) =>
      _generations[partition.isEmpty ? appPartition : partition] ?? 0;

  void _invalidateSession(String partition) {
    final name = partition.isEmpty ? appPartition : partition;
    _generations[name] = generation(name) + 1;
  }

  Directory get _root => Directory(p.join(AppPaths.data.path, 'cookie_jars'));

  Future<void> init() async {
    _jars.clear();
    _browserUris.clear();
    _generations.clear();
    _operations.clear();
    await _root.create(recursive: true);
  }

  PersistCookieJar jar(String partition) {
    final name = partition.isEmpty ? appPartition : partition;
    return _jars.putIfAbsent(
      name,
      () => PersistCookieJar(
        storage: FileStorage(_partitionDirectory(name).path),
      ),
    );
  }

  Future<String> headerFor(Uri uri, {required String partition}) async {
    final cookies = await _serialize(
      partition,
      () => _forRequest(uri, partition),
    );
    return cookies.map((c) => '${c.name}=${c.value}').join('; ');
  }

  Future<List<Cookie>> _forRequest(Uri uri, String partition) async {
    if (!{'http', 'https'}.contains(uri.scheme)) return [];
    final j = jar(partition);
    final cookies = await j.loadForRequest(uri);
    final expiry = Map<Cookie, bool>.identity();
    // PersistCookieJar loads host JSON through a cast view. Recast the nested
    // map as dynamic values, just as its request selector does, before iteration.
    for (final hosts in [j.hostCookies, j.domainCookies]) {
      for (final paths in hosts.values) {
        for (final values
            in paths.cast<String, Map<String, dynamic>>().values) {
          for (final stored in values.values.whereType<SerializableCookie>()) {
            expiry[stored.cookie] = stored.isExpired();
          }
        }
      }
    }
    return cookies.where((cookie) {
      if (cookie.secure && uri.scheme != 'https') return false;
      // 依赖的 Secure 分支也会放行过期 Cookie，按原始创建时间检查 Max-Age。
      return expiry[cookie] == false;
    }).toList();
  }

  void checkBrowserUri(Uri uri, String partition) {
    final domains = domainsForPartition?.call(partition);
    if (!{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        domains == null ||
        !hostInDomains(uri.host, domains)) {
      throw SourceError('CONFIG', '浏览器地址不在站点声明的域名范围内');
    }
  }

  void trackBrowserUri(Uri uri, String partition) {
    checkBrowserUri(uri, partition);
    (_browserUris[partition] ??= {}).add(uri);
  }

  Future<void> saveFromResponse(
    Uri uri,
    List<String> setCookies, {
    required String partition,
    int? requestGeneration,
  }) async {
    final acceptedGeneration = requestGeneration ?? generation(partition);
    final cookies = <Cookie>[];
    for (final line in setCookies) {
      try {
        cookies.add(Cookie.fromSetCookieValue(line));
      } catch (_) {
        // Some sites send cookies dart:io considers invalid (e.g. spaces); keep what we can.
        final pair = line.split(';').first;
        final i = pair.indexOf('=');
        if (i > 0) {
          try {
            final value = pair
                .substring(i + 1)
                .trim()
                .replaceAll(RegExp(r'[\s",;\\]'), '');
            cookies.add(
              Cookie.fromSetCookieValue(
                '${pair.substring(0, i).trim()}=$value${line.substring(pair.length)}',
              ),
            );
          } catch (_) {}
        }
      }
    }
    await _serialize(partition, () async {
      if (acceptedGeneration != generation(partition)) return;
      if (cookies.isNotEmpty) {
        await jar(partition).saveFromResponse(uri, cookies);
      }
    });
  }

  Future<Map<String, String>> get(Uri uri, {required String partition}) async {
    final cookies = await _serialize(
      partition,
      () => _forRequest(uri, partition),
    );
    return {for (final c in cookies) c.name: c.value};
  }

  /// Sets cookies on the requested host; never widens a source's subdomain permission.
  Future<void> set(
    Uri uri,
    Map<String, String> values, {
    required String partition,
    bool mirror = true,
  }) async {
    if (mirror) checkBrowserUri(uri, partition);
    final acceptedGeneration = generation(partition);
    await _serialize(partition, () async {
      if (acceptedGeneration != generation(partition)) {
        throw SourceError('CANCELLED', '浏览器会话已关闭');
      }
      // 网页登录已导入真实 Cookie；插件再次确认同值时不能重建成一年期根路径 Cookie。
      final existing = await _forRequest(uri, partition);
      final changed = Map<String, String>.fromEntries(
        values.entries.where(
          (entry) => !existing.any(
            (cookie) => cookie.name == entry.key && cookie.value == entry.value,
          ),
        ),
      );
      final domain = _cookieDomain(uri.host);
      final cookies = changed.entries.map((e) {
        final c = Cookie(e.key, e.value)
          ..domain = domain
          ..path = '/'
          ..expires = DateTime.now().add(const Duration(days: 365));
        return c;
      }).toList();
      if (cookies.isNotEmpty) {
        await jar(partition).saveFromResponse(uri, cookies);
      }
      if (mirror) {
        trackBrowserUri(uri, partition);
        await _mirrorToWebView(uri, changed);
        await _restoreToWebView(uri, partition);
      }
    });
  }

  Future<void> clear(
    Uri uri, {
    required String partition,
    bool mirror = true,
  }) async {
    _invalidateSession(partition);
    await _serialize(partition, () async {
      await jar(partition).delete(uri, true);
      if (mirror && _webViewSupported) {
        try {
          await wv.CookieManager.instance().deleteCookies(
            url: wv.WebUri(uri.toString()),
            domain: _cookieDomain(uri.host),
          );
        } catch (error) {
          AppLog.error(error, event: 'cookie_clear');
          rethrow;
        }
      }
    });
  }

  /// Removes every cookie of a partition (source uninstalled or "clear cookies" in storage settings).
  Future<void> clearPartition(String partition) {
    _invalidateSession(partition);
    return _serialize(partition, () => _clearPartition(partition));
  }

  Future<void> _clearPartition(String partition) async {
    final snapshot = _snapshotCookies(await _snapshotPartition(partition));
    final domains = domainsForPartition?.call(partition) ?? const <String>[];
    final sharedPartitions = _browserUris.keys
        .where(
          (key) =>
              _browserUris[key]!.any((uri) => hostInDomains(uri.host, domains)),
        )
        .toList();
    await Future.wait([
      for (final key in {partition, ...sharedPartitions})
        ..._browserSessions.toList().map((close) => close(key)),
    ]);
    final browserUris = _browserUris.remove(partition) ?? <Uri>{};
    final hosts = <String>{
      for (final uri in browserUris) uri.host,
      ...domains,
      ...BrowserFetcher.instance.hostsForDomains(domains),
      for (final cookie in snapshot.values)
        if (hostInDomains(cookie.host, domains)) cookie.host,
    };
    // 先终止旧网页请求，防止清除后迟到的响应重新建立登录态。
    await BrowserFetcher.instance.clearDomains(hosts);
    if (_webViewSupported && hosts.isNotEmpty) {
      final manager = wv.CookieManager.instance();
      final addresses = <Uri>{
        for (final host in hosts) Uri(scheme: 'https', host: host, path: '/'),
        ...browserUris,
      };
      for (final uri in addresses) {
        final host = uri.host;
        for (final cookie in await manager.getCookies(
          url: wv.WebUri(uri.toString()),
        )) {
          final domain =
              cookie.domain?.replaceFirst(RegExp(r'^\.'), '') ?? host;
          if (!hostInDomains(host, [domain])) continue;
          await _deleteBrowserCookie(
            manager,
            uri,
            cookie.name,
            cookie.domain,
            cookie.path ??
                (uri.path.endsWith('/') ? uri.path : uri.resolve('.').path),
            domains,
          );
        }
      }
      // 已持久化的非根路径 Cookie 不能仅通过根 URL 枚举。
      for (final entry in snapshot.values) {
        if (!hostInDomains(entry.host, domains)) continue;
        final cookie = entry.value.cookie;
        await _deleteBrowserCookie(
          manager,
          Uri(scheme: 'https', host: entry.host, path: cookie.path ?? '/'),
          cookie.name,
          cookie.domain,
          cookie.path ?? '/',
          domains,
        );
      }
    }
    final name = partition.isEmpty ? appPartition : partition;
    final j = _jars.remove(name) ?? jar(name);
    _jars.remove(name);
    await j.deleteAll();
  }

  Future<void> _deleteBrowserCookie(
    wv.CookieManager manager,
    Uri uri,
    String name,
    String? domain,
    String path,
    List<String> domains,
  ) async {
    final identities = <String?>{domain};
    // Android 只返回 name/value，枚举权限范围内的 host-only 和 Domain 身份。
    if (domain == null) {
      final labels = uri.host.split('.');
      for (var start = 0; start < labels.length; start++) {
        final candidate = labels.sublist(start).join('.');
        if (!hostInDomains(candidate, domains)) continue;
        identities.add(candidate);
        identities.add('.$candidate');
      }
    }
    for (final identity in identities) {
      await manager.deleteCookie(
        url: wv.WebUri(uri.toString()),
        name: name,
        domain: identity,
        path: path,
      );
    }
  }

  Directory _partitionDirectory(String key) {
    final name = identity.sourceIdentity(key.isEmpty ? appPartition : key);
    final root = p.normalize(p.absolute(_root.path));
    final path = p.normalize(p.join(root, name));
    if (!p.isWithin(root, path)) throw ArgumentError.value(key, 'key');
    return Directory(path);
  }

  /// Exact files for one source's install journal; cookie_jar persists UTF-8 JSON.
  Future<Map<String, String>> snapshotPartition(String key) =>
      _serialize(key, () => _snapshotPartition(key));

  Future<Map<String, String>> _snapshotPartition(String key) async {
    final directory = _partitionDirectory(key);
    if (!await directory.exists()) return {};
    final snapshot = <String, String>{};
    await for (final entry in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entry is File) {
        snapshot[p
            .relative(entry.path, from: directory.path)
            .replaceAll('\\', '/')] = await entry
            .readAsString();
      }
    }
    return snapshot;
  }

  static void validateSnapshot(Object? snapshot, {List<String>? domains}) =>
      validateCookieSnapshot(snapshot, domains: domains);

  /// Restore only this native jar and the affected browser cookie identities.
  Future<void> restorePartition(
    String key,
    Map<String, String> snapshot, {
    List<String> domains = const [],
    Map<String, String>? browserSnapshot,
  }) async {
    _invalidateSession(key);
    await _serialize(key, () async {
      final directory = _partitionDirectory(key);
      for (final path in snapshot.keys) {
        if (p.isAbsolute(path) ||
            !p.isWithin(
              directory.path,
              p.normalize(p.join(directory.path, path)),
            )) {
          throw ArgumentError.value(path, 'snapshot');
        }
      }
      final current = await _snapshotPartition(key);
      if (domains.isNotEmpty) {
        final shared = {
          key,
          for (final entry in _browserUris.entries)
            if (entry.value.any((uri) => hostInDomains(uri.host, domains)))
              entry.key,
        };
        await Future.wait([
          for (final partition in shared)
            for (final close in _browserSessions.toList()) close(partition),
        ]);
        await BrowserFetcher.instance.clearDomains(domains);
      }
      // Mirror first so a failed restore can retry using the unchanged candidate files.
      await _restoreBrowserCookies(
        current,
        snapshot,
        domains,
        attempted: browserSnapshot,
      );
      _jars.remove(key.isEmpty ? appPartition : key);
      if (await directory.exists()) await directory.delete(recursive: true);
      for (final entry in snapshot.entries) {
        final file = File(p.join(directory.path, entry.key));
        await file.parent.create(recursive: true);
        await writeFileAtomic(file, utf8.encode(entry.value));
      }
    });
  }

  static Map<String, ({String host, SerializableCookie value})>
  _snapshotCookies(Map<String, String> snapshot) {
    final cookies = <String, ({String host, SerializableCookie value})>{};
    void add(String host, Object? paths) {
      if (paths is! Map) return;
      for (final values in paths.values.whereType<Map>()) {
        for (final value in values.values.whereType<String>()) {
          final stored = SerializableCookie.fromJson(value);
          final cookie = stored.cookie;
          final domain = cookie.domain ?? host;
          final id =
              '${domain.toLowerCase()}\n${cookie.path ?? '/'}\n${cookie.name}';
          cookies[id] = (
            host: host.replaceFirst(RegExp(r'^\.'), ''),
            value: stored,
          );
        }
      }
    }

    for (final file in snapshot.entries) {
      final name = p.basename(file.key);
      if (name == '.index') continue;
      final data = jsonDecode(file.value);
      if (name == '.domains') {
        for (final entry in (data as Map).entries) {
          add(entry.key as String, entry.value);
        }
      } else {
        add(name, data);
      }
    }
    return cookies;
  }

  Future<Map<String, String>> authenticationValues(
    String key,
    List<String> names,
  ) async => {
    for (final entry in _snapshotCookies(await snapshotPartition(key)).entries)
      if (names.contains(entry.value.value.cookie.name))
        entry.key: entry.value.value.cookie.value,
  };

  Future<void> _restoreBrowserCookies(
    Map<String, String> current,
    Map<String, String> snapshot,
    List<String> domains, {
    Map<String, String>? attempted,
  }) async {
    if (!_webViewSupported || domains.isEmpty) return;
    final before = {
      ..._snapshotCookies(current),
      if (attempted != null) ..._snapshotCookies(attempted),
    };
    final restored = _snapshotCookies(snapshot);
    for (final id in {...before.keys, ...restored.keys}) {
      if (attempted == null &&
          before[id]?.value.toJson() == restored[id]?.value.toJson()) {
        continue;
      }
      final previous = restored[id];
      final target = previous ?? before[id]!;
      if (!hostInDomains(target.host, domains)) continue;
      final cookie = target.value.cookie;
      final url = wv.WebUri('https://${target.host}${cookie.path ?? '/'}');
      final manager = wv.CookieManager.instance();
      if (previous == null || previous.value.isExpired()) {
        await manager.deleteCookie(
          url: url,
          name: cookie.name,
          domain: cookie.domain,
          path: cookie.path ?? '/',
        );
      } else {
        // Convert Max-Age to its original expiry instead of restarting its lifetime.
        final expiry = cookie.maxAge == null
            ? cookie.expires?.millisecondsSinceEpoch
            : (target.value.createTimeStamp + cookie.maxAge!) * 1000;
        await manager.setCookie(
          url: url,
          name: cookie.name,
          value: cookie.value,
          domain: cookie.domain,
          path: cookie.path ?? '/',
          expiresDate: expiry,
          isSecure: cookie.secure,
          isHttpOnly: cookie.httpOnly,
        );
      }
    }
  }

  /// 恢复浏览器丢失的持久凭证，不覆盖浏览器刚轮换的新值。
  Future<void> restoreToWebView(Uri uri, {required String partition}) async {
    checkBrowserUri(uri, partition);
    final acceptedGeneration = generation(partition);
    await _serialize(partition, () async {
      if (acceptedGeneration != generation(partition)) {
        throw SourceError('CANCELLED', '浏览器会话已关闭');
      }
      await _restoreToWebView(uri, partition);
    });
  }

  Future<void> _restoreToWebView(Uri uri, String partition) async {
    trackBrowserUri(uri, partition);
    if (!_webViewSupported) return;
    final manager = wv.CookieManager.instance();
    final current = await manager.getCookies(url: wv.WebUri(uri.toString()));
    final cookies = await _forRequest(uri, partition);
    final stored = _snapshotCookies(await _snapshotPartition(partition));
    for (final cookie in cookies) {
      if (current.any((c) => _browserCookieMatches(c, cookie, uri))) {
        continue;
      }
      int? expiry = cookie.expires?.millisecondsSinceEpoch;
      if (cookie.maxAge != null) {
        for (final value in stored.values) {
          final saved = value.value.cookie;
          if (saved.name == cookie.name &&
              saved.domain == cookie.domain &&
              saved.path == cookie.path) {
            expiry = (value.value.createTimeStamp + cookie.maxAge!) * 1000;
            break;
          }
        }
      }
      await manager.setCookie(
        url: wv.WebUri(uri.toString()),
        name: cookie.name,
        value: cookie.value,
        domain: cookie.domain,
        path: cookie.path ?? '/',
        expiresDate: expiry,
        isSecure: cookie.secure,
        isHttpOnly: cookie.httpOnly,
      );
    }
  }

  bool _browserCookieMatches(wv.Cookie browser, Cookie native, Uri uri) =>
      browser.name == native.name &&
      (browser.path == null || browser.path == (native.path ?? '/')) &&
      (browser.domain == null ||
          browser.domain!.replaceFirst(RegExp(r'^\.'), '') ==
              (native.domain ?? uri.host).replaceFirst(RegExp(r'^\.'), ''));

  /// Copies cookies from the WebView store (after a Cloudflare check or web login) into a source's jar.
  Future<Map<String, String>> importFromWebView(
    Uri uri, {
    required String partition,
    bool authoritative = false,
  }) async {
    checkBrowserUri(uri, partition);
    final acceptedGeneration = generation(partition);
    trackBrowserUri(uri, partition);
    if (!_webViewSupported) return {};
    final list = await wv.CookieManager.instance().getCookies(
      url: wv.WebUri(uri.toString()),
    );
    checkBrowserUri(uri, partition);
    if (acceptedGeneration != generation(partition)) {
      throw SourceError('CANCELLED', '浏览器会话已关闭');
    }
    final domains = domainsForPartition!(partition)!;
    final allowed = list.where((c) {
      final domain = c.domain?.replaceFirst(RegExp(r'^\.'), '') ?? uri.host;
      return _validCookie(c.name, c.value.toString()) &&
          !(c.isSecure == true && uri.scheme != 'https') &&
          hostInDomains(uri.host, [domain]) &&
          hostInDomains(domain, domains) &&
          (c.expiresDate == null ||
              c.expiresDate! > DateTime.now().millisecondsSinceEpoch);
    }).toList();
    final values = <String, String>{
      for (final c in allowed) c.name: c.value.toString(),
    };
    await _serialize(partition, () async {
      checkBrowserUri(uri, partition);
      if (acceptedGeneration != generation(partition)) {
        throw SourceError('CANCELLED', '浏览器会话已关闭');
      }
      final removed = <Cookie>[];
      final previous = await _forRequest(uri, partition);
      final stored = _snapshotCookies(await _snapshotPartition(partition));
      final imported = <Cookie>[];
      for (final c in allowed) {
        final candidates = previous
            .where((old) => _browserCookieMatches(c, old, uri))
            .toList();
        // 缺失属性时只恢复已知身份，不把非根路径或 Domain 凭证改成根路径 host-only。
        final matches = candidates.where((old) => old.value == c.value);
        final old = matches.firstOrNull ?? candidates.firstOrNull;
        final metadataMissing =
            c.path == null &&
            c.domain == null &&
            c.isSecure == null &&
            c.isHttpOnly == null;
        DateTime? expiry = c.expiresDate != null
            ? DateTime.fromMillisecondsSinceEpoch(c.expiresDate!)
            : metadataMissing
            ? old?.expires
            : null;
        if (metadataMissing && old?.maxAge != null) {
          final saved = stored.values
              .where(
                (entry) =>
                    entry.host ==
                        (old!.domain ?? uri.host).replaceFirst(
                          RegExp(r'^\.'),
                          '',
                        ) &&
                    entry.value.cookie.name == old.name &&
                    entry.value.cookie.path == old.path &&
                    entry.value.cookie.domain == old.domain,
              )
              .firstOrNull;
          if (saved != null) {
            expiry = DateTime.fromMillisecondsSinceEpoch(
              (saved.value.createTimeStamp + old!.maxAge!) * 1000,
            );
          }
        }
        imported.add(
          Cookie(c.name, c.value.toString())
            ..domain = metadataMissing ? old?.domain : c.domain
            ..path = c.path ?? old?.path ?? '/'
            ..secure = c.isSecure ?? old?.secure ?? (uri.scheme == 'https')
            ..httpOnly = c.isHttpOnly ?? old?.httpOnly ?? true
            ..expires = expiry,
        );
      }
      if (authoritative) {
        for (final old in previous) {
          if (allowed.any((c) => _browserCookieMatches(c, old, uri))) {
            continue;
          }
          removed.add(
            Cookie(old.name, '')
              ..domain = old.domain
              ..path = old.path
              ..maxAge = 0
              ..expires = DateTime.fromMillisecondsSinceEpoch(0),
          );
        }
      }
      await jar(partition).saveFromResponse(uri, [...removed, ...imported]);
    });
    return values;
  }

  Future<void> _mirrorToWebView(Uri uri, Map<String, String> values) async {
    if (!_webViewSupported) return;
    for (final e in values.entries) {
      try {
        await wv.CookieManager.instance().setCookie(
          url: wv.WebUri('${uri.scheme}://${uri.host}/'),
          name: e.key,
          value: e.value,
          domain: _cookieDomain(uri.host),
          expiresDate: DateTime.now()
              .add(const Duration(days: 365))
              .millisecondsSinceEpoch,
        );
      } catch (e) {
        AppLog.error(e, event: 'cookie_sync');
      }
    }
  }

  bool _validCookie(String name, String value) {
    try {
      Cookie(name, value);
      return true;
    } catch (_) {
      return false;
    }
  }

  static String _cookieDomain(String host) =>
      host.contains(':') || RegExp(r'^\d+(?:\.\d+){3}$').hasMatch(host)
      ? host
      : '.${host.toLowerCase().replaceFirst(RegExp(r'\.$'), '')}';

  static bool get _webViewSupported =>
      Platform.isAndroid ||
      Platform.isIOS ||
      Platform.isWindows ||
      Platform.isMacOS ||
      Platform.isLinux;
}
