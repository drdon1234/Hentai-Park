import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app_updater.dart';
import 'background_downloads.dart';
import 'http_service.dart';

class AppInstallFailure implements Exception {
  const AppInstallFailure(this.message);
  final String message;
}

/// 检查版本不使用此服务。只有用户确认后才下载并打开系统安装程序。
class AppInstaller {
  AppInstaller({
    Future<Directory> Function()? cache,
    Future<List<String>> Function()? abis,
    Future<void> Function(String, String, CancelToken, void Function(int, int))?
    download,
    Future<bool> Function(File, String)? install,
    Future<void> Function()? openPermission,
    bool? supported,
    String? platform,
    String? architecture,
  }) : _platform = platform ?? Platform.operatingSystem,
       _architecture = architecture ?? _currentArchitecture(),
       _cache = cache ?? _updateCache,
       _abis =
           abis ??
           (() async =>
               await _channel.invokeListMethod<String>('appUpdateAbis') ?? []),
       _download = download ?? _downloadAsset,
       _install =
           install ??
           ((file, version) => _installPackage(
             file,
             version,
             platform ?? Platform.operatingSystem,
           )),
       _openPermission =
           openPermission ??
           (() => _channel.invokeMethod<void>('appUpdatePermission')),
       supported = supported ?? _supportsCurrentPlatform();

  static const _channel = MethodChannel('hentai_park/platform');
  final bool supported;
  final String _platform, _architecture;
  bool get desktop => _platform == 'windows';
  final Future<Directory> Function() _cache;
  final Future<List<String>> Function() _abis;
  final Future<void> Function(
    String,
    String,
    CancelToken,
    void Function(int, int),
  )
  _download;
  final Future<bool> Function(File, String) _install;
  final Future<void> Function() _openPermission;

  Future<File> prepare(
    AppRelease release,
    CancelToken token,
    void Function(int, int) progress,
  ) async {
    final lease = await BackgroundDownloads.instance.acquire(
      cancelToken: token,
    );
    try {
      return await _prepare(release, token, (done, total) {
        lease.reportProgress(done, total);
        progress(done, total);
      });
    } finally {
      await lease.release();
    }
  }

  Future<File> _prepare(
    AppRelease release,
    CancelToken token,
    void Function(int, int) progress,
  ) async {
    final asset = await selectAsset(release);
    if (token.cancelError != null) throw token.cancelError!;
    if (asset == null) throw const AppInstallFailure('没有适合此设备的安装包，请前往官方发布页下载');
    final directory = await _cache();
    await directory.create(recursive: true);
    // 每次确认创建独立目录，取消和失败只清理自己的临时文件。
    final session = await directory.createTemp('update-');
    final partial = File(p.join(session.path, 'update.part'));
    final complete = File(
      p.join(session.path, 'update${p.extension(asset.name)}'),
    );
    try {
      await _download(asset.url.toString(), partial.path, token, (
        received,
        total,
      ) {
        if (received > asset.size) {
          throw const AppInstallFailure('安装包校验失败，请重新下载');
        }
        progress(received, asset.size);
      });
      if (token.cancelError != null) throw token.cancelError!;
      if (await partial.length() != asset.size ||
          (await sha256.bind(partial.openRead()).first).toString() !=
              asset.sha256) {
        throw const AppInstallFailure('安装包校验失败，请重新下载');
      }
      if (token.cancelError != null) throw token.cancelError!;
      return await partial.rename(complete.path);
    } catch (_) {
      await session.delete(recursive: true);
      rethrow;
    }
  }

  Future<AppReleaseAsset?> selectAsset(AppRelease release) async {
    if (!supported) return null;
    final suffix = switch ((_platform, _architecture)) {
      ('windows', 'x64') => '-windows-x64-setup.exe',
      _ => null,
    };
    if (desktop) {
      return suffix == null
          ? null
          : release.assets
                .where((asset) => asset.name.endsWith(suffix))
                .firstOrNull;
    }
    if (_platform != 'android') return null;
    final abis = await _abis();
    for (final abi in abis) {
      for (final asset in release.assets) {
        if (asset.name.endsWith('-$abi.apk')) {
          return asset;
        }
      }
    }
    return release.assets
        .where((a) => a.name.endsWith('-universal.apk'))
        .firstOrNull;
  }

  /// false 表示需要用户先授权，再明确点击继续安装。
  Future<bool> install(File file, String version) => _install(file, version);
  Future<void> openPermission() => _openPermission();

  /// 仅清理本服务创建的单次下载目录，不触及其他缓存或用户文件。
  Future<void> discard(File file) async {
    final root = await _cache();
    if (!await root.exists() || !await file.exists()) return;
    final rootPath = await root.resolveSymbolicLinks();
    final filePath = await file.resolveSymbolicLinks();
    final session = p.dirname(filePath);
    if (p.dirname(session) != rootPath ||
        !p.basename(session).startsWith('update-') ||
        !const {'update.apk', 'update.exe'}.contains(p.basename(filePath))) {
      return;
    }
    await Directory(session).delete(recursive: true);
  }

  static Future<Directory> _updateCache() async => Directory(
    p.join((await getApplicationCacheDirectory()).path, 'app_updates'),
  );
  static Future<void> _downloadAsset(
    String url,
    String path,
    CancelToken token,
    void Function(int, int) progress,
  ) => HttpService.instance.download(
    url: url,
    savePath: path,
    cancelToken: token,
    onProgress: progress,
  );
  static Future<bool> _installPackage(
    File file,
    String version,
    String platform,
  ) async {
    if (platform == 'android') {
      return await _channel.invokeMethod<bool>('appUpdateInstall', {
            'path': file.path,
            'version': version.split('+').first,
          }) ??
          false;
    }
    if (platform == 'windows' && p.extension(file.path) == '.exe') {
      await Process.start(file.path, [
        '/DIR=${p.dirname(Platform.resolvedExecutable)}',
        '/NORESTART',
        '/NOCLOSEAPPLICATIONS',
      ], mode: ProcessStartMode.detached);
      return true;
    }
    throw const AppInstallFailure('没有适合此设备的安装包，请前往官方发布页下载');
  }

  static String _currentArchitecture() => switch (Abi.current()) {
    Abi.windowsX64 => 'x64',
    _ => '',
  };

  static bool _supportsCurrentPlatform() =>
      Platform.isAndroid ||
      (Platform.isWindows && _currentArchitecture() == 'x64');
}
