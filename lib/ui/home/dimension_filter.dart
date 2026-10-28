import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/localization.dart';
import '../../core/models.dart';
import '../kit/kit.dart';
import '../theme.dart';

/// 搜索上方的主页筛选；两项保持同一行，并同时影响主页域展示和搜索范围。
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

  static Widget _dropdown<T>({
    required BuildContext context,
    required List<T> values,
    required T selected,
    required String title,
    required String Function(T) label,
    required ValueChanged<T> onSelected,
  }) {
    final colors = context.colors;
    return PopupMenuButton<T>(
      tooltip: title,
      position: PopupMenuPosition.under,
      popUpAnimationStyle: Motion.menu(context),
      onSelected: (value) {
        if (value == selected) return;
        HapticFeedback.selectionClick();
        onSelected(value);
      },
      itemBuilder: (_) => [
        for (final value in values)
          SelectionPopupMenuItem<T>(
            value: value,
            selected: value == selected,
            child: SelectionContainer.disabled(child: Text(label(value))),
          ),
      ],
      child: Semantics(
        button: true,
        label: '$title：${label(selected)}',
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(
            horizontal: Gap.m,
            vertical: Gap.s,
          ),
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            border: Border.all(color: colors.outlineVariant),
            borderRadius: Radii.small,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final titleStyle = context.text.labelMedium?.copyWith(
                color: colors.onSurfaceVariant,
                fontWeight: FontWeight.w400,
              );
              final valueStyle = context.text.labelLarge?.copyWith(
                color: colors.onSurface,
                fontWeight: FontWeight.w600,
              );
              double widthOf(String text, TextStyle? style) {
                final painter = TextPainter(
                  text: TextSpan(text: text, style: style),
                  textDirection: Directionality.of(context),
                  textScaler: MediaQuery.textScalerOf(context),
                )..layout();
                final width = painter.width;
                painter.dispose();
                return width;
              }

              final stacked =
                  widthOf(title, titleStyle) +
                      widthOf(label(selected), valueStyle) +
                      Gap.s +
                      Gap.xs +
                      20 >
                  constraints.maxWidth;
              final heading = Text(title, style: titleStyle);
              final value = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      label(selected),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: valueStyle,
                    ),
                  ),
                  const SizedBox(width: Gap.xs),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 20,
                    color: colors.onSurfaceVariant,
                  ),
                ],
              );
              return stacked
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        heading,
                        const SizedBox(height: Gap.xs),
                        value,
                      ],
                    )
                  : Row(
                      children: [
                        heading,
                        const SizedBox(width: Gap.s),
                        Flexible(child: value),
                      ],
                    );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Gap.page, Gap.s, Gap.page, Gap.m),
    child: Row(
      children: [
        Expanded(
          child: _dropdown(
            context: context,
            title: tr('内容范围'),
            values: const [
              ContentDimension.all,
              ContentDimension.twoD,
              ContentDimension.threeD,
            ],
            selected: dimension,
            label: (value) => value.label,
            onSelected: onDimension,
          ),
        ),
        const SizedBox(width: Gap.s),
        Expanded(
          child: _dropdown(
            context: context,
            title: tr('媒体类型'),
            values: ContentMedia.values,
            selected: media,
            label: (value) => value.label,
            onSelected: onMedia,
          ),
        ),
      ],
    ),
  );
}
