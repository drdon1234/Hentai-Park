import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../core/app_log.dart';
import '../core/models.dart';
import '../core/storage.dart';
import '../engine/background_downloads.dart';
import '../engine/media_transport_factory.dart';
import '../engine/source_manager.dart';
import '../video/hls.dart';
import '../video/hls_recording.dart';

enum RecordingStatus { recording, stopping, finished, interrupted, failed }

class LiveRecording {
  LiveRecording({
    required this.id,
    required this.item,
    required this.directory,
    required this.startedAt,
    this.status = RecordingStatus.recording,
    this.seconds = 0,
    this.bytes = 0,
  });
  final String id;
  final WorkItem item;
  final Directory directory;
  final DateTime startedAt;
  RecordingStatus status;
  double seconds;
  int bytes;
  bool get active =>
      status == RecordingStatus.recording || status == RecordingStatus.stopping;
  final cancel = CancelToken();
  Future<void>? operation;

  Map<String, Object?> toJson() => {
    'id': id,
    'item': item.toJson(),
    'directory': directory.path,
    'startedAt': startedAt.toIso8601String(),
    'status': status.name,
    'seconds': seconds,
    'bytes': bytes,
  };

  Future<List<File>> volumes() async {
    if (!await directory.exists()) return [];
    final files = await directory
        .list(followLinks: false)
        .where(
          (entry) =>
              entry is File &&
              RegExp(r'^\d+\.m3u8$').hasMatch(p.basename(entry.path)),
        )
        .cast<File>()
        .toList();
    files.sort(
      (a, b) =>
          int.parse(p.basenameWithoutExtension(a.path))
              .compareTo(int.parse(p.basenameWithoutExtension(b.path))),
    );
    return files;
  }
}

/// 录制独立于播放器生命周期；重启只恢复成品，不重新连接直播。
class LiveRecordings extends ChangeNotifier {
  LiveRecordings({BackgroundDownloads? background})
    : _background = background ?? BackgroundDownloads.instance;
  static final instance = LiveRecordings();
  final BackgroundDownloads _background;
  final _store = JsonStore('recordings.json');
  final _tasks = <LiveRecording>[];
  final _starting = <String>{};
  final _unrestored = <Map>[];
  bool _loaded = false;
  List<LiveRecording> get tasks => List.unmodifiable(_tasks);
  LiveRecording? activeFor(String uid) =>
      _tasks.where((task) => task.item.uid == uid && task.active).firstOrNull;

  Future<void> load() async {
    if (_loaded) return;
    final data = await _store.load();
    if (data is! List) {
      _loaded = true;
      return;
    }
    for (final row in data.whereType<Map>()) {
      try {
        final id = row['id'] as String;
        if (_tasks.any((task) => task.id == id)) continue;
        final directory = Directory(row['directory'] as String);
        if (!RegExp(r'^[0-9a-f-]{36}$').hasMatch(id) ||
            !p.isAbsolute(directory.path) ||
            p.basename(directory.path) != id) {
          _unrestored.add(row);
          continue;
        }
        final savedStatus = RecordingStatus.values.byName(
          row['status'] as String,
        );
        final task = LiveRecording(
          id: id,
          item: WorkItem.fromStored(
            (row['item'] as Map).cast<String, dynamic>(),
          ),
          directory: directory,
          startedAt: DateTime.parse(row['startedAt'] as String),
          status:
              savedStatus == RecordingStatus.recording ||
                  savedStatus == RecordingStatus.stopping
              ? RecordingStatus.interrupted
              : savedStatus,
        );
        // 进程可能在分片提交后、元数据刷新前被关闭，按本地成品恢复统计。
        for (final file in await task.volumes()) {
          final playlist = HlsPlaylist.parse(
            await file.readAsString(),
            Uri.parse('https://offline.park.invalid/index.m3u8'),
          );
          for (final segment in playlist.segments) {
            final relative =
                '${p.basename(file.path)}.part.hls/${p.posix.basename(segment.url.path)}';
            final media = File(p.join(directory.path, relative));
            task.seconds += segment.duration;
            task.bytes += await media.length();
          }
        }
        _tasks.add(task);
      } catch (error) {
        _unrestored.add(row);
        // 损坏的记录和文件仍留在磁盘，不自动删除。
        AppLog.error(error, event: 'recording_restore');
      }
    }
    _loaded = true;
    notifyListeners();
  }

  void _save() {
    _store.save([..._unrestored, for (final task in _tasks) task.toJson()]);
    notifyListeners();
  }

  Future<void> start(WorkItem item) async {
    if (activeFor(item.uid) != null || !_starting.add(item.uid)) return;
    LiveRecording? task;
    try {
      final manifest = SourceManager.instance.manifest(item.source);
      if (manifest?.isLive != true) throw SourceError('UNSUPPORTED', '仅支持录制直播');
      final id = const Uuid().v4();
      final directory = Directory(
        p.join(AppPaths.downloadRoot.path, 'recordings', id),
      );
      await directory.create(recursive: true);
      await writeFileAtomic(
        File(p.join(directory.path, 'recording.json')),
        utf8.encode(jsonEncode({'id': id})),
      );
      task = LiveRecording(
        id: id,
        item: item,
        directory: directory,
        startedAt: DateTime.now(),
      );
      _tasks.insert(0, task);
      _save();
      await _store.flush();
      final lease = await _background.acquire(
        cancelToken: task.cancel,
        recording: true,
      );
      task.operation = _record(task, lease);
    } catch (_) {
      if (task != null) {
        task.status = task.cancel.isCancelled
            ? RecordingStatus.finished
            : RecordingStatus.failed;
        _save();
      }
      rethrow;
    } finally {
      _starting.remove(item.uid);
    }
  }

  Future<void> _record(LiveRecording task, DownloadLease lease) async {
    var failed = false;
    try {
      await HlsRecording(directory: task.directory).run(
        resolve: () async {
          lease.check();
          final sources = await SourceManager.instance.videos(
            task.item.source,
            task.item.id,
            cancelToken: task.cancel,
            refresh: true,
          );
          lease.check();
          final source =
              sources
                  .where((source) => source.format == 'hls')
                  .where((source) => source.preferred)
                  .firstOrNull ??
              sources.where((source) => source.format == 'hls').firstOrNull;
          if (source == null) throw SourceError('UNSUPPORTED', '直播间暂无可用播放地址');
          if (source.audio != null) {
            throw SourceError('UNSUPPORTED', '此直播的音轨单独存放，暂不支持录制');
          }
          final manifest = SourceManager.instance.manifest(task.item.source);
          if (manifest == null) throw SourceError('CONFIG', '视频站点未加载');
          final url = Uri.parse(source.url);
          return (
            url: url,
            transport: createMediaTransport(
              manifest,
              headers: source.headers,
              initialUrl: url,
              hls: source.hls,
            ),
          );
        },
        cancelToken: task.cancel,
        onProgress: (seconds, bytes) async {
          task.seconds = seconds;
          task.bytes = bytes;
          _save();
        },
      );
    } catch (error, stack) {
      failed = true;
      AppLog.error(
        error,
        event: 'live_recording',
        site: task.item.source,
        stack: error is SourceError ? null : stack,
      );
    } finally {
      task.status = failed
          ? RecordingStatus.failed
          : BackgroundDownloads.interruption(
                  task.cancel.cancelError ?? Object(),
                ) !=
                null
          ? RecordingStatus.interrupted
          : RecordingStatus.finished;
      _save();
      try {
        await _store.flush();
      } catch (error) {
        AppLog.error(error, event: 'recording_save');
      } finally {
        await lease.release();
      }
    }
  }

  Future<void> stop(LiveRecording task) async {
    if (!task.active) return;
    task.status = RecordingStatus.stopping;
    task.cancel.cancel();
    notifyListeners();
    // start() 可能仍在等待后台服务租约。
    while (_starting.contains(task.item.uid)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await task.operation;
  }

  Future<void> stopAll() async {
    await Future.wait([
      for (final task in _tasks.where((task) => task.active).toList())
        stop(task),
    ]);
    await _store.flush();
  }

  Future<void> delete(LiveRecording task) async {
    await stop(task);
    final marker = File(p.join(task.directory.path, 'recording.json'));
    if (await task.directory.exists()) {
      final actual = await task.directory.resolveSymbolicLinks();
      final parent = await task.directory.parent.resolveSymbolicLinks();
      if (p.basename(actual) != task.id ||
          !p.equals(actual, p.join(parent, task.id)) ||
          jsonDecode(await marker.readAsString())['id'] != task.id) {
        throw const FileSystemException('Invalid recording directory');
      }
      await task.directory.delete(recursive: true);
    }
    _tasks.remove(task);
    _save();
    await _store.flush();
  }
}
