import 'package:flutter/material.dart';

import '../theme.dart';
import 'tokens.dart';

/// 紧凑排布的内容标签，保留点击、长按与键盘操作。
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
        minimumSize: const Size(32, 28),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.standard,
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
