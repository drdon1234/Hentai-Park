import 'package:flutter/material.dart';

/// 勾选占位始终保留，避免 Wrap 内的多选项在切换状态时改变宽度。
class SelectionChip extends StatelessWidget {
  const SelectionChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) => FilterChip(
    label: Text(label),
    selected: selected,
    showCheckmark: false,
    avatar: ExcludeSemantics(
      child: SizedBox.square(
        dimension: 18,
        child: selected ? const Icon(Icons.check_rounded, size: 18) : null,
      ),
    ),
    onSelected: onSelected,
  );
}
