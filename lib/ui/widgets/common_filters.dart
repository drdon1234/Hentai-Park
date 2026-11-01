import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/localization.dart';
import '../../core/models.dart';
import '../kit/selection_menu.dart';
import '../kit/tokens.dart';
import '../theme.dart';

class CommonFilterFields extends StatefulWidget {
  const CommonFilterFields({
    super.key,
    required this.definitions,
    required this.initialValues,
    required this.onChanged,
  });

  final List<CommonFilterDef> definitions;
  final Map<String, Object?> initialValues;
  final void Function(Map<String, Object?> values, bool valid) onChanged;

  @override
  State<CommonFilterFields> createState() => _CommonFilterFieldsState();
}

class _CommonFilterFieldsState extends State<CommonFilterFields> {
  final _controllers = <String, TextEditingController>{};
  final _orders = <String, String>{};
  Map<String, String> _errors = const {};

  @override
  void initState() {
    super.initState();
    for (final definition in widget.definitions) {
      final key = definition.dimension.name;
      final value = widget.initialValues[key] as Map?;
      _controllers['$key:min'] = TextEditingController(
        text: value?['min']?.toString() ?? '',
      );
      _controllers['$key:max'] = TextEditingController(
        text: value?['max']?.toString() ?? '',
      );
      final order = value?['order'];
      _orders[key] = definition.sortOrders.contains(order)
          ? order.toString()
          : '';
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _emit();
    });
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _emit() {
    final values = <String, Object?>{};
    final errors = <String, String>{};
    for (final definition in widget.definitions) {
      final key = definition.dimension.name;
      final minText = definition.minimum
          ? _controllers['$key:min']!.text.trim()
          : '';
      final maxText = definition.maximum
          ? _controllers['$key:max']!.text.trim()
          : '';
      final decimal = definition.dimension == CommonFilterDimension.duration;
      final min = minText.isEmpty
          ? null
          : decimal
          ? num.tryParse(minText)
          : int.tryParse(minText);
      final max = maxText.isEmpty
          ? null
          : decimal
          ? num.tryParse(maxText)
          : int.tryParse(maxText);
      final signed = definition.dimension == CommonFilterDimension.score;
      if ((minText.isNotEmpty && (min == null || (!signed && min < 0))) ||
          (maxText.isNotEmpty && (max == null || (!signed && max < 0)))) {
        errors[key] = tr(signed ? '请输入有效的整数' : '请输入有效的非负数');
        continue;
      }
      if (min != null && max != null && min > max) {
        errors[key] = tr('最小值不能大于最大值');
        continue;
      }
      final value = <String, Object?>{};
      if (definition.range && min != null) value['min'] = min;
      if (definition.range && max != null) value['max'] = max;
      final order = _orders[key];
      if (definition.sort && (order == 'asc' || order == 'desc')) {
        value['order'] = order;
      }
      if (value.isNotEmpty) {
        try {
          values.addAll(normalizeCommonFilters([definition], {key: value}));
        } on FormatException {
          errors[key] = tr(signed ? '请输入有效的整数' : '请输入有效的非负数');
        }
      }
    }
    setState(() => _errors = errors);
    widget.onChanged(Map.unmodifiable(values), errors.isEmpty);
  }

  void _setOrder(String key, String? value) {
    final order = value ?? '';
    if (order.isNotEmpty) {
      for (final otherKey in _orders.keys.toList()) {
        if (otherKey != key && _orders[otherKey]!.isNotEmpty) {
          _orders[otherKey] = '';
        }
      }
    }
    _orders[key] = order;
    _emit();
  }

  String _label(CommonFilterDimension dimension) => tr(switch (dimension) {
    CommonFilterDimension.pages => '页数',
    CommonFilterDimension.likes => '点赞数',
    CommonFilterDimension.score => '分数',
    CommonFilterDimension.favorites => '收藏数',
    CommonFilterDimension.duration => '时长（秒）',
  });

  Widget _boundField(
    BuildContext context,
    String key,
    String side,
    String label,
  ) => TextField(
    controller: _controllers['$key:$side'],
    keyboardType: TextInputType.numberWithOptions(
      decimal: key == CommonFilterDimension.duration.name,
      signed: key == CommonFilterDimension.score.name,
    ),
    inputFormatters: [
      FilteringTextInputFormatter.allow(
        key == CommonFilterDimension.duration.name
            ? RegExp(r'[0-9.]')
            : key == CommonFilterDimension.score.name
            ? RegExp(r'[0-9-]')
            : RegExp(r'[0-9]'),
      ),
    ],
    decoration: InputDecoration(
      labelText: label,
      hintText: tr('不限制'),
      suffixIcon: _controllers['$key:$side']!.text.isEmpty
          ? null
          : IconButton(
              tooltip: tr('清空'),
              onPressed: () {
                _controllers['$key:$side']!.clear();
                _emit();
              },
              icon: const Icon(Icons.close_rounded),
            ),
    ),
    onChanged: (_) => _emit(),
  );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final definition in widget.definitions) ...[
            const SizedBox(height: Gap.m),
            Text(_label(definition.dimension), style: context.text.titleSmall),
            if (definition.range) ...[
              const SizedBox(height: Gap.s),
              if (constraints.maxWidth < 440 ||
                  definition.minimum != definition.maximum) ...[
                if (definition.minimum)
                  _boundField(
                    context,
                    definition.dimension.name,
                    'min',
                    tr('最小值'),
                  ),
                if (definition.minimum && definition.maximum)
                  const SizedBox(height: Gap.s),
                if (definition.maximum)
                  _boundField(
                    context,
                    definition.dimension.name,
                    'max',
                    tr('最大值'),
                  ),
              ] else
                Row(
                  children: [
                    Expanded(
                      child: _boundField(
                        context,
                        definition.dimension.name,
                        'min',
                        tr('最小值'),
                      ),
                    ),
                    const SizedBox(width: Gap.s),
                    Expanded(
                      child: _boundField(
                        context,
                        definition.dimension.name,
                        'max',
                        tr('最大值'),
                      ),
                    ),
                  ],
                ),
            ],
            if (definition.sort) ...[
              const SizedBox(height: Gap.s),
              SelectionDropdownTheme(
                child: DropdownButtonFormField<String>(
                  key: ValueKey((
                    definition.dimension,
                    _orders[definition.dimension.name],
                  )),
                  initialValue: _orders[definition.dimension.name] ?? '',
                  decoration: InputDecoration(labelText: tr('排序')),
                  items: [
                    SelectionDropdownItem(
                      value: '',
                      selected:
                          (_orders[definition.dimension.name] ?? '').isEmpty,
                      child: Text(tr('默认')),
                    ),
                    if (definition.sortOrders.contains('asc'))
                      SelectionDropdownItem(
                        value: 'asc',
                        selected: _orders[definition.dimension.name] == 'asc',
                        child: Text(tr('升序')),
                      ),
                    if (definition.sortOrders.contains('desc'))
                      SelectionDropdownItem(
                        value: 'desc',
                        selected: _orders[definition.dimension.name] == 'desc',
                        child: Text(tr('降序')),
                      ),
                  ],
                  onChanged: (value) {
                    _setOrder(definition.dimension.name, value);
                  },
                ),
              ),
            ],
            if (_errors[definition.dimension.name] case final error?)
              Padding(
                padding: const EdgeInsets.only(top: Gap.xs),
                child: Text(
                  error,
                  style: context.text.bodySmall?.copyWith(
                    color: context.colors.error,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
