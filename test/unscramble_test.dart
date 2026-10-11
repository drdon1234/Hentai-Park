import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:hentai_park/images/park_image.dart';

/// Builds an image whose row y is filled with grey level `label(y)`.
Future<ui.Image> _image(int w, int h, int Function(int y) label) {
  final pixels = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final o = (y * w + x) * 4;
      pixels[o] = pixels[o + 1] = pixels[o + 2] = label(y);
      pixels[o + 3] = 255;
    }
  }
  final c = Completer<ui.Image>();
  ui.decodeImageFromPixels(pixels, w, h, ui.PixelFormat.rgba8888, c.complete);
  return c.future;
}

void main() {
  testWidgets('unscrambleStrips restores JM strip order (with remainder rows)', (tester) async {
    await tester.runAsync(() async {
      const w = 4, h = 37, n = 4; // 37 = 4 * 9 + 1 → exercises the remainder handling
      // Reference decoder (jmcomic): dst[yDst..yDst+move] = src[ySrc..ySrc+move].
      // Build the scrambled source by inverting that mapping over an image labelled by row.
      final srcRowFor = List<int>.filled(h, 0);
      final base = h ~/ n, over = h % n;
      for (var i = 0; i < n; i++) {
        var move = base;
        final ySrc = h - base * (i + 1) - over;
        var yDst = base * i;
        if (i == 0) {
          move += over;
        } else {
          yDst += over;
        }
        for (var k = 0; k < move; k++) {
          srcRowFor[ySrc + k] = yDst + k;
        }
      }
      final scrambled = await _image(w, h, (y) => srcRowFor[y] * 5);
      final restored = await unscrambleStrips(scrambled, n);
      final data = (await restored.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      for (var y = 0; y < h; y++) {
        expect(data.getUint8(y * w * 4), y * 5, reason: 'row $y');
      }
    });
  });
}
