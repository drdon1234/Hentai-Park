import 'package:flutter/material.dart';

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
import '../widgets/cover_tile.dart';
import 'history_scope_selector.dart';

/// Reading / watching history grouped by day, with search, swipe-to-delete and a resume button.
class HistoryPage extends StatefulWidget {
  const HistoryPage({
    super.key,
    this.scope = const ContentScope.all(),
    this.openRequest = 0,
  });
  final ContentScope scope;
  final int openRequest;

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final _query = TextEditingController();
  bool _searching = false;
  late ContentScope _scope = widget.scope;

  @override
  void didUpdateWidget(HistoryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scope != widget.scope ||
        oldWidget.openRequest != widget.openRequest) {
      _scope = widget.scope;
    }
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _clearAll() async {
    final scope = _scope;
    final label = scope.sourceKey == null
        ? scope.label
        : SourceManager.instance.manifest(scope.sourceKey!)?.name ??
              scope.sourceKey!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('清空历史记录？')),
        content: Text(tr('仅清空“{scope}”的浏览与阅读位置记录，章节已读状态保留。', {'scope': label})),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('清空')),
          ),
        ],
      ),
    );
    if (ok == true) Library.instance.clearHistory(scope: scope);
  }

  void _resume(HistoryEntry h) {
    if (kindOf(h.item) != MediaKind.video &&
        h.position == null &&
        h.pageCount == 0) {
      Nav.openWork(context, h.item);
    } else {
      Nav.openChapter(context, h.item, h.chapterId, page: h.page);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TranslationPage(
      child: ListenableBuilder(
        listenable: Listenable.merge([
          Library.instance.collection(LibraryCollection.history),
          AppSettings.instance.watch(const {'domainOrder'}),
          SourceManager.instance,
        ]),
        builder: (context, _) {
          final q = _query.text.trim().toLowerCase();
          final list = Library.instance
              .history(scope: _scope)
              .where((h) => q.isEmpty || h.item.title.toLowerCase().contains(q))
              .toList();
          return Scaffold(
            appBar: PageHeader(
              title: _searching ? null : tr('历史'),
              titleWidget: _searching
                  ? TextField(
                      controller: _query,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: tr('搜索历史'),
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                      ),
                      onChanged: (_) => setState(() {}),
                    )
                  : null,
              actions: [
                const TranslationControls(),
                IconButton(
                  tooltip: _searching ? tr('关闭搜索') : tr('搜索'),
                  icon: Icon(
                    _searching ? Icons.close_rounded : Icons.search_rounded,
                  ),
                  onPressed: () => setState(() {
                    _searching = !_searching;
                    if (!_searching) _query.clear();
                  }),
                ),
                IconButton(
                  tooltip: tr('清空历史'),
                  icon: const Icon(Icons.delete_sweep_outlined),
                  onPressed: _clearAll,
                ),
              ],
            ),
            body: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: HistoryScopeSelector(
                    scope: _scope,
                    onChanged: (scope) => setState(() => _scope = scope),
                  ),
                ),
                if (list.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyState(
                      icon: Icons.history_rounded,
                      title: q.isEmpty ? tr('暂无浏览记录') : tr('没有匹配的记录'),
                      message: q.isEmpty ? tr('看过的作品会按日期出现在这里') : null,
                    ),
                  )
                else
                  _list(context, list),
                const SliverToBoxAdapter(child: SizedBox(height: Gap.xl)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _list(BuildContext context, List<HistoryEntry> list) {
    final rows = <Widget>[];
    String? day;
    for (final h in list) {
      final label = dayLabel(h.time);
      if (label != day) {
        day = label;
        rows.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Gap.page,
              Gap.l,
              Gap.page,
              Gap.xs,
            ),
            child: Semantics(
              header: true,
              child: Text(
                label,
                style: context.text.labelLarge?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ),
          ),
        );
      }
      rows.add(_tile(context, h));
    }
    return SliverList.list(children: rows);
  }

  Widget _tile(BuildContext context, HistoryEntry h) {
    final c = context.colors;
    final time =
        '${h.time.hour.toString().padLeft(2, '0')}:${h.time.minute.toString().padLeft(2, '0')}';
    return Dismissible(
      key: ValueKey(h.uid),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: Icon(Icons.delete_outline_rounded, color: c.error),
      ),
      onDismissed: (_) => Library.instance.removeHistory(h.uid),
      child: InkWell(
        onTap: () => Nav.openWork(context, h.item),
        onLongPress: () => showWorkActions(context, h.item),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Gap.page, Gap.s, Gap.xs, Gap.s),
          child: Row(
            children: [
              if (!h.item.isNovel &&
                  SourceManager.instance.manifest(h.item.source)?.isNovel !=
                      true) ...[
                SizedBox(
                  width: 48,
                  height: 66,
                  child: CoverImage(source: h.item.source, url: h.item.cover),
                ),
                const SizedBox(width: Gap.m),
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
                          fontWeight: FontWeight.w500,
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
                              time,
                              if (h.pageCount > 0)
                                '${h.chapterTitle != null ? '${h.chapterTitle} ' : ''}${h.item.isNovel ? '${(h.progress * 100).round()}%' : '${h.page + 1}/${h.pageCount}'}',
                              if (h.position != null && h.chapterTitle != null)
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
                      const SizedBox(height: Gap.s),
                      ClipRRect(
                        borderRadius: const BorderRadius.all(
                          Radius.circular(2),
                        ),
                        child: LinearProgressIndicator(
                          value: h.progress,
                          minHeight: 2,
                          semanticsLabel: tr('阅读进度'),
                          semanticsValue: '${(h.progress * 100).round()}%',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                tooltip: tr('继续'),
                icon: const Icon(Icons.play_arrow_rounded),
                onPressed: () => _resume(h),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
