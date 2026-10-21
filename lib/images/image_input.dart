import 'dart:io';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:pasteboard/pasteboard.dart';

import 'search_image.dart';

/// 系统选图、拖放及复制文件共用大小限制；所有输入仍需经过图片解码。
abstract final class ImageInput {
  static Future<Uint8List> readFile(XFile file) async {
    if (await file.length() > SearchImage.maxInputBytes) {
      throw const FormatException();
    }
    // 流式限量读取，避免检查后文件增长导致无界分配。
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in file.openRead()) {
      if (bytes.length + chunk.length > SearchImage.maxInputBytes) {
        throw const FormatException();
      }
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  }

  static Future<Uint8List?> readClipboard() async {
    // 资源管理器复制的文件优先，避免将文件缩略图当成原图。
    final files = await Pasteboard.files();
    if (files.isNotEmpty) {
      if (files.length != 1 || !File(files.single).isAbsolute) {
        throw const FormatException();
      }
      return readFile(XFile(files.single));
    }
    return Pasteboard.image;
  }
}
