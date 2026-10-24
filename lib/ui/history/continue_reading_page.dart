import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/content_scope.dart';
import '../../core/localization.dart';
import '../../core/models.dart';
import '../../core/settings.dart';
import '../../engine/source_manager.dart';
import '../../library/library.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/content_translation.dart';
import 'history_scope_selector.dart';

/// Full "continue reading" list with multi-select: remove many entries at once.
class ContinueReadingPage extends StatefulWidget {
  const ContinueReadingPage({
    super.key,
    this.scope = const ContentScope.domain(SourceCategory.doujin),
  });
  final ContentScope scope;

  @override
  State<ContinueReadingPage> createState() => _ContinueReadingPageState();
}

class _ContinueReadingPageState extends State<ContinueReadingPage> {
  final Set<String> _selected = {};
  late ContentScope _scope = widget.scope;

  void _resume(HistoryEntry h) {
    if (kindOf(h.item) != MediaKind.video &&
        h.position == null &&
        h.pageCount == 0) {
      Nav.openWork(context, h.item);
    } else {
      Nav.openChapter(context, h.item, h.chapterId, page: h.page);
    }
  }

  Future<void> _delete() async {
    final n = _selected.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('移除 {value0} 项？', {'value0': n})),
        content: Text(tr('从继续阅读与历史中移除，章节的已读状态会保留。')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: SelectionContainer.disabled(child: Text(tr('取消'))),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: SelectionContainer.disabled(child: Text(tr('移除'))),
          ),
        ],
      ),
    );
    if (ok != true) return;
    Library.instance.removeHistoryMany(_selected);
    setState(_selected.clear);
    if (mounted) context.toast(tr('已移除 {value0} 项', {'value0': n}));
  }

  @override
  Widget build(BuildContext context) {
    return TranslationPage(
      child: ListenableBuilder(
        listenable: Listenable.merge([
          Library.instance.collection(LibraryCollection.history),
          SourceManager.instance,
          AppSettings.instance.watch(const {'domainOrder'}),
        ]),
        builder: (context, _) {
          final list = Library.instance.history(scope: _scope);
          _selected.removeWhere((uid) => !list.any((h) => h.uid == uid));
          final allSelected =
              list.isNotEmpty && list.every((h) => _selected.contains(h.uid));
          final partlySelected =
              !allSelected && list.any((h) => _selected.contains(h.uid));
          return Scaffold(
            appBar: AppBar(
              title: Text(
                _selected.isEmpty
                    ? tr('继续阅读')
                    : tr('已选择 {value0} 项', {'value0': _selected.length}),
              ),
              actions: [
                const TranslationControls(),
                ToolbarActions(
                  actions: [
                    if (partlySelected)
                      ToolbarAction(
                        label: tr('反选'),
                        icon: Icons.swap_horiz_rounded,
                        showLabel: true,
                        onPressed: () => setState(() {
                          for (final h in list) {
                            if (!_selected.remove(h.uid)) _selected.add(h.uid);
                          }
                        }),
                      ),
                    ToolbarAction(
                      label: allSelected ? tr('取消全选') : tr('全选'),
                      icon: Icons.select_all_rounded,
                      showLabel: true,
                      onPressed: list.isEmpty
                          ? null
                          : () => setState(() {
                              if (allSelected) {
                                _selected.removeAll(list.map((h) => h.uid));
                              } else {
                                _selected.addAll(list.map((h) => h.uid));
                              }
                            }),
                    ),
                  ],
                ),
                const SizedBox(width: 4),
              ],
            ),
            body: Column(
              children: [
                HistoryScopeSelector(
                  scope: _scope,
                  onChanged: (scope) => setState(() {
                    _scope = scope;
                    _selected.clear();
                  }),
                ),
                Expanded(
                  child: list.isEmpty
                      ? EmptyState(
                          icon: Icons.history_rounded,
                          title: tr('没有继续阅读的作品'),
                        )
                      : ReadableWidth(
                          child: ListView.builder(
                            padding: const EdgeInsets.only(bottom: 24),
                            itemCount: list.length,
                            itemBuilder: (context, i) =>
                                _tile(context, list[i]),
                          ),
                        ),
                ),
              ],
            ),
            bottomNavigationBar: _selected.isEmpty
                ? null
                : SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => setState(_selected.clear),
                              child: SelectionContainer.disabled(
                                child: Text(tr('取消选择')),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: context.colors.error,
                                foregroundColor: context.colors.onError,
                              ),
                              onPressed: _delete,
                              icon: const Icon(Icons.delete_outline_rounded),
                              label: SelectionContainer.disabled(
                                child: Text(
                                  tr('移除 {value0} 项', {
                                    'value0': _selected.length,
                                  }),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          );
        },
      ),
    );
  }

  void _setSelected(String uid, bool selected) {
    HapticFeedback.selectionClick();
    setState(() => selected ? _selected.add(uid) : _selected.remove(uid));
  }

  Widget _tile(BuildContext context, HistoryEntry h) {
    final c = context.colors;
    final selected = _selected.contains(h.uid);
    return Material(
      color: selected
          ? c.primaryContainer.withValues(alpha: 0.35)
          : Colors.transparent,
      child: InkWell(
        onTap: () => _setSelected(h.uid, !selected),
        child: SelectionContainer.disabled(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
            child: Row(
              children: [
                Checkbox(
                  value: selected,
                  onChanged: (v) => _setSelected(h.uid, v == true),
                ),
                if (!h.item.isNovel &&
                    SourceManager.instance.manifest(h.item.source)?.isNovel !=
                        true) ...[
                  SizedBox(
                    width: 52,
                    height: 70,
                    child: CoverImage(
                      source: h.item.source,
                      url: h.item.cover,
                      sourceBlurred: h.item.json['coverBlurred'] == true,
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ContentTranslation(
                        text: h.item.title,
                        source: h.item.source,
                        builder: (value) => Text(
                          value,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          SourceAvatar(h.item.source, size: 16),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              [
                                dayLabel(h.time),
                                if (h.pageCount > 0)
                                  '${h.chapterTitle != null ? '${h.chapterTitle} ' : ''}${h.item.isNovel ? '${(h.progress * 100).round()}%' : '${h.page + 1}/${h.pageCount}'}',
                                if (h.position != null &&
                                    h.chapterTitle != null)
                                  h.chapterTitle!,
                                if (h.position != null && h.position! > 0)
                                  tr('看到 {value0}:{value1}', {
                                    'value0': h.position! ~/ 60,
                                    'value1': (h.position! % 60)
                                        .toString()
                                        .padLeft(2, '0'),
                                  }),
                              ].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.text.labelMedium?.copyWith(
                                color: c.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (h.progress > 0) ...[
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: const BorderRadius.all(
                            Radius.circular(2),
                          ),
                          child: LinearProgressIndicator(
                            value: h.progress,
                            minHeight: 3,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  tooltip: tr('继续'),
                  icon: const Icon(Icons.play_circle_outline_rounded),
                  onPressed: () => _resume(h),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
