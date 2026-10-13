import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pub_semver/pub_semver.dart';

import '../core/settings.dart';
import 'http_service.dart';

class AppRelease {
  const AppRelease({
    required this.version,
    required this.url,
    required this.notes,
    this.assets = const [],
  });

  final String version;
  final Uri url;
  final String notes;
  final List<AppApk> assets;
}

class AppApk {
  const AppApk({
    required this.name,
    required this.url,
    required this.size,
    required this.sha256,
  });
  final String name;
  final Uri url;
  final int size;
  final String sha256;

  static AppApk? parse(Object? data, String tag) {
    if (data is! Map) return null;
    final name = data['name'];
    final rawUrl = data['browser_download_url'];
    final size = data['size'];
    final digest = data['digest'];
    if (name is! String ||
        !RegExp(r'^[A-Za-z0-9._-]+\.apk$').hasMatch(name) ||
        rawUrl is! String ||
        size is! int ||
        size <= 0 ||
        size > 512 * 1024 * 1024 ||
        digest is! String ||
        !RegExp(r'^sha256:[a-fA-F0-9]{64}$').hasMatch(digest)) {
      return null;
    }
    final expected = Uri(
      scheme: 'https',
      host: 'github.com',
      pathSegments: [
        'drdon1234',
        'Hentai-Park',
        'releases',
        'download',
        tag,
        name,
      ],
    );
    if (rawUrl != expected.toString()) return null;
    return AppApk(
      name: name,
      url: expected,
      size: size,
      sha256: digest.substring(7).toLowerCase(),
    );
  }
}

class AppUpdateResult {
  const AppUpdateResult({this.currentVersion, this.release, this.failure});

  final String? currentVersion;
  final AppRelease? release;
  final String? failure;
}

/// 仅检查官方稳定版发布；下载和安装须由界面获得用户确认后处理。
class AppUpdater extends ChangeNotifier {
  AppUpdater({
    Future<String> Function(String url)? read,
    Future<String> Function()? currentVersion,
    bool Function()? autoEnabled,
  }) : _read = read ?? _readOfficialRelease,
       _currentVersion = currentVersion ?? _installedVersion,
       _autoEnabled =
           autoEnabled ?? (() => AppSettings.instance.autoAppUpdates);

  static final instance = AppUpdater();
  static const _latestReleaseUrl =
      'https://api.github.com/repos/drdon1234/Hentai-Park/releases/latest';
  static const _invalidInformation = '软件版本信息无效';
  static const _networkFailure = '无法检查软件更新，请检查网络后重试';

  final Future<String> Function(String url) _read;
  final Future<String> Function() _currentVersion;
  final bool Function() _autoEnabled;
  Future<AppUpdateResult>? _inFlight;
  AppUpdateResult? _lastResult;
  bool _launchChecked = false;
  bool _disposed = false;

  bool get running => _inFlight != null;
  AppUpdateResult? get lastResult => _lastResult;

  /// 手动检查始终执行；并发调用复用同一个结果和请求。
  Future<AppUpdateResult> checkNow() {
    final pending = _inFlight;
    if (pending != null) return pending;
    final completer = Completer<AppUpdateResult>();
    _inFlight = completer.future;
    _notify();
    _check().then((result) {
      _lastResult = result;
      _inFlight = null;
      _notify();
      completer.complete(result);
    });
    return completer.future;
  }

  /// 每次应用启动仅尝试一次；关闭设置不会读取网络或安装版本。
  Future<AppUpdateResult?> checkOnLaunch() {
    if (_launchChecked) return Future.value();
    _launchChecked = true;
    try {
      if (!_autoEnabled()) return Future.value();
      return checkNow();
    } catch (_) {
      return Future.value(const AppUpdateResult(failure: _networkFailure));
    }
  }

  Future<AppUpdateResult> _check() async {
    String? installed;
    String payload;
    try {
      installed = await _currentVersion();
      payload = await _read(_latestReleaseUrl);
    } catch (_) {
      return AppUpdateResult(
        currentVersion: installed,
        failure: _networkFailure,
      );
    }
    try {
      _parseVersion(installed);
      final data = jsonDecode(payload);
      if (data == null || (data is Map && data.isEmpty)) {
        return AppUpdateResult(currentVersion: installed);
      }
      if (data is! Map ||
          data['draft'] is! bool ||
          data['prerelease'] is! bool) {
        throw const FormatException();
      }
      if (data['draft'] == true || data['prerelease'] == true) {
        return AppUpdateResult(currentVersion: installed);
      }
      final tag = data['tag_name'];
      if (tag is! String) throw const FormatException();
      final versionText = tag.startsWith('v') ? tag.substring(1) : tag;
      final version = _parseVersion(versionText);
      if (version.isPreRelease) {
        return AppUpdateResult(currentVersion: installed);
      }
      final rawUrl = data['html_url'];
      if (rawUrl is! String) throw const FormatException();
      final url = Uri.parse(rawUrl);
      if (!_isOfficialReleasePage(rawUrl, url)) throw const FormatException();
      final notes = data['body'];
      if (notes != null && notes is! String) throw const FormatException();
      // pub_semver 对构建号排序；应用升级遵循 SemVer，忽略构建号。
      final precedence = Version.parse(versionText.split('+').first);
      final installedPrecedence = Version.parse(installed.split('+').first);
      return AppUpdateResult(
        currentVersion: installed,
        release: precedence > installedPrecedence
            ? AppRelease(
                version: versionText,
                url: url,
                notes: notes ?? '',
                assets: List.unmodifiable(
                  data['assets'] is List
                      ? (data['assets'] as List)
                            .map((asset) => AppApk.parse(asset, tag))
                            .whereType<AppApk>()
                      : <AppApk>[],
                ),
              )
            : null,
      );
    } on FormatException {
      return AppUpdateResult(
        currentVersion: installed,
        failure: _invalidInformation,
      );
    } catch (_) {
      return AppUpdateResult(
        currentVersion: installed,
        failure: _networkFailure,
      );
    }
  }

  static Version _parseVersion(String text) {
    final match = RegExp(
      r'^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)'
      r'(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?'
      r'(?:\+([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$',
    ).firstMatch(text);
    if (match == null) throw const FormatException();
    final preRelease = match.group(4);
    if (preRelease != null &&
        preRelease
            .split('.')
            .any(
              (part) =>
                  RegExp(r'^[0-9]+$').hasMatch(part) &&
                  part.length > 1 &&
                  part.startsWith('0'),
            )) {
      throw const FormatException();
    }
    return Version.parse(text);
  }

  static bool _isOfficialReleasePage(String rawUrl, Uri url) {
    final segments = url.pathSegments;
    // Uri 会规范化空 userinfo 和默认端口，先校验原文中的 authority。
    return rawUrl.startsWith(
          'https://github.com/drdon1234/Hentai-Park/releases/tag/',
        ) &&
        url.scheme == 'https' &&
        url.host == 'github.com' &&
        url.userInfo.isEmpty &&
        !url.hasPort &&
        !url.hasQuery &&
        !url.hasFragment &&
        segments.length == 5 &&
        segments[0] == 'drdon1234' &&
        segments[1] == 'Hentai-Park' &&
        segments[2] == 'releases' &&
        segments[3] == 'tag' &&
        segments[4].isNotEmpty &&
        segments[4] != '.' &&
        segments[4] != '..' &&
        !segments[4].contains('/') &&
        !segments[4].contains('\\');
  }

  static Future<String> _installedVersion() async =>
      (await PackageInfo.fromPlatform()).version;

  /// 注入的 read 与此保持一致：HTTP 404 返回 'null'，其他失败抛异常。
  static Future<String> _readOfficialRelease(String url) async {
    final response = await HttpService.instance.send(
      method: 'GET',
      url: url,
      headers: const {'Accept': 'application/vnd.github+json'},
      timeout: const Duration(seconds: 15),
    );
    if (response.status == 404) return 'null';
    if (response.status != 200) throw StateError(_networkFailure);
    return response.text;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
