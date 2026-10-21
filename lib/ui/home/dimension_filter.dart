import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models.dart';
import '../kit/tokens.dart';

/// 与域导航分层，保持三项选择始终可见；大字体时允许横向滚动。
class DimensionFilter extends StatelessWidget {
  const DimensionFilter({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final ContentDimension selected;
  final ValueChanged<ContentDimension> onSelected;

  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(Gap.page, Gap.xs, Gap.page, Gap.s),
      child: SegmentedButton<ContentDimension>(
        showSelectedIcon: false,
        style: SegmentedButton.styleFrom(
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(
            horizontal: Gap.l,
            vertical: Gap.s,
          ),
        ),
        segments: [
          for (final dimension in const [
            ContentDimension.all,
            ContentDimension.twoD,
            ContentDimension.threeD,
          ])
            ButtonSegment(
              value: dimension,
              label: SelectionContainer.disabled(child: Text(dimension.label)),
            ),
        ],
        selected: {selected},
        onSelectionChanged: (values) {
          final value = values.single;
          if (value == selected) return;
          HapticFeedback.selectionClick();
          onSelected(value);
        },
      ),
    ),
  );
}
