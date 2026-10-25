import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../theme.dart';
import 'tokens.dart';

/// 标题栏动作保留明确名称，空间不足时统一收进可见的“更多”入口。
class ToolbarAction {
  const ToolbarAction({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.showLabel = false,
    this.shortLabel,
    this.compactLabel = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool showLabel;
  final String? shortLabel;
  final bool compactLabel;

  String get visibleLabel => shortLabel ?? label;
}

class ToolbarActions extends StatelessWidget {
  const ToolbarActions({super.key, required this.actions});

  final List<ToolbarAction> actions;

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) return const SizedBox.shrink();
    final available =
        (MediaQuery.sizeOf(context).width -
            MediaQuery.paddingOf(context).horizontal) /
        2;
    TextStyle? labelStyle(ToolbarAction action) => action.compactLabel
        ? context.text.labelSmall?.copyWith(
            fontSize: 10,
            fontWeight: FontWeight.w400,
          )
        : Theme.of(context).outlinedButtonTheme.style?.textStyle?.resolve({}) ??
              context.text.labelLarge;
    var width = 0.0;
    for (final action in actions) {
      if (!action.showLabel) {
        width += 48;
        continue;
      }
      final painter = TextPainter(
        text: TextSpan(text: action.visibleLabel, style: labelStyle(action)),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      width += action.compactLabel
          ? painter.width + 24 + Gap.s * 2
          : (painter.width + Gap.l * 2).clamp(64, double.infinity);
      painter.dispose();
    }
    width += Gap.xs * (actions.length - 1);
    if (width > available) {
      return PopupMenuButton<int>(
        tooltip: tr('更多'),
        popUpAnimationStyle: Motion.menu(context),
        onSelected: (index) => actions[index].onPressed?.call(),
        itemBuilder: (context) => [
          for (var i = 0; i < actions.length; i++)
            PopupMenuItem(
              value: i,
              enabled: actions[i].onPressed != null,
              child: SelectionContainer.disabled(
                child: Row(
                  children: [
                    ExcludeSemantics(child: Icon(actions[i].icon)),
                    const SizedBox(width: Gap.m),
                    Flexible(child: Text(actions[i].label)),
                  ],
                ),
              ),
            ),
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < actions.length; i++) ...[
          if (i > 0) const SizedBox(width: Gap.xs),
          if (actions[i].showLabel && actions[i].compactLabel)
            TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: context.colors.onSurfaceVariant,
                minimumSize: const Size(48, 48),
                padding: const EdgeInsets.symmetric(horizontal: Gap.s),
                textStyle: labelStyle(actions[i]),
              ),
              onPressed: actions[i].onPressed,
              icon: Icon(actions[i].icon, size: 20),
              label: SelectionContainer.disabled(
                child: Text(actions[i].visibleLabel),
              ),
            )
          else if (actions[i].showLabel)
            OutlinedButton(
              onPressed: actions[i].onPressed,
              child: SelectionContainer.disabled(
                child: Text(actions[i].visibleLabel),
              ),
            )
          else
            IconButton(
              tooltip: actions[i].label,
              onPressed: actions[i].onPressed,
              icon: Icon(actions[i].icon),
            ),
        ],
      ],
    );
  }
}
