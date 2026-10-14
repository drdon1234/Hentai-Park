import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/localization.dart';
import '../../core/settings.dart';
import '../../core/titles.dart';
import '../../engine/source_manager.dart';
import '../../library/downloads.dart';
import '../../library/library.dart';
import '../../library/updater.dart';
import '../migration/migration_page.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/cover_tile.dart';
import 'category_manage_page.dart';
import 'favorite_actions.dart';
import 'library_options_sheet.dart';
import 'shelf_page.dart';

/// The library (Mihon style): one tab per category, filter / sort / display options, search,
/// pull-to-refresh library updates and multi-select actions.
class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  final _query = TextEditingController();
  bool _searching = false;
  final Set<String> _selected = {};

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  /// Tabs: all favorites, then "默认" (when it has items) and each category. null = all.
  List<int?> _tabs(Library lib) {
    if (lib.categories.isEmpty) return const [null];
    return [
      null,
      if (lib.favorites(category: Library.defaultCategory).isNotEmpty)
        Library.defaultCategory,
      for (final c in lib.categories) c.id,
    ];
  }

  String _tabLabel(Library lib, int? id) {
    final n = lib.favorites(category: id).length;
    if (id == null) return tr('全部 {value0}', {'value0': n});
    if (id == Library.defaultCategory) return tr('默认 {value0}', {'value0': n});
    return '${lib.category(id)?.name ?? ''} $n';
  }

  Future<void> _update(int? category) async {
    final updater = LibraryUpdater.instance;
    if (updater.running) {
      context.toast(tr('正在检查更新…'));
      return;
    }
    final r = await updater.run(category: category);
    if (!mounted || r == null) return;
    context.toast(
      r.newChapters > 0
          ? tr('{value0} 部作品有新章节，详见「更新」', {'value0': r.updated.length})
          : tr('没有新章节{value0}', {
              'value0': r.errors.isNotEmpty
                  ? tr('（{value0} 部检查失败）', {'value0': r.errors.length})
                  : '',
            }),
    );
  }

  void _toggle(String uid) {
    HapticFeedback.selectionClick();
    setState(
      () =>
          _selected.contains(uid) ? _selected.remove(uid) : _selected.add(uid),
    );
  }

  Future<void> _selectionAction(String action) async {
    final lib = Library.instance;
    final uids = _selected.toList();
    switch (action) {
      case 'categories':
        final first = uids.length == 1 ? lib.categoriesOf(uids.first) : <int>{};
        final picked = await pickCategories(context, selected: first);
        if (picked == null) return;
        for (final uid in uids) {
          lib.setCategories(uid, picked);
        }
      case 'read':
        for (final uid in uids) {
          final chapters =
              lib.chaptersCached(uid) ?? await lib.loadChapters(uid);
          lib.markRead(uid, chapters.map((c) => c.chapterId), true);
        }
      case 'remove':
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(tr('取消收藏 {value0} 部作品？', {'value0': uids.length})),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(tr('取消')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(tr('取消收藏')),
              ),
            ],
          ),
        );
        if (ok != true) return;
        for (final uid in uids) {
          lib.removeFavorite(uid);
        }
      case 'migrate':
        final items = [for (final uid in uids) lib.favorite(uid)?.item].nonNulls
            .toList();
        if (items.isNotEmpty) {
          await Nav.push(context, MigrationPage(items: items));
        }
    }
    if (mounted) setState(_selected.clear);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        for (final c in LibraryCollection.values)
          if (c != LibraryCollection.history) Library.instance.collection(c),
      ]),
      builder: (context, _) {
        final lib = Library.instance;
        final tabs = _tabs(lib);
        _selected.removeWhere((uid) => !lib.isFavorite(uid));
        return DefaultTabController(
          key: ValueKey(tabs.join(',')),
          length: tabs.length,
          child: Builder(
            builder: (context) => Scaffold(
              appBar: _selected.isNotEmpty
                  ? _selectionBar()
                  : _appBar(context, lib, tabs),
              body: tabs.length == 1
                  ? _LibraryTab(
                      category: null,
                      query: _query.text,
                      selected: _selected,
                      onToggle: _toggle,
                      onRefresh: () => _update(null),
                    )
                  : TabBarView(
                      children: [
                        for (final t in tabs)
                          _LibraryTab(
                            category: t,
                            query: _query.text,
                            selected: _selected,
                            onToggle: _toggle,
                            onRefresh: () => _update(t),
                          ),
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }

  PreferredSizeWidget _selectionBar() => AppBar(
    leading: IconButton(
      tooltip: tr('取消选择'),
      icon: const Icon(Icons.close_rounded),
      onPressed: () => setState(_selected.clear),
    ),
    title: Text(tr('已选 {value0}', {'value0': _selected.length})),
    actions: [
      TextButton(
        onPressed: () => _selectionAction('categories'),
        child: Text(tr('分类')),
      ),
      TextButton(
        onPressed: () => _selectionAction('read'),
        child: Text(tr('标为已读')),
      ),
      PopupMenuButton<String>(
        tooltip: tr('更多'),
        onSelected: _selectionAction,
        itemBuilder: (_) => [
          PopupMenuItem(value: 'migrate', child: Text(tr('迁移到其他站点'))),
          PopupMenuItem(value: 'remove', child: Text(tr('取消收藏'))),
        ],
      ),
    ],
  );

  PreferredSizeWidget _appBar(
    BuildContext context,
    Library lib,
    List<int?> tabs,
  ) {
    final controller = DefaultTabController.of(context);
    return PageHeader(
      titleWidget: _searching
          ? TextField(
              controller: _query,
              autofocus: true,
              decoration: InputDecoration(
                hintText: tr('搜索书架'),
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
              onChanged: (_) => setState(() {}),
            )
          : ShelfTitle(tr('书架')),
      actions: [
        IconButton(
          tooltip: _searching ? tr('关闭搜索') : tr('搜索'),
          icon: Icon(_searching ? Icons.close_rounded : Icons.search_rounded),
          onPressed: () => setState(() {
            _searching = !_searching;
            if (!_searching) _query.clear();
          }),
        ),
        IconButton(
          tooltip: tr('筛选与排序'),
          icon: const Icon(Icons.filter_list_rounded),
          onPressed: () => showLibraryOptions(context),
        ),
        PopupMenuButton<String>(
          tooltip: tr('更多'),
          onSelected: (v) {
            switch (v) {
              case 'update':
                _update(tabs[controller.index]);
              case 'updateAll':
                _update(null);
              case 'categories':
                Nav.push(context, const CategoryManagePage());
            }
          },
          itemBuilder: (_) => [
            if (tabs.length > 1)
              PopupMenuItem(value: 'update', child: Text(tr('检查当前分类的更新'))),
            PopupMenuItem(value: 'updateAll', child: Text(tr('检查全部更新'))),
            PopupMenuItem(value: 'categories', child: Text(tr('管理分类'))),
          ],
        ),
      ],
      bottom: tabs.length > 1
          ? TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [for (final t in tabs) Tab(text: _tabLabel(lib, t))],
            )
          : null,
    );
  }
}

class _LibraryTab extends StatelessWidget {
  const _LibraryTab({
    required this.category,
    required this.query,
    required this.selected,
    required this.onToggle,
    required this.onRefresh,
  });
  final int? category;
  final String query;
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  final Future<void> Function() onRefresh;

  List<FavoriteEntry> _entries() {
    final lib = Library.instance;
    final s = AppSettings.instance;
    final dm = DownloadManager.instance;
    final q = normalizeTitle(query);
    final sources = s.libraryFilterSources;
    bool downloaded(String uid) {
      final t = dm.task(uid);
      return t != null && (t.status == DownloadStatus.done || t.done > 0);
    }

    final list = lib.favorites(category: category).where((f) {
      final uid = f.item.uid;
      if (query.trim().isNotEmpty &&
          !normalizeTitle(f.item.title).contains(q)) {
        return false;
      }
      if (sources.isNotEmpty && !sources.contains(f.item.source)) return false;
      if (s.libraryFilterKind != 'all' &&
          kindOf(f.item).name != s.libraryFilterKind) {
        return false;
      }
      if (s.libraryFilterDownloaded && !downloaded(uid)) return false;
      if (s.libraryFilterUnread && lib.statsOf(uid).unread == 0) return false;
      return true;
    }).toList();
    int byKey(FavoriteEntry a, FavoriteEntry b) {
      switch (s.librarySort) {
        case 'title':
          return a.item.title.toLowerCase().compareTo(
            b.item.title.toLowerCase(),
          );
        case 'read':
          final x = lib.historyOf(a.item.uid)?.time.millisecondsSinceEpoch ?? 0;
          final y = lib.historyOf(b.item.uid)?.time.millisecondsSinceEpoch ?? 0;
          return x.compareTo(y);
        case 'updated':
          final x =
              lib.statsOf(a.item.uid).latestFetch?.millisecondsSinceEpoch ?? 0;
          final y =
              lib.statsOf(b.item.uid).latestFetch?.millisecondsSinceEpoch ?? 0;
          return x.compareTo(y);
        case 'unread':
          return lib
              .statsOf(a.item.uid)
              .unread
              .compareTo(lib.statsOf(b.item.uid).unread);
        default:
          return a.added.compareTo(b.added);
      }
    }

    list.sort((a, b) => s.librarySortAsc ? byKey(a, b) : byKey(b, a));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        AppSettings.instance.domain(SettingsDomain.library),
        AppSettings.instance.watch(const {'gridColumns'}),
        DownloadManager.instance,
        SourceManager.instance,
      ]),
      builder: (context, _) {
        final entries = _entries();
        final s = AppSettings.instance;
        final Widget content;
        if (entries.isEmpty) {
          final filtered = Library.instance
              .favorites(category: category)
              .isNotEmpty;
          content = SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              icon: Icons.bookmark_border_rounded,
              title: filtered ? tr('没有符合条件的作品') : tr('还没有收藏'),
              message: filtered
                  ? tr('调整搜索或筛选条件试试')
                  : tr('在作品详情页点“收藏”，作品就会出现在这里'),
            ),
          );
        } else if (s.libraryDisplay == 'list' ||
            entries.any(
              (f) =>
                  f.item.isNovel ||
                  SourceManager.instance.manifest(f.item.source)?.isNovel ==
                      true,
            )) {
          content = SliverList.builder(
            itemCount: entries.length,
            itemBuilder: (context, i) => _listTile(context, entries[i]),
          );
        } else {
          content = _grid(context, entries);
        }
        return ParkRefresh(
          onRefresh: onRefresh,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              const SliverToBoxAdapter(child: SizedBox(height: Gap.s)),
              content,
              const SliverToBoxAdapter(child: SizedBox(height: Gap.xl)),
            ],
          ),
        );
      },
    );
  }

  void _tap(BuildContext context, FavoriteEntry f) => selected.isNotEmpty
      ? onToggle(f.item.uid)
      : Nav.openWork(context, f.item);

  List<CoverBadge> _badges(BuildContext context, FavoriteEntry f) {
    final s = AppSettings.instance;
    final lib = Library.instance;
    final stats = lib.statsOf(f.item.uid);
    final t = DownloadManager.instance.task(f.item.uid);
    return [
      if (s.badgeUnread && stats.unread > 0 && !lib.isOneShot(f.item.uid))
        (
          tag: Tag('${stats.unread}', accent: true),
          label: '${tr('未读数')} ${stats.unread}',
        ),
      if (s.badgeDownloaded &&
          t != null &&
          (t.status == DownloadStatus.done || t.done > 0))
        (
          tag: const Tag('', icon: Icons.download_done_rounded, onImage: true),
          label: tr('已下载'),
        ),
    ];
  }

  Widget _grid(BuildContext context, List<FavoriteEntry> entries) {
    return SliverLayoutBuilder(
      builder: (context, c) {
        final cols = gridColumnsFor(c.crossAxisExtent);
        final width =
            (c.crossAxisExtent - Gap.page * 2 - (cols - 1) * Gap.m) / cols;
        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: Gap.page),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              crossAxisSpacing: Gap.m,
              mainAxisSpacing: Gap.l,
              mainAxisExtent: width / 0.7 + cardTextExtent(context),
            ),
            delegate: SliverChildBuilderDelegate((context, i) {
              final f = entries[i];
              return CoverTile(
                item: f.item,
                aspect: 0.7,
                showSource: AppSettings.instance.badgeSource,
                selected: selected.contains(f.item.uid),
                badges: _badges(context, f),
                onTap: selected.isNotEmpty ? () => onToggle(f.item.uid) : null,
                onLongPress: () => onToggle(f.item.uid),
              );
            }, childCount: entries.length),
          ),
        );
      },
    );
  }

  Widget _listTile(BuildContext context, FavoriteEntry f) {
    final c = context.colors;
    final sel = selected.contains(f.item.uid);
    final h = Library.instance.historyOf(f.item.uid);
    return Material(
      color: sel ? c.secondaryContainer : Colors.transparent,
      child: InkWell(
        onTap: () => _tap(context, f),
        onLongPress: () => onToggle(f.item.uid),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Gap.page,
            vertical: Gap.s,
          ),
          child: Row(
            children: [
              if (!f.item.isNovel &&
                  SourceManager.instance.manifest(f.item.source)?.isNovel !=
                      true) ...[
                SizedBox(
                  width: 46,
                  height: 62,
                  child: CoverImage(source: f.item.source, url: f.item.cover),
                ),
                const SizedBox(width: Gap.m),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      f.item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: Gap.xs),
                    Row(
                      children: [
                        if (AppSettings.instance.badgeSource) ...[
                          SourceAvatar(f.item.source, size: 16),
                          const SizedBox(width: 6),
                        ],
                        Expanded(
                          child: Text(
                            h == null
                                ? tr('未读')
                                : tr('上次阅读 {value0}', {
                                    'value0': timeAgo(h.time),
                                  }),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.labelMedium?.copyWith(
                              color: c.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              for (final b in _badges(context, f))
                Semantics(
                  label: b.label,
                  child: ExcludeSemantics(child: b.tag),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
