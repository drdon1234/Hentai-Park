import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import '../core/models.dart';
import '../core/storage.dart';
import 'hls.dart';
import 'hls_download.dart';
import 'hls_fragment.dart';
import 'playback_cache.dart';

typedef HlsWindowRemux = Future<HlsFragmentTiming> Function(
  File input,
  File output,
  CancelToken token, {
  int prefixBytes,
});

class _WindowJob {
  _WindowJob(this.index);
  final int index;
  final token = CancelToken();
  final done = Completer<void>();
  bool running = false;
}

/// 有限窗口按需封装。完整 VOD 时间轴只登记路由，不触发全片下载。
class HlsWindows {
  HlsWindows(
    this.list,
    this.root,
    this.disk,
    this.read, {
    this.remux = remuxTransportStreamFragment,
  });

  final HlsPlaylist list;
  final Uri root;
  final SegmentCache? disk;
  final Future<Uint8List> Function(HlsSegment, CancelToken) read;
  final HlsWindowRemux remux;
  final _jobs = <int, _WindowJob>{};
  final _memory = <String, Uint8List>{};
  Uint8List? _bootstrap;
  Uint8List? _initialization;
  (CancelToken, Future<Uint8List>)? _priming;
  bool _closed = false;
  int _focus = 0;
  int _prefetchEnd = 0;
  int _running = 0;
  int _bytes = 0;
  static const _limit = 24 * 1024 * 1024;
  static const _parallelWindows = 2;
  static const _maxAhead = 4;
  static const _aheadSeconds = 20.0;

  String playlist() {
    return [
      '#EXTM3U',
      '#EXT-X-VERSION:7',
      '#EXT-X-PLAYLIST-TYPE:VOD',
      '#EXT-X-TARGETDURATION:${list.segments.map((s) => s.duration).reduce(max).ceil()}',
      '#EXT-X-MEDIA-SEQUENCE:0',
      '#EXT-X-MAP:URI="$_initUrl"',
      for (var i = 0; i < list.segments.length; i++) ...[
        '#EXTINF:${list.segments[i].duration.toStringAsFixed(6)},',
        '${_url(i)}',
      ],
      '#EXT-X-ENDLIST',
      '',
    ].join('\n');
  }

  Uri get _initUrl => root.resolve('init.mp4');
  Uri _url(int index) => root.resolve('w$index.m4s');

  int? _index(String path) {
    final match = RegExp(r'^w(\d+)\.m4s$').firstMatch(p.posix.basename(path));
    final index = match == null ? null : int.tryParse(match[1]!);
    return index != null &&
            index < list.segments.length &&
            path == _url(index).path
        ? index
        : null;
  }

  bool contains(String path) => path == _initUrl.path || _index(path) != null;

  Future<Uint8List> resource(String path) async {
    if (path == _initUrl.path) {
      while (!_closed && _initialization == null) {
        try {
          await _ensure(_focus);
        } catch (error) {
          final cancelled =
              error is DioException && CancelToken.isCancel(error) ||
              error is SourceError && error.code == 'CANCELLED';
          if (_closed || !cancelled) rethrow;
        }
      }
      if (_closed) throw SourceError('CANCELLED', '媒体会话已关闭');
      return _initialization!;
    }
    final index = _index(path);
    if (_closed || index == null) throw SourceError('CANCELLED', '媒体会话已关闭');
    _focus = index;
    _prefetchEnd = index;
    var ahead = 0.0;
    while (_prefetchEnd + 1 < list.segments.length &&
        _prefetchEnd - index < _maxAhead &&
        ahead < _aheadSeconds) {
      ahead += list.segments[++_prefetchEnd].duration;
    }
    for (final job in _jobs.values.toList()) {
      if (!_wanted(job.index)) {
        _cancelJob(job, 'window superseded');
      }
    }
    // 先登记当前请求，再启动有界预取；下载可与当前窗口的封装重叠。
    final demanded = _ensure(index);
    for (var next = index + 1; next <= _prefetchEnd; next++) {
      _ensure(next).ignore();
    }
    await demanded;
    final bytes = await _cached(path);
    if (bytes == null) throw SourceError('NETWORK', 'HLS 分段不完整');
    return bytes;
  }

  bool _wanted(int index) => index >= _focus - 1 && index <= _prefetchEnd;

  void _cancelJob(_WindowJob job, String reason) {
    job.token.cancel(reason);
    if (!job.running) {
      if (identical(_jobs[job.index], job)) _jobs.remove(job.index);
      if (!job.done.isCompleted) job.done.completeError(job.token.cancelError!);
    }
  }

  void _pump() {
    if (_closed) return;
    final waiting = _jobs.values.where((job) => !job.running).toList()
      ..sort((a, b) {
        int priority(_WindowJob job) =>
            job.index >= _focus ? job.index - _focus : _maxAhead + 1;
        return priority(a).compareTo(priority(b));
      });
    for (final job in waiting) {
      if (_running >= _parallelWindows) break;
      if (job.token.isCancelled) continue;
      job.running = true;
      _running++;
      unawaited(_run(job));
    }
  }

  Future<void> _run(_WindowJob job) async {
    try {
      await _build(job.index, job.token);
      job.done.complete();
    } catch (error, stack) {
      job.done.completeError(error, stack);
    } finally {
      if (identical(_jobs[job.index], job)) _jobs.remove(job.index);
      _running--;
      _pump();
    }
  }

  Future<Uint8List?> _cached(String path) async {
    final bytes = _memory.remove(path);
    if (bytes != null) {
      _memory[path] = bytes;
      return bytes;
    }
    return disk?.read(path);
  }

  Future<void> _store(String path, Uint8List bytes) async {
    await disk?.store(path, bytes);
    if (_closed) return;
    _bytes -= _memory.remove(path)?.length ?? 0;
    while (_memory.isNotEmpty && _bytes + bytes.length > _limit) {
      _bytes -= _memory.remove(_memory.keys.first)!.length;
    }
    // 超出内存额度的窗口只存磁盘。
    if (bytes.length > _limit) {
      if (disk == null) throw SourceError('UNSUPPORTED', 'HLS 使用了不支持的媒体格式');
      return;
    }
    _memory[path] = bytes;
    _bytes += bytes.length;
  }

  Future<void> _ensure(int index) async {
    if (_closed) throw SourceError('CANCELLED', '媒体会话已关闭');
    if (_jobs[index] case final job?) {
      if (!job.token.isCancelled) return job.done.future;
      try {
        await job.done.future;
      } catch (_) {}
      if (identical(_jobs[index], job)) _jobs.remove(index);
      if (_closed) throw SourceError('CANCELLED', '媒体会话已关闭');
    }
    if (_initialization != null && await _cached(_url(index).path) != null) {
      return;
    }
    // _cached 有异步磁盘读取，登记前再次合并并发请求。
    if (_closed) throw SourceError('CANCELLED', '媒体会话已关闭');
    if (!_wanted(index)) {
      throw SourceError('CANCELLED', '请求已取消');
    }
    if (_jobs[index] case final job?) return job.done.future;
    final job = _WindowJob(index);
    _jobs[index] = job;
    _pump();
    return job.done.future;
  }

  void _check(CancelToken token) {
    if (token.cancelError case final error?) throw error;
    if (_closed) throw SourceError('CANCELLED', '媒体会话已关闭');
  }

  Future<Uint8List> _prime(CancelToken token) async {
    if (_bootstrap case final bytes?) return bytes;
    // 失败或跳转取消后允许重试，不保留失败 Future。
    final operation = _priming ??= (token, read(list.segments.first, token));
    try {
      return _bootstrap = await operation.$2;
    } catch (_) {
      _check(token);
      if (!operation.$1.isCancelled) rethrow;
      if (identical(_priming, operation)) _priming = null;
      // 另一个窗口的下载可能刚被跳转取消，本窗口使用自己的令牌重取。
      return _prime(token);
    } finally {
      if (identical(_priming, operation)) _priming = null;
    }
  }

  Future<void> _build(int index, CancelToken token) async {
    final work = await Directory(p.join(AppPaths.cache.path, 'playback'))
        .create(recursive: true);
    final temp = await work.createTemp('window-');
    final input = File(p.join(temp.path, 'input.ts'));
    final output = File(p.join(temp.path, 'output.mp4'));
    try {
      final bootstrap = await _prime(token);
      _check(token);
      // 一个原始分片就是一个窗口，避免等待多段下载才向播放器返回数据。
      final bytes = index == 0
          ? bootstrap
          : await read(list.segments[index], token);
      _check(token);
      final sink = await input.open(mode: FileMode.write);
      try {
        if (index > 0) await sink.writeFrom(bootstrap);
        await sink.writeFrom(bytes);
      } finally {
        await sink.close();
      }
      _check(token);
      final timing = await remux(
        input,
        output,
        token,
        prefixBytes: index == 0 ? 0 : bootstrap.length,
      );
      _check(token);
      final (init, media) = splitHlsFragment(
        await output.readAsBytes(),
        timing: timing,
      );
      _initialization ??= init;
      await _store(_url(index).path, media);
    } finally {
      token.cancel('window finished');
      await temp.delete(recursive: true);
    }
  }

  Future<void> close() async {
    _closed = true;
    final jobs = _jobs.values.toList();
    for (final job in jobs) {
      _cancelJob(job, 'playback closed');
    }
    await Future.wait(
      jobs.map((job) => job.done.future.catchError((Object _) {})),
    );
    _memory.clear();
    _bootstrap = null;
    _initialization = null;
    _bytes = 0;
  }
}
