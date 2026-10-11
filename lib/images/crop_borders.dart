import 'dart:typed_data';

/// Content bounds of an image with uniform (white / black / any flat color) margins.
class CropRect {
  const CropRect(this.left, this.top, this.right, this.bottom);
  final int left, top, right, bottom; // right / bottom are exclusive
  int get width => right - left;
  int get height => bottom - top;

  @override
  bool operator ==(Object other) => other is CropRect && other.left == left && other.top == top && other.right == right && other.bottom == bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);

  @override
  String toString() => 'CropRect($left, $top, $right, $bottom)';
}

/// Finds the content rectangle of an RGBA image by trimming rows / columns that match the border
/// color (sampled at the top-left pixel) within [tolerance]. Returns null when there is nothing worth
/// cropping (< 1% per side) or the content would shrink below [minKeep] of either dimension
/// (blank or almost blank pages stay as they are).
CropRect? detectContentRect(Uint8List rgba, int width, int height, {int tolerance = 24, double minKeep = 0.4}) {
  if (width < 8 || height < 8 || rgba.length < width * height * 4) return null;
  final br = rgba[0], bg = rgba[1], bb = rgba[2];
  bool same(int i) => (rgba[i] - br).abs() <= tolerance && (rgba[i + 1] - bg).abs() <= tolerance && (rgba[i + 2] - bb).abs() <= tolerance;
  // Sampling every few pixels keeps this fast on large pages; a 1-pixel stroke may be missed, which only
  // means slightly less cropping.
  final stepX = (width / 400).ceil().clamp(1, 8);
  final stepY = (height / 400).ceil().clamp(1, 8);
  bool rowBlank(int y) {
    final base = y * width * 4;
    for (var x = 0; x < width; x += stepX) {
      if (!same(base + x * 4)) return false;
    }
    return true;
  }

  bool colBlank(int x, int top, int bottom) {
    for (var y = top; y < bottom; y += stepY) {
      if (!same((y * width + x) * 4)) return false;
    }
    return true;
  }

  var top = 0;
  while (top < height && rowBlank(top)) {
    top++;
  }
  if (top >= height) return null; // the whole page is one color
  var bottom = height;
  while (bottom > top && rowBlank(bottom - 1)) {
    bottom--;
  }
  var left = 0;
  while (left < width && colBlank(left, top, bottom)) {
    left++;
  }
  var right = width;
  while (right > left && colBlank(right - 1, top, bottom)) {
    right--;
  }
  // Leave a hairline of margin so the content does not touch the screen edge.
  final padX = (width * 0.005).round(), padY = (height * 0.005).round();
  left = (left - padX).clamp(0, width);
  top = (top - padY).clamp(0, height);
  right = (right + padX).clamp(0, width);
  bottom = (bottom + padY).clamp(0, height);
  final rect = CropRect(left, top, right, bottom);
  if (rect.width < width * minKeep || rect.height < height * minKeep) return null;
  final minX = width * 0.01, minY = height * 0.01;
  if (left < minX && top < minY && width - right < minX && height - bottom < minY) return null;
  return rect;
}
