import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../../core/models.dart';
import '../kit/selection_menu.dart';
import '../kit/tokens.dart';
import '../theme.dart';
import 'content_translation.dart';

/// Rows of horizontally scrolling chips, one row per option (period, category, sort…).
class OptionBar extends StatelessWidget {
  const OptionBar({
    super.key,
    required this.options,
    required this.values,
    required this.onChanged,
    this.dropdowns = false,
    this.source = '',
    this.dynamicChoices = const {},
    this.loadingOptions = const {},
    this.optionErrors = const {},
    this.enabledOptions = const {},
    this.onRetry,
    this.padding = const EdgeInsets.fromLTRB(Gap.page, Gap.s, Gap.page, 0),
  });
  final List<OptionDef> options;
  final Map<String, Object?> values;
  final ValueChanged<Map<String, Object?>> onChanged;
  final EdgeInsets padding;
  final bool dropdowns;
  final String source;
  final Map<String, List<Choice>> dynamicChoices;
  final Set<String> loadingOptions;
  final Map<String, String?> optionErrors;
  final Map<String, bool> enabledOptions;
  final ValueChanged<String>? onRetry;

  static Widget choiceLabel(OptionDef option, Choice choice, String source) {
    Widget text(String value) =>
        Text(value, maxLines: 1, overflow: TextOverflow.ellipsis);
    return option.dynamicValues
        ? ContentTranslation(
            text: choice.label,
            source: source,
            tag: true,
            namespace: option.key,
            builder: text,
          )
        : text(choice.label);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Column(
        children: [
          for (final o in options)
            if (enabledOptions[o.key] == false)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  o.label,
                  style: TextStyle(color: Theme.of(context).disabledColor),
                ),
              )
            else if (dropdowns && o.type == 'select')
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SelectionContainer.disabled(
                  child: SelectionDropdownTheme(
                    child: DropdownButtonFormField<int>(
                      key: ValueKey('${o.key}:${values[o.key]}'),
                      initialValue:
                          (dynamicChoices[o.key] ?? o.values).indexWhere(
                                (c) => c.value == values[o.key],
                              ) <
                              0
                          ? null
                          : (dynamicChoices[o.key] ?? o.values).indexWhere(
                              (c) => c.value == values[o.key],
                            ),
                      isExpanded: true,
                      decoration: InputDecoration(labelText: o.label),
                      items: [
                        for (
                          var i = 0;
                          i < (dynamicChoices[o.key] ?? o.values).length;
                          i++
                        )
                          SelectionDropdownItem(
                            value: i,
                            selected:
                                (dynamicChoices[o.key] ?? o.values).indexWhere(
                                  (choice) => choice.value == values[o.key],
                                ) ==
                                i,
                            child: SelectionContainer.disabled(
                              child: choiceLabel(
                                o,
                                (dynamicChoices[o.key] ?? o.values)[i],
                                source,
                              ),
                            ),
                          ),
                      ],
                      onChanged: (i) {
                        if (i != null) {
                          onChanged({
                            ...values,
                            o.key: (dynamicChoices[o.key] ?? o.values)[i].value,
                          });
                        }
                      },
                    ),
                  ),
                ),
              )
            else if (o.type == 'select' || o.type == 'multi')
              _OptionRow(
                option: o,
                values: values,
                onChanged: onChanged,
                showLabel: options.length > 1,
                source: source,
                choices: dynamicChoices[o.key] ?? o.values,
                loading: loadingOptions.contains(o.key),
                error: optionErrors[o.key],
                onRetry: onRetry,
              ),
        ],
      ),
    );
  }
}

/// One option row. The selected chip is scrolled into view, so a default like "全彩" that sits far
/// down a long category list is still visible when the page opens.
class _OptionRow extends StatefulWidget {
  const _OptionRow({
    required this.option,
    required this.values,
    required this.onChanged,
    required this.showLabel,
    required this.source,
    required this.choices,
    required this.loading,
    required this.error,
    required this.onRetry,
  });
  final OptionDef option;
  final Map<String, Object?> values;
  final ValueChanged<Map<String, Object?>> onChanged;
  final bool showLabel;
  final String source;
  final List<Choice> choices;
  final bool loading;
  final String? error;
  final ValueChanged<String>? onRetry;

  @override
  State<_OptionRow> createState() => _OptionRowState();
}

class _OptionRowState extends State<_OptionRow> {
  final _selectedKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _selectedKey.currentContext;
      if (ctx != null) {
        final object = ctx.findRenderObject();
        final scrollable = Scrollable.maybeOf(ctx, axis: Axis.horizontal);
        if (object != null && scrollable != null) {
          scrollable.position.ensureVisible(object, alignment: 0.3);
        }
      }
    });
  }

  bool _isSelected(Choice choice) {
    final v = widget.values[widget.option.key];
    return widget.option.type == 'multi'
        ? ((v as List?) ?? const []).contains(choice.value)
        : v == choice.value;
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.option;
    if (widget.choices.isEmpty && widget.loading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Text(o.label),
            const SizedBox(width: 10),
            const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ),
      );
    }
    if (widget.choices.isEmpty && widget.error != null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: widget.onRetry == null
              ? null
              : () => widget.onRetry!(o.key),
          icon: const Icon(Icons.refresh_rounded),
          label: Text(tr('加载失败，点击重试  {value0}', {'value0': o.label})),
        ),
      );
    }
    var keyed = false;
    final labelStyle = context.text.labelMedium;
    final labelHeight =
        MediaQuery.textScalerOf(context).scale(labelStyle?.fontSize ?? 14) *
        (labelStyle?.height ?? 1.4);
    return SizedBox(
      height: (labelHeight + Gap.l).clamp(48.0, double.infinity),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          if (widget.showLabel)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(left: 4, right: 10),
                child: Text(
                  o.label,
                  style: context.text.labelLarge?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          for (final choice in widget.choices)
            Padding(
              // Only the first selected chip needs a key to scroll to.
              key: !keyed && _isSelected(choice) && (keyed = true)
                  ? _selectedKey
                  : null,
              padding: const EdgeInsets.only(right: 6),
              child: Center(child: _chip(context, o, choice)),
            ),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, OptionDef o, Choice choice) {
    final color = choice.color != null ? parseHexColor(choice.color!) : null;
    final values = widget.values;
    if (o.type == 'multi') {
      final current = (values[o.key] as List?)?.toList() ?? [];
      return FilterChip(
        label: SelectionContainer.disabled(
          child: OptionBar.choiceLabel(o, choice, widget.source),
        ),
        selected: current.contains(choice.value),
        showCheckmark: false,
        selectedColor: color?.withValues(alpha: 0.35),
        avatar: color != null
            ? CircleAvatar(backgroundColor: color, radius: 5)
            : null,
        onSelected: (on) {
          final next = [...current];
          on ? next.add(choice.value) : next.remove(choice.value);
          widget.onChanged({...values, o.key: next});
        },
      );
    }
    return ChoiceChip(
      label: SelectionContainer.disabled(
        child: OptionBar.choiceLabel(o, choice, widget.source),
      ),
      selected: values[o.key] == choice.value,
      showCheckmark: false,
      onSelected: (_) => widget.onChanged({...values, o.key: choice.value}),
    );
  }
}
