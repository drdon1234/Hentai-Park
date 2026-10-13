import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app_updater.dart';
import 'http_service.dart';

class AppInstallFailure implements Exception {
  const AppInstallFailure(this.message);
  final String message;
}

/// 检查版本不使用此服务。只有用户确认后才准备 APK 和请求系统安装。
class AppInstaller {
  AppInstaller({
    Future<Directory> Function()? cache,
    Future<List<String>> Function()? abis,
    Future<void> Function(String, String, CancelToken, void Function(int, int))?
    download,
    Future<bool> Function(File, String)? install,
    Future<void> Function()? openPermission,
    bool? supported,
  }) : _cache = cache ?? _updateCache,
       _abis =
           abis ??
           (() async =>
               await _channel.invokeListMethod<String>('appUpdateAbis') ?? []),
       _download = download ?? _downloadApk,
       _install = install ?? _installApk,
       _openPermission =
           openPermission ??
           (() => _channel.invokeMethod<void>('appUpdatePermission')),
       supported = supported ?? Platform.isAndroid;

  static const _channel = MethodChannel('hentai_park/platform');
  final bool supported;
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
    final abis = await _abis();
    if (token.cancelError != null) throw token.cancelError!;
    AppApk? apk;
    for (final abi in abis) {
      for (final asset in release.assets) {
        if (asset.name.endsWith('-$abi.apk')) {
          apk = asset;
          break;
        }
      }
      if (apk != null) break;
    }
    apk ??= release.assets
        .where((a) => a.name.endsWith('-universal.apk'))
        .firstOrNull;
    if (apk == null) throw const AppInstallFailure('没有适合此设备的安装包，请前往官方发布页下载');
    final directory = await _cache();
    await directory.create(recursive: true);
    // 每次确认创建独立目录，取消和失败只清理自己的临时文件。
    final session = await directory.createTemp('apk-');
    final partial = File(p.join(session.path, 'update.part'));
    final complete = File(p.join(session.path, 'update.apk'));
    try {
      await _download(apk.url.toString(), partial.path, token, (
        received,
        total,
      ) {
        if (received > apk!.size) {
          throw const AppInstallFailure('安装包校验失败，请重新下载');
        }
        progress(received, apk.size);
      });
      if (token.cancelError != null) throw token.cancelError!;
      if (await partial.length() != apk.size ||
          (await sha256.bind(partial.openRead()).first).toString() !=
              apk.sha256) {
        throw const AppInstallFailure('安装包校验失败，请重新下载');
      }
      if (token.cancelError != null) throw token.cancelError!;
      return await partial.rename(complete.path);
    } catch (_) {
      await session.delete(recursive: true);
      rethrow;
    }
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
        !p.basename(session).startsWith('apk-') ||
        p.basename(filePath) != 'update.apk') {
      return;
    }
    await Directory(session).delete(recursive: true);
  }

  static Future<Directory> _updateCache() async => Directory(
    p.join((await getApplicationCacheDirectory()).path, 'app_updates'),
  );
  static Future<void> _downloadApk(
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
  static Future<bool> _installApk(File file, String version) async =>
      await _channel.invokeMethod<bool>('appUpdateInstall', {
        'path': file.path,
        'version': version.split('+').first,
      }) ??
      false;
}
