import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/models.dart';
import '../../core/localization.dart';
import '../../engine/source_manager.dart';
import '../../library/downloads.dart';
import '../../library/library.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/error_view.dart';
import '../widgets/paged_grid.dart';
import '../../core/settings.dart';
import '../../core/tag_blocklist.dart';
import '../../core/titles.dart';
import '../library/favorite_actions.dart';
import '../migration/migration_page.dart';
import 'thumbnail_grid.dart';

class DetailPage extends StatefulWidget {
  const DetailPage({
    super.key,
    required this.source,
    required this.id,
    this.preview,
  });
  final String source;
  final String id;
  final WorkItem? preview;

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  WorkDetail? _detail;
  Object? _error;
  bool _reversed = false;
  final Set<String> _selected = {};

  SourceManifest? get _m => SourceManager.instance.manifest(widget.source);
  String get _uid => '${widget.source}:${widget.id}';

  @override
  void initState() {
    super.initState();
    Library.instance.loadChapters(_uid);
    _load();
  }

  /// Keeps the stored chapter list (and with it read state and library updates) in step with the site.
  Future<void> _syncChapters(WorkDetail d) async {
    if (_m?.isVideo == true) return;
    final chapters =
        d.chapters ?? [Chapter(chapterKeyOf(d.singleChapterId), tr('全本'))];
    try {
      await Library.instance.syncChapters(
        d.toItem(),
        chapters,
        oneShot: d.chapters == null,
      );
    } catch (e) {
      debugPrint('sync chapters failed: $e');
    }
  }

  Future<void> _load() async {
    setState(() => _error = null);
    if (widget.source == localSource) {
      // Imported files: everything is on disk, there is no site to ask.
      final d = DownloadManager.instance.offlineDetail(
        widget.source,
        widget.id,
      );
      setState(
        () => d == null
            ? _error = SourceError('NOT_FOUND', '本地文件已被删除')
            : _detail = d,
      );
      if (d != null) {
        Library.instance.recordVisit(d.toItem());
        _syncChapters(d);
      }
      return;
    }
    try {
      final d = await SourceManager.instance.detail(widget.source, widget.id);
      if (!mounted) return;
      setState(() => _detail = d);
      Library.instance.recordVisit(d.toItem());
      _syncChapters(d);
    } catch (e) {
      if (!mounted) return;
      // Offline (or the site is down): fall back to the downloaded copy when there is one.
      final offline = DownloadManager.instance.offlineDetail(
        widget.source,
        widget.id,
      );
      if (offline != null) {
        setState(() => _detail = offline);
        context.toast(
          tr('无法连接{source}，已打开离线下载的内容', {'source': _m?.name ?? ''}),
        );
        return;
      }
      setState(() => _error = e);
    }
  }

  WorkItem get _item =>
      _detail?.toItem() ??
      widget.preview ??
      WorkItem({'id': widget.id, 'title': widget.id}, widget.source);

  void _read({Chapter? chapter, int page = 0}) {
    final d = _detail;
    if (d == null) return;
    if (d.chapters != null && chapter == null) {
      final h = Library.instance.historyOf(d.uid);
      chapter = d.chapters!.firstWhere(
        (c) => c.id == h?.chapterId,
        orElse: () => d.chapters!.first,
      );
    }
    Nav.openReader(context, d, chapter: chapter, startPage: page);
  }

  void _continue() {
    final d = _detail;
    if (d == null) return;
    if (_m?.isVideo == true) {
      Nav.openVideo(context, d);
      return;
    }
    final h = Library.instance.historyOf(d.uid);
    if (h != null && h.pageCount > 0) {
      final chapter = d.chapters?.firstWhere(
        (c) => c.id == h.chapterId,
        orElse: () => d.chapters!.first,
      );
      Nav.openReader(context, d, chapter: chapter, startPage: h.page);
    } else {
      _read();
    }
  }

  Future<void> _download() async {
    final d = _detail;
    if (d == null) return;
    if (_m?.isVideo == true) {
      final sources = await guarded(
        context,
        widget.source,
        () => SourceManager.instance.videos(widget.source, d.id),
      );
      if (sources == null || !mounted) return;
      final picked = await showModalBottomSheet<VideoSource>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(
                  tr('选择下载清晰度'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              for (final s in sources)
                ListTile(
                  leading: const Icon(Icons.high_quality_outlined),
                  title: Text(s.label),
                  trailing: s.preferred ? Pill(tr('推荐')) : null,
                  onTap: () => Navigator.pop(ctx, s),
                ),
            ],
          ),
        ),
      );
      if (picked == null) return;
      DownloadManager.instance.enqueue(_item, [
        Chapter('${picked.quality}', picked.label),
      ]);
    } else if (d.chapters != null && d.chapters!.length > 1) {
      final picked = await showModalBottomSheet<List<Chapter>>(
        context: context,
        isScrollControlled: true,
        builder: (_) => _ChapterPicker(chapters: d.chapters!),
      );
      if (picked == null || picked.isEmpty) return;
      DownloadManager.instance.enqueue(_item, picked);
    } else {
      final id = d.chapters?.first.id ?? d.singleChapterId ?? '_';
      DownloadManager.instance.enqueue(_item, [Chapter(id, tr('全本'))]);
    }
    if (mounted) context.toast(tr('已加入下载队列'));
  }

  @override
  Widget build(BuildContext context) {
    AppLocalizations.of(context);
    final m = _m;
    final color = m?.color ?? context.colors.primary;
    return Theme(
      data: ParkTheme.build(Theme.of(context).brightness, color),
      child: Builder(
        builder: (context) {
          return Scaffold(
            body: ListenableBuilder(
              listenable: Listenable.merge([
                Library.instance,
                DownloadManager.instance,
              ]),
              builder: (context, _) => CustomScrollView(
                slivers: [
                  _Header(item: _item, detail: _detail, manifest: m),
                  SliverToBoxAdapter(child: _actions(context)),
                  if (_error != null && _detail == null)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: SourceErrorView(
                        error: _error!,
                        source: widget.source,
                        onRetry: _load,
                      ),
                    )
                  else if (_detail == null)
                    const SliverToBoxAdapter(child: _BodySkeleton())
                  else
                    ..._body(context, _detail!),
                  const SliverToBoxAdapter(child: SizedBox(height: 48)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _actions(BuildContext context) {
    final d = _detail;
    final isVideo = _m?.isVideo == true;
    final h = Library.instance.historyOf(_item.uid);
    final fav = Library.instance.isFavorite(_item.uid);
    final dl = DownloadManager.instance.task(_item.uid);
    final resumeLabel = isVideo
        ? (h?.position != null && h!.position! > 5 ? tr('继续播放') : tr('立即播放'))
        : (h != null && h.pageCount > 0
              ? tr('继续 {chapter}{page}/{total}', {
                  'chapter': h.chapterTitle != null && d?.chapters != null
                      ? '${h.chapterTitle} · '
                      : '',
                  'page': h.page + 1,
                  'total': h.pageCount,
                })
              : tr('开始阅读'));
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: d == null ? null : _continue,
              icon: Icon(
                isVideo ? Icons.play_arrow_rounded : Icons.auto_stories_rounded,
              ),
              label: Text(resumeLabel, overflow: TextOverflow.ellipsis),
            ),
          ),
          const SizedBox(width: 10),
          _SquareButton(
            icon: fav ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
            tooltip: fav ? tr('取消收藏') : tr('收藏'),
            active: fav,
            onPressed: () => toggleFavorite(context, _item),
            onLongPress: fav
                ? () => editFavoriteCategories(context, _item.uid)
                : null,
          ),
          const SizedBox(width: 8),
          _SquareButton(
            icon: dl == null
                ? Icons.download_rounded
                : (dl.status == DownloadStatus.done
                      ? Icons.download_done_rounded
                      : Icons.downloading_rounded),
            tooltip: tr('下载'),
            active: dl != null,
            onPressed: d == null ? null : _download,
          ),
          const SizedBox(width: 8),
          _SquareButton(
            icon: Icons.more_horiz_rounded,
            tooltip: tr('更多'),
            onPressed: d == null ? null : () => _more(context),
          ),
        ],
      ),
    );
  }

  Future<void> _more(BuildContext context) async {
    final d = _detail!;
    await showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (d.url.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.open_in_browser_rounded),
                title: Text(tr('在浏览器中打开')),
                onTap: () {
                  Navigator.pop(ctx);
                  launchUrl(
                    Uri.parse(d.url),
                    mode: LaunchMode.externalApplication,
                  );
                },
              ),
            if (d.url.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.share_rounded),
                title: Text(tr('分享链接')),
                onTap: () {
                  Navigator.pop(ctx);
                  SharePlus.instance.share(
                    ShareParams(text: '${d.title}\n${d.url}'),
                  );
                },
              ),
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: Text(tr('复制标题')),
              onTap: () {
                Clipboard.setData(ClipboardData(text: d.title));
                Navigator.pop(ctx);
                context.toast(tr('已复制'));
              },
            ),
            ListTile(
              leading: const Icon(Icons.tag_rounded),
              title: Text(tr('复制编号  {id}', {'id': d.id})),
              onTap: () {
                Clipboard.setData(ClipboardData(text: d.id));
                Navigator.pop(ctx);
                context.toast(tr('已复制'));
              },
            ),
            ListTile(
              leading: const Icon(Icons.travel_explore_rounded),
              title: Text(tr('在所有源站搜索标题')),
              onTap: () {
                Navigator.pop(ctx);
                Nav.openAggregateSearch(
                  context,
                  keyword: searchableTitle(d.title),
                );
              },
            ),
            if (Library.instance.isFavorite(d.uid))
              ListTile(
                leading: const Icon(Icons.swap_horiz_rounded),
                title: Text(tr('迁移到其他源')),
                subtitle: Text(tr('保留分类与已读进度')),
                onTap: () {
                  Navigator.pop(ctx);
                  Nav.push(context, MigrationPage(items: [_item]));
                },
              ),
          ],
        ),
      ),
    );
  }

  int _unread(List<Chapter> chapters) => chapters
      .where((ch) => Library.instance.chapterState(_uid, ch.id)?.read != true)
      .length;

  void _toggleSelect(String id) => setState(
    () => _selected.contains(id) ? _selected.remove(id) : _selected.add(id),
  );

  Widget _selectionBar(BuildContext context, List<Chapter> chapters) {
    void done() => setState(_selected.clear);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: tr('取消选择'),
                onPressed: done,
                icon: const Icon(Icons.close_rounded),
              ),
              Text(
                tr('已选 {count}', {'count': _selected.length}),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              TextButton(
                onPressed: () =>
                    setState(() => _selected.addAll(chapters.map((c) => c.id))),
                child: Text(tr('全选')),
              ),
              IconButton(
                tooltip: tr('下载所选'),
                onPressed: () {
                  DownloadManager.instance.enqueue(
                    _item,
                    chapters.where((c) => _selected.contains(c.id)).toList(),
                  );
                  context.toast(tr('已加入下载队列'));
                  done();
                },
                icon: const Icon(Icons.download_rounded),
              ),
            ],
          ),
          Wrap(
            spacing: 4,
            children: [
              TextButton(
                onPressed: () {
                  Library.instance.markRead(_uid, _selected.toList(), true);
                  done();
                },
                child: Text(tr('标为已读')),
              ),
              TextButton(
                onPressed: () {
                  Library.instance.markRead(_uid, _selected.toList(), false);
                  done();
                },
                child: Text(tr('标为未读')),
              ),
              if (_selected.length == 1)
                TextButton(
                  onPressed: () {
                    final i = chapters.indexWhere(
                      (c) => c.id == _selected.first,
                    );
                    Library.instance.markRead(
                      _uid,
                      chapters.take(i).map((c) => c.id).toList(),
                      true,
                    );
                    done();
                  },
                  child: Text(tr('之前的章节标为已读')),
                ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _body(BuildContext context, WorkDetail d) {
    final c = context.colors;
    final isVideo = _m?.isVideo == true;
    final chapters = d.chapters;
    final blocked = TagBlocklist.current().matchDetail(d);
    return [
      if (blocked.isNotEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: c.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.block_rounded,
                    color: c.onErrorContainer,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      tr('包含已屏蔽的内容：{tags}', {'tags': blocked.join(tr('、'))}),
                      style: TextStyle(color: c.onErrorContainer),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      if (d.description.isNotEmpty)
        SliverToBoxAdapter(child: _Description(text: d.description)),
      if (d.tagGroups.isNotEmpty || d.authors.isNotEmpty)
        SliverToBoxAdapter(
          child: _Tags(detail: d, source: widget.source),
        ),
      if (chapters != null && chapters.isNotEmpty) ...[
        SliverToBoxAdapter(
          child: _selected.isEmpty
              ? SectionHeader(
                  tr('章节 · {count}{unread}', {
                    'count': chapters.length,
                    'unread': _unread(chapters) > 0
                        ? tr('（未读 {count}）', {'count': _unread(chapters)})
                        : '',
                  }),
                  leading: Icon(
                    Icons.format_list_numbered_rounded,
                    color: c.primary,
                    size: 20,
                  ),
                  trailing: TextButton.icon(
                    onPressed: () => setState(() => _reversed = !_reversed),
                    icon: Icon(
                      _reversed
                          ? Icons.arrow_upward_rounded
                          : Icons.arrow_downward_rounded,
                      size: 16,
                    ),
                    label: Text(_reversed ? tr('倒序') : tr('正序')),
                  ),
                )
              : _selectionBar(context, chapters),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 180,
              mainAxisExtent: 44,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            delegate: SliverChildBuilderDelegate((context, i) {
              final ch = (_reversed ? chapters.reversed.toList() : chapters)[i];
              final h = Library.instance.historyOf(d.uid);
              final current = h?.chapterId == ch.id;
              final state = Library.instance.chapterState(d.uid, ch.id);
              final read = state?.read == true;
              final selected = _selected.contains(ch.id);
              final downloaded = DownloadManager.instance.isChapterDownloaded(
                d.uid,
                ch.id,
              );
              return Material(
                color: selected
                    ? c.primary.withValues(alpha: 0.35)
                    : (current
                          ? c.primary.withValues(alpha: 0.2)
                          : c.surfaceContainerHigh),
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => _selected.isNotEmpty
                      ? _toggleSelect(ch.id)
                      : _read(chapter: ch),
                  onLongPress: () => _toggleSelect(ch.id),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            ch.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: current
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: current
                                  ? c.primary
                                  : (read
                                        ? c.onSurface.withValues(alpha: 0.4)
                                        : null),
                            ),
                          ),
                        ),
                        if (!read &&
                            state != null &&
                            state.lastPage > 0 &&
                            state.pageCount > 0)
                          Text(
                            '${state.lastPage + 1}/${state.pageCount}',
                            style: TextStyle(
                              fontSize: 10,
                              color: c.onSurfaceVariant,
                            ),
                          ),
                        if (downloaded)
                          Icon(
                            Icons.download_done_rounded,
                            size: 14,
                            color: c.primary,
                          ),
                      ],
                    ),
                  ),
                ),
              );
            }, childCount: chapters.length),
          ),
        ),
      ],
      if (!isVideo &&
          (d.thumbnails.isNotEmpty || _m?.can('thumbnails') == true))
        SliverToBoxAdapter(
          child: ThumbnailSection(
            detail: d,
            onOpen: (page) => _read(page: page),
          ),
        ),
      if (d.series.isNotEmpty)
        SliverToBoxAdapter(
          child: WorkCarousel(
            title: tr('同系列'),
            items: d.series,
            leading: Icon(
              Icons.video_library_outlined,
              color: c.primary,
              size: 20,
            ),
          ),
        ),
      if (d.related.isNotEmpty)
        SliverToBoxAdapter(
          child: WorkCarousel(
            title: tr('相关推荐'),
            items: d.related,
            leading: Icon(Icons.recommend_outlined, color: c.primary, size: 20),
          ),
        ),
    ];
  }
}

class _SquareButton extends StatelessWidget {
  const _SquareButton({
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.onLongPress,
    this.active = false,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final bool active;

  @override
  Widget build(BuildContext context) {
    AppLocalizations.of(context);
    final c = context.colors;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: active
            ? c.primary.withValues(alpha: 0.2)
            : c.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onPressed,
          onLongPress: onLongPress,
          child: SizedBox(
            width: 50,
            height: 50,
            child: Icon(
              icon,
              color: active
                  ? c.primary
                  : (onPressed == null
                        ? c.onSurface.withValues(alpha: 0.3)
                        : c.onSurface),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.item,
    required this.detail,
    required this.manifest,
  });
  final WorkItem item;
  final WorkDetail? detail;
  final SourceManifest? manifest;

  @override
  Widget build(BuildContext context) {
    AppLocalizations.of(context);
    final c = context.colors;
    final isVideo = manifest?.isVideo == true;
    final d = detail;
    final top = MediaQuery.paddingOf(context).top;
    final coverAspect = item.coverAspect ?? (isVideo ? 16 / 9 : 0.7);
    final coverWidth = coverAspect > 1 ? 200.0 : 128.0;
    final meta = <Widget>[
      if ((d?.pages ?? item.pages ?? 0) > 0)
        _Meta(
          Icons.photo_library_outlined,
          tr('{count} 页', {'count': d?.pages ?? item.pages}),
        ),
      if ((d?.rating ?? item.rating) != null)
        _Meta(
          Icons.star_rounded,
          (d?.rating ?? item.rating)!.toStringAsFixed(2),
          color: const Color(0xFFFFC94D),
        ),
      if ((d?.likes ?? item.likes ?? 0) > 0)
        _Meta(
          Icons.favorite_rounded,
          formatCount(d?.likes ?? item.likes),
          color: const Color(0xFFFF6B8B),
        ),
      if ((d?.views ?? item.views ?? 0) > 0)
        _Meta(Icons.visibility_outlined, formatCount(d?.views ?? item.views)),
      if ((d?.language ?? item.language).isNotEmpty)
        _Meta(Icons.translate_rounded, d?.language ?? item.language),
      if ((d?.uploaded ?? item.uploaded).isNotEmpty)
        _Meta(Icons.schedule_rounded, d?.uploaded ?? item.uploaded),
      if (d != null && d.size.isNotEmpty)
        _Meta(Icons.sd_storage_outlined, d.size),
      if (d?.comments != null && d!.comments! > 0)
        _Meta(Icons.forum_outlined, '${d.comments}'),
    ];
    return SliverAppBar(
      pinned: true,
      stretch: true,
      expandedHeight: (coverWidth / coverAspect) + top + 70,
      title: _CollapsingTitle(item.title),
      flexibleSpace: LayoutBuilder(
        builder: (context, constraints) {
          final collapsed = constraints.maxHeight <= kToolbarHeight + top + 4;
          return FlexibleSpaceBar(
            collapseMode: CollapseMode.parallax,
            stretchModes: const [StretchMode.zoomBackground],
            background: Stack(
              fit: StackFit.expand,
              children: [
                if (item.cover.isNotEmpty)
                  ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                    child: Opacity(
                      opacity: 0.45,
                      child: CoverImage(
                        source: item.source,
                        url: item.cover,
                        radius: 0,
                      ),
                    ),
                  ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [c.surface.withValues(alpha: 0.2), c.surface],
                    ),
                  ),
                ),
                if (!collapsed)
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 8,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        SizedBox(
                          width: coverWidth,
                          child: AspectRatio(
                            aspectRatio: coverAspect,
                            child: GestureDetector(
                              onTap: isVideo && d != null
                                  ? () => Nav.openVideo(context, d)
                                  : null,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Hero(
                                    tag: 'cover-${item.uid}',
                                    child: CoverImage(
                                      source: item.source,
                                      url: item.cover,
                                    ),
                                  ),
                                  if (isVideo)
                                    Center(
                                      child: Container(
                                        decoration: const BoxDecoration(
                                          color: Colors.black45,
                                          shape: BoxShape.circle,
                                        ),
                                        padding: const EdgeInsets.all(8),
                                        child: const Icon(
                                          Icons.play_arrow_rounded,
                                          color: Colors.white,
                                          size: 34,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  SourceAvatar(item.source, size: 20),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      manifest?.name ?? item.source,
                                      style: context.text.labelMedium?.copyWith(
                                        color: c.onSurfaceVariant,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if ((d?.category ?? item.category)
                                      .isNotEmpty) ...[
                                    const SizedBox(width: 6),
                                    Pill(
                                      d?.category ?? item.category,
                                      color: item.badgeColor.isNotEmpty
                                          ? parseHexColor(item.badgeColor)
                                          : c.primary,
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 6),
                              SelectableText(
                                item.title,
                                maxLines: 4,
                                style: context.text.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  height: 1.3,
                                ),
                              ),
                              if (item.subtitle.isNotEmpty &&
                                  item.subtitle != item.title) ...[
                                const SizedBox(height: 4),
                                Text(
                                  item.subtitle,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: context.text.bodySmall?.copyWith(
                                    color: c.onSurfaceVariant,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 8),
                              Wrap(spacing: 10, runSpacing: 4, children: meta),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta(this.icon, this.text, {this.color});
  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 14, color: color ?? context.colors.onSurfaceVariant),
      const SizedBox(width: 3),
      Text(
        text,
        style: context.text.labelMedium?.copyWith(
          color: context.colors.onSurfaceVariant,
        ),
      ),
    ],
  );
}

class _Description extends StatefulWidget {
  const _Description({required this.text});
  final String text;

  @override
  State<_Description> createState() => _DescriptionState();
}

class _DescriptionState extends State<_Description> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _open = !_open),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.topCenter,
          child: Text(
            widget.text,
            maxLines: _open ? null : 3,
            overflow: _open ? null : TextOverflow.ellipsis,
            style: context.text.bodyMedium?.copyWith(
              color: context.colors.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ),
      ),
    );
  }
}

/// Tag groups by namespace. Tap searches the tag in this source; long-press copies it.
class _Tags extends StatelessWidget {
  const _Tags({required this.detail, required this.source});
  final WorkDetail detail;
  final String source;

  void _search(BuildContext context, TagRef t) {
    Nav.openSourceSearch(
      context,
      source,
      keyword: t.keyword,
      filters: t.filters.isEmpty ? null : t.filters.cast<String, Object?>(),
    );
  }

  @override
  Widget build(BuildContext context) {
    AppLocalizations.of(context);
    final c = context.colors;
    final groups = [...detail.tagGroups];
    final hasAuthorGroup = groups.any(
      (g) => g.tags.any((t) => detail.authors.contains(t.name)),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!hasAuthorGroup && detail.authors.isNotEmpty)
            _row(context, tr('作者'), [
              for (final a in detail.authors)
                _chip(context, a, () {
                  final s = detail.authorSearch;
                  Nav.openSourceSearch(
                    context,
                    source,
                    keyword: (s?['keyword'] ?? a).toString(),
                    filters: (s?['filters'] as Map?)?.cast<String, Object?>(),
                  );
                }),
            ]),
          for (final g in groups)
            _row(context, tr(g.label), [
              for (final t in g.tags)
                _chip(
                  context,
                  t.name,
                  () => _search(context, t),
                  count: t.count,
                  namespace: g.namespace,
                ),
            ]),
          if (detail.uploader.isNotEmpty)
            _row(context, tr('上传者'), [
              Text(
                detail.uploader,
                style: context.text.bodySmall?.copyWith(
                  color: c.onSurfaceVariant,
                ),
              ),
            ]),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String label, List<Widget> chips) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 56,
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                label,
                style: context.text.labelMedium?.copyWith(
                  color: context.colors.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Expanded(child: Wrap(spacing: 6, runSpacing: 6, children: chips)),
          ],
        ),
      );

  Future<void> _chipMenu(
    BuildContext context,
    String label,
    String namespace,
  ) async {
    final scoped = namespace.isEmpty ? null : '$namespace:$label';
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                scoped ?? label,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: Text(tr('复制')),
              onTap: () => Navigator.pop(ctx, 'copy'),
            ),
            ListTile(
              leading: const Icon(Icons.block_rounded),
              title: Text(tr('屏蔽「{label}」', {'label': label})),
              onTap: () => Navigator.pop(ctx, 'block'),
            ),
            if (scoped != null)
              ListTile(
                leading: const Icon(Icons.block_outlined),
                title: Text(tr('仅屏蔽「{label}」', {'label': scoped})),
                onTap: () => Navigator.pop(ctx, 'blockScoped'),
              ),
          ],
        ),
      ),
    );
    if (!context.mounted || action == null) return;
    switch (action) {
      case 'copy':
        await Clipboard.setData(ClipboardData(text: label));
        if (context.mounted)
          context.toast(tr('已复制「{label}」', {'label': label}));
      case 'block':
      case 'blockScoped':
        final entry = action == 'block' ? label : scoped!;
        AppSettings.instance.addBlockedTag(entry);
        context.toast(tr('已屏蔽「{label}」，列表中将隐藏带有该标签的作品', {'label': entry}));
    }
  }

  Widget _chip(
    BuildContext context,
    String label,
    VoidCallback onTap, {
    int? count,
    String namespace = '',
  }) {
    final c = context.colors;
    return Material(
      color: c.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        onLongPress: () => _chipMenu(context, label, namespace),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: label),
                if (count != null)
                  TextSpan(
                    text: '  ${formatCount(count)}',
                    style: TextStyle(color: c.onSurfaceVariant, fontSize: 10.5),
                  ),
              ],
            ),
            style: context.text.labelMedium,
          ),
        ),
      ),
    );
  }
}

class _BodySkeleton extends StatelessWidget {
  const _BodySkeleton();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LoadingIndicator(
          label: context.tr('正在加载详情…'),
          padding: const EdgeInsets.only(bottom: 20),
        ),
        const Skeleton(height: 14, radius: 4),
        const SizedBox(height: 8),
        const Skeleton(height: 14, width: 220, radius: 4),
        const SizedBox(height: 24),
        const Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Skeleton(width: 64, height: 28, radius: 8),
            Skeleton(width: 90, height: 28, radius: 8),
            Skeleton(width: 54, height: 28, radius: 8),
            Skeleton(width: 80, height: 28, radius: 8),
            Skeleton(width: 70, height: 28, radius: 8),
          ],
        ),
      ],
    ),
  );
}

class _ChapterPicker extends StatefulWidget {
  const _ChapterPicker({required this.chapters});
  final List<Chapter> chapters;

  @override
  State<_ChapterPicker> createState() => _ChapterPickerState();
}

class _ChapterPickerState extends State<_ChapterPicker> {
  final Set<String> _selected = {};

  @override
  Widget build(BuildContext context) {
    AppLocalizations.of(context);
    final all = _selected.length == widget.chapters.length;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      builder: (context, scroll) => Column(
        children: [
          ListTile(
            title: Text(
              tr('选择要下载的章节（{count}）', {'count': _selected.length}),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            trailing: TextButton(
              onPressed: () => setState(
                () => all
                    ? _selected.clear()
                    : _selected.addAll(widget.chapters.map((c) => c.id)),
              ),
              child: Text(all ? tr('全不选') : tr('全选')),
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: scroll,
              itemCount: widget.chapters.length,
              itemBuilder: (_, i) {
                final ch = widget.chapters[i];
                return CheckboxListTile(
                  value: _selected.contains(ch.id),
                  title: Text(ch.title),
                  onChanged: (v) => setState(
                    () => v == true
                        ? _selected.add(ch.id)
                        : _selected.remove(ch.id),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _selected.isEmpty
                      ? null
                      : () => Navigator.pop(
                          context,
                          widget.chapters
                              .where((c) => _selected.contains(c.id))
                              .toList(),
                        ),
                  child: Text(tr('开始下载')),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// App bar title that fades in only once the header has collapsed (the expanded header shows it already).
class _CollapsingTitle extends StatelessWidget {
  const _CollapsingTitle(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    final settings = context
        .dependOnInheritedWidgetOfExactType<FlexibleSpaceBarSettings>();
    var t = 1.0;
    if (settings != null && settings.maxExtent > settings.minExtent) {
      t =
          ((settings.maxExtent - settings.currentExtent) /
                  (settings.maxExtent - settings.minExtent))
              .clamp(0.0, 1.0);
    }
    return Opacity(
      opacity: t < 0.85 ? 0 : (t - 0.85) / 0.15,
      child: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.text.titleMedium,
      ),
    );
  }
}
