import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/async_tasks.dart';
import '../core/storage.dart';

/// 海报是独立的本机展示资产，不进入源设置和凭据，也不保存外部文件路径。
class SourcePosterStore extends ChangeNotifier {
  static final instance = SourcePosterStore();
  final _writes = SerialExecutor();
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
        notifyListeners();
      });

  Future<void> useAutomatic(String source) => _writes.run(() async {
    final file = localFile(source);
    if (await file.exists()) await file.delete();
    notifyListeners();
  });
}
