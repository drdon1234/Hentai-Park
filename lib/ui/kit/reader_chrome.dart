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
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final duration = Motion.of(context, Motion.medium);
    final text = Theme.of(context).textTheme;
    final stackActions =
        actions.isNotEmpty && MediaQuery.textScalerOf(context).scale(14) > 20;
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
                  child: Material(
                    color: barColor,
                    child: SafeArea(
                      bottom: false,
                      child: IconTheme.merge(
                        data: IconThemeData(color: foreground),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 56),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
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
                                          style: text.titleSmall?.copyWith(
                                            color: foreground,
                                          ),
                                        ),
                                        if (subtitle != null &&
                                            subtitle!.isNotEmpty)
                                          Text(
                                            subtitle!,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: text.bodySmall?.copyWith(
                                              color: foreground.withValues(
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
                              if (stackActions) Wrap(children: actions),
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
                    child: Material(
                      color: barColor,
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
    this.divisions,
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
  final int? divisions;

  @override
  State<ReaderProgress> createState() => _ReaderProgressState();
}

class _ReaderProgressState extends State<ReaderProgress> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final fg = DefaultTextStyle.of(context).style.color ?? Scrims.onScrim;
    final value = (_drag ?? widget.value).clamp(0.0, widget.max);
    final text = Theme.of(context).textTheme.labelLarge?.copyWith(color: fg);
    return Row(
      children: [
        IconButton(
          tooltip: widget.previousTooltip ?? tr('上一章'),
          onPressed: widget.onPrevious,
          icon: const Icon(Icons.skip_previous_rounded),
          color: fg,
          disabledColor: fg.withValues(alpha: .25),
        ),
        Text(widget.label(value), style: text),
        Expanded(
          child: Slider(
            value: value,
            max: widget.max <= 0 ? 1 : widget.max,
            divisions: widget.divisions,
            label: widget.label(value),
            onChanged: (v) => setState(() => _drag = v),
            onChangeEnd: (v) {
              setState(() => _drag = null);
              widget.onSeek(v);
            },
          ),
        ),
        if (widget.trailingLabel != null)
          Text(
            widget.trailingLabel!,
            style: text?.copyWith(color: fg.withValues(alpha: .6)),
          ),
        IconButton(
          tooltip: widget.nextTooltip ?? tr('下一章'),
          onPressed: widget.onNext,
          icon: const Icon(Icons.skip_next_rounded),
          color: fg,
          disabledColor: fg.withValues(alpha: .25),
        ),
      ],
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
        color: Scrims.medium,
        borderRadius: Radii.small,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Gap.s, vertical: 3),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: Scrims.onScrim.withValues(alpha: .8)),
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
    this.foreground = Scrims.onScrim,
  });
  final bool hasNext;
  final VoidCallback onNext;
  final Color foreground;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 240,
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            hasNext ? tr('本章完') : tr('全部读完啦'),
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(color: foreground.withValues(alpha: .8)),
          ),
          const SizedBox(height: Gap.m),
          if (hasNext)
            FilledButton.icon(
              onPressed: onNext,
              icon: const Icon(Icons.skip_next_rounded),
              label: Text(tr('下一章')),
            )
          else
            OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: foreground),
              onPressed: () => Navigator.maybePop(context),
              child: Text(tr('返回详情')),
            ),
        ],
      ),
    ),
  );
}
