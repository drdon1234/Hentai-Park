import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

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
