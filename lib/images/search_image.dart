import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// 图片仅在内存中准备；统一重编码，上传时不携带本机路径和原始元数据。
class SearchImage {
  SearchImage._(this.bytes, this.width, this.height);
  static const maxBytes = 1800000;
  static const maxInputBytes = 20 * 1024 * 1024;
  final Uint8List bytes;
  final int width, height;
  String get base64 => base64Encode(bytes);

  static Future<SearchImage> prepare(
    Uint8List input, {
    ui.Rect crop = const ui.Rect.fromLTWH(0, 0, 1, 1),
  }) async {
    if (input.isEmpty ||
        input.length > maxInputBytes ||
        !crop.left.isFinite ||
        !crop.top.isFinite ||
        !crop.right.isFinite ||
        !crop.bottom.isFinite ||
        crop.left < 0 ||
        crop.top < 0 ||
        crop.right > 1 ||
        crop.bottom > 1 ||
        crop.width <= 0 ||
        crop.height <= 0) {
      throw const FormatException('图片无法处理');
    }
    // 常用格式走 CPU 编解码，避免 Android 从系统选图返回时 GPU
    // 表面尚未恢复导致 Picture.toImage/toByteData 偶发失败。
    final prepared = await compute(_prepareRaster, (input, crop));
    if (prepared != null) return prepared;
    final buffer = await ui.ImmutableBuffer.fromUint8List(input);
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? image;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      if (descriptor.width * descriptor.height > 80000000) {
        throw const FormatException('图片无法处理');
      }
      final scale = math.min(
        1.0,
        1800 / math.max(descriptor.width, descriptor.height),
      );
      codec = await descriptor.instantiateCodec(
        targetWidth: math.max(1, (descriptor.width * scale).round()),
        targetHeight: math.max(1, (descriptor.height * scale).round()),
      );
      image = (await codec.getNextFrame()).image;
      final source = ui.Rect.fromLTRB(
        crop.left * image.width,
        crop.top * image.height,
        crop.right * image.width,
        crop.bottom * image.height,
      );
      var width = math.max(1, source.width.round());
      var height = math.max(1, source.height.round());
      while (true) {
        final recorder = ui.PictureRecorder();
        ui.Canvas(recorder).drawImageRect(
          image,
          source,
          ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
          ui.Paint()..filterQuality = ui.FilterQuality.medium,
        );
        final picture = recorder.endRecording();
        ui.Image? output;
        try {
          output = await picture.toImage(width, height);
          final data = await output.toByteData(format: ui.ImageByteFormat.png);
          if (data == null) throw const FormatException('图片无法处理');
          if (data.lengthInBytes <= maxBytes) {
            return SearchImage._(
              data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
              width,
              height,
            );
          }
        } finally {
          output?.dispose();
          picture.dispose();
        }
        if (width <= 128 || height <= 128) {
          throw const FormatException('图片无法处理');
        }
        width = math.max(1, (width * .75).round());
        height = math.max(1, (height * .75).round());
      }
    } finally {
      image?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer.dispose();
    }
  }
}

SearchImage? _prepareRaster((Uint8List, ui.Rect) request) {
  final (bytes, crop) = request;
  final decoder = img.findDecoderForData(bytes);
  if (decoder == null) return null; // HEIF 等格式仍使用平台解码器。
  final info = decoder.startDecode(bytes);
  if (info == null || info.width * info.height > 80000000) {
    throw const FormatException('图片无法处理');
  }
  final decoded = decoder.decodeFrame(0);
  if (decoded == null) throw const FormatException('图片无法处理');
  final oriented = img.bakeOrientation(decoded);
  final image = img.copyCrop(
    oriented,
    x: (crop.left * oriented.width).floor(),
    y: (crop.top * oriented.height).floor(),
    width: math.max(1, (crop.width * oriented.width).round()),
    height: math.max(1, (crop.height * oriented.height).round()),
  );
  final scale = math.min(1.0, 1800 / math.max(image.width, image.height));
  var width = math.max(1, (image.width * scale).round());
  var height = math.max(1, (image.height * scale).round());
  while (true) {
    final resized = img.copyResize(
      image,
      width: width,
      height: height,
      interpolation: img.Interpolation.average,
    );
    // 新建画布，不携带 EXIF、GPS 或原图文本元数据。
    final clean = img.Image(width: width, height: height, numChannels: 4);
    img.compositeImage(clean, resized, blend: img.BlendMode.direct);
    final output = img.encodePng(clean);
    if (output.length <= SearchImage.maxBytes) {
      return SearchImage._(output, width, height);
    }
    if (width == 1 && height == 1) throw const FormatException('图片无法处理');
    width = math.max(1, (width * .75).round());
    height = math.max(1, (height * .75).round());
  }
}
