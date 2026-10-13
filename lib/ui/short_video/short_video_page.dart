import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/app_lock.dart';
import '../../core/localization.dart';
import '../../core/models.dart';
import '../../core/content_scope.dart';
import '../../core/tag_blocklist.dart';
import '../history/history_page.dart';
import '../widgets/content_translation.dart';
import '../../engine/source_manager.dart';
import '../../images/park_image.dart';
import '../../library/library.dart';
import '../nav.dart';
import '../discovery_navigation.dart';
import '../video/adaptive_video_progress.dart';
import '../widgets/error_view.dart';
import '../widgets/source_network_hint.dart';
import 'short_video_feed.dart';
import 'short_video_playback.dart';
import 'short_video_player.dart';

class ShortVideoPage extends StatefulWidget {
  const ShortVideoPage({
    super.key,
    required this.source,
    this.initial,
    this.initialId,
    this.feedIndex,
  });
  final String source;
  final WorkItem? initial;
  final String? initialId;
  final int? feedIndex;
  @override
  State<ShortVideoPage> createState() => _ShortVideoPageState();
}

class _ShortVideoPageState extends State<ShortVideoPage>
    with WidgetsBindingObserver, RouteAware {
  late final ShortVideoFeed _feed;
  late final ShortVideoPlayback _playback;
  final PageController _pages = PageController();
  Timer? _saveTimer;
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppLock.instance.addListener(_sync);
    _playback = ShortVideoPlayback(ShortVideoPlayer.open)
      ..addListener(_changed);
    _feed = ShortVideoFeed((page, cursor) {
      final m = SourceManager.instance.manifest(widget.source);
      if (m == null || m.feeds.isEmpty) throw SourceError('CONFIG', '源未加载');
      final i = (widget.feedIndex ?? m.defaultFeedIndex).clamp(
        0,
        m.feeds.length - 1,
      );
      return SourceManager.instance.feed(
        widget.source,
        m.feeds[i].key,
        page: page,
        cursor: cursor,
        options: m.feeds[i].defaultOptions(),
      );
    })..addListener(_feedChanged);
    _saveTimer = Timer.periodic(const Duration(seconds: 10), (_) => _save());
    if (widget.initial != null) {
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
    final hit = TagBlocklist.current().matchItem(item);
    if (hit != null) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr('内容已屏蔽')),
          content: Text(tr('包含已屏蔽的内容：{tags}', {'tags': hit})),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('取消')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('继续')),
            ),
          ],
        ),
      );
      if (!mounted || proceed != true) return;
    }
    if (mounted) _feed.seed(item, allowBlocked: hit != null);
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
      item,
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
    unawaited(
      _playback.select(
        current,
        index + 1 < _feed.items.length ? _feed.items[index + 1] : null,
      ),
    );
    _sync();
    setState(() {});
  }

  Future<void> _refresh() async {
    if (_refreshing || _resolving) return;
    _refreshing = true;
    _sync();
    _save();
    try {
      _visible = null;
      await _playback.select(null, null);
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

  @override
  void dispose() {
    _save();
    _saveTimer?.cancel();
    Nav.routeObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    AppLock.instance.removeListener(_sync);
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
      return _error(_feed.error!, () => _feed.loadMore());
    }
    if (_feed.loading || _resolving) return _loading();
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              tr(_feed.hasNext ? '当前页没有可显示的短视频，可继续加载' : '暂时没有更多短视频'),
              textAlign: TextAlign.center,
            ),
            if (_feed.hasNext)
              TextButton(
                onPressed: () => _feed.loadMore(),
                child: Text(tr('继续加载')),
              ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
              label: Text(tr('刷新')),
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
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _playback.toggle(),
            child: c == null && error == null
                ? _loading()
                : !_playback.wantsPlayback
                ? const Center(
                    child: Icon(
                      Icons.play_arrow_rounded,
                      size: 80,
                      color: Colors.white70,
                    ),
                  )
                : const SizedBox.expand(),
          ),
        if (error != null)
          ColoredBox(
            color: Colors.black87,
            child: _error(error, () => _playback.retry()),
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
                        onPressed: () => _playback.retry(),
                        child: Text(tr('重试')),
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
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GestureDetector(
                            onTap: active
                                ? () => setState(() => _expanded = !_expanded)
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
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  shadows: [
                                    Shadow(blurRadius: 5, color: Colors.black),
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
                                style: const TextStyle(color: Colors.white70),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ListenableBuilder(
                  listenable: Library.instance,
                  builder: (context, _) {
                    final favorite = Library.instance.isFavorite(item.uid);
                    return IconButton(
                      tooltip: tr(favorite ? '取消收藏' : '收藏'),
                      onPressed: () {
                        if (favorite) {
                          Library.instance.removeFavorite(item.uid);
                        } else {
                          Library.instance.addFavorite(item);
                        }
                      },
                      icon: Icon(
                        favorite ? Icons.favorite : Icons.favorite_border,
                        color: favorite ? Colors.pinkAccent : Colors.white,
                        size: 32,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    AppLocalizations.of(context);
    final manifest = SourceManager.instance.manifest(widget.source);
    return TranslationPage(
      child: Theme(
        data: ThemeData.dark(useMaterial3: true),
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
                                if (_overscroll >= 64) unawaited(_refresh());
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
                                  : _video(_feed.items[i], i == _feed.index),
                            ),
                          ),
                  ),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: ColoredBox(
                      color: Colors.black38,
                      child: Row(
                        children: [
                          BackButton(color: Colors.white),
                          Expanded(
                            child: Text(
                              manifest?.name ?? tr('短视频'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                          const DomainMenu(),
                          TranslationControls(source: widget.source),
                          if (manifest?.can('search') == true)
                            IconButton(
                              tooltip: tr('搜索'),
                              icon: const Icon(Icons.search),
                              onPressed: () =>
                                  Nav.openSourceSearch(context, widget.source),
                            ),
                          PopupMenuButton<String>(
                            icon: const Icon(
                              Icons.more_vert,
                              color: Colors.white,
                            ),
                            itemBuilder: (context) => [
                              PopupMenuItem(
                                value: 'history',
                                child: Text(tr('浏览历史')),
                              ),
                              PopupMenuItem(
                                value: 'refresh',
                                child: Text(tr('刷新')),
                              ),
                              PopupMenuItem(
                                value: 'settings',
                                child: Text(tr('源设置')),
                              ),
                            ],
                            onSelected: (action) {
                              if (action == 'history') {
                                Nav.push(
                                  context,
                                  HistoryPage(
                                    scope: ContentScope.source(widget.source),
                                  ),
                                );
                              } else if (action == 'refresh') {
                                _refresh();
                              } else {
                                Nav.openSourceSettings(context, widget.source);
                              }
                            },
                          ),
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
    );
  }
}
