import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/settings.dart';
import '../../library/library.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Reading / watching history grouped by day, with search, swipe-to-delete and a resume button.
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final _query = TextEditingController();
  bool _searching = false;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _clearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空历史记录？'),
        content: const Text('只删除浏览与阅读位置记录，章节的已读状态会保留。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('清空')),
        ],
      ),
    );
    if (ok == true) Library.instance.clearHistory();
  }

  void _resume(HistoryEntry h) {
    if (kindOf(h.item.source) == MediaKind.video || h.pageCount == 0) {
      Nav.openWork(context, h.item);
    } else {
      Nav.openChapter(context, h.item, h.chapterId, page: h.page);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([Library.instance, AppSettings.instance]),
      builder: (context, _) {
        final q = _query.text.trim().toLowerCase();
        final list = Library.instance.history().where((h) => q.isEmpty || h.item.title.toLowerCase().contains(q)).toList();
        return Scaffold(
          appBar: AppBar(
            title: _searching
                ? TextField(
                    controller: _query,
                    autofocus: true,
                    decoration: const InputDecoration(hintText: '搜索历史', border: InputBorder.none),
                    onChanged: (_) => setState(() {}),
                  )
                : const Text('历史'),
            actions: [
              IconButton(
                tooltip: _searching ? '关闭搜索' : '搜索',
                icon: Icon(_searching ? Icons.close_rounded : Icons.search_rounded),
                onPressed: () => setState(() {
                  _searching = !_searching;
                  if (!_searching) _query.clear();
                }),
              ),
              IconButton(tooltip: '清空历史', icon: const Icon(Icons.delete_sweep_outlined), onPressed: _clearAll),
            ],
          ),
          body: Column(
            children: [
              if (AppSettings.instance.incognito)
                MaterialBanner(
                  content: const Text('无痕模式已开启，新的浏览与阅读不会被记录'),
                  leading: const Icon(Icons.visibility_off_outlined),
                  actions: [TextButton(onPressed: () => AppSettings.instance.incognito = false, child: const Text('关闭'))],
                ),
              Expanded(child: list.isEmpty ? MessageView(icon: Icons.history_rounded, title: q.isEmpty ? '暂无浏览记录' : '没有匹配的记录') : _list(context, list)),
            ],
          ),
        );
      },
    );
  }

  Widget _list(BuildContext context, List<HistoryEntry> list) {
    final rows = <Widget>[];
    String? day;
    for (final h in list) {
      final label = dayLabel(h.time);
      if (label != day) {
        day = label;
        rows.add(SectionHeader(label, padding: const EdgeInsets.fromLTRB(16, 16, 8, 4)));
      }
      rows.add(_tile(context, h));
    }
    return ListView(padding: const EdgeInsets.only(bottom: 24), children: rows);
  }

  Widget _tile(BuildContext context, HistoryEntry h) {
    final c = context.colors;
    final time = '${h.time.hour.toString().padLeft(2, '0')}:${h.time.minute.toString().padLeft(2, '0')}';
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
              SizedBox(
                width: 56,
                height: 76,
                child: CoverImage(source: h.item.source, url: h.item.cover, radius: 8),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      h.item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
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
                              if (h.pageCount > 0) '${h.chapterTitle != null ? '${h.chapterTitle} ' : ''}${h.page + 1}/${h.pageCount}',
                              if (h.position != null && h.position! > 0) '看到 ${h.position! ~/ 60}:${(h.position! % 60).toString().padLeft(2, '0')}',
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.labelMedium?.copyWith(color: c.onSurfaceVariant),
                          ),
                        ),
                      ],
                    ),
                    if (h.progress > 0) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(value: h.progress, minHeight: 3),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(tooltip: '继续', icon: const Icon(Icons.play_circle_outline_rounded), onPressed: () => _resume(h)),
            ],
          ),
        ),
      ),
    );
  }
}
