import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../../core/localization.dart';
import '../../core/platform_capabilities.dart';
import '../theme.dart';

export 'package:share_plus/share_plus.dart' show XFile;

/// 桌面文件使用目录选择和流式复制，避免大文件占满内存。
Future<void> shareContent(
  BuildContext context, {
  List<XFile>? files,
  String? text,
  String? subject,
  Rect? origin,
}) async {
  if (PlatformCapabilities.desktop) {
    if (files != null && files.isNotEmpty) {
      final directory = await FilePicker.getDirectoryPath();
      if (directory == null) return;
      for (final file in files) {
        final source = File(file.path);
        final target = File(p.join(directory, p.basename(file.path)));
        if (p.equals(p.absolute(source.path), p.absolute(target.path))) {
          continue;
        }
        // 使用独占目标创建，不覆盖用户已有资产。
        if (await target.exists()) {
          throw const FileSystemException('Export destination already exists');
        }
        await target.create(exclusive: true);
        try {
          await source.openRead().pipe(target.openWrite());
        } catch (_) {
          if (await target.exists()) await target.delete();
          rethrow;
        }
      }
    } else if (text != null) {
      await Clipboard.setData(ClipboardData(text: text));
      if (context.mounted) context.toast(tr('已复制'));
    }
    return;
  }
  if (!context.mounted) return;
  Rect? resolvedOrigin = origin;
  if (resolvedOrigin == null) {
    final screen = MediaQuery.maybeSizeOf(context);
    final box = context.findRenderObject();
    if (box is RenderBox &&
        box.hasSize &&
        box.size.width > 0 &&
        box.size.height > 0) {
      final rect = box.localToGlobal(Offset.zero) & box.size;
      if (screen != null &&
          rect.width >= screen.width * 0.8 &&
          rect.height >= screen.height * 0.8) {
        resolvedOrigin = Rect.fromCenter(
          center: Offset(screen.width / 2, screen.height / 2),
          width: 1,
          height: 1,
        );
      } else {
        resolvedOrigin = rect;
      }
    } else if (screen != null && screen.width > 0 && screen.height > 0) {
      resolvedOrigin = Rect.fromCenter(
        center: Offset(screen.width / 2, screen.height / 2),
        width: 1,
        height: 1,
      );
    }
  }
  await SharePlus.instance.share(
    ShareParams(
      files: files,
      text: text,
      subject: subject,
      sharePositionOrigin: resolvedOrigin,
    ),
  );
}
