import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/models.dart';
import '../core/settings.dart';
import '../core/storage.dart';
import '../engine/media_transport.dart';
import '../engine/network_client.dart';
import '../engine/source_manager.dart';
import '../library/downloads.dart' show DownloadManager, DownloadStatus;

class GameDownloadTask {
  static String fileName(String value) {
    var name = p
        .basename(value.replaceAll('\\', '/'))
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_')
        .trim()
        .replaceAll(RegExp(r'[. ]+$'), '');
    if (name.isEmpty || name == '.' || name == '..') name = 'game.bin';
    if (RegExp(
      r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)',
      caseSensitive: false,
    ).hasMatch(name)) {
      name = '_$name';
    }
    if (name.length > 180) {
      name =
          '${name.substring(0, 150)}${p.extension(name).substring(0, p.extension(name).length.clamp(0, 20))}';
    }
    return name;
  }

  GameDownloadTask._({
    required this.item,
    required this.resourceId,
    required this.channelId,
    required this.filename,
    required this.directory,
    required this.createdAt,
    this.status = DownloadStatus.queued,
    this.bytes = 0,
    this.total = 0,
  });
  factory GameDownloadTask.create(
    WorkItem item,
    GameResource resource,
    GameChannel channel,
    Directory root,
  ) {
    final filename = fileName(channel.label);
    return GameDownloadTask._(
      item: item,
      resourceId: resource.id,
      channelId: channel.id,
      filename: filename.isEmpty ? 'game.bin' : filename,
      directory: p.join(
        root.path,
        'games',
        safeFileName(item.source),
        safeFileName(item.id),
        safeFileName(resource.id),
        safeFileName(channel.id),
      ),
      createdAt: DateTime.now(),
    );
  }
  factory GameDownloadTask.fromJson(Map<String, dynamic> json) {
    final name = json['filename'] as String;
    if (name.isEmpty || name != fileName(name)) {
      throw const FormatException('游戏文件名无效');
    }
    final status = DownloadStatus.values.byName(json['status'] as String);
    final task = GameDownloadTask._(
      item: WorkItem.fromStored((json['item'] as Map).cast<String, dynamic>()),
      resourceId: json['resourceId'] as String,
      channelId: json['channelId'] as String,
      filename: name,
      directory: json['directory'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      status: status == DownloadStatus.done ? status : DownloadStatus.paused,
      bytes: (json['bytes'] as num?)?.toInt() ?? 0,
      total: (json['total'] as num?)?.toInt() ?? 0,
    );
    final expected = p.join(
      'games',
      safeFileName(task.item.source),
      safeFileName(task.item.id),
      safeFileName(task.resourceId),
      safeFileName(task.channelId),
    );
    if (!p.isAbsolute(task.directory) ||
        !p.normalize(task.directory).endsWith('${p.separator}$expected')) {
      throw const FormatException('游戏下载目录无效');
    }
    task.extractionCode = json['extractionCode'] as String? ?? '';
    task.archivePassword = json['archivePassword'] as String? ?? '';
    return task;
  }
  final WorkItem item;
  final String resourceId, channelId, filename, directory;
  final DateTime createdAt;
  DownloadStatus status;
  int bytes, total;
  String? error;
  String extractionCode = '', archivePassword = '';
  String get key => '${item.uid}:$resourceId:$channelId';
  File get file => File(p.join(directory, filename));
  Map<String, dynamic> toJson() => {
    'item': item.toJson(),
    'resourceId': resourceId,
    'channelId': channelId,
    'filename': filename,
    'directory': directory,
    'createdAt': createdAt.toIso8601String(),
    'status': status.name,
    'bytes': bytes,
    'total': total,
    'extractionCode': extractionCode,
    'archivePassword': archivePassword,
  };
}

/// Streams large files without source cookies, memory buffering, or automatic redirects.
class GameFileDownloader {
  GameFileDownloader({Dio? client}) : _client = client ?? _build();
  final Dio _client;
  static Dio _build() =>
      Dio(BaseOptions(connectTimeout: const Duration(seconds: 20)))
        ..httpClientAdapter = IOHttpClientAdapter(
          createHttpClient: () =>
              createHttpClient(proxy: AppSettings.instance.proxy),
        );

  Future<void> download(
    SourceManifest manifest,
    GameResourceLink link,
    File file, {
    required CancelToken cancelToken,
    required void Function(int bytes, int total) onProgress,
  }) async {
    final partial = File('${file.path}.part');
    RandomAccessFile? sink;
    try {
      final policy = MediaPolicy.fromManifest(manifest);
      if (policy.mode != 'native' || link.kind != GameChannelKind.direct) {
        throw SourceError('CONFIG', '该渠道不支持直链下载');
      }
      if (await file.exists()) throw SourceError('CONFIG', '游戏文件已存在');
      var target = Uri.parse(link.url);
      for (var hop = 0; hop < 8; hop++) {
        policy.validate(target);
        if (cancelToken.isCancelled) throw SourceError('CANCELLED', '已取消');
        final requestToken = CancelToken();
        final cancellation = cancelToken.whenCancel.asStream().listen(
          requestToken.cancel,
        );
        try {
          final response = await _client.get<ResponseBody>(
            target.toString(),
            options: Options(
              responseType: ResponseType.stream,
              followRedirects: false,
              validateStatus: (_) => true,
              receiveTimeout: const Duration(seconds: 45),
              headers: {
                'Accept-Encoding': 'identity',
                'Referer': '${policy.origin}/',
              },
            ),
            cancelToken: requestToken,
          );
          final body = response.data;
          if (body == null) throw SourceError('NETWORK', '游戏下载响应为空');
          if (const {301, 302, 303, 307, 308}.contains(response.statusCode)) {
            await body.stream.listen((_) {}).cancel();
            final location = response.headers.value('location');
            if (location == null) throw SourceError('NETWORK', '游戏下载重定向无效');
            target = target.resolve(location);
            continue;
          }
          final type =
              response.headers.value('content-type')?.toLowerCase() ?? '';
          if (response.statusCode != 200 ||
              type.contains('text/') ||
              type.contains('json') ||
              type.contains('html')) {
            await body.stream.listen((_) {}).cancel();
            throw SourceError('NETWORK', '直链下载失败，可重试或选择网盘渠道');
          }
          final length = int.tryParse(
            response.headers.value('content-length') ?? '',
          );
          final encoding = response.headers.value('content-encoding');
          if (encoding != null && encoding != 'identity') {
            await body.stream.listen((_) {}).cancel();
            throw SourceError('NETWORK', '游戏下载响应格式无效');
          }
          await file.parent.create(recursive: true);
          sink = await partial.open(mode: FileMode.write);
          var received = 0;
          Future<void> write() async {
            await for (final chunk in body.stream.timeout(
              const Duration(seconds: 45),
            )) {
              if (cancelToken.isCancelled) {
                throw SourceError('CANCELLED', '已取消');
              }
              await sink!.writeFrom(chunk);
              received += chunk.length;
              if (length != null && received > length) {
                throw SourceError('NETWORK', '游戏文件不完整');
              }
              onProgress(received, length ?? 0);
            }
            await sink!.flush();
          }

          await write();
          if (received == 0 || (length != null && length != received)) {
            throw SourceError('NETWORK', '游戏文件不完整');
          }
          await sink.close();
          sink = null;
          if (cancelToken.isCancelled) throw SourceError('CANCELLED', '已取消');
          // Each channel owns a private directory; a completed file is never overwritten.
          if (await file.exists()) throw SourceError('CONFIG', '游戏文件已存在');
          await partial.rename(file.path);
          return;
        } finally {
          // Dio does not forward stream subscription cancellation to its source.
          requestToken.cancel('game resource finished');
          await requestToken.whenCancel;
          await cancellation.cancel();
        }
      }
      throw SourceError('NETWORK', '游戏下载重定向次数过多');
    } catch (error) {
      if (cancelToken.isCancelled) throw SourceError('CANCELLED', '已取消');
      if (error is SourceError) rethrow;
      throw SourceError('NETWORK', '直链下载失败，可重试或选择网盘渠道');
    } finally {
      cancelToken.cancel('game transfer ended');
      await sink?.close();
      if (await partial.exists()) await partial.delete();
      _client.close(force: true);
    }
  }
}

class GameDownloadManager extends ChangeNotifier {
  GameDownloadManager._();
  static final instance = GameDownloadManager._();
  final _store = JsonStore('game_downloads.json');
  final _tasks = <String, GameDownloadTask>{};
  GameDownloadTask? _active;
  CancelToken? _cancel;
  bool _loaded = false;
  List<GameDownloadTask> get tasks =>
      _tasks.values.toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  GameDownloadTask? task(String key) => _tasks[key];
  bool isActive(String key) => _active?.key == key;
  Future<void> load() async {
    final raw = await _store.load();
    for (final entry in raw is List ? raw : const []) {
      try {
        final task = GameDownloadTask.fromJson(
          (entry as Map).cast<String, dynamic>(),
        );
        if (task.status == DownloadStatus.done && !await task.file.exists()) {
          task.status = DownloadStatus.failed;
          task.error = '本地文件已被删除';
        }
        _tasks[task.key] = task;
      } catch (_) {
        /* Invalid records cannot define download destinations. */
      }
    }
    _loaded = true;
    DownloadManager.instance.addListener(_networkChanged);
    notifyListeners();
  }

  void _save() => _store.save(tasks.map((t) => t.toJson()).toList());
  Future<void> flush() => _store.flush();
  Future<void> enqueue(
    WorkItem item,
    GameResource resource,
    GameChannel channel,
  ) async {
    if (!_loaded) throw SourceError('CONFIG', '游戏下载器尚未就绪');
    if (channel.kind != GameChannelKind.direct) {
      throw SourceError('CONFIG', '该渠道不支持直链下载');
    }
    final task = GameDownloadTask.create(
      item,
      resource,
      channel,
      AppPaths.downloadRoot,
    );
    if (_tasks.containsKey(task.key)) {
      retry(task.key);
      return;
    }
    _tasks[task.key] = task;
    _save();
    await flush();
    notifyListeners();
    _pump();
  }

  void retry(String key) {
    final task = _tasks[key];
    if (task == null || task == _active || task.status == DownloadStatus.done) {
      return;
    }
    task.status = DownloadStatus.queued;
    task.error = null;
    task.bytes = 0;
    task.total = 0;
    _save();
    notifyListeners();
    _pump();
  }

  void cancel(String key) {
    final task = _tasks[key];
    if (task == null || task.status == DownloadStatus.done) return;
    task.status = DownloadStatus.paused;
    if (task == _active) _cancel?.cancel('user cancelled');
    _save();
    notifyListeners();
  }

  Future<void> remove(String key) async {
    if (_active?.key == key) throw SourceError('CONFIG', '请先取消下载并等待结束');
    // Removing the record keeps the user's downloaded file intact.
    _tasks.remove(key);
    _save();
    await flush();
    notifyListeners();
  }

  void _networkChanged() {
    if (!DownloadManager.instance.networkAllowed &&
        _active?.status == DownloadStatus.running) {
      _active!.status = DownloadStatus.queued;
      _cancel?.cancel('waiting for Wi-Fi');
    }
    _pump();
  }

  void _pump() {
    if (_active != null || !DownloadManager.instance.networkAllowed) return;
    final task = tasks
        .where((t) => t.status == DownloadStatus.queued)
        .firstOrNull;
    if (task != null) unawaited(_run(task));
  }

  Future<void> _run(GameDownloadTask task) async {
    _active = task;
    final token = _cancel = CancelToken();
    task.status = DownloadStatus.running;
    task.error = null;
    notifyListeners();
    try {
      final sources = SourceManager.instance;
      await sources.ready;
      final manifest = sources.manifest(task.item.source);
      if (manifest == null || !manifest.isGame) {
        throw SourceError('CONFIG', '游戏站点未加载');
      }
      final link = await sources.resolveGameResource(
        task.item.source,
        task.item.id,
        task.resourceId,
        task.channelId,
        cancelToken: token,
      );
      task.extractionCode = link.extractionCode;
      task.archivePassword = link.archivePassword;
      _save();
      notifyListeners();
      var lastUpdate = DateTime.now();
      await GameFileDownloader().download(
        manifest,
        link,
        task.file,
        cancelToken: token,
        onProgress: (bytes, total) {
          task.bytes = bytes;
          task.total = total;
          if (DateTime.now().difference(lastUpdate).inMilliseconds > 250) {
            lastUpdate = DateTime.now();
            notifyListeners();
          }
        },
      );
      task.status = DownloadStatus.done;
    } catch (_) {
      if (task.status == DownloadStatus.running) {
        task.status = DownloadStatus.failed;
        task.error = '直链下载失败，可重试或选择网盘渠道';
      }
    } finally {
      _active = null;
      _cancel = null;
      _save();
      notifyListeners();
      _pump();
    }
  }
}
