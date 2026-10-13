import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/async_tasks.dart';
import '../core/storage.dart';

/// 海报是独立的本机展示资产，不进入源设置和凭据，也不保存外部文件路径。
class SourcePosterStore extends ChangeNotifier {
  static final instance = SourcePosterStore();
  final _writes = SerialExecutor();
  final _revisions = <String, int>{};
  int revision(String source) => _revisions[source] ?? 0;
  void _changed(String source) {
    _revisions[source] = revision(source) + 1;
    notifyListeners();
  }

  File _automaticFile(String source) => File(
    p.join(
      AppPaths.data.path,
      'source_posters',
      '${safeFileName(source)}.automatic.json',
    ),
  );

  Future<Map<String, dynamic>?> _automatic(String source) async {
    try {
      return (jsonDecode(await _automaticFile(source).readAsString()) as Map)
          .cast<String, dynamic>();
    } catch (_) {
      return null;
    }
  }

  Future<String?> automaticUrl(String source) async =>
      (await _automatic(source))?['url'] as String?;

  Future<Uint8List?> readImage(String source, String identity) async {
    final file = localFile(source);
    if (await file.exists()) return file.readAsBytes();
    final saved = await _automatic(source);
    if (saved?['identity'] != identity) return null;
    try {
      return base64Decode(saved!['image'] as String);
    } catch (_) {
      return null;
    }
  }

  Future<bool> saveAutomatic(
    String source,
    String identity,
    String url,
    Uint8List bytes, {
    bool replaceManual = false,
    required bool Function() canCommit,
  }) => _writes.run(() async {
    if (!canCommit()) return false;
    if (bytes.isEmpty || bytes.length > 20 * 1024 * 1024) {
      throw const FormatException('海报图片无效或超过20MB');
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final codec = await ui.instantiateImageCodecWithSize(
      buffer,
      getTargetSize: (width, height) {
        final scale = min(1.0, 960 / max(width, height));
        return ui.TargetImageSize(
          width: max(1, (width * scale).round()),
          height: max(1, (height * scale).round()),
        );
      },
    );
    Uint8List image;
    try {
      final frame = await codec.getNextFrame();
      try {
        image = (await frame.image.toByteData(format: ui.ImageByteFormat.png))!
            .buffer
            .asUint8List();
      } finally {
        frame.image.dispose();
      }
    } finally {
      codec.dispose();
    }
    if (image.length > 20 * 1024 * 1024) {
      throw const FormatException('海报图片无效或超过20MB');
    }
    final file = _automaticFile(source);
    await file.parent.create(recursive: true);
    final stored = await writeFileAtomic(
      file,
      utf8.encode(
        jsonEncode({
          'identity': identity,
          'url': url,
          'image': base64Encode(image),
        }),
      ),
      canCommit: canCommit,
    );
    if (!stored) return false;
    if (replaceManual) {
      final manual = localFile(source);
      if (await manual.exists()) await manual.delete();
    }
    _changed(source);
    return true;
  });
  File localFile(String source) => File(
    p.join(
      AppPaths.data.path,
      'source_posters',
      '${safeFileName(source)}.image',
    ),
  );

  Future<void> importImage(String source, Uint8List bytes) =>
      _writes.run(() async {
        if (bytes.isEmpty || bytes.length > 20 * 1024 * 1024) {
          throw const FormatException('海报图片无效或超过20MB');
        }
        // 确认首帧可解码，再写入；失败不会覆盖用户现有图片。
        final codec = await ui.instantiateImageCodec(
          bytes,
          targetWidth: 1920,
          allowUpscaling: false,
        );
        try {
          final frame = await codec.getNextFrame();
          frame.image.dispose();
        } finally {
          codec.dispose();
        }
        final file = localFile(source);
        await file.parent.create(recursive: true);
        await writeFileAtomic(file, bytes);
        _changed(source);
      });

  Future<void> useAutomatic(String source) => _writes.run(() async {
    final file = localFile(source);
    if (await file.exists()) await file.delete();
    _changed(source);
  });
}
