import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../kit/adaptive_sheet.dart';
import '../kit/kit.dart';
import 'reader_zoom.dart';

/// Grayscale and invert filters on the pages, and the dim and warm layers above them.
class ReaderFilters extends StatelessWidget {
  const ReaderFilters({
    super.key,
    required this.child,
    this.grayscale = false,
    this.invert = false,
    this.dim = 0,
    this.warm = 0,
  });
  final Widget child;
  final bool grayscale;
  final bool invert;
  final double dim;
  final double warm;

  static const _grayscale = ColorFilter.matrix([
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0, 0, 0, 1, 0, //
  ]);
  static const _invert = ColorFilter.matrix([
    -1, 0, 0, 0, 255, //
    0, -1, 0, 0, 255, //
    0, 0, -1, 0, 255, //
    0, 0, 0, 1, 0, //
  ]);

  @override
  Widget build(BuildContext context) {
    var out = child;
    if (grayscale) out = ColorFiltered(colorFilter: _grayscale, child: out);
    if (invert) out = ColorFiltered(colorFilter: _invert, child: out);
    return Stack(
      fit: StackFit.expand,
      children: [
        out,
        if (dim > 0)
          IgnorePointer(
            child: ColoredBox(
              color: Colors.black.withValues(alpha: dim.clamp(0, 0.8)),
            ),
          ),
        if (warm > 0)
          IgnorePointer(
            child: ColoredBox(
              color: ReaderPalette.warm.withValues(alpha: warm.clamp(0, 0.5)),
            ),
          ),
      ],
    );
  }
}

enum PageAction { share, save }

/// What to do with one page (long press).
Future<PageAction?> showPageActions(BuildContext context, int index) =>
    showAdaptiveSheet<PageAction>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Gap.page,
                Gap.m,
                Gap.page,
                Gap.xs,
              ),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  tr('第 {value0} 页', {'value0': index + 1}),
                  style: Theme.of(ctx).textTheme.titleMedium,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.share_rounded),
              title: Text(tr('分享图片')),
              onTap: () => Navigator.pop(ctx, PageAction.share),
            ),
            ListTile(
              leading: const Icon(Icons.save_alt_rounded),
              title: Text(tr('保存到相册')),
              onTap: () => Navigator.pop(ctx, PageAction.save),
            ),
          ],
        ),
      ),
    );

/// Shows the left or right half of a wide page, scaled to fill the screen height.
class HalfPage extends StatelessWidget {
  const HalfPage({super.key, required this.left, required this.child});
  final bool left;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) => ClipRect(
        child: OverflowBox(
          alignment: left ? Alignment.centerLeft : Alignment.centerRight,
          minWidth: c.maxWidth * 2,
          maxWidth: c.maxWidth * 2,
          child: child,
        ),
      ),
    );
  }
}

/// Double-tap to zoom in/out on a single page.
class ZoomablePage extends StatefulWidget {
  const ZoomablePage({super.key, required this.child});
  final Widget child;

  @override
  State<ZoomablePage> createState() => _ZoomablePageState();
}

class _ZoomablePageState extends State<ZoomablePage>
    with SingleTickerProviderStateMixin {
  final _t = TransformationController();
  TapDownDetails? _down;
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );
  Animation<Matrix4>? _tween;

  @override
  void initState() {
    super.initState();
    _anim.addListener(() => _t.value = _tween!.value);
  }

  @override
  void dispose() {
    _t.dispose();
    _anim.dispose();
    super.dispose();
  }

  void _toggle() {
    final zoomed = _t.value.getMaxScaleOnAxis() > 1.01;
    final p = _down?.localPosition ?? Offset.zero;
    final target = zoomed
        ? Matrix4.identity()
        : (Matrix4.identity()
            ..translateByDouble(-p.dx * 1.5, -p.dy * 1.5, 0, 1)
            ..scaleByDouble(2.5, 2.5, 1, 1));
    if (MediaQuery.disableAnimationsOf(context)) {
      _anim.stop();
      _t.value = target;
      return;
    }
    _tween = Matrix4Tween(
      begin: _t.value,
      end: target,
    ).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOut));
    _anim.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTapDown: (d) => _down = d,
      onDoubleTap: _toggle,
      child: ReaderZoom(
        controller: _t,
        onInteractionStart: (_) => _anim.stop(),
        child: SizedBox.expand(child: widget.child),
      ),
    );
  }
}
