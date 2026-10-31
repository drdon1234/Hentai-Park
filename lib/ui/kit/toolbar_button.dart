import 'package:flutter/material.dart';

import '../theme.dart';
import 'tokens.dart';

/// 页面工具区的轻量操作；与提交按钮、筛选选择项保持层级区别。
class ToolbarButton extends StatelessWidget {
  const ToolbarButton({
    super.key,
    required this.onPressed,
    required Widget child,
  }) : label = child,
       icon = null;

  const ToolbarButton.icon({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.label,
  });

  final VoidCallback? onPressed;
  final Widget? icon;
  final Widget label;

  @override
  Widget build(BuildContext context) {
    final style = TextButton.styleFrom(
      foregroundColor: context.colors.onSurfaceVariant,
      textStyle: context.text.labelMedium,
      minimumSize: const Size(48, 48),
      padding: const EdgeInsets.symmetric(horizontal: Gap.s),
      iconSize: 18,
    );
    final content = SelectionContainer.disabled(child: label);
    return icon == null
        ? TextButton(onPressed: onPressed, style: style, child: content)
        : TextButton.icon(
            onPressed: onPressed,
            style: style,
            icon: icon,
            label: content,
          );
  }
}
