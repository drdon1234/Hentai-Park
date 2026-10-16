import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../../core/models.dart';
import '../../core/settings.dart';
import '../../core/translation_options.dart';
import '../../core/translator.dart';
import '../../engine/source_manager.dart';
import '../kit/adaptive_sheet.dart';
import '../kit/selection_chip.dart';
import '../theme.dart';

/// A keyword plus its translations, searched together.
class MultiKeyword {
  const MultiKeyword(this.original, this.translations, {this.sourceLanguage});
  final String original;
  final String? sourceLanguage;

  /// Language code → translated keyword (only the ones that differ from [original]).
  final Map<String, String> translations;

  /// Original first, then distinct translations.
  List<String> get all {
    final seen = <String>{original.toLowerCase()};
    return [
      original,
      ...translations.values.where((t) => seen.add(t.toLowerCase())),
    ];
  }
}

/// 搜索页面共享翻译忙碌状态；编辑、提交新搜索或销毁后丢弃旧结果。
class KeywordTranslationRequest extends ChangeNotifier {
  bool _busy = false;
  bool _disposed = false;
  bool get busy => _busy;

  Future<MultiKeyword?> run({
    required String Function() keyword,
    required int Function() generation,
    required Future<MultiKeyword?> Function(String) translate,
  }) async {
    if (_disposed || _busy) return null;
    final text = keyword().trim();
    if (text.isEmpty) return null;
    final revision = generation();
    _busy = true;
    notifyListeners();
    try {
      final result = await translate(text);
      if (_disposed || keyword().trim() != text || generation() != revision) {
        return null;
      }
      return result;
    } finally {
      _busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// 给多语言按钮明确职责和执行入口，空输入也能看到说明与设置。
Future<bool> confirmMultiLanguageSearch(
  BuildContext context,
  String keyword,
) async {
  final settings = AppSettings.instance;
  final selected = settings.translateTargets.toSet();
  final approved = await showAdaptiveSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, refresh) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(tr('多语言搜索'), style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 12),
              Text(tr('将关键词翻译为所选语言，同时搜索原词和译词并合并结果。')),
              const SizedBox(height: 12),
              if (keyword.trim().isEmpty)
                Text(tr('请先输入搜索关键词'))
              else
                Text(keyword),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final language in translateLanguages.entries)
                    SelectionChip(
                      label: tr(language.value),
                      selected: selected.contains(language.key),
                      onSelected: (on) => refresh(() {
                        on
                            ? selected.add(language.key)
                            : selected.remove(language.key);
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: keyword.trim().isEmpty || selected.isEmpty
                    ? null
                    : () => Navigator.pop(ctx, true),
                icon: const Icon(Icons.search),
                label: Text(tr('翻译并搜索')),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(tr('取消')),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  if (approved != true) return false;
  settings.translateTargets = selected.toList();
  return true;
}

/// Translates [keyword] into the languages picked in settings. Shows a toast and returns null on failure.
Future<MultiKeyword?> translateKeyword(
  BuildContext context,
  String keyword,
) async {
  final k = keyword.trim();
  if (k.isEmpty) return null;
  final s = AppSettings.instance;
  final targets = s.translateTargets;
  if (targets.isEmpty) {
    context.toast(tr('请先在「我的 › 搜索与翻译」中选择语言'));
    return null;
  }
  try {
    final result = await Translator.instance.translateAll(
      k,
      targets,
      engine: s.translateEngine,
    );
    final map = result.translations;
    map.removeWhere((_, v) => v.toLowerCase() == k.toLowerCase());
    return MultiKeyword(k, map, sourceLanguage: result.sourceLanguage);
  } catch (e) {
    if (context.mounted) {
      context.toast(
        tr('翻译失败：{error}', {'error': e is SourceError ? e.message : e}),
      );
    }
    return null;
  }
}

/// Pages through one source for several keywords at once, interleaving and merging the results.
class MultiKeywordSearch {
  MultiKeywordSearch(
    this.source,
    this.keywords,
    this.filters, {
    SourceManager? sourceManager,
    this.cancelToken,
  }) : _sources = sourceManager ?? SourceManager.instance;
  final SourceManager _sources;
  final CancelToken? cancelToken;
  final String source;
  final List<String> keywords;
  final Map<String, Object?> filters;
  final _state = <String, ({int page, String? cursor, bool hasNext})>{};
  int _page = 0;

  Future<WorkPage> next() async {
    final active = keywords.where((k) => _state[k]?.hasNext ?? true).toList();
    if (cancelToken?.cancelError case final error?) throw error;
    Object? firstError;
    final results = await Future.wait(
      active.map((k) async {
        final st = _state[k];
        final prev = st?.page ?? 0;
        try {
          final r = await _sources.search(
            source,
            keyword: k,
            page: prev + 1,
            cursor: st?.cursor,
            filters: filters,
            cancelToken: cancelToken,
          );
          _state[k] = (
            page: r.page > prev ? r.page : prev + 1,
            cursor: r.cursor,
            hasNext: r.hasNext && r.items.isNotEmpty,
          );
          return r.items;
        } catch (e) {
          firstError ??= e;
          // Failed requests did not consume a page. Keep them active for the next retry.
          _state[k] = (page: prev, cursor: st?.cursor, hasNext: true);
          return null;
        }
      }),
    );
    if (results.every((r) => r == null) && firstError != null) {
      throw firstError!;
    }
    final lists = results.whereType<List<WorkItem>>().toList();
    final merged = <WorkItem>[];
    final seen = <String>{};
    for (var i = 0; lists.any((l) => i < l.length); i++) {
      for (final l in lists) {
        if (i < l.length && seen.add(l[i].id)) merged.add(l[i]);
      }
    }
    final more = _state.values.any((s) => s.hasNext);
    return WorkPage(
      items: merged,
      page: ++_page,
      hasNext: more,
      cursor: more ? 'multi' : null,
    );
  }
}

/// Strip listing the translated keywords; tapping one searches only that keyword.
class TranslationsBar extends StatelessWidget {
  const TranslationsBar({
    super.key,
    required this.keyword,
    required this.onPick,
  });
  final MultiKeyword keyword;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final entries = keyword.translations.entries.toList();
    return SizedBox(
      height:
          48 +
          (MediaQuery.textScalerOf(context).scale(14) - 14).clamp(
            0,
            double.infinity,
          ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Chip(
              avatar: Icon(
                Icons.translate_rounded,
                size: 16,
                color: context.colors.primary,
              ),
              label: Text(
                tr('多语言 · {count} 个关键词', {'count': keyword.all.length}),
              ),
              visualDensity: VisualDensity.compact,
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 6),
            child: ActionChip(
              avatar: const Icon(Icons.edit_note_rounded, size: 16),
              label: Text(
                keyword.sourceLanguage == null
                    ? tr('原文：{keyword}', {'keyword': keyword.original})
                    : tr('原文 · {language}：{keyword}', {
                        'language': tr(
                          translateLanguages[keyword.sourceLanguage] ??
                              keyword.sourceLanguage!,
                        ),
                        'keyword': keyword.original,
                      }),
              ),
              visualDensity: VisualDensity.compact,
              onPressed: () => onPick(keyword.original),
            ),
          ),
          for (final e in entries)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ActionChip(
                label: Text(
                  '${tr(translateLanguages[e.key] ?? e.key)}：${e.value}',
                ),
                visualDensity: VisualDensity.compact,
                onPressed: () => onPick(e.value),
              ),
            ),
        ],
      ),
    );
  }
}
