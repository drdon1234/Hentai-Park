import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../kit/kit.dart';
import '../theme.dart';

/// 设置单选统一使用整行入口、当前值和共享选择面板。
class SettingsChoice<T> extends StatelessWidget {
  const SettingsChoice({
    super.key,
    required this.title,
    required this.value,
    required this.options,
    required this.onChanged,
    this.leading,
  });

  final String title;
  final T value;
  final Map<T, String> options;
  final ValueChanged<T>? onChanged;
  final Widget? leading;

  @override
  Widget build(BuildContext context) => ListRow(
    title: title,
    titleMaxLines: null,
    subtitle: options[value] ?? '$value',
    leading: leading,
    trailing: const Icon(Icons.chevron_right_rounded),
    enabled: onChanged != null,
    onTap: () async {
      final selected = await chooseSetting(context, title, options, value);
      if (selected != null && context.mounted && selected != value) {
        onChanged?.call(selected);
      }
    },
  );
}

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
          Slider.adaptive(
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
  var value = initial;
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextFormField(
        initialValue: initial,
        onChanged: (text) => value = text,
        autofocus: true,
        decoration: InputDecoration(hintText: hint),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: SelectionContainer.disabled(child: Text(tr('取消'))),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, value.trim()),
          child: SelectionContainer.disabled(child: Text(tr('保存'))),
        ),
      ],
    ),
  );
}
