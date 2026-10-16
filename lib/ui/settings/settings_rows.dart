import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../kit/kit.dart';
import '../theme.dart';

/// A labelled integer slider row used by several settings sections.
class SettingsSlider extends StatelessWidget {
  const SettingsSlider({
    super.key,
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });
  final String title;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => SelectionContainer.disabled(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(Gap.page, Gap.m, Gap.s, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: context.text.bodyLarge)),
              Padding(
                padding: const EdgeInsets.only(right: Gap.s),
                child: Text(
                  '$value',
                  style: context.text.bodyLarge?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          Slider(
            value: value.toDouble(),
            min: min.toDouble(),
            max: max.toDouble(),
            divisions: max - min,
            label: '$value',
            onChanged: (v) => onChanged(v.round()),
          ),
        ],
      ),
    ),
  );
}

/// Picks one of [options] (value → label) in the shared choice sheet.
Future<T?> chooseSetting<T>(
  BuildContext context,
  String title,
  Map<T, String> options,
  T current,
) => showChoiceSheet<T>(
  context,
  title: title,
  options: options.keys.toList(),
  selected: current,
  label: (option) => options[option]!,
);

/// Asks for one line of text, starting from [initial].
Future<String?> askSettingText(
  BuildContext context,
  String title,
  String initial, {
  String? hint,
}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        decoration: InputDecoration(hintText: hint),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: SelectionContainer.disabled(child: Text(tr('取消'))),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, c.text.trim()),
          child: SelectionContainer.disabled(child: Text(tr('保存'))),
        ),
      ],
    ),
  );
}
