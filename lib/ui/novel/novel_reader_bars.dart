import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../kit/adaptive_sheet.dart';
import '../kit/kit.dart';
import '../theme.dart';
import 'novel_settings_sheet.dart';

/// Chapter title and progress under the text. It is part of the layout whether or not
/// the controls show, so toggling them never reflows the text.
class NovelStatusLine extends StatelessWidget {
  const NovelStatusLine({
    super.key,
    required this.foreground,
    required this.offline,
    required this.title,
    required this.progress,
  });
  final Color foreground;
  final bool offline;
  final String title;
  final String progress;

  @override
  Widget build(BuildContext context) {
    final muted = foreground.withValues(alpha: .7);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Gap.page,
        vertical: Gap.xs,
      ),
      child: DefaultTextStyle.merge(
        style: context.text.labelSmall?.copyWith(color: muted),
        child: Row(
          children: [
            if (offline)
              Padding(
                padding: const EdgeInsets.only(right: Gap.s),
                child: Icon(
                  Icons.offline_pin_outlined,
                  size: 14,
                  color: muted,
                  semanticLabel: tr('离线阅读'),
                ),
              ),
            Expanded(
              child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            Text(progress),
          ],
        ),
      ),
    );
  }
}

/// Progress slider with chapter navigation, plus the directory and settings buttons.
class NovelReaderBottomBar extends StatelessWidget {
  const NovelReaderBottomBar({
    super.key,
    required this.foreground,
    required this.progress,
    required this.onSeek,
    required this.onPrevious,
    required this.onNext,
    required this.onDirectory,
  });
  final Color foreground;

  /// Reading progress in the chapter, 0–1.
  final double progress;
  final ValueChanged<double> onSeek;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback onDirectory;

  @override
  Widget build(BuildContext context) {
    final style = TextButton.styleFrom(foregroundColor: foreground);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ReaderProgress(
          value: progress,
          max: 1,
          label: (v) => '${(v * 100).round()}%',
          onSeek: onSeek,
          onPrevious: onPrevious,
          onNext: onNext,
        ),
        Wrap(
          alignment: WrapAlignment.spaceEvenly,
          spacing: Gap.m,
          runSpacing: Gap.xs,
          children: [
            TextButton(
              style: style,
              onPressed: onDirectory,
              child: SelectionContainer.disabled(child: Text(tr('目录'))),
            ),
            TextButton(
              style: style,
              onPressed: () => showAdaptiveSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => const NovelSettingsSheet(),
              ),
              child: SelectionContainer.disabled(child: Text(tr('阅读设置'))),
            ),
          ],
        ),
      ],
    );
  }
}
