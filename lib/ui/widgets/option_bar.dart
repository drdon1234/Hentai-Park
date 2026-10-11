import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../theme.dart';

/// Rows of horizontally scrolling chips, one row per option (period, category, sort…).
class OptionBar extends StatelessWidget {
  const OptionBar({super.key, required this.options, required this.values, required this.onChanged, this.padding = const EdgeInsets.fromLTRB(12, 8, 12, 0)});
  final List<OptionDef> options;
  final Map<String, Object?> values;
  final ValueChanged<Map<String, Object?>> onChanged;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Column(
        children: [
          for (final o in options)
            if (o.type == 'select' || o.type == 'multi') _OptionRow(option: o, values: values, onChanged: onChanged, showLabel: options.length > 1),
        ],
      ),
    );
  }
}

/// One option row. The selected chip is scrolled into view, so a default like "全彩" that sits far
/// down a long category list is still visible when the page opens.
class _OptionRow extends StatefulWidget {
  const _OptionRow({required this.option, required this.values, required this.onChanged, required this.showLabel});
  final OptionDef option;
  final Map<String, Object?> values;
  final ValueChanged<Map<String, Object?>> onChanged;
  final bool showLabel;

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
      if (ctx != null) Scrollable.ensureVisible(ctx, alignment: 0.3);
    });
  }

  bool _isSelected(Choice choice) {
    final v = widget.values[widget.option.key];
    return widget.option.type == 'multi' ? ((v as List?) ?? const []).contains(choice.value) : v == choice.value;
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.option;
    var keyed = false;
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          if (widget.showLabel)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(left: 4, right: 10),
                child: Text(o.label, style: context.text.labelLarge?.copyWith(color: context.colors.onSurfaceVariant)),
              ),
            ),
          for (final choice in o.values)
            Padding(
              // Only the first selected chip needs a key to scroll to.
              key: !keyed && _isSelected(choice) && (keyed = true) ? _selectedKey : null,
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
        label: Text(choice.label),
        selected: current.contains(choice.value),
        showCheckmark: false,
        selectedColor: color?.withValues(alpha: 0.35),
        avatar: color != null ? CircleAvatar(backgroundColor: color, radius: 5) : null,
        visualDensity: VisualDensity.compact,
        onSelected: (on) {
          final next = [...current];
          on ? next.add(choice.value) : next.remove(choice.value);
          widget.onChanged({...values, o.key: next});
        },
      );
    }
    return ChoiceChip(
      label: Text(choice.label),
      selected: values[o.key] == choice.value,
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      onSelected: (_) => widget.onChanged({...values, o.key: choice.value}),
    );
  }
}
