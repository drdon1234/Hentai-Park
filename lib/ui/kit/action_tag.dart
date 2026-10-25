import 'package:flutter/material.dart';

import '../theme.dart';
import 'tokens.dart';

/// 紧凑的可操作标签：32dp 视觉轮廓与独立的 48dp 点击区域。
/// 静态元数据使用 Tag，筛选项使用 SelectionChip，页面操作使用按钮。
class ActionTag extends StatelessWidget {
  const ActionTag({
    super.key,
    required this.child,
    required this.onTap,
    this.onLongPress,
  });

  final Widget child;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onSecondaryTap: onLongPress,
    child: OutlinedButton(
      onPressed: onTap,
      onLongPress: onLongPress,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 32),
        padding: const EdgeInsets.symmetric(
          horizontal: Gap.s,
          vertical: Gap.xs,
        ),
        textStyle: context.text.labelMedium?.copyWith(
          fontWeight: FontWeight.w500,
        ),
      ),
      child: SelectionContainer.disabled(child: child),
    ),
  );
}
