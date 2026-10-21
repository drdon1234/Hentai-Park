import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/models.dart';

typedef DynamicOptionLoader = Future<List<Choice>> Function(
  String filter,
  Map<String, Object?> values,
  CancelToken cancelToken,
);

class _CachedChoices {
  _CachedChoices(this.choices, this.createdAt);
  final List<Choice> choices;
  final DateTime createdAt;
}

/// Holds feed or search filter values and their dynamically loaded choices.
class FilterController extends ChangeNotifier {
  FilterController({
    required this.source,
    required this.scope,
    required this.definitions,
    required this.loader,
    this.feed,
    this.keyword,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    if (scope != 'feed' && scope != 'search') {
      throw ArgumentError.value(scope, 'scope');
    }
    _byKey = {for (final option in definitions) option.key: option};
    if (_byKey.length != definitions.length ||
        definitions.any((option) => option.key.isEmpty)) {
      throw ArgumentError('筛选项 key 必须唯一且非空');
    }
    for (final option in definitions) {
      if (!option.dynamicValues && option.dependsOn.isNotEmpty) {
        throw ArgumentError('只有动态筛选项可以声明依赖');
      }
      if (option.dependsOn.toSet().length != option.dependsOn.length ||
          option.dependsOn.any((key) => !_byKey.containsKey(key))) {
        throw ArgumentError('筛选项依赖不存在或重复');
      }
    }
    _checkAcyclic();
    _values = {
      for (final option in definitions) option.key: option.defaultValue,
    };
  }

  static const cacheDuration = Duration(minutes: 2);
  final String source;
  final String scope;
  final String? feed;
  final String? keyword;
  final List<OptionDef> definitions;
  final DynamicOptionLoader loader;
  final DateTime Function() _clock;
  late final Map<String, OptionDef> _byKey;
  late final Map<String, Object?> _values;
  final Map<String, List<Choice>> _choices = {};
  final Map<String, String> _errors = {};
  final Map<String, CancelToken> _requests = {};
  final Map<String, int> _generations = {};
  final Map<String, _CachedChoices> _cache = {};
  bool _disposed = false;

  Map<String, Object?> get values => Map.unmodifiable(_values);
  List<Choice> choicesFor(String key) =>
      _choices[key] ?? _byKey[key]?.values ?? const [];
  bool get isLoading => _requests.isNotEmpty;
  bool isLoadingOption(String key) => _requests.containsKey(key);
  String? errorFor(String key) => _errors[key];

  Future<void> initialize({
    Map<String, Object?> initialValues = const {},
  }) async {
    for (final option in _topologicalOrder()) {
      if (_disposed) return;
      if (initialValues.containsKey(option.key)) {
        if (option.dynamicValues && isEnabled(option.key)) {
          await loadDynamic(option.key);
          if (_disposed) return;
        }
        setValue(option.key, initialValues[option.key]);
      }
    }
  }

  Future<void> loadEnabledDynamic() async {
    for (final option in _topologicalOrder()) {
      if (_disposed) return;
      if (option.dynamicValues && isEnabled(option.key)) {
        await loadDynamic(option.key);
      }
    }
  }

  bool isEnabled(String key) {
    final option = _byKey[key];
    return option != null && option.dependsOn.every(_hasValidValue);
  }

  void setValue(String key, Object? value) {
    if (_disposed) return;
    final option = _byKey[key];
    if (option == null) throw ArgumentError.value(key, 'key');
    if (!isEnabled(key) && value != null) return;
    if (value != null && !_isValid(option, value)) return;
    if (_values[key] == value || _sameList(_values[key], value)) return;
    _values[key] = value;
    for (final child in _descendants(key)) {
      _values[child] = null;
      _choices.remove(child);
      _errors.remove(child);
      _requests.remove(child)?.cancel('上级筛选已变化');
      _generations[child] = (_generations[child] ?? 0) + 1;
    }
    notifyListeners();
  }

  Future<bool> loadDynamic(String key) async {
    final option = _byKey[key];
    if (_disposed ||
        option == null ||
        !option.dynamicValues ||
        !isEnabled(key)) {
      return false;
    }
    final parents = <String, Object?>{
      for (final parent in option.dependsOn) parent: _values[parent],
    };
    final cacheKey = jsonEncode([
      source,
      scope,
      feed,
      keyword,
      key,
      for (final parent in option.dependsOn) [parent, parents[parent]],
    ]);
    final cached = _cache[cacheKey];
    if (cached != null &&
        _clock().difference(cached.createdAt) < cacheDuration) {
      _choices[key] = cached.choices;
      _errors.remove(key);
      _pruneSelection(option, cached.choices);
      notifyListeners();
      return true;
    }

    _requests.remove(key)?.cancel('筛选上下文已变化');
    final token = CancelToken();
    _requests[key] = token;
    final generation = (_generations[key] ?? 0) + 1;
    _generations[key] = generation;
    _errors.remove(key);
    notifyListeners();
    try {
      final choices = await loader(key, Map.unmodifiable(parents), token);
      if (token.isCancelled ||
          _generations[key] != generation ||
          !_sameContext(option, parents)) {
        return false;
      }
      final seen = <Object?>{};
      if (choices.length > 500 ||
          choices.any(
            (choice) =>
                choice.value == null ||
                choice.label.trim().isEmpty ||
                !seen.add(choice.value),
          )) {
        throw const FormatException('动态筛选候选无效');
      }
      _choices[key] = List.unmodifiable(choices);
      _cache[cacheKey] = _CachedChoices(_choices[key]!, _clock());
      _cache.removeWhere(
        (_, item) => _clock().difference(item.createdAt) >= cacheDuration,
      );
      while (_cache.length > 128) {
        _cache.remove(_cache.keys.first);
      }
      _pruneSelection(option, choices);
      return true;
    } catch (error) {
      if (!token.isCancelled && _generations[key] == generation) {
        _errors[key] = error.toString();
      }
      return false;
    } finally {
      if (identical(_requests[key], token)) {
        _requests.remove(key);
        notifyListeners();
      }
    }
  }

  void reset() {
    if (_disposed) return;
    for (final token in _requests.values) {
      token.cancel('筛选已重置');
    }
    _requests.clear();
    _choices.clear();
    _errors.clear();
    _values
      ..clear()
      ..addEntries(
        definitions.map((option) => MapEntry(option.key, option.defaultValue)),
      );
    unawaited(loadEnabledDynamic());
    notifyListeners();
  }

  bool _hasValidValue(String key) {
    final parent = _byKey[key];
    final value = _values[key];
    return parent != null &&
        value != null &&
        value != '' &&
        _isValid(parent, value);
  }

  bool _isValid(OptionDef option, Object value) {
    final choices = _choices[option.key] ?? option.values;
    if (option.type == 'multi' && value is List) {
      return value.every(
        (item) => choices.any((choice) => choice.value == item),
      );
    }
    if (option.type == 'switch') return value is bool;
    if (option.type == 'text' || option.type == 'number') return true;
    return choices.any((choice) => choice.value == value);
  }

  Set<String> _descendants(String key) {
    final result = <String>{};
    var changed = true;
    while (changed) {
      changed = false;
      for (final option in definitions) {
        if (!result.contains(option.key) &&
            option.dependsOn.any(
              (parent) => parent == key || result.contains(parent),
            )) {
          result.add(option.key);
          changed = true;
        }
      }
    }
    return result;
  }

  bool _sameContext(OptionDef option, Map<String, Object?> parents) =>
      option.dependsOn.every((key) => _values[key] == parents[key]);

  void _pruneSelection(OptionDef option, List<Choice> choices) {
    final selected = _values[option.key];
    if (selected is List) {
      _values[option.key] = selected
          .where((value) => choices.any((choice) => choice.value == value))
          .toList();
    } else if (selected == null ||
        !choices.any((choice) => choice.value == selected)) {
      _values[option.key] =
          option.defaultValue != null &&
              choices.any((choice) => choice.value == option.defaultValue)
          ? option.defaultValue
          : null;
    }
  }

  bool _sameList(Object? a, Object? b) =>
      a is List && b is List && listEquals(a, b);

  void _checkAcyclic() {
    final visiting = <String>{};
    final visited = <String>{};
    void visit(String key) {
      if (visiting.contains(key)) throw ArgumentError('筛选项依赖存在循环');
      if (!visited.add(key)) return;
      visiting.add(key);
      for (final parent in _byKey[key]!.dependsOn) {
        visit(parent);
      }
      visiting.remove(key);
    }

    for (final key in _byKey.keys) {
      visit(key);
    }
  }

  List<OptionDef> _topologicalOrder() {
    final ordered = <OptionDef>[];
    final visited = <String>{};
    void visit(OptionDef option) {
      if (!visited.add(option.key)) return;
      for (final key in option.dependsOn) {
        visit(_byKey[key]!);
      }
      ordered.add(option);
    }

    for (final option in definitions) {
      visit(option);
    }
    return ordered;
  }

  @override
  void dispose() {
    _disposed = true;
    for (final token in _requests.values) {
      token.cancel('筛选控制器已销毁');
    }
    _requests.clear();
    super.dispose();
  }
}
