import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hentai_park/images/crop_borders.dart';

/// A white w×h image with a black block covering [l,t)–[r,b).
Uint8List page(int w, int h, int l, int t, int r, int b) {
  final px = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 4;
      final ink = x >= l && x < r && y >= t && y < b;
      px[i] = px[i + 1] = px[i + 2] = ink ? 0 : 255;
      px[i + 3] = 255;
    }
  }
  return px;
}

void main() {
  test('finds content inside white margins', () {
    final rect = detectContentRect(page(200, 300, 20, 30, 180, 270), 200, 300)!;
    expect(rect.left, inInclusiveRange(18, 20));
    expect(rect.top, inInclusiveRange(28, 30));
    expect(rect.right, inInclusiveRange(180, 182));
    expect(rect.bottom, inInclusiveRange(270, 272));
  });

  test('no crop when content reaches the edges or the page is blank', () {
    expect(detectContentRect(page(100, 100, 0, 0, 100, 100), 100, 100), isNull);
    expect(detectContentRect(page(100, 100, 0, 0, 0, 0), 100, 100), isNull);
  });

  test('refuses to crop away most of the page', () {
    expect(detectContentRect(page(200, 200, 90, 90, 110, 110), 200, 200), isNull);
  });
}
