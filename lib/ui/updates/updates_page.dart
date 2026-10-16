import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/localization.dart';
import '../../core/models.dart';
import '../../core/settings.dart';
import '../../library/downloads.dart';
import '../../library/library.dart';
import '../../library/updater.dart';
import '../library/shelf_components.dart';
import '../nav.dart';
import '../subscriptions/subscription_updates_page.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Mihon's Updates tab: new chapters of favorites, newest first, grouped by day.
class UpdatesPage extends StatefulWidget {
  const UpdatesPage({super.key});

  @override
  State<UpdatesPage> createState() => _UpdatesPageState();
}

class _UpdatesPageState extends State<UpdatesPage> {
  List<UpdateEntry>? _entries;
  final Set<String> _selected = {};
  Timer? _debounce;

  static String _keyOf(UpdateEntry e) =>
      '${e.item.uid}\u0000${e.chapter.chapterId}';

  /// The feed lists new chapters of favorites; history changes do not affect it.
  final _library = Listenable.merge([
    Library.instance.collection(LibraryCollection.chapters),
    Library.instance.collection(LibraryCollection.favorites),
  ]);

  @override
  void initState() {
    super.initState();
    _reload();
    _library.addListener(_scheduleReload);
    LibraryUpdater.instance.addListener(_scheduleReload);
  }

  @override
  void dispose() {
    _library.removeListener(_scheduleReload);
    LibraryUpdater.instance.removeListener(_scheduleReload);
    _debounce?.cancel();
    super.dispose();
  }

  void _scheduleReload() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _reload);
  }

  Future<void> _reload() async {
    final list = await Library.instance.recentUpdates();
    if (mounted) setState(() => _entries = list);
  }

  Future<void> _refresh() async {
    final updater = LibraryUpdater.instance;
    if (updater.running) return;
    final result = await updater.run();
    if (!mounted || result == null) return;
    context.toast(
      result.newChapters > 0
          ? tr('{value0} 部作品有 {value1} 个新章节', {
              'value0': result.updated.length,
              'value1': result.newChapters,
            })
          : tr('没有新章节{value0}', {
              'value0': result.errors.isNotEmpty
                  ? tr('（{value0} 部检查失败）', {'value0': result.errors.length})
                  : '',
            }),
    );
  }

  void _toggle(UpdateEntry e) {
    HapticFeedback.selectionClick();
    _toggleSelection(e);
  }

  void _toggleSelection(UpdateEntry e) => setState(() {
    final k = _keyOf(e);
    _selected.contains(k) ? _selected.remove(k) : _selected.add(k);
  });

  List<UpdateEntry> get _selectedEntries => (_entries ?? const [])
      .where((e) => _selected.contains(_keyOf(e)))
      .toList();

  void _markSelected(bool read) {
    final byWork = <String, List<String>>{};
    for (final e in _selectedEntries) {
      byWork.putIfAbsent(e.item.uid, () => []).add(e.chapter.chapterId);
    }
    for (final w in byWork.entries) {
      Library.instance.markRead(w.key, w.value, read);
    }
    setState(_selected.clear);
  }

  void _download(Iterable<UpdateEntry> entries) {
    final byWork = <String, (WorkItem, List<Chapter>)>{};
    for (final e in entries) {
      byWork
          .putIfAbsent(e.item.uid, () => (e.item, <Chapter>[]))
          .$2
          .add(Chapter(e.chapter.chapterId, e.chapter.title));
    }
    for (final w in byWork.values) {
      DownloadManager.instance.enqueueNewChapters(w.$1, w.$2);
    }
    context.toast(tr('已加入下载队列'));
  }

  @override
  Widget build(BuildContext context) {
    final updater = LibraryUpdater.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([updater, DownloadManager.instance]),
      builder: (context, _) {
        final selecting = _selected.isNotEmpty;
        final last = AppSettings.instance.lastLibraryUpdate;
        return Scaffold(
          appBar: selecting
              ? AppBar(
                  leading: IconButton(
                    tooltip: tr('取消选择'),
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => setState(_selected.clear),
                  ),
                  title: Text(tr('已选 {value0}', {'value0': _selected.length})),
                  actions: [
                    TextButton(
                      onPressed: () => _markSelected(true),
                      child: Text(tr('标为已读')),
                    ),
                    TextButton(
                      onPressed: () => _markSelected(false),
                      child: Text(tr('标为未读')),
                    ),
                    IconButton(
                      tooltip: tr('下载'),
                      icon: const Icon(Icons.download_rounded),
                      onPressed: () {
                        _download(_selectedEntries);
                        setState(_selected.clear);
                      },
                    ),
                  ],
                )
              : PageHeader(
                  titleWidget: ShelfTitle(tr('更新')),
                  // The status sits under the tabs so they stay where the other shelves have them.
                  bottom: PreferredSize(
                    preferredSize: const Size.fromHeight(23),
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            Gap.page,
                            0,
                            Gap.page,
                            Gap.xs,
                          ),
                          child: Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: Text(
                              updater.running
                                  ? tr('正在检查 {value0}/{value1}', {
                                      'value0': updater.done,
                                      'value1': updater.total,
                                    })
                                  : (last == 0
                                        ? tr('尚未检查过更新')
                                        : tr('上次检查：{value0}', {
                                            'value0': timeAgo(
                                              DateTime.fromMillisecondsSinceEpoch(
                                                last,
                                              ),
                                            ),
                                          })),
                              style: context.text.labelSmall?.copyWith(
                                color: context.colors.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                        if (updater.running)
                          LinearProgressIndicator(
                            value: updater.total > 0
                                ? updater.done / updater.total
                                : null,
                            minHeight: 3,
                          )
                        else
                          const SizedBox(height: 3),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () =>
                          Nav.push(context, const SubscriptionUpdatesPage()),
                      child: Text(tr('订阅')),
                    ),
                    if (updater.running)
                      IconButton(
                        tooltip: tr('停止'),
                        icon: const Icon(Icons.stop_circle_outlined),
                        onPressed: updater.cancel,
                      )
                    else
                      IconButton(
                        tooltip: tr('检查更新'),
                        icon: const Icon(Icons.refresh_rounded),
                        onPressed: _refresh,
                      ),
                  ],
                ),
          body: ParkRefresh(onRefresh: _refresh, child: _body(context)),
        );
      },
    );
  }

  Widget _body(BuildContext context) {
    final entries = _entries;
    if (entries == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (entries.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 120),
          EmptyState(
            icon: Icons.update_rounded,
            title: tr('暂无更新'),
            message: tr('下拉检查收藏中连载作品的新章节。自动检查可在“我的 → 书架与下载”中设置。'),
          ),
        ],
      );
    }
    final rows = <Widget>[];
    String? day;
    for (final e in entries) {
      final label = dayLabel(e.chapter.dateFetch);
      if (label != day) {
        day = label;
        rows.add(
          SectionHeader(
            label,
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 4),
          ),
        );
      }
      rows.add(_tile(context, e));
    }
    return ListView(padding: const EdgeInsets.only(bottom: 24), children: rows);
  }

  Widget _tile(BuildContext context, UpdateEntry e) {
    final c = context.colors;
    final read = e.chapter.read;
    final selected = _selected.contains(_keyOf(e));
    final downloaded = DownloadManager.instance.isChapterDownloaded(
      e.item.uid,
      e.chapter.chapterId,
    );
    final muted = read ? c.onSurface.withValues(alpha: 0.45) : null;
    return Material(
      color: selected ? c.secondaryContainer : Colors.transparent,
      child: InkWell(
        onTap: () => _selected.isNotEmpty
            ? _toggle(e)
            : Nav.openChapter(context, e.item, e.chapter.chapterId),
        onLongPress: () => _toggle(e),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              // The row opens the chapter; the cover opens the work.
              Semantics(
                button: true,
                label: tr('打开详情'),
                child: GestureDetector(
                  onTap: () => Nav.openWork(context, e.item),
                  child: SizedBox(
                    width: 46,
                    height: 62,
                    child: CoverImage(source: e.item.source, url: e.item.cover),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.bodyMedium?.copyWith(
                        fontWeight: read ? FontWeight.w500 : FontWeight.w600,
                        color: muted,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        if (!read)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Icon(
                              Icons.circle,
                              size: 8,
                              color: c.primary,
                            ),
                          ),
                        Expanded(
                          child: Text(
                            [
                              e.chapter.title,
                              if (!read &&
                                  e.chapter.lastPage > 0 &&
                                  e.chapter.pageCount > 0)
                                tr('读到 {value0}/{value1}', {
                                  'value0': e.chapter.lastPage + 1,
                                  'value1': e.chapter.pageCount,
                                }),
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.labelMedium?.copyWith(
                              color: muted ?? c.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (downloaded)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Icon(
                    Icons.download_done_rounded,
                    color: c.onSurfaceVariant,
                    size: 20,
                    semanticLabel: tr('已下载'),
                  ),
                )
              else
                IconButton(
                  tooltip: tr('下载'),
                  icon: const Icon(Icons.download_outlined, size: 20),
                  onPressed: () => _download([e]),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
