import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import '../core/models.dart';
import '../core/storage.dart';
import '../engine/media_transport.dart';
import 'hls.dart';
import 'hls_resources.dart';
import 'rou_hls_wrapper.dart';

typedef RecordingStream = ({Uri url, MediaTransport transport});

/// 从首次清单的尾部之后开始录制。每一段提交后，本地卷都是完整的点播包。
/// 进程被杀不需要补写 ENDLIST，也不会把临时签名地址、密钥写到磁盘。
class HlsRecording {
  HlsRecording({
    required this.directory,
    this.maxSegments = 20000,
    this.pollInterval,
  });
  final Directory directory;
  final int maxSegments;
  final Duration? pollInterval;

  Future<void> run({
    required Future<RecordingStream> Function() resolve,
    required CancelToken cancelToken,
    required Future<void> Function(double duration, int bytes) onProgress,
  }) async {
    if (maxSegments < 1 || maxSegments > 20000) {
      throw ArgumentError.value(maxSegments);
    }
    BigInt? last;
    var volume = 0;
    final durations = <double>[];
    var totalDuration = 0.0;
    var totalBytes = 0;
    var failures = 0;
    var boundary = false;
    var resetSequence = false;
    var lastAdvance = DateTime.now();
    await directory.create(recursive: true);
    while (!cancelToken.isCancelled) {
      MediaTransport? transport;
      HlsResources? resources;
      try {
        final stream = await resolve();
        transport = stream.transport;
        if (cancelToken.isCancelled) return;
        resources = HlsResources(transport, cancelToken);
        transport.validate(stream.url);
        while (!cancelToken.isCancelled) {
          final response = await transport.fetch(
            stream.url,
            maxBytes: 2 * 1024 * 1024,
            cancelToken: cancelToken,
          );
          final playlist = HlsPlaylist.parse(
            utf8.decode(
              unwrapRouHlsIfWrapped(response.bytes, maxBytes: 2 * 1024 * 1024),
            ),
            response.url,
            live: true,
          );
          resources.validate(playlist);
          if (last == null ||
              (resetSequence && playlist.segments.last.sequence < last)) {
            // 首次或服务重启后的旧窗口不回录，等待边界之后的新分片。
            last = playlist.segments.last.sequence;
            lastAdvance = DateTime.now();
            boundary = totalBytes > 0;
          } else {
            final discontinuities = <bool>[];
            var nextBoundary = false;
            for (final line in playlist.lines) {
              if (line == '#EXT-X-DISCONTINUITY') nextBoundary = true;
              if (!line.startsWith('#')) {
                discontinuities.add(nextBoundary);
                nextBoundary = false;
              }
            }
            for (var i = 0; i < playlist.segments.length; i++) {
              final segment = playlist.segments[i];
              if (segment.sequence <= last!) continue;
              if (cancelToken.isCancelled) return;
              final data = await resources.read(segment);
              if (cancelToken.isCancelled) return;
              if (durations.length >= maxSegments ||
                  (durations.isNotEmpty &&
                      (boundary ||
                          discontinuities[i] ||
                          segment.sequence != last + BigInt.one))) {
                volume++;
                durations.clear();
              }
              final name = '$volume.m3u8';
              final folder = Directory(
                p.join(directory.path, '$name.part.hls'),
              );
              await folder.create(recursive: true);
              await writeFileAtomic(
                File(p.join(folder.path, '${durations.length}.ts')),
                data,
              );
              durations.add(segment.duration);
              final target = durations.reduce(max).ceil();
              final text = StringBuffer(
                '#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-TARGETDURATION:$target\n#EXT-X-MEDIA-SEQUENCE:0\n#EXT-X-PLAYLIST-TYPE:VOD\n',
              );
              for (var j = 0; j < durations.length; j++) {
                text.writeln('#EXTINF:${durations[j]},');
                text.writeln('$name.part.hls/$j.ts');
              }
              text.writeln('#EXT-X-ENDLIST');
              await writeFileAtomic(
                File(p.join(directory.path, name)),
                utf8.encode(text.toString()),
              );
              totalDuration += segment.duration;
              totalBytes += data.length;
              last = segment.sequence;
              lastAdvance = DateTime.now();
              failures = 0;
              boundary = false;
              await onProgress(totalDuration, totalBytes);
            }
          }
          resetSequence = false;
          if (playlist.lines.contains('#EXT-X-ENDLIST') ||
              cancelToken.isCancelled) {
            return;
          }
          if (DateTime.now().difference(lastAdvance) >
              const Duration(seconds: 60)) {
            resetSequence = true;
            throw SourceError('NETWORK', '直播暂时没有新分片');
          }
          transport.policy.retainSessionResources({
            stream.url,
            response.url,
            for (final s in playlist.segments) ...[
              s.url,
              if (s.key != null) s.key!,
            ],
          });
          resources.retainKeys({
            for (final s in playlist.segments)
              if (s.key != null) s.key!,
          });
          final target = int.parse(
            playlist.lines
                .firstWhere((line) => line.startsWith('#EXT-X-TARGETDURATION:'))
                .split(':')
                .last,
          );
          await _wait(
            pollInterval ??
                Duration(milliseconds: (target * 500).clamp(500, 10000)),
            cancelToken,
          );
        }
      } catch (error) {
        if (cancelToken.isCancelled) return;
        // 断线或签名过期重新解析媒体，已提交分片不重复写入。
        if (error is FileSystemException ||
            (error is SourceError &&
                error.code != 'NETWORK' &&
                error.code != 'HTTP') ||
            ++failures > 5) {
          rethrow;
        }
        boundary = totalBytes > 0;
      } finally {
        resources?.clear();
        await transport?.close();
      }
      await _wait(Duration(seconds: min(15, failures * 2)), cancelToken);
      lastAdvance = DateTime.now();
    }
  }

  static Future<void> _wait(Duration duration, CancelToken token) async {
    if (token.isCancelled) return;
    final done = Completer<void>();
    final timer = Timer(duration, () => done.complete());
    try {
      await Future.any([done.future, token.whenCancel]);
    } finally {
      timer.cancel();
    }
  }
}
