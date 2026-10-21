import 'package:flutter/material.dart';

/// 文字居中的选择项，通过主题边框表达选中状态，不为勾号预留空间。
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
    label: SelectionContainer.disabled(child: Text(label)),
    selected: selected,
    showCheckmark: false,
    onSelected: onSelected,
  );
}
