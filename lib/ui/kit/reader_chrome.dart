import 'package:flutter/material.dart';

import '../../core/localization.dart';
import 'tokens.dart';

/// The immersive control layer shared by the comic, novel and video readers: tap the middle to
/// show it, tap the edges to turn pages (each reader decides), progress at the bottom. Bars are
/// overlays, so showing them never changes the reading layout.
class ReaderChrome extends StatelessWidget {
  const ReaderChrome({
    super.key,
    required this.visible,
    required this.child,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.bottom,
    this.barColor = Scrims.strong,
    this.foreground = Scrims.onScrim,
    this.fade = false,
    this.onBack,
  });
  final bool visible;
  final Widget child;
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget? bottom;
  final Color barColor;
  final Color foreground;

  /// Bars fade from [barColor] at the screen edge to clear, instead of solid blocks. For video,
  /// where solid bars would cover most of a short inline player.
  final bool fade;
  final VoidCallback? onBack;

  Widget _bar({required bool top, required Widget child}) {
    child = SelectionContainer.disabled(child: child);
    if (!fade) return Material(color: barColor, child: child);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: top ? Alignment.topCenter : Alignment.bottomCenter,
          end: top ? Alignment.bottomCenter : Alignment.topCenter,
          colors: [barColor, barColor.withValues(alpha: 0)],
        ),
      ),
      child: Material(type: MaterialType.transparency, child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    final duration = Motion.of(context, Motion.medium);
    final text = Theme.of(context).textTheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final stackActions =
            actions.isNotEmpty &&
            (MediaQuery.textScalerOf(context).scale(14) > 20 ||
                constraints.maxWidth -
                        MediaQuery.paddingOf(context).horizontal <
                    360);
        return Stack(
          children: [
            Positioned.fill(child: child),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: ExcludeSemantics(
                excluding: !visible,
                child: ExcludeFocus(
                  excluding: !visible,
                  child: IgnorePointer(
                    ignoring: !visible,
                    child: AnimatedSlide(
                      offset: visible ? Offset.zero : const Offset(0, -1),
                      duration: duration,
                      curve: Motion.curve,
                      child: _bar(
                        top: true,
                        child: SafeArea(
                          bottom: false,
                          child: IconTheme.merge(
                            data: IconThemeData(color: foreground),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Center(
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      minHeight: 56,
                                    ),
                                    child: Row(
                                      children: [
                                        BackButton(
                                          color: foreground,
                                          onPressed: onBack,
                                        ),
                                        Expanded(
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Text(
                                                title,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: text.titleSmall
                                                    ?.copyWith(
                                                      color: foreground,
                                                    ),
                                              ),
                                              if (subtitle != null &&
                                                  subtitle!.isNotEmpty)
                                                Text(
                                                  subtitle!,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: text.bodySmall
                                                      ?.copyWith(
                                                        color: foreground
                                                            .withValues(
                                                              alpha: .7,
                                                            ),
                                                      ),
                                                ),
                                            ],
                                          ),
                                        ),
                                        if (!stackActions) ...actions,
                                        const SizedBox(width: Gap.xs),
                                      ],
                                    ),
                                  ),
                                ),
                                if (stackActions)
                                  Align(
                                    alignment: AlignmentDirectional.centerEnd,
                                    child: Wrap(children: actions),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (bottom != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: ExcludeSemantics(
                  excluding: !visible,
                  child: ExcludeFocus(
                    excluding: !visible,
                    child: IgnorePointer(
                      ignoring: !visible,
                      child: AnimatedSlide(
                        offset: visible ? Offset.zero : const Offset(0, 1),
                        duration: duration,
                        curve: Motion.curve,
                        child: _bar(
                          top: false,
                          child: SafeArea(
                            top: false,
                            child: IconTheme.merge(
                              data: IconThemeData(color: foreground),
                              child: DefaultTextStyle.merge(
                                style: TextStyle(color: foreground),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: Gap.xs,
                                    vertical: Gap.s - 2,
                                  ),
                                  child: bottom!,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Previous / progress / next, the bottom row every reader shares.
class ReaderProgress extends StatefulWidget {
  const ReaderProgress({
    super.key,
    required this.value,
    required this.max,
    required this.onSeek,
    required this.label,
    this.trailingLabel,
    this.onPrevious,
    this.onNext,
    this.previousTooltip,
    this.nextTooltip,
  });
  final double value;
  final double max;
  final ValueChanged<double> onSeek;
  final String Function(double value) label;
  final String? trailingLabel;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final String? previousTooltip;
  final String? nextTooltip;

  @override
  State<ReaderProgress> createState() => _ReaderProgressState();
}

class _ReaderProgressState extends State<ReaderProgress> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final fg = DefaultTextStyle.of(context).style.color ?? Scrims.onScrim;
    final value = (_drag ?? widget.value).clamp(0.0, widget.max);
    final text = Theme.of(context).textTheme.labelLarge?.copyWith(
      color: fg,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final previous = IconButton(
      tooltip: widget.previousTooltip ?? tr('上一章'),
      onPressed: widget.onPrevious,
      icon: const Icon(Icons.skip_previous_rounded),
      color: fg,
      disabledColor: fg.withValues(alpha: .25),
    );
    final next = IconButton(
      tooltip: widget.nextTooltip ?? tr('下一章'),
      onPressed: widget.onNext,
      icon: const Icon(Icons.skip_next_rounded),
      color: fg,
      disabledColor: fg.withValues(alpha: .25),
    );
    final slider = Expanded(
      child: Slider(
        value: value,
        max: widget.max <= 0 ? 1 : widget.max,
        label: widget.label(value),
        onChanged: widget.max <= 0 ? null : (v) => setState(() => _drag = v),
        onChangeEnd: widget.max <= 0
            ? null
            : (v) {
                setState(() => _drag = null);
                widget.onSeek(v);
              },
      ),
    );
    final labels = [
      Text(widget.label(value), style: text),
      if (widget.trailingLabel != null)
        Text(
          widget.trailingLabel!,
          style: text?.copyWith(color: fg.withValues(alpha: .6)),
        ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth / MediaQuery.textScalerOf(context).scale(1) <
            360) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                spacing: Gap.m,
                alignment: WrapAlignment.center,
                children: labels,
              ),
              Row(children: [previous, slider, next]),
            ],
          );
        }
        return Row(
          children: [previous, labels.first, slider, ...labels.skip(1), next],
        );
      },
    );
  }
}

/// Small position label shown while the chrome is hidden.
class ReaderBadge extends StatelessWidget {
  const ReaderBadge(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: DecoratedBox(
      decoration: const BoxDecoration(
        color: Scrims.strong,
        borderRadius: Radii.small,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Gap.s, vertical: 3),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Scrims.onScrim,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    ),
  );
}

/// End of a chapter: go on to the next one, or back to the work.
class ReaderChapterEnd extends StatelessWidget {
  const ReaderChapterEnd({
    super.key,
    required this.hasNext,
    required this.onNext,
  });
  final bool hasNext;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurface;
    return LayoutBuilder(
      builder: (context, constraints) => ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: constraints.maxHeight.isFinite
              ? constraints.maxHeight.clamp(0, 240)
              : 240,
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Gap.page),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  hasNext ? tr('本章完') : tr('全部读完啦'),
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(color: color),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: Gap.m),
                if (hasNext)
                  FilledButton.icon(
                    onPressed: onNext,
                    icon: const Icon(Icons.skip_next_rounded),
                    label: SelectionContainer.disabled(child: Text(tr('下一章'))),
                  )
                else
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(foregroundColor: color),
                    onPressed: () => Navigator.maybePop(context),
                    child: SelectionContainer.disabled(child: Text(tr('返回详情'))),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
