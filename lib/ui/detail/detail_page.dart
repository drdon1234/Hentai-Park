import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/diagnostics.dart';
import '../../core/localization.dart';
import '../../core/models.dart';
import '../../core/tag_blocklist.dart';
import '../../engine/source_manager.dart';
import '../../library/downloads.dart';
import '../../library/library.dart';
import '../game/game_resources.dart';
import '../kit/kit.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/content_translation.dart';
import '../widgets/error_view.dart';
import '../widgets/expandable_description.dart';
import '../widgets/paged_grid.dart';
import 'detail_action_bar.dart';
import 'detail_actions.dart';
import 'detail_download.dart';
import 'detail_header.dart';
import 'detail_sections.dart';
import 'detail_tags.dart';
import 'thumbnail_grid.dart';

/// A work's page: header, one primary action, then description, tags, chapters, previews and
/// related works. Layout pieces live in detail_header.dart and detail_sections.dart.

class DetailPage extends StatefulWidget {
  const DetailPage({
    super.key,
    required this.source,
    required this.id,
    this.preview,
    this.coverHeroTag,
    this.onClose,
  });
  final String source;
  final String id;
  final WorkItem? preview;
  final Object? coverHeroTag;

  /// Closes the page when it is shown beside a list instead of as a route.
  final VoidCallback? onClose;

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  WorkDetail? _detail;
  Object? _error;
  bool _reversed = false;
  final Set<String> _selected = {};
  final _resourcesKey = GlobalKey();

  SourceManifest? get _m => SourceManager.instance.manifest(widget.source);
  String get _uid => '${widget.source}:${widget.id}';
  bool get _isVideo =>
      _m?.isVideo ?? DownloadManager.instance.task(_uid)?.isVideo ?? false;
  bool get _opensExternally => _m?.opensExternally == true;
  bool get _isGame => _m?.isGame == true || _item.isGame;

  @override
  void initState() {
    super.initState();
    Library.instance.loadChapters(_uid);
    _load();
  }

  /// Keeps the stored chapter list (and with it read state and library updates) in step with the site.
  Future<void> _syncChapters(WorkDetail d) async {
    if (_opensExternally || _isGame) return;
    final chapters = _isVideo
        ? d.videoEpisodes
        : d.chapters ?? [Chapter(chapterKeyOf(d.singleChapterId), tr('全本'))];
    try {
      await Library.instance.syncChapters(
        d.toItem(),
        chapters,
        oneShot: _isVideo ? !d.hasVideoEpisodes : d.chapters == null,
        complete: d.chaptersComplete,
      );
    } catch (e) {
      debugPrint(Diagnostics.error(e));
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
        unawaited(_syncChapters(d));
      }
      return;
    }
    try {
      final d = await SourceManager.instance.detail(
        widget.source,
        widget.id,
        preview: widget.preview,
      );
      if (!mounted) return;
      setState(() => _detail = d);
      Library.instance.recordVisit(d.toItem());
      unawaited(_syncChapters(d));
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

  DetailKind get _kind {
    if (_isGame) return DetailKind.game;
    if (_opensExternally) return DetailKind.external;
    if (_isVideo) return DetailKind.video;
    final novel =
        _m?.isNovel == true ||
        DownloadManager.instance.task(_uid)?.isNovel == true ||
        _item.isNovel;
    return novel ? DetailKind.novel : DetailKind.reading;
  }

  WorkItem get _item =>
      _detail?.toItem() ??
      widget.preview ??
      WorkItem({'id': widget.id, 'title': widget.id}, widget.source);

  void _read({Chapter? chapter, int page = 0}) {
    final d = _detail;
    if (d == null) return;
    if (_opensExternally || _isGame) {
      _openOriginal();
      return;
    }
    if (_isVideo) {
      Nav.openVideo(context, d, episodeId: chapter?.id);
      return;
    }
    if (d.hasNoChapters) {
      context.toast(tr('暂无章节'));
      return;
    }
    chapter ??= d.chapterToOpen(Library.instance.historyOf(d.uid)?.chapterId);
    Nav.openReader(context, d, chapter: chapter, startPage: page);
  }

  void _continue() {
    if (_isGame) {
      final target = _resourcesKey.currentContext;
      if (target != null) {
        Scrollable.ensureVisible(
          target,
          duration: Motion.of(context, Motion.medium),
        );
      } else if (_detail != null) {
        showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (_) => SafeArea(
            child: FractionallySizedBox(
              heightFactor: .85,
              child: SingleChildScrollView(
                child: GameResources(work: _detail!),
              ),
            ),
          ),
        );
      }
      return;
    }
    final d = _detail;
    if (d == null) return;
    if (_opensExternally) {
      _openOriginal();
      return;
    }
    if (_isVideo) {
      Nav.openVideo(context, d);
      return;
    }
    final h = Library.instance.historyOf(d.uid);
    if (h != null && h.pageCount > 0 && !d.hasNoChapters) {
      final chapter = d.chapterToOpen(h.chapterId);
      Nav.openReader(context, d, chapter: chapter, startPage: h.page);
    } else {
      _read();
    }
  }

  @override
  Widget build(BuildContext context) {
    return TranslationPage(
      child: Scaffold(
        body: ListenableBuilder(
          listenable: Listenable.merge([
            Library.instance.work(_uid),
            DownloadManager.instance,
          ]),
          builder: (context, _) => CustomScrollView(
            slivers: [
              DetailHeader(
                item: _item,
                detail: _detail,
                manifest: _m,
                coverHeroTag: widget.coverHeroTag,
                onClose: widget.onClose,
                body: [
                  SliverToBoxAdapter(
                    child: DetailActionBar(
                      item: _item,
                      detail: _detail,
                      kind: _kind,
                      onPrimary: _opensExternally && !_canOpenOriginal
                          ? null
                          : _continue,
                      onDownload: () => downloadWork(
                        context,
                        _detail!,
                        _item,
                        isVideo: _isVideo,
                      ),
                      onMore: () => _more(context),
                    ),
                  ),
                  if (_detail != null)
                    ..._body(context, _detail!)
                  else if (_error == null)
                    SliverToBoxAdapter(
                      child: DetailBodySkeleton(source: widget.source),
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: Gap.xxl)),
                ],
              ),
              if (_error != null && _detail == null)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: SourceErrorView(
                    error: _error!,
                    source: widget.source,
                    onRetry: _load,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Uri? get _originalUri {
    final uri = Uri.tryParse(_detail?.url ?? '');
    return uri != null &&
            (uri.scheme == 'https' || uri.scheme == 'http') &&
            uri.host.isNotEmpty &&
            uri.userInfo.isEmpty
        ? uri
        : null;
  }

  bool get _canOpenOriginal => _originalUri != null;

  Future<void> _openOriginal() async {
    final uri = _originalUri;
    if (uri == null) return;
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) context.toast(tr('无法打开原站，请稍后重试'));
    } catch (_) {
      if (mounted) context.toast(tr('无法打开原站，请稍后重试'));
    }
  }

  Future<void> _more(BuildContext context) => showDetailMore(
    context,
    detail: _detail!,
    item: _item,
    onOpenOriginal: _canOpenOriginal ? _openOriginal : null,
  );

  int _unread(List<Chapter> chapters) => chapters
      .where((ch) => Library.instance.chapterState(_uid, ch.id)?.read != true)
      .length;

  void _toggleSelect(String id) {
    HapticFeedback.selectionClick();
    setState(
      () => _selected.contains(id) ? _selected.remove(id) : _selected.add(id),
    );
  }

  Widget _chapterHeader(BuildContext context, List<Chapter> chapters) {
    if (_selected.isNotEmpty) {
      void done() => setState(_selected.clear);
      return ChapterSelectionBar(
        count: _selected.length,
        isVideo: _isVideo,
        onClear: done,
        onSelectAll: () =>
            setState(() => _selected.addAll(chapters.map((c) => c.id))),
        onDownload: () async {
          final selected = chapters
              .where((c) => _selected.contains(c.id))
              .toList();
          if (_isVideo) {
            await downloadEpisodes(context, _detail!, _item, selected);
            if (mounted) done();
            return;
          }
          DownloadManager.instance.enqueue(_item, selected);
          context.toast(tr('已加入下载队列'));
          done();
        },
        onMarkRead: (read) {
          Library.instance.markRead(_uid, _selected.toList(), read);
          done();
        },
        onMarkPreviousRead: _selected.length == 1
            ? () {
                final i = chapters.indexWhere((c) => c.id == _selected.first);
                Library.instance.markRead(
                  _uid,
                  chapters.take(i).map((c) => c.id).toList(),
                  true,
                );
                done();
              }
            : null,
      );
    }
    final unread = _unread(chapters);
    return SectionHeader(
      _isVideo
          ? tr('选集 · {count}', {'count': chapters.length})
          : tr('章节 · {count}{unread}', {
              'count': chapters.length,
              'unread': unread > 0 ? tr('（未读 {count}）', {'count': unread}) : '',
            }),
      trailing: TextButton(
        onPressed: () => setState(() => _reversed = !_reversed),
        child: Text(_reversed ? tr('倒序') : tr('正序')),
      ),
    );
  }

  List<Widget> _body(BuildContext context, WorkDetail d) {
    final isVideo = _isVideo;
    final chapters = _opensExternally || _isGame
        ? null
        : isVideo && d.hasVideoEpisodes
        ? d.videoEpisodes
        : d.chapters;
    final blocked = TagBlocklist.current().matchDetail(d);
    final ordered = chapters == null
        ? null
        : (_reversed ? chapters.reversed.toList() : chapters);
    final current = Library.instance.historyOf(d.uid)?.chapterId;
    final isNovel = _m?.isNovel == true || d.isNovel;
    return [
      if (blocked.isNotEmpty)
        SliverToBoxAdapter(child: BlockedNotice(tags: blocked)),
      if (d.description.isNotEmpty)
        SliverToBoxAdapter(child: ExpandableDescription(text: d.description)),
      if (_isGame)
        SliverToBoxAdapter(
          child: GameResources(key: _resourcesKey, work: d),
        ),
      if (d.tagGroups.isNotEmpty ||
          d.authors.isNotEmpty ||
          d.uploader.isNotEmpty)
        SliverToBoxAdapter(
          child: TagSection(detail: d, source: widget.source),
        ),
      if (d.hasNoChapters && !isVideo && !_isGame && !_opensExternally)
        SliverToBoxAdapter(
          child: EmptyState(
            compact: true,
            icon: Icons.format_list_bulleted_rounded,
            title: tr('暂无章节'),
            message: tr('站点还没有列出章节，稍后再来看看。'),
            actions: [TextButton(onPressed: _load, child: Text(tr('刷新')))],
          ),
        ),
      if (ordered != null && ordered.isNotEmpty) ...[
        SliverToBoxAdapter(child: _chapterHeader(context, ordered)),
        SliverList.separated(
          itemCount: ordered.length,
          separatorBuilder: (_, _) =>
              const Divider(indent: Gap.page, endIndent: Gap.page),
          itemBuilder: (context, i) {
            final ch = ordered[i];
            return ChapterRow(
              chapter: ch,
              uid: d.uid,
              isVideo: isVideo,
              isNovel: isNovel,
              current: current == ch.id,
              selected: _selected.contains(ch.id),
              onTap: () => _selected.isNotEmpty
                  ? _toggleSelect(ch.id)
                  : _read(chapter: ch),
              onLongPress: () => _toggleSelect(ch.id),
            );
          },
        ),
      ],
      if (!isVideo &&
          !_isGame &&
          (d.thumbnails.isNotEmpty || _m?.can('thumbnails') == true))
        SliverToBoxAdapter(
          child: ThumbnailSection(
            detail: d,
            onOpen: (page) => _read(page: page),
          ),
        ),
      if (d.series.isNotEmpty)
        SliverToBoxAdapter(
          child: WorkCarousel(title: tr('同系列'), items: d.series),
        ),
      if (d.related.isNotEmpty)
        SliverToBoxAdapter(
          child: WorkCarousel(title: tr('相关推荐'), items: d.related),
        ),
    ];
  }
}
