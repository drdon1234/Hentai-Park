import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/settings.dart';
import '../../core/content_scope.dart';
import '../../engine/source_manager.dart';
import 'history_scope_selector.dart';
import '../widgets/content_translation.dart';
import '../../library/library.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'recent_history.dart';
import '../discovery_navigation.dart';
import '../../core/localization.dart';

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
    AppLocalizations.of(context);
    return TranslationPage(
      child: ListenableBuilder(
        listenable: Listenable.merge([
          Library.instance,
          AppSettings.instance,
          SourceManager.instance,
        ]),
        builder: (context, _) {
          final q = _query.text.trim().toLowerCase();
          final list = Library.instance
              .history(scope: _scope)
              .where((h) => q.isEmpty || h.item.title.toLowerCase().contains(q))
              .toList();
          return Scaffold(
            appBar: AppBar(
              title: _searching
                  ? TextField(
                      controller: _query,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: tr('搜索历史'),
                        border: InputBorder.none,
                      ),
                      onChanged: (_) => setState(() {}),
                    )
                  : Text(tr('历史')),
              actions: [
                const DomainMenu(),
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
                SliverToBoxAdapter(child: RecentHistory()),
                SliverToBoxAdapter(child: SectionHeader(tr('完整历史'))),
                SliverToBoxAdapter(
                  child: HistoryScopeSelector(
                    scope: _scope,
                    onChanged: (scope) => setState(() => _scope = scope),
                  ),
                ),
                if (AppSettings.instance.incognito)
                  SliverToBoxAdapter(
                    child: MaterialBanner(
                      content: Text(tr('无痕模式已开启，新的浏览与阅读不会被记录')),
                      leading: const Icon(Icons.visibility_off_outlined),
                      actions: [
                        TextButton(
                          onPressed: () =>
                              AppSettings.instance.incognito = false,
                          child: Text(tr('关闭')),
                        ),
                      ],
                    ),
                  ),
                if (list.isEmpty)
                  SliverToBoxAdapter(
                    child: MessageView(
                      icon: Icons.history_rounded,
                      title: q.isEmpty ? tr('暂无浏览记录') : tr('没有匹配的记录'),
                    ),
                  )
                else
                  _list(context, list),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
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
          SectionHeader(
            label,
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 4),
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
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 4, 6),
          child: Row(
            children: [
              if (h.item.json['mediaKind'] != 'novel' &&
                  SourceManager.instance.manifest(h.item.source)?.isNovel !=
                      true) ...[
                SizedBox(
                  width: 56,
                  height: 76,
                  child: CoverImage(
                    source: h.item.source,
                    url: h.item.cover,
                    radius: 8,
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
                              time,
                              if (h.pageCount > 0)
                                '${h.chapterTitle != null ? '${h.chapterTitle} ' : ''}${h.item.json['mediaKind'] == 'novel' ? '${(h.progress * 100).round()}%' : '${h.page + 1}/${h.pageCount}'}',
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
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
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
    );
  }
}
