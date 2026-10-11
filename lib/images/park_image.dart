import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../core/models.dart';
import '../engine/source_manager.dart';
import 'crop_borders.dart';
import 'image_store.dart';

/// Loads an image for a source: direct URL, or a page resolved lazily through the source
/// (`resolveImage`), with the source's default headers and an optional pixel transform.
@immutable
class ParkImage extends ImageProvider<ParkImage> {
  const ParkImage({
    required this.source,
    this.url = '',
    this.headers = const {},
    this.cacheKey,
    this.fallbacks = const [],
    this.transform,
    this.lazy,
    this.highPriority = false,
    this.localPath,
    this.crop = false,
  });

  /// A direct image (cover, thumbnail or page with a known URL).
  factory ParkImage.url(String source, String url, {Map<String, String>? headers}) {
    if (url.startsWith('file://')) return ParkImage(source: source, localPath: url.substring(7));
    final m = SourceManager.instance.manifest(source);
    return ParkImage(source: source, url: url, headers: {...?m?.imageHeaders, ...?headers});
  }

  /// A reader page. Pages without a URL are resolved through the source on first load.
  factory ParkImage.page(String source, String workId, String? chapterId, int index, PageImage page, {bool crop = false}) {
    final m = SourceManager.instance.manifest(source);
    if (page.url.startsWith('file://')) {
      return ParkImage(source: source, localPath: page.url.substring(7), transform: page.transform, crop: crop);
    }
    return ParkImage(
      source: source,
      url: page.url,
      headers: {...?m?.imageHeaders, ...page.headers},
      cacheKey: page.cacheKey ?? (page.needsResolve ? '$source:$workId:${chapterId ?? ''}:$index' : null),
      fallbacks: page.fallbacks,
      transform: page.transform,
      lazy: page.needsResolve ? LazyPage(workId, chapterId, index, page.token) : null,
      highPriority: true,
      crop: crop,
    );
  }

  final String source;
  final String url;
  final Map<String, String> headers;
  final String? cacheKey;
  final List<String> fallbacks;
  final Map<String, dynamic>? transform;
  final LazyPage? lazy;
  final bool highPriority;
  final String? localPath;

  /// Trim uniform page margins after decoding (reader "crop borders").
  final bool crop;

  String get identity => localPath ?? cacheKey ?? url;

  @override
  Future<ParkImage> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(ParkImage key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(codec: _loadCodec(decode), scale: 1, debugLabel: identity);
  }

  Future<ui.Codec> _loadCodec(ImageDecoderCallback decode) async {
    final bytes = await loadBytes();
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final codec = await decode(buffer);
    final segments = _segments;
    if (segments <= 1 && !crop) return codec;
    if (codec.frameCount > 1) return codec; // animated: leave untouched
    final frame = await codec.getNextFrame();
    codec.dispose();
    var image = frame.image;
    if (segments > 1) image = await unscrambleStrips(image, segments);
    if (crop) image = await cropBorders(image);
    return _SingleFrameCodec(image);
  }

  int get _segments {
    final t = transform;
    if (t == null || t['type'] != 'unscramble-strips') return 0;
    return (t['segments'] as num?)?.toInt() ?? 0;
  }

  /// The bytes of the image as displayed: raw file bytes when no processing applies, otherwise
  /// the restored / cropped image encoded as PNG (used for saving and sharing pages).
  Future<Uint8List> displayBytes() async {
    final bytes = await loadBytes();
    if (_segments <= 1 && !crop) return bytes;
    final codec = await _loadCodec((buffer, {getTargetSize}) => ui.instantiateImageCodecFromBuffer(buffer));
    final frame = await codec.getNextFrame();
    codec.dispose();
    final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    frame.image.dispose();
    return data!.buffer.asUint8List();
  }

  /// Raw (still scrambled) bytes; also used by the downloader.
  Future<Uint8List> loadBytes() async {
    if (localPath != null) return await File(localPath!).readAsBytes();
    final lazyPage = lazy;
    if (lazyPage == null) {
      return ImageStore.instance.load(url: url, headers: headers, cacheKey: cacheKey, fallbacks: fallbacks, highPriority: highPriority, partition: source);
    }
    final hit = await ImageStore.instance.cached(cacheKey!);
    if (hit != null) return hit;
    Object? lastError;
    for (var retry = 0; retry < 3; retry++) {
      try {
        final page = await SourceManager.instance.resolveImage(
          source,
          id: lazyPage.workId,
          chapterId: lazyPage.chapterId,
          index: lazyPage.index,
          token: lazyPage.token,
          retry: retry,
        );
        return await ImageStore.instance.load(
          url: page.url,
          headers: {...headers, ...page.headers},
          cacheKey: cacheKey,
          fallbacks: page.fallbacks,
          highPriority: true,
          partition: source,
        );
      } on SourceError catch (e) {
        lastError = e;
        if (e.code == 'BLOCKED' || e.code == 'LOGIN_REQUIRED' || e.code == 'NOT_FOUND') rethrow;
      }
    }
    throw lastError ?? SourceError('NETWORK', '图片加载失败');
  }

  @override
  bool operator ==(Object other) =>
      other is ParkImage && other.source == source && other.identity == identity && other.crop == crop && mapEquals(other.transform, transform);

  @override
  int get hashCode => Object.hash(source, identity, crop);

  @override
  String toString() => 'ParkImage($source, $identity)';
}

@immutable
class LazyPage {
  const LazyPage(this.workId, this.chapterId, this.index, this.token);
  final String workId;
  final String? chapterId;
  final int index;
  final String? token;
}

/// Reassembles an image cut into [segments] horizontal strips stored in reverse order (JMComic).
/// Strip heights are floor(h / n) with the remainder added to the (source) first strip.
Future<ui.Image> unscrambleStrips(ui.Image src, int segments) async {
  final w = src.width.toDouble();
  final h = src.height;
  final base = h ~/ segments;
  final over = h % segments;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final paint = ui.Paint()..filterQuality = ui.FilterQuality.none;
  for (var i = 0; i < segments; i++) {
    var move = base;
    final ySrc = h - base * (i + 1) - over;
    var yDst = base * i;
    if (i == 0) {
      move += over;
    } else {
      yDst += over;
    }
    canvas.drawImageRect(src, ui.Rect.fromLTWH(0, ySrc.toDouble(), w, move.toDouble()), ui.Rect.fromLTWH(0, yDst.toDouble(), w, move.toDouble()), paint);
  }
  final picture = recorder.endRecording();
  final out = await picture.toImage(src.width, h);
  picture.dispose();
  src.dispose();
  return out;
}

/// Crops uniform margins off [src] (detection runs on a background isolate). Returns [src] unchanged
/// when there is nothing to crop.
Future<ui.Image> cropBorders(ui.Image src) async {
  final data = await src.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (data == null) return src;
  final w = src.width, h = src.height;
  final rect = await compute(_detect, (TransferableTypedData.fromList([data.buffer.asUint8List()]), w, h));
  if (rect == null) return src;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawImageRect(
    src,
    ui.Rect.fromLTRB(rect.left.toDouble(), rect.top.toDouble(), rect.right.toDouble(), rect.bottom.toDouble()),
    ui.Rect.fromLTWH(0, 0, rect.width.toDouble(), rect.height.toDouble()),
    ui.Paint()..filterQuality = ui.FilterQuality.none,
  );
  final picture = recorder.endRecording();
  final out = await picture.toImage(rect.width, rect.height);
  picture.dispose();
  src.dispose();
  return out;
}

CropRect? _detect((TransferableTypedData, int, int) args) => detectContentRect(args.$1.materialize().asUint8List(), args.$2, args.$3);

class _SingleFrameCodec implements ui.Codec {
  _SingleFrameCodec(this._image);
  final ui.Image _image;

  @override
  int get frameCount => 1;
  @override
  int get repetitionCount => 0;
  @override
  Future<ui.FrameInfo> getNextFrame() async => _Frame(_image.clone());
  @override
  void dispose() => _image.dispose();
}

class _Frame implements ui.FrameInfo {
  _Frame(this.image);
  @override
  final ui.Image image;
  @override
  Duration get duration => Duration.zero;
}
