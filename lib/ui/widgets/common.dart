import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/settings.dart';
import '../../engine/source_manager.dart';
import '../../images/park_image.dart';
import '../kit/tokens.dart';
import '../theme.dart';

export '../kit/kit.dart';

/// Brand monogram for a source (favicons are .ico, which Flutter cannot decode; a monogram in the
/// brand color is crisper and more consistent anyway).
class SourceAvatar extends StatelessWidget {
  const SourceAvatar(this.sourceKey, {super.key, this.size = 36});
  final String sourceKey;
  final double size;

  static String monogram(String name) {
    final clean = name.replaceAll(RegExp(r'[^\w一-龥]'), '');
    if (clean.isEmpty) return '?';
    if (RegExp(r'^[一-龥]').hasMatch(clean)) return clean.substring(0, 1);
    final caps = RegExp(r'[A-Z]')
        .allMatches(clean)
        .map((m) => m.group(0))
        .join();
    return (caps.length >= 2
            ? caps.substring(0, 2)
            : clean.substring(0, clean.length >= 2 ? 2 : 1))
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final m = SourceManager.instance.manifest(sourceKey);
    final local = sourceKey == 'local';
    final c = context.colors;
    // The site's own color identifies it; a flat tile keeps it from competing with covers.
    final color = local ? c.surfaceContainerHighest : (m?.color ?? c.outline);
    final ink = ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Scrims.onScrim
        : Colors.black87;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      padding: EdgeInsets.all(size * .16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.all(Radius.circular(size * .28)),
      ),
      child: local
          ? Icon(
              Icons.book_rounded,
              color: c.onSurfaceVariant,
              size: size * 0.5,
            )
          : FittedBox(
              child: Text(
                monogram(m?.name ?? sourceKey),
                style: context.text.labelLarge?.copyWith(
                  color: ink,
                  fontWeight: FontWeight.w600,
                  height: 1,
                ),
              ),
            ),
    );
  }
}

/// Network/local cover image with fade-in, placeholder, error state and optional privacy blur.
class CoverImage extends StatelessWidget {
  const CoverImage({
    super.key,
    required this.source,
    required this.url,
    this.fit = BoxFit.cover,
    this.radius = Radii.sm,
    this.blur,
    this.title = '',
    this.mediaKind,
    this.onReady,
  });
  final String source;
  final String url;
  final BoxFit fit;
  final double radius;
  final bool? blur;
  final String title;
  final MediaKind? mediaKind;
  final VoidCallback? onReady;

  void _notifyReady() {
    final callback = onReady;
    if (callback != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => callback());
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    Widget child;
    if (url.isEmpty) {
      _notifyReady();
      child =
          title.isNotEmpty &&
              (mediaKind == MediaKind.novel ||
                  SourceManager.instance.manifest(source)?.isNovel == true)
          ? LayoutBuilder(
              builder: (context, constraints) {
                final compact =
                    constraints.maxWidth < 90 || constraints.maxHeight < 100;
                return Padding(
                  padding: EdgeInsets.all(compact ? 6 : 16),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (!compact)
                        Icon(
                          Icons.menu_book_rounded,
                          color: colors.outline,
                          size: 28,
                        ),
                      if (!compact) const SizedBox(height: 16),
                      Flexible(
                        child: Text(
                          title,
                          textAlign: TextAlign.center,
                          maxLines: compact ? 3 : 6,
                          overflow: TextOverflow.ellipsis,
                          style: ParkText.serif(context.text.bodyMedium)
                              ?.copyWith(color: colors.onSurface),
                        ),
                      ),
                    ],
                  ),
                );
              },
            )
          : _placeholder(
              colors,
              SourceManager.instance.manifest(source)?.isNovel == true
                  ? Icons.menu_book_rounded
                  : Icons.image_not_supported_outlined,
            );
    } else {
      child = LayoutBuilder(
        builder: (context, constraints) {
          final ratio = MediaQuery.devicePixelRatioOf(context);
          final width = constraints.hasBoundedWidth && constraints.maxWidth > 0
              ? (constraints.maxWidth * ratio).ceil()
              : null;
          final height =
              constraints.hasBoundedHeight && constraints.maxHeight > 0
              ? (constraints.maxHeight * ratio).ceil()
              : null;
          final provider = ParkImage.url(source, url);
          return Image(
            image: width != null && height != null
                ? _CoverImageProvider(
                    provider,
                    Size(width.toDouble(), height.toDouble()),
                    fit,
                  )
                : width == null && height == null
                ? provider
                : ResizeImage(
                    provider,
                    width: width,
                    height: height,
                    policy: ResizeImagePolicy.fit,
                  ),
            fit: fit,
            gaplessPlayback: true,
            frameBuilder: (context, child, frame, sync) {
              if (sync || frame != null) _notifyReady();
              if (sync) return child;
              return AnimatedOpacity(
                opacity: frame == null ? 0 : 1,
                duration: Motion.of(context, Motion.medium),
                curve: Motion.curve,
                child: child,
              );
            },
            errorBuilder: (_, _, _) {
              _notifyReady();
              return _placeholder(colors, Icons.broken_image_outlined);
            },
          );
        },
      );
      if (blur ?? AppSettings.instance.blurCovers) {
        child = ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: child,
        );
      }
    }
    return ClipRRect(
      borderRadius: BorderRadius.all(Radius.circular(radius)),
      child: ColoredBox(color: colors.surfaceContainerHigh, child: child),
    );
  }

  Widget _placeholder(ColorScheme c, IconData icon) => Center(
    child: Icon(icon, color: c.onSurfaceVariant.withValues(alpha: 0.4)),
  );
}

/// Decode enough pixels for the actual fit without enlarging the original.
/// A wide image filling a tall cover needs its height, not just its width.
class _CoverImageProvider extends ImageProvider<_CoverImageProvider> {
  const _CoverImageProvider(this.image, this.size, this.fit);
  final ParkImage image;
  final Size size;
  final BoxFit fit;

  @override
  Future<_CoverImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    _CoverImageProvider key,
    ImageDecoderCallback decode,
  ) {
    final completer = image.loadImage(
      image,
      (buffer, {getTargetSize}) => decode(
        buffer,
        getTargetSize: (width, height) {
          final fitted = applyBoxFit(
            fit,
            Size(width.toDouble(), height.toDouble()),
            size,
          );
          final scale = math.min(
            1.0,
            math.max(
              fitted.destination.width / fitted.source.width,
              fitted.destination.height / fitted.source.height,
            ),
          );
          return TargetImageSize(
            width: (width * scale).round().clamp(1, width),
            height: (height * scale).round().clamp(1, height),
          );
        },
      ),
    );
    completer.addEphemeralErrorListener((error, stack) {
      scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(key));
    });
    return completer;
  }

  @override
  bool operator ==(Object other) =>
      other is _CoverImageProvider &&
      image == other.image &&
      size == other.size &&
      fit == other.fit;

  @override
  int get hashCode => Object.hash(image, size, fit);
}

/// 普通加载只显示转圈，避免在已有内容上重复叠加状态文案。
class LoadingIndicator extends StatelessWidget {
  const LoadingIndicator({
    super.key,
    this.padding = const EdgeInsets.all(20),
    this.color,
  });
  final EdgeInsets padding;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: color),
          ),
        ],
      ),
    );
  }
}

/// Shimmer skeleton block.
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, this.width, this.height, this.radius = Radii.sm});
  final double? width;
  final double? height;
  final double radius;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // "Remove animations" leaves a still placeholder.
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = context.colors.surfaceContainerHigh;
    final hi = context.colors.surfaceContainerHighest;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.all(Radius.circular(widget.radius)),
          gradient: LinearGradient(
            begin: Alignment(-1 - 2 * (1 - _c.value) + 2, 0),
            end: Alignment(1 - 2 * (1 - _c.value) + 2, 0),
            colors: [base, hi, base],
            stops: const [0.2, 0.5, 0.8],
          ),
        ),
      ),
    );
  }
}

/// Adaptive column count for cover grids.
int gridColumnsFor(double width) {
  final fixed = AppSettings.instance.gridColumns;
  if (fixed > 0) return fixed;
  if (width >= 1200) return 7;
  if (width >= 900) return 5;
  if (width >= 600) return 4;
  if (width >= 360) return 3;
  return 2;
}

extension SourceErrorX on Object {
  SourceError get asSourceError => this is SourceError
      ? this as SourceError
      : SourceError('UNKNOWN', toString());
}

MediaKind kindOf(WorkItem item) => SourceManager.instance.kindOf(item);
