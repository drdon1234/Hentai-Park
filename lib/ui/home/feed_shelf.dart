import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../core/localization.dart';
import '../../core/models.dart';
import '../../core/settings.dart';
import '../../core/tag_blocklist.dart';
import '../../engine/shared_feed.dart';
import '../album/open_album.dart';
import '../subscriptions/subscription_source_page.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/cover_tile.dart';
import '../widgets/error_view.dart';
import '../widgets/on_visible.dart';
import '../widgets/source_network_hint.dart';
import '../widgets/work_text_row.dart';
import 'feed_sessions.dart';

/// 主页和域页订阅同一推荐会话，滚动到右侧继续分页。
class FeedShelf extends StatefulWidget {
  const FeedShelf({
    super.key,
    required this.sessions,
    required this.sourceKey,
    required this.title,
    this.onMore,
    this.moreLabel,
    this.onToggleVisibility,
  });
  final FeedSessions sessions;
  final String sourceKey;
  final String title;
  final VoidCallback? onMore;
  final String? moreLabel;
  final VoidCallback? onToggleVisibility;

  @override
  State<FeedShelf> createState() => _FeedShelfState();
}

class _FeedShelfState extends State<FeedShelf>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  final _scroll = ScrollController();
  SharedFeedSession? _session;
  bool _visible = false;
  bool _scheduled = false;
  int _revision = -1;
  int _fillRequests = 0;
  late final Listenable _filters = AppSettings.instance.watch(
    AppSettings.filterKeys,
  );
  late final Listenable _homeVisibility = AppSettings.instance.watch(const {
    'homeHiddenSources',
  });

  @override
  void initState() {
    super.initState();
    _filters.addListener(_filtersChanged);
    _homeVisibility.addListener(_homeVisibilityChanged);
    _scroll.addListener(_scheduleFill);
    _bind();
  }

  void _homeVisibilityChanged() {
    _bind();
    if (mounted) setState(() {});
  }

  void _bind() {
    final session = widget.sessions.session(widget.sourceKey);
    if (identical(session, _session)) return;
    _session?.removeListener(_changed);
    _session = session;
    _revision = session?.revision ?? -1;
    _fillRequests = 0;
    _session?.addListener(_changed);
    _scheduleFill();
  }

  @override
  void didUpdateWidget(FeedShelf old) {
    super.didUpdateWidget(old);
    _bind();
  }

  void _changed() {
    if (!mounted) return;
    if (_revision != _session?.revision) {
      _revision = _session?.revision ?? -1;
      _fillRequests = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
      });
    }
    setState(() {});
    _scheduleFill();
  }

  void _filtersChanged() {
    _fillRequests = 0;
    _changed();
  }

  void _onVisible(bool visible) {
    _visible = visible;
    if (visible) _scheduleFill();
  }

  void _scheduleFill() {
    if (_scheduled || !mounted) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted || !_visible) return;
      final session = _session;
      if (session == null ||
          session.loading ||
          session.error != null ||
          !session.hasNext) {
        return;
      }
      if (!session.initialized) {
        unawaited(session.loadMore());
      } else if (widget.sessions.sources.manifest(widget.sourceKey)?.isNovel !=
              true &&
          _fillRequests < 3 &&
          (!_scroll.hasClients ||
              (_scroll.position.hasContentDimensions &&
                  _scroll.position.extentAfter <
                      _scroll.position.viewportDimension / 2))) {
        _fillRequests++;
        unawaited(session.loadMore());
      }
    });
  }

  void _loadMore() {
    _fillRequests = 0;
    final session = _session;
    if (session != null) {
      if (!session.hasNext && session.error == null) session.reset();
      unawaited(session.retry());
    }
  }

  Widget _horizontal(Widget child) =>
      NotificationListener<ScrollMetricsNotification>(
        onNotification: (_) {
          _scheduleFill();
          return false;
        },
        child: NotificationListener<UserScrollNotification>(
          onNotification: (notification) {
            if (notification.direction != ScrollDirection.idle) {
              _fillRequests = 0;
              _scheduleFill();
            }
            return false;
          },
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context)
                .copyWith(scrollbars: false),
            child: Scrollbar(
              controller: _scroll,
              thumbVisibility: true,
              child: child,
            ),
          ),
        ),
      );

  Widget _tail(SharedFeedSession session) => SizedBox(
    width: 112,
    child: Center(
      child: session.loading
          ? const CircularProgressIndicator()
          : OutlinedButton(
              onPressed: _loadMore,
              child: SelectionContainer.disabled(
                child: Text(tr(session.error == null ? '加载更多' : '重试')),
              ),
            ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (!AppSettings.instance.homeSourceVisible(widget.sourceKey)) {
      return const SizedBox.shrink();
    }
    final manifest = widget.sessions.sources.manifest(widget.sourceKey);
    final session = _session;
    final blocklist = TagBlocklist.current();
    final items =
        session?.items
            .where((item) => blocklist.matchItem(item) == null)
            .toList() ??
        <WorkItem>[];
    final ready = session?.initialized == true || items.isNotEmpty;
    final novel = manifest?.isNovel == true;
    final more = session != null && (session.hasNext || session.error != null);
    final Widget body;
    if (manifest?.can('subscription') == true &&
        (session == null ||
            (ready && items.isEmpty && session.error == null) ||
            (session.error?.asSourceError.needsLogin == true && !ready))) {
      body = Padding(
        padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.m),
        child: SubscriptionSourceEntry(
          source: widget.sourceKey,
          sourceManager: widget.sessions.sources,
          onOpened: _loadMore,
        ),
      );
    } else if (session?.error != null && !ready) {
      body = _ShelfMessage(
        error: session!.error!,
        source: widget.sourceKey,
        onRetry: _loadMore,
      );
    } else if (!ready) {
      body = TickerMode(
        enabled: session?.loading == true,
        child: _ShelfSkeleton(
          aspect: manifest?.isVideo == true ? 16 / 9 : .7,
          novel: novel,
          imageOnly: manifest?.isLive == true,
          source: widget.sourceKey,
        ),
      );
    } else if (items.isEmpty) {
      body = _ShelfMessage(message: tr('暂时没有内容'), onRetry: _loadMore);
    } else if (novel) {
      final preview = widget.onMore == null ? items : items.take(3).toList();
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < preview.length; i++) ...[
            if (i > 0) const Divider(indent: Gap.page, endIndent: Gap.page),
            WorkTextRow(item: preview[i]),
          ],
          if (more && widget.onMore == null) _tail(session),
        ],
      );
    } else {
      final aspect = gridAspectFor(items, manifest?.kind ?? MediaKind.comic);
      final imageOnly = manifest?.category == SourceCategory.live;
      final width = aspect > 1 ? 200.0 : 112.0;
      body = SizedBox(
        height:
            width / aspect + (imageOnly ? 0 : cardTextExtent(context)) + Gap.m,
        child: _horizontal(
          ListView.separated(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.m),
            itemCount: items.length + (more ? 1 : 0),
            separatorBuilder: (_, _) => const SizedBox(width: Gap.m),
            itemBuilder: (context, i) => i == items.length
                ? _tail(session!)
                : SizedBox(
                    width: width,
                    child: CoverTile(
                      item: items[i],
                      aspect: aspect,
                      imageOnly: imageOnly,
                    ),
                  ),
          ),
        ),
      );
    }
    return OnVisible(
      onVisible: _onVisible,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            widget.title,
            leading: SourceAvatar(widget.sourceKey, size: 22),
            trailing: Wrap(
              alignment: WrapAlignment.end,
              spacing: Gap.xs,
              runSpacing: Gap.xs,
              children: [
                if (widget.onToggleVisibility != null)
                  IconButton(
                    tooltip: tr('隐藏该站点的作品并停止自动加载'),
                    icon: const Icon(Icons.visibility_outlined),
                    onPressed: widget.onToggleVisibility,
                  ),
                if (widget.sessions.albumScope(widget.sourceKey)
                    case final scope?)
                  IconButton(
                    tooltip: tr('相册'),
                    icon: const Icon(Icons.photo_library_outlined),
                    onPressed: () => openMediaAlbum(
                      context,
                      source: widget.sourceKey,
                      title: widget.title,
                      scope: scope,
                      sources: widget.sessions.sources,
                    ),
                  ),
                if (widget.onMore != null)
                  OutlinedButton(
                    onPressed: widget.onMore,
                    child: SelectionContainer.disabled(
                      child: Text(widget.moreLabel ?? tr('全部')),
                    ),
                  ),
              ],
            ),
          ),
          if (session?.error != null && ready)
            _ShelfMessage(
              error: session!.error!,
              source: widget.sourceKey,
              onRetry: _loadMore,
            ),
          body,
        ],
      ),
    );
  }

  @override
  void dispose() {
    _filters.removeListener(_filtersChanged);
    _homeVisibility.removeListener(_homeVisibilityChanged);
    _session?.removeListener(_changed);
    _scroll.dispose();
    super.dispose();
  }
}

class _ShelfSkeleton extends StatelessWidget {
  const _ShelfSkeleton({
    required this.aspect,
    required this.novel,
    required this.source,
    this.imageOnly = false,
  });
  final double aspect;
  final bool novel;
  final bool imageOnly;
  final String source;

  @override
  Widget build(BuildContext context) {
    final width = aspect > 1 ? 200.0 : 112.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (novel)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: Gap.page),
            child: Column(
              children: [
                Skeleton(height: 16),
                SizedBox(height: Gap.s),
                Skeleton(height: 16),
              ],
            ),
          )
        else
          SizedBox(
            height: width / aspect + (imageOnly ? 0 : cardTextExtent(context)),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: Gap.page),
              itemCount: 6,
              separatorBuilder: (_, _) => const SizedBox(width: Gap.m),
              itemBuilder: (_, _) => SizedBox(
                width: width,
                child: CoverTileSkeleton(aspect: aspect, imageOnly: imageOnly),
              ),
            ),
          ),
        SourceNetworkHint(source: source),
      ],
    );
  }
}

class _ShelfMessage extends StatelessWidget {
  const _ShelfMessage({this.message, this.error, this.onRetry, this.source});
  final String? message;
  final Object? error;
  final VoidCallback? onRetry;
  final String? source;

  @override
  Widget build(BuildContext context) => error != null && source != null
      ? Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gap.page),
          child: SourceErrorView(
            error: error!,
            source: source!,
            onRetry: onRetry ?? () {},
            compact: true,
          ),
        )
      : Padding(
          padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.s, Gap.s),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  message ?? '',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodyMedium?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              ),
              if (onRetry != null)
                OutlinedButton(
                  onPressed: onRetry,
                  child: SelectionContainer.disabled(child: Text(tr('重试'))),
                ),
            ],
          ),
        );
}
