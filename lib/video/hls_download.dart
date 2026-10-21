import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../core/models.dart';
import '../engine/media_transport.dart';
import 'hls.dart';
import 'hls_resources.dart';
import 'rou_hls_wrapper.dart';

typedef MediaRemux = Future<void> Function(
  File input,
  File output,
  CancelToken token,
);

Future<void> remuxTransportStream(
  File input,
  File output,
  CancelToken token,
) async {
  if (!Platform.isAndroid) throw SourceError('UNSUPPORTED', 'HLS 下载封装目前仅支持安卓');
  const channel = MethodChannel('hentai_park/media');
  final id = const Uuid().v4();
  if (token.cancelError case final error?) throw error;
  var finished = false;
  final operation = channel.invokeMethod<void>('remux', {
    'id': id,
    'input': input.path,
    'output': output.path,
  });
  final cancelled = token.whenCancel.then((error) async {
    if (!finished) await channel.invokeMethod<void>('cancel', {'id': id});
    throw error;
  });
  try {
    await Future.any([operation, cancelled]);
  } finally {
    // A cancelled task must finish releasing its files before a retry/delete.
    if (token.isCancelled && !finished) {
      try {
        await channel.invokeMethod<void>('cancel', {'id': id});
      } catch (_) {}
      try {
        await operation;
      } catch (_) {}
    }
    finished = true;
  }
  if (token.cancelError case final error?) throw error;
}

/// Validated per-segment state survives pause/restart; no partial MP4 is published.
class HlsDownload {
  HlsDownload(
    this.transport, {
    this.remux = remuxTransportStream,
    this.keepPlaylist = false,
  });
  final MediaTransport transport;
  final MediaRemux remux;
  final bool keepPlaylist;

  static void _check(CancelToken token) {
    if (token.cancelError case final error?) throw error;
  }

  Future<void> run(
    Uri url, {
    required File output,
    required CancelToken cancelToken,
    required void Function(int done, int total, int bytes) onProgress,
  }) async {
    final resources = HlsResources(transport, cancelToken);
    final work = Directory('${output.path}.hls');
    final input = File(p.join(work.path, 'input.ts'));
    final temporary = File('${output.path}.${const Uuid().v4()}.mux');
    var published = false;
    try {
      _check(cancelToken);
      transport.validate(url);
      final response = await transport.fetch(
        url,
        maxBytes: 2 * 1024 * 1024,
        cancelToken: cancelToken,
      );
      final playlist = HlsPlaylist.parse(
        utf8.decode(
          unwrapRouHlsIfWrapped(response.bytes, maxBytes: 2 * 1024 * 1024),
        ),
        response.url,
      );
      resources.validate(playlist);
      final entries = playlist.resources;
      _check(cancelToken);
      await work.create(recursive: true);
      // Reuse only the exact manifest and segment addresses, order and durations.
      final signature = sha256
          .convert(
            utf8.encode(
              jsonEncode([
                url.toString(),
                for (final s in entries)
                  [
                    s.url.toString(),
                    s.duration,
                    if (s.kind != HlsResourceKind.transportStream) s.kind.name,
                    if (s.key != null) ...[
                      s.key.toString(),
                      s.iv!.toList(),
                      s.sequence.toString(),
                    ],
                  ],
              ]),
            ),
          )
          .toString();
      final stateFile = File(p.join(work.path, 'state.json'));
      var saved = <String, dynamic>{};
      if (await stateFile.exists()) {
        try {
          saved = (jsonDecode(await stateFile.readAsString()) as Map)
              .cast<String, dynamic>();
        } catch (_) {}
      }
      final hashes = saved['signature'] == signature && saved['segments'] is Map
          ? (saved['segments'] as Map).cast<String, dynamic>()
          : <String, dynamic>{};
      final total =
          entries.length + 1; // The last step publishes the local media.
      var bytes = 0;
      onProgress(0, total, 0);
      for (var i = 0; i < entries.length; i++) {
        _check(cancelToken);
        final segment = File(p.join(work.path, '$i.${entries[i].extension}'));
        var valid = false;
        if (hashes['$i'] is String &&
            await segment.exists() &&
            await segment.length() <= 32 * 1024 * 1024) {
          try {
            final data = await segment.readAsBytes();
            validateHlsResource(data, entries[i].kind);
            valid = sha256.convert(data).toString() == hashes['$i'];
          } on SourceError {
            valid = false;
          }
        }
        if (!valid) {
          final data = await resources.read(entries[i]);
          _check(cancelToken);
          validateHlsResource(data, entries[i].kind);
          final part = File('${segment.path}.part');
          await part.writeAsBytes(data, flush: true);
          _check(cancelToken);
          if (await segment.exists()) await segment.delete();
          await part.rename(segment.path);
          hashes['$i'] = sha256.convert(data).toString();
          final statePart = File('${stateFile.path}.part');
          await statePart.writeAsString(
            jsonEncode({'signature': signature, 'segments': hashes}),
            flush: true,
          );
          _check(cancelToken);
          if (await stateFile.exists()) await stateFile.delete();
          await statePart.rename(stateFile.path);
        }
        bytes += await segment.length();
        _check(cancelToken);
        onProgress(i + 1, total, bytes);
      }
      if (keepPlaylist) {
        var index = 0;
        final text = playlist.rewrite(
          (resource) =>
              '${Uri.encodeComponent(p.basename(work.path))}/${index++}.${resource.extension}',
        );
        await temporary.writeAsString(text, flush: true);
        _check(cancelToken);
        await temporary.rename(output.path);
        published = true;
        onProgress(total, total, bytes);
        return;
      }
      final sink = await input.open(mode: FileMode.write);
      try {
        for (var i = 0; i < entries.length; i++) {
          await for (final chunk in File(
            p.join(work.path, '$i.${entries[i].extension}'),
          ).openRead()) {
            _check(cancelToken);
            await sink.writeFrom(chunk);
          }
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      _check(cancelToken);
      if (playlist.initialization != null) {
        // 单初始化段的 fMP4 已是完整 MP4 容器，按顺序保留初始化段和片段。
        await input.rename(temporary.path);
      } else {
        await remux(input, temporary, cancelToken);
      }
      _check(cancelToken);
      if (!await temporary.exists() || await temporary.length() == 0) {
        throw SourceError('NETWORK', '视频封装未生成有效文件');
      }
      if (await output.exists()) await output.delete();
      await temporary.rename(output.path);
      published = true;
      onProgress(total, total, bytes);
    } finally {
      resources.clear();
      try {
        await transport.close();
      } finally {
        try {
          if (await temporary.exists()) await temporary.delete();
        } finally {
          if (await input.exists()) await input.delete();
          if (published && !keepPlaylist && await work.exists()) {
            await work.delete(recursive: true);
          }
        }
      }
    }
  }
}
