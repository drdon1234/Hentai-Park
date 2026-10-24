import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models.dart';
import '../kit/tokens.dart';

/// 与域导航分层，维度与媒体两组选择始终可见；窄屏或大字体时横向滚动。
class DimensionFilter extends StatelessWidget {
  const DimensionFilter({
    super.key,
    required this.dimension,
    required this.media,
    required this.onDimension,
    required this.onMedia,
  });

  final ContentDimension dimension;
  final ContentMedia media;
  final ValueChanged<ContentDimension> onDimension;
  final ValueChanged<ContentMedia> onMedia;

  static Widget _group<T>({
    required List<T> values,
    required T selected,
    required String Function(T) label,
    required ValueChanged<T> onSelected,
  }) => SegmentedButton<T>(
    showSelectedIcon: false,
    style: SegmentedButton.styleFrom(
      minimumSize: const Size(0, 40),
      tapTargetSize: MaterialTapTargetSize.padded,
      padding: const EdgeInsets.symmetric(horizontal: Gap.l),
    ),
    segments: [
      for (final value in values)
        ButtonSegment(
          value: value,
          label: SelectionContainer.disabled(child: Text(label(value))),
        ),
    ],
    selected: {selected},
    onSelectionChanged: (values) {
      final value = values.single;
      if (value == selected) return;
      HapticFeedback.selectionClick();
      onSelected(value);
    },
  );

  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(Gap.page, Gap.xs, Gap.page, Gap.s),
      child: Row(
        children: [
          _group(
            values: const [
              ContentDimension.all,
              ContentDimension.twoD,
              ContentDimension.threeD,
            ],
            selected: dimension,
            label: (value) => value.label,
            onSelected: onDimension,
          ),
          const SizedBox(width: Gap.m),
          _group(
            values: ContentMedia.values,
            selected: media,
            label: (value) => value.label,
            onSelected: onMedia,
          ),
        ],
      ),
    ),
  );
}
