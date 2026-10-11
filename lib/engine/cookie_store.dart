import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart' as wv;
import 'package:path/path.dart' as p;

import '../core/storage.dart';
import 'domains.dart';

/// Persistent cookies for native requests, partitioned per source: every source has its own jar,
/// so one source can never send or read another source's login cookies. App-level requests
/// (repository downloads etc.) use [appPartition].
///
/// The WebView cookie store is process-wide; cookies are mirrored into it only for a source's own
/// domains (browser-mode sources, Cloudflare verification and web logins rely on it).
class CookieStore {
  CookieStore._();
  static final CookieStore instance = CookieStore._();

  static const appPartition = '_app';

  final Map<String, PersistCookieJar> _jars = {};

  Directory get _root => Directory(p.join(AppPaths.data.path, 'cookie_jars'));
  Directory get _legacy => Directory(p.join(AppPaths.data.path, 'cookies'));

  Future<void> init() async {
    await _root.create(recursive: true);
  }

  PersistCookieJar jar(String partition) {
    final name = partition.isEmpty ? appPartition : partition;
    return _jars.putIfAbsent(name, () => PersistCookieJar(storage: FileStorage(p.join(_root.path, safeFileName(name))), ignoreExpires: false));
  }

  /// Copies the single jar used by older versions into every installed source's partition, so
  /// existing logins keep working, then retires it.
  Future<void> migrateLegacy(Iterable<String> sourceKeys) async {
    if (!await _legacy.exists()) return;
    for (final key in {...sourceKeys, appPartition}) {
      final target = Directory(p.join(_root.path, safeFileName(key)));
      if (await target.exists()) continue;
      await _copyDir(_legacy, target);
    }
    try {
      await _legacy.rename('${_legacy.path}.migrated');
    } catch (e) {
      debugPrint('retire legacy cookies: $e');
    }
    _jars.clear();
  }

  static Future<void> _copyDir(Directory from, Directory to) async {
    await to.create(recursive: true);
    await for (final e in from.list()) {
      final dest = p.join(to.path, p.basename(e.path));
      if (e is Directory) {
        await _copyDir(e, Directory(dest));
      } else if (e is File) {
        await e.copy(dest);
      }
    }
  }

  Future<String> headerFor(Uri uri, {required String partition}) async {
    final cookies = await jar(partition).loadForRequest(uri);
    return cookies.map((c) => '${c.name}=${c.value}').join('; ');
  }

  Future<void> saveFromResponse(Uri uri, List<String> setCookies, {required String partition}) async {
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
            cookies.add(Cookie(pair.substring(0, i).trim(), pair.substring(i + 1).trim().replaceAll(RegExp(r'[\s",;\\]'), '')));
          } catch (_) {}
        }
      }
    }
    if (cookies.isNotEmpty) await jar(partition).saveFromResponse(uri, cookies);
  }

  Future<Map<String, String>> get(Uri uri, {required String partition}) async {
    final cookies = await jar(partition).loadForRequest(uri);
    return {for (final c in cookies) c.name: c.value};
  }

  /// Sets cookies for the whole registrable host (".example.com"); [mirror] also writes them to the WebView store.
  Future<void> set(Uri uri, Map<String, String> values, {required String partition, bool mirror = true}) async {
    final domain = _cookieDomain(uri.host);
    final cookies = values.entries.map((e) {
      final c = Cookie(e.key, e.value)
        ..domain = domain
        ..path = '/'
        ..expires = DateTime.now().add(const Duration(days: 365));
      return c;
    }).toList();
    await jar(partition).saveFromResponse(uri, cookies);
    if (mirror) await _mirrorToWebView(uri, values);
  }

  Future<void> clear(Uri uri, {required String partition, bool mirror = true}) async {
    await jar(partition).delete(uri, true);
    if (mirror && _webViewSupported) {
      try {
        await wv.CookieManager.instance().deleteCookies(url: wv.WebUri(uri.toString()), domain: _cookieDomain(uri.host));
      } catch (_) {}
    }
  }

  /// Removes every cookie of a partition (source uninstalled or "clear cookies" in storage settings).
  Future<void> clearPartition(String partition) async {
    final j = _jars.remove(partition) ?? jar(partition);
    _jars.remove(partition);
    await j.deleteAll();
  }

  /// Copies cookies from the WebView store (after a Cloudflare check or web login) into a source's jar.
  Future<Map<String, String>> importFromWebView(Uri uri, {required String partition}) async {
    if (!_webViewSupported) return {};
    final list = await wv.CookieManager.instance().getCookies(url: wv.WebUri(uri.toString()));
    final values = <String, String>{for (final c in list) c.name: c.value.toString()};
    final domain = _cookieDomain(uri.host);
    await jar(partition).saveFromResponse(uri, [
      for (final c in list)
        if (_validCookie(c.name, c.value.toString()))
          (Cookie(c.name, c.value.toString())
            ..domain = c.domain ?? domain
            ..path = c.path ?? '/'
            ..expires = c.expiresDate != null ? DateTime.fromMillisecondsSinceEpoch(c.expiresDate!) : DateTime.now().add(const Duration(days: 30))),
    ]);
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
          path: '/',
          expiresDate: DateTime.now().add(const Duration(days: 365)).millisecondsSinceEpoch,
        );
      } catch (e) {
        debugPrint('cookie mirror failed: $e');
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

  static String _cookieDomain(String host) => '.${registrableDomain(host)}';

  static bool get _webViewSupported => Platform.isAndroid || Platform.isIOS || Platform.isWindows || Platform.isMacOS;
}
