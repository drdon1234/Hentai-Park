import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/app_lock.dart';
import '../../core/app_log.dart';
import '../../core/content_scope.dart';
import '../../core/localization.dart';
import '../../core/models.dart';
import '../../core/platform_capabilities.dart';
import '../../core/settings.dart';
import '../../core/tag_blocklist.dart';
import '../../engine/cancellation.dart';
import '../../engine/source_manager.dart';
import '../../images/park_image.dart';
import '../../library/library.dart';
import '../history/history_page.dart';
import '../kit/kit.dart';
import '../nav.dart';
import '../settings/settings_sections.dart';
import '../theme.dart';
import '../video/adaptive_video_progress.dart';
import '../widgets/content_translation.dart';
import '../widgets/cover_tile.dart';
import '../widgets/error_view.dart';
import '../widgets/source_account_strip.dart';
import '../widgets/source_interaction.dart';
import '../widgets/source_network_hint.dart';
import 'post_video_feed.dart';
import 'short_video_feed.dart';
import 'short_video_playback.dart';
import 'short_video_player.dart';
import 'short_video_sequence.dart';

class ShortVideoPage extends StatefulWidget {
  const ShortVideoPage({
    super.key,
    required this.source,
    this.initial,
    this.initialId,
    this.feedIndex,
    this.postScope,
    this.sequence,
  });
  final String source;
  final WorkItem? initial;
  final String? initialId;
  final int? feedIndex;
  final PostVideoScope? postScope;

  /// 从列表点开时按列表顺序播放，[initial] 是被点开的作品。
  final ShortVideoSequence? sequence;
  @override
  State<ShortVideoPage> createState() => _ShortVideoPageState();
}

class _ShortVideoPageState extends State<ShortVideoPage>
    with WidgetsBindingObserver, RouteAware {
  late final ShortVideoFeed _feed;
  late final ShortVideoPlayback _playback;
  final _preferences = AppSettings.instance.domain(SettingsDomain.shortVideo);
  late final PageController _pages;
  Timer? _saveTimer;
  StreamSubscription<String>? _authentication;
  WorkItem? _visible;
  ModalRoute<dynamic>? _route;
  bool _foreground = true,
      _covered = false,
      _scrolling = false,
      _expanded = false;
  bool _resolving = false;
  bool _refreshing = false;
  double _overscroll = 0;
  Object? _initialError;
  final _retrySources = <String>{};
  CancelToken _loadCancel = CancelToken();
  DateTime _lastWheel = DateTime.fromMillisecondsSinceEpoch(0);

  void _step(int delta) {
    if (!_pages.hasClients || _scrolling || _resolving) return;
    final next = (_feed.index + delta).clamp(0, _feed.items.length);
    if (next == _feed.index) return;
    unawaited(
      _pages.animateToPage(
        next,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppLock.instance.addListener(_sync);
    _playback = ShortVideoPlayback(
      (item, cancel) => ShortVideoPlayer.open(
        item,
        cancel,
        refresh: _retrySources.remove(item.uid),
      ),
      preloadCount: AppSettings.instance.shortVideoPreloadCount,
      retainedCount: AppSettings.instance.shortVideoRetainedCount,
    )..addListener(_changed);
    _preferences.addListener(_limitsChanged);
    _authentication = SourceManager.instance.authenticationChanges.listen((
      key,
    ) {
      if (key == widget.source) unawaited(_refresh());
    });
    final posts =
        SourceManager.instance
            .manifest(widget.source)
            ?.json['postShortVideos'] ==
        true;
    WorkPage clips(WorkPage page) => posts ? postVideoPage(page) : page;
    final sequence = widget.sequence;
    final sequenceItems = sequence == null
        ? const <WorkItem>[]
        : clips(WorkPage(items: sequence.items, page: sequence.page)).items;
    _feed = ShortVideoFeed(
      (page, cursor) async {
        if (sequence != null) {
          return clips(
            await awaitCancelled(sequence.load(page, cursor), _loadCancel),
          );
        }
        if (AppSettings.instance.searchOnlySources) {
          AppLog.record({
            'event': 'content',
            'site': widget.source,
            'action': 'feed',
            'reason': 'SEARCH_ONLY',
          });
          return Future.value(WorkPage(items: const [], page: page));
        }
        if (widget.postScope case final scope?) {
          return postVideoPage(
            await scope.load(
              page,
              cursor,
              refresh: _refreshing,
              cancelToken: _loadCancel,
            ),
          );
        }
        final m = SourceManager.instance.manifest(widget.source);
        if (m == null || m.feeds.isEmpty) throw SourceError('CONFIG', '站点未加载');
        final i =
            (widget.feedIndex ??
                    SourceManager.instance.entryFeedIndex(widget.source))
                .clamp(0, m.feeds.length - 1);
        final result = await SourceManager.instance.feed(
          widget.source,
          m.feeds[i].key,
          page: page,
          cursor: cursor,
          options: m.feeds[i].defaultOptions(),
          refresh: _refreshing,
          cancelToken: _loadCancel,
          onCached: page == 1 && m.json['postShortVideos'] != true
              ? _feed.cachedReceiver()
              : null,
        );
        return m.json['postShortVideos'] == true
            ? postVideoPage(result)
            : result;
      },
      source: widget.source,
      initialItems: sequenceItems,
      initialUid: sequenceItems
          .where((item) => videoPost(item).uid == widget.initial?.uid)
          .firstOrNull
          ?.uid,
      initialPage: sequence?.page ?? 0,
      initialCursor: sequence?.cursor,
      hasMore: sequence?.hasNext ?? true,
      allowItem: (item) =>
          TagBlocklist.current().matchItem(videoPost(item)) == null &&
          (widget.initial?.isSubscriptionPost != true ||
              (item.mediaKind == MediaKind.video &&
                  (item.json['media'] as List? ?? const []).any(
                    isPostVideoAttachment,
                  ))),
    )..addListener(_feedChanged);
    _pages = PageController(initialPage: _feed.index);
    _saveTimer = Timer.periodic(const Duration(seconds: 10), (_) => _save());
    if (sequence != null) {
      _feedChanged();
      if (_feed.items.isEmpty) unawaited(_feed.loadMore());
    } else if (widget.initial != null) {
      _resolving = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await _seedInitial(widget.initial!);
        if (mounted) {
          setState(() => _resolving = false);
          _feedChanged();
          unawaited(_feed.loadMore());
        }
      });
    } else if (widget.initialId != null) {
      unawaited(_resolveInitial());
    } else {
      _feedChanged();
      unawaited(_feed.loadMore());
    }
  }

  Future<void> _resolveInitial() async {
    setState(() {
      _resolving = true;
      _initialError = null;
    });
    try {
      final detail = await SourceManager.instance.detail(
        widget.source,
        widget.initialId!,
      );
      if (!mounted) return;
      await _seedInitial(detail.toItem());
      unawaited(_feed.loadMore());
    } catch (e) {
      if (mounted) setState(() => _initialError = e);
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
  }

  Future<void> _seedInitial(WorkItem item) async {
    final hit = TagBlocklist.current().matchItem(videoPost(item));
    if (hit != null) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr('内容已屏蔽')),
          content: Text(tr('包含已屏蔽的内容：{tags}', {'tags': hit})),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: SelectionContainer.disabled(child: Text(tr('取消'))),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: SelectionContainer.disabled(child: Text(tr('继续'))),
            ),
          ],
        ),
      );
      if (!mounted || proceed != true) return;
    }
    if (!mounted) return;
    if (SourceManager.instance
            .manifest(widget.source)
            ?.json['postShortVideos'] ==
        true) {
      for (final clip in postVideoPage(
        WorkPage(items: [item], page: 1),
      ).items.reversed) {
        _feed.seed(clip, allowBlocked: hit != null);
      }
    } else {
      _feed.seed(item, allowBlocked: hit != null);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (!identical(route, _route) && route != null) {
      Nav.routeObserver.unsubscribe(this);
      _route = route;
      Nav.routeObserver.subscribe(this, route);
    }
  }

  @override
  void didPushNext() {
    _covered = true;
    _save();
    _sync();
  }

  @override
  void didPopNext() {
    _covered = false;
    _sync();
  }

  @override
  void didPop() {
    _covered = true;
    _save();
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) _save();
    _sync();
  }

  void _sync() {
    final enabled =
        _visible != null &&
        _foreground &&
        !_covered &&
        !_scrolling &&
        !_refreshing &&
        !AppLock.instance.locked;
    unawaited(_playback.setEnabled(enabled));
    if (enabled && _visible != null) {
      unawaited(WakelockPlus.enable());
    } else {
      unawaited(WakelockPlus.disable());
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _limitsChanged() {
    unawaited(
      _playback.setLimits(
        preloadCount: AppSettings.instance.shortVideoPreloadCount,
        retainedCount: AppSettings.instance.shortVideoRetainedCount,
      ),
    );
  }

  ShortVideoPlayer? _player(WorkItem? item) {
    final handle = item == null ? null : _playback.handle(item.uid);
    return handle is ShortVideoPlayer ? handle : null;
  }

  void _save() {
    final item = _visible, player = _player(_visible);
    if (item == null ||
        player == null ||
        !player.controller.value.isInitialized) {
      return;
    }
    final value = player.controller.value;
    Library.instance.recordVideoPosition(
      videoPost(item),
      value.position.inSeconds,
      duration: value.duration.inSeconds,
    );
  }

  void _feedChanged() {
    if (!mounted) return;
    final index = _feed.index;
    final current = index < _feed.items.length ? _feed.items[index] : null;
    if (_visible?.uid != current?.uid) {
      _save();
      _visible = current;
      _expanded = false;
    }
    if (_pages.hasClients && _pages.page?.round() != index) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pages.hasClients) _pages.jumpToPage(_feed.index);
      });
    }
    // 列表尾页只暂停，翻回时继续复用；刷新或清空列表才释放全部缓存。
    if (current != null || _feed.items.isEmpty) {
      unawaited(
        _playback.select(
          current,
          _feed.items
              .skip(index + 1)
              .take(AppSettings.maxShortVideoPreloadCount),
        ),
      );
    }
    _sync();
    setState(() {});
  }

  Future<void> _refresh() async {
    if (_refreshing || _resolving) return;
    _refreshing = true;
    _loadCancel.cancel();
    _loadCancel = CancelToken();
    _sync();
    _save();
    try {
      _visible = null;
      await _playback.select(null, const []);
      if (!mounted) return;
      setState(() {
        _expanded = false;
        _initialError = null;
      });
      if (_pages.hasClients) _pages.jumpToPage(0);
      await _feed.refresh();
    } finally {
      _refreshing = false;
      if (mounted) _sync();
    }
  }

  Future<void> _retryPlayback() async {
    final item = _visible;
    if (item == null) return;
    if (item.isSubscriptionPost) {
      await _refresh();
      return;
    }
    _retrySources.add(item.uid);
    await _playback.retry();
  }

  @override
  void dispose() {
    _loadCancel.cancel();
    _authentication?.cancel();
    _save();
    _saveTimer?.cancel();
    Nav.routeObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    AppLock.instance.removeListener(_sync);
    _preferences.removeListener(_limitsChanged);
    _feed.removeListener(_feedChanged);
    _feed.dispose();
    _playback.removeListener(_changed);
    _playback.dispose();
    _pages.dispose();
    unawaited(WakelockPlus.disable());
    super.dispose();
  }

  Widget _loading() => Center(
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          SourceNetworkHint(source: widget.source),
        ],
      ),
    ),
  );
  Widget _error(Object error, VoidCallback retry) => Center(
    child: SingleChildScrollView(
      child: SourceErrorView(
        error: error,
        source: widget.source,
        onRetry: retry,
      ),
    ),
  );
  Widget _tail() {
    if (_feed.error != null) {
      return _error(_feed.error!, _feed.hasNext ? _feed.loadMore : _refresh);
    }
    if (_feed.loading || _resolving) return _loading();
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              tr(
                _feed.allFiltered
                    ? '内容已屏蔽'
                    : AppSettings.instance.searchOnlySources
                    ? '超级省流'
                    : _feed.hasNext
                    ? '当前页没有可显示的短视频，可继续加载'
                    : '暂时没有更多短视频',
              ),
              textAlign: TextAlign.center,
            ),
            if (_feed.hasNext)
              TextButton(
                onPressed: () => _feed.loadMore(),
                child: SelectionContainer.disabled(child: Text(tr('继续加载'))),
              ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
              label: SelectionContainer.disabled(child: Text(tr('刷新'))),
            ),
          ],
        ),
      ),
    );
  }

  Widget _video(WorkItem item, bool active) {
    final player = active ? _player(item) : null, c = player?.controller;
    final error = active ? _playback.error(item.uid) : null;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (item.cover.isNotEmpty)
          Image(
            image: ParkImage.url(widget.source, item.cover),
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        if (c != null)
          Center(
            child: AspectRatio(
              aspectRatio: c.value.aspectRatio,
              child: VideoPlayer(c),
            ),
          ),
        if (active)
          Semantics(
            button: true,
            label: tr(_playback.wantsPlayback ? '暂停' : '播放'),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _playback.toggle(),
              child: c == null && error == null
                  ? _loading()
                  : !_playback.wantsPlayback
                  ? Center(
                      child: FadeIn(
                        child: Container(
                          width: 76,
                          height: 76,
                          decoration: const BoxDecoration(
                            color: Scrims.medium,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.play_arrow_rounded,
                            size: 48,
                            color: Scrims.onScrim,
                          ),
                        ),
                      ),
                    )
                  : const SizedBox.expand(),
            ),
          ),
        if (error != null)
          ColoredBox(
            color: Colors.black87,
            child: _error(error, _retryPlayback),
          ),
        const Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 280,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Scrims.strong, Scrims.faint, Colors.transparent],
                  stops: [0, .55, 1],
                ),
              ),
            ),
          ),
        ),
        if (active && c != null)
          Positioned(
            left: 16,
            right: 16,
            bottom: 12,
            child: ValueListenableBuilder<VideoPlayerValue>(
              valueListenable: c,
              builder: (context, value, _) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (value.hasError)
                      FilledButton.tonal(
                        onPressed: _retryPlayback,
                        child: SelectionContainer.disabled(
                          child: Text(tr('重试')),
                        ),
                      ),
                    if (value.isBuffering) const LinearProgressIndicator(),
                    AdaptiveVideoProgress(
                      position: value.position,
                      duration: value.duration,
                      buffered: value.buffered.isEmpty
                          ? Duration.zero
                          : value.buffered.last.end,
                      onSeek: (position) => c.seekTo(position),
                      onScrubbingChanged: (scrubbing) {
                        _scrolling = scrubbing;
                        _sync();
                      },
                    ),
                  ],
                );
              },
            ),
          ),
        Positioned(
          left: 18,
          right: 18,
          bottom: 76,
          child: SafeArea(
            top: false,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * .32,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                GestureDetector(
                                  onLongPress: () =>
                                      showWorkActions(context, item),
                                  onSecondaryTap: PlatformCapabilities.desktop
                                      ? () => showWorkActions(context, item)
                                      : null,
                                  onTap: active
                                      ? () => setState(
                                          () => _expanded = !_expanded,
                                        )
                                      : null,
                                  child: ContentTranslation(
                                    text: item.title,
                                    source: item.source,
                                    builder: (value) => Text(
                                      value,
                                      maxLines: active && _expanded ? null : 3,
                                      overflow: active && _expanded
                                          ? null
                                          : TextOverflow.ellipsis,
                                      style: context.text.titleMedium?.copyWith(
                                        color: Colors.white,
                                        height: 1.4,
                                        shadows: const [
                                          Shadow(
                                            blurRadius: 8,
                                            color: Scrims.medium,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                if (item.subtitle.isNotEmpty)
                                  ContentTranslation(
                                    text: item.subtitle,
                                    source: item.source,
                                    builder: (value) => Text(
                                      value,
                                      maxLines: active && _expanded ? null : 2,
                                      overflow: active && _expanded
                                          ? null
                                          : TextOverflow.ellipsis,
                                      style: context.text.bodyMedium?.copyWith(
                                        color: Colors.white70,
                                        height: 1.45,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        if (active)
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              foregroundColor: Scrims.onScrim,
                            ),
                            onPressed: () =>
                                setState(() => _expanded = !_expanded),
                            icon: Icon(
                              _expanded
                                  ? Icons.expand_less_rounded
                                  : Icons.expand_more_rounded,
                            ),
                            label: Text(tr(_expanded ? '收起简介' : '展开简介')),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ListenableBuilder(
                  listenable: Library.instance.work(videoPost(item).uid),
                  builder: (context, _) {
                    final favorite = Library.instance.isFavorite(
                      videoPost(item).uid,
                    );
                    return IconButton(
                      tooltip: tr(favorite ? '取消应用内收藏' : '应用内收藏'),
                      onPressed: () {
                        if (favorite) {
                          Library.instance.removeFavorite(videoPost(item).uid);
                        } else {
                          Library.instance.addFavorite(videoPost(item));
                        }
                      },
                      icon: Icon(
                        favorite ? Icons.bookmark : Icons.bookmark_border,
                        color: favorite ? context.colors.primary : Colors.white,
                        size: 32,
                      ),
                    );
                  },
                ),
                if (SourceManager.instance
                        .manifest(item.source)
                        ?.can('interaction') ==
                    true)
                  IconButton(
                    tooltip: tr('原站互动'),
                    onPressed: () =>
                        showSourceInteraction(context, videoPost(item)),
                    icon: const Icon(
                      Icons.thumb_up_outlined,
                      color: Colors.white,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) =>
      ImmersiveRegion(child: _buildPage(context));

  Widget _buildPage(BuildContext context) {
    final manifest = SourceManager.instance.manifest(widget.source);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowDown): () => _step(1),
        const SingleActivator(LogicalKeyboardKey.pageDown): () => _step(1),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () => _step(-1),
        const SingleActivator(LogicalKeyboardKey.pageUp): () => _step(-1),
        const SingleActivator(LogicalKeyboardKey.space): () =>
            unawaited(_playback.toggle()),
      },
      child: Focus(
        autofocus: true,
        child: Listener(
          onPointerSignal: (event) {
            if (event is! PointerScrollEvent ||
                event.scrollDelta.dy == 0 ||
                _expanded) {
              return;
            }
            GestureBinding.instance.pointerSignalResolver.register(event, (
              event,
            ) {
              final now = DateTime.now();
              if (now.difference(_lastWheel).inMilliseconds < 300) return;
              _lastWheel = now;
              _step((event as PointerScrollEvent).scrollDelta.dy > 0 ? 1 : -1);
            });
          },
          child: TranslationPage(
            child: Theme(
              data: ParkTheme.of(
                Brightness.dark,
                Color(AppSettings.instance.seedColor),
              ),
              child: Builder(
                builder: (context) => Scaffold(
                  backgroundColor: Colors.black,
                  body: SafeArea(
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: _initialError != null
                              ? _error(_initialError!, _resolveInitial)
                              : _resolving
                              ? _loading()
                              : NotificationListener<ScrollNotification>(
                                  onNotification: (n) {
                                    if (n.depth != 0) return false;
                                    if (n is ScrollStartNotification) {
                                      _scrolling = true;
                                      _overscroll = 0;
                                      _sync();
                                    }
                                    if (n is OverscrollNotification &&
                                        n.dragDetails != null) {
                                      final atStart =
                                          _feed.index == 0 && n.overscroll < 0;
                                      final atEnd =
                                          _feed.index == _feed.items.length &&
                                          !_feed.hasNext &&
                                          n.overscroll > 0;
                                      if (atStart || atEnd) {
                                        _overscroll += n.overscroll.abs();
                                      }
                                    }
                                    if (n is ScrollEndNotification) {
                                      _scrolling = false;
                                      if (_overscroll >= 64) {
                                        unawaited(_refresh());
                                      }
                                      _sync();
                                    }
                                    return false;
                                  },
                                  child: PageView.builder(
                                    key: ValueKey(_feed.generation),
                                    controller: _pages,
                                    scrollDirection: Axis.vertical,
                                    itemCount: _feed.items.length + 1,
                                    onPageChanged: (i) {
                                      _save();
                                      _feed.select(i);
                                    },
                                    itemBuilder: (context, i) =>
                                        i == _feed.items.length
                                        ? _tail()
                                        : _video(
                                            _feed.items[i],
                                            i == _feed.index,
                                          ),
                                  ),
                                ),
                        ),
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: DecoratedBox(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Scrims.strong,
                                  Scrims.faint,
                                  Colors.transparent,
                                ],
                                stops: [0, .6, 1],
                              ),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  children: [
                                    const BackButton(color: Colors.white),
                                    Expanded(
                                      child: Text(
                                        widget.postScope?.title ??
                                            manifest?.name ??
                                            tr('短视频'),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: context.text.titleMedium
                                            ?.copyWith(color: Colors.white),
                                      ),
                                    ),
                                    TranslationControls(source: widget.source),
                                    if (manifest?.can('search') == true)
                                      IconButton(
                                        tooltip: tr('搜索'),
                                        icon: const Icon(Icons.search),
                                        onPressed: () => Nav.openSourceSearch(
                                          context,
                                          widget.source,
                                        ),
                                      ),
                                    PopupMenuButton<String>(
                                      icon: const Icon(
                                        Icons.more_vert,
                                        color: Colors.white,
                                      ),
                                      itemBuilder: (context) => [
                                        PopupMenuItem(
                                          value: 'history',
                                          child: SelectionContainer.disabled(
                                            child: Text(tr('浏览历史')),
                                          ),
                                        ),
                                        PopupMenuItem(
                                          value: 'refresh',
                                          child: SelectionContainer.disabled(
                                            child: Text(tr('刷新')),
                                          ),
                                        ),
                                        PopupMenuItem(
                                          value: 'playback-settings',
                                          child: SelectionContainer.disabled(
                                            child: Text(tr('短视频设置')),
                                          ),
                                        ),
                                        PopupMenuItem(
                                          value: 'settings',
                                          child: SelectionContainer.disabled(
                                            child: Text(tr('站点设置')),
                                          ),
                                        ),
                                      ],
                                      onSelected: (action) {
                                        if (action == 'history') {
                                          Nav.push(
                                            context,
                                            HistoryPage(
                                              scope: ContentScope.source(
                                                widget.source,
                                              ),
                                            ),
                                          );
                                        } else if (action == 'refresh') {
                                          _refresh();
                                        } else if (action ==
                                            'playback-settings') {
                                          Nav.push(
                                            context,
                                            const SettingsSectionPage(
                                              SettingsSection.shortVideo,
                                            ),
                                          );
                                        } else {
                                          Nav.openSourceSettings(
                                            context,
                                            widget.source,
                                          );
                                        }
                                      },
                                    ),
                                  ],
                                ),
                                if (manifest?.account != null)
                                  SourceAccountStrip(source: widget.source),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
