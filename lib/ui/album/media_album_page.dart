import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../../core/settings.dart';
import '../../core/tag_blocklist.dart';
import '../widgets/common.dart';
import '../widgets/error_view.dart';
import '../widgets/on_visible.dart';
import '../widgets/source_network_hint.dart';
import 'album_controller.dart';
import 'album_media.dart';
import 'album_preview.dart';

typedef AlbumOpener = Future<void> Function(
  BuildContext context,
  AlbumMediaEntry entry,
);

/// 页面拥有分页会话与滚动控制器，作品页出栈时原位置与筛选仍在。
class MediaAlbumPage extends StatefulWidget {
  const MediaAlbumPage({
    super.key,
    required this.source,
    required this.title,
    required this.loader,
    required this.onOpen,
  });
  final String source, title;
  final AlbumLoader loader;
  final AlbumOpener onOpen;
  @override
  State<MediaAlbumPage> createState() => _MediaAlbumPageState();
}

class _MediaAlbumPageState extends State<MediaAlbumPage> {
  late final _controller = AlbumController(
    source: widget.source,
    loader: widget.loader,
  );
  final _scroll = ScrollController();
  late final _settings = AppSettings.instance.watch({
    ...AppSettings.filterKeys,
    'blurCovers',
  });
  String _type = 'all';
  DateTimeRange? _range;
  late int _columns = AppSettings.instance.albumColumns;
  late bool _collapsed = AppSettings.instance.albumCollapsed;
  int _autoPages = 0;
  bool _opening = false;
  List<AlbumMediaEntry> _entries = [];

  @override
  void initState() {
    super.initState();
    _controller.addListener(_changed);
    _settings.addListener(_changed);
    _scroll.addListener(_nearEnd);
    unawaited(_controller.loadMore());
  }

  void _changed() {
    if (!mounted) return;
    final blocklist = TagBlocklist.current();
    final entries = albumMedia(
      _controller.items.where((item) => blocklist.matchItem(item) == null),
      type: _type,
      start: _range?.start,
      end: _range?.end,
      collapsed: _collapsed,
    );
    setState(() => _entries = entries);
  }

  void _nearEnd() {
    if (_scroll.hasClients &&
        _scroll.position.extentAfter < _scroll.position.viewportDimension) {
      _loadAutomatically();
    }
  }

  void _loadAutomatically() {
    if (!mounted ||
        _opening ||
        _controller.loading ||
        !_controller.hasNext ||
        _controller.error != null ||
        _autoPages >= 3) {
      return;
    }
    _autoPages++;
    unawaited(_controller.loadMore());
  }

  void _filter(VoidCallback update) {
    update();
    _autoPages = 0;
    _changed();
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _date() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(1970),
      lastDate: DateTime(2100),
      initialDateRange: _range,
    );
    if (!mounted || range == null) return;
    _filter(() => _range = range);
  }

  Future<void> _open(AlbumMediaEntry entry) async {
    if (_opening) return;
    _opening = true;
    try {
      await widget.onOpen(context, entry);
    } finally {
      _opening = false;
    }
  }

  Future<void> _refresh() async {
    _autoPages = 0;
    if (_scroll.hasClients) _scroll.jumpTo(0);
    await _controller.refresh();
  }

  Widget _controls(BuildContext context) {
    final dates = MaterialLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(Gap.page),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: Gap.s,
            runSpacing: Gap.s,
            children: [
              for (final type in const ['all', 'image', 'video'])
                SelectionChip(
                  label: tr(switch (type) {
                    'image' => '照片',
                    'video' => '视频',
                    _ => '全部',
                  }),
                  selected: _type == type,
                  onSelected: (_) => _filter(() => _type = type),
                ),
              OutlinedButton.icon(
                onPressed: _date,
                icon: const Icon(Icons.date_range_outlined),
                label: Text(
                  _range == null
                      ? tr('日期范围')
                      : '${dates.formatCompactDate(_range!.start)} – ${dates.formatCompactDate(_range!.end)}',
                ),
              ),
              if (_range != null)
                OutlinedButton(
                  onPressed: () => _filter(() => _range = null),
                  child: Text(tr('清除日期')),
                ),
              MenuChip<int>(
                label: tr('每行 {count} 个', {'count': _columns}),
                selected: _columns,
                options: {
                  for (var i = 1; i <= 6; i++)
                    i: tr('每行 {count} 个', {'count': i}),
                },
                onSelected: (v) {
                  setState(() => _columns = v);
                  AppSettings.instance.albumColumns = v;
                },
              ),
            ],
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('收起同一作品的媒体')),
            subtitle: Text(tr('仅显示首个匹配媒体，叠层标记表示已收起')),
            value: _collapsed,
            onChanged: (v) {
              AppSettings.instance.albumCollapsed = v;
              _filter(() => _collapsed = v);
            },
          ),
        ],
      ),
    );
  }

  Widget _footer() => Padding(
    padding: const EdgeInsets.all(Gap.page),
    child: Column(
      children: [
        if (_controller.error != null)
          SourceErrorView(
            error: _controller.error!,
            source: widget.source,
            compact: true,
            onRetry: () =>
                _controller.hasNext ? _controller.loadMore() : _refresh(),
          )
        else if (_controller.loading) ...[
          const CircularProgressIndicator(),
          SourceNetworkHint(source: widget.source),
        ] else if (_controller.hasNext)
          OnVisible(
            onVisible: (visible) {
              if (visible) _loadAutomatically();
            },
            child: OutlinedButton(
              onPressed: () {
                _autoPages = 0;
                _controller.loadMore();
              },
              child: Text(tr('加载更多')),
            ),
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('${widget.title} · ${tr('相册')}'),
      actions: [
        IconButton(
          tooltip: tr('刷新'),
          onPressed: _refresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: ParkRefresh(
      showRefreshButton: false,
      onRefresh: _refresh,
      child: NotificationListener<UserScrollNotification>(
        onNotification: (_) {
          _autoPages = 0;
          return false;
        },
        child: CustomScrollView(
          key: const ValueKey('album-scroll'),
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _controls(context)),
            if (_entries.isEmpty &&
                !_controller.loading &&
                _controller.error == null)
              SliverToBoxAdapter(
                child: EmptyState(
                  icon: Icons.photo_library_outlined,
                  title: tr('当前筛选下没有媒体'),
                  message: _controller.hasNext ? tr('本页没有匹配的内容，可继续加载') : null,
                  compact: true,
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: Gap.xs),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: _columns,
                  crossAxisSpacing: Gap.xs,
                  mainAxisSpacing: Gap.xs,
                ),
                delegate: SliverChildBuilderDelegate((context, index) {
                  final entry = _entries[index];
                  return AlbumMediaTile(
                    key: ValueKey(entry.identity),
                    entry: entry,
                    collapsed: _collapsed,
                    onTap: () => _open(entry),
                  );
                }, childCount: _entries.length),
              ),
            ),
            SliverToBoxAdapter(child: _footer()),
          ],
        ),
      ),
    ),
  );

  @override
  void dispose() {
    _settings.removeListener(_changed);
    _controller.removeListener(_changed);
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }
}

class AlbumMediaTile extends StatelessWidget {
  const AlbumMediaTile({
    super.key,
    required this.entry,
    required this.collapsed,
    required this.onTap,
  });
  final AlbumMediaEntry entry;
  final bool collapsed;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label:
        '${entry.work.title}, ${tr(entry.type == 'video' ? '视频' : '照片')}${collapsed && entry.count > 1 ? ', ${tr('已收起 {count} 项', {'count': entry.count})}' : ''}',
    child: ActionInkWell(
      key: const ValueKey('album-tile'),
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          AlbumPreview(key: ValueKey(entry.identity), entry: entry),
          if (entry.media['previewOnly'] == true ||
              entry.work.json['locked'] == true)
            PositionedDirectional(
              bottom: Gap.xs,
              start: Gap.xs,
              child: Tooltip(
                message: tr('公开预览，完整内容请到原站查看'),
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    color: Scrims.strong,
                    shape: BoxShape.circle,
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(Gap.xs),
                    child: Icon(
                      Icons.lock_outline,
                      color: Scrims.onScrim,
                      size: 16,
                    ),
                  ),
                ),
              ),
            ),
          if (entry.type == 'video')
            const Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Scrims.medium,
                  shape: BoxShape.circle,
                ),
                child: Padding(
                  padding: EdgeInsets.all(Gap.xs),
                  child: Icon(Icons.play_arrow_rounded, color: Scrims.onScrim),
                ),
              ),
            ),
          if (collapsed && entry.count > 1)
            PositionedDirectional(
              top: Gap.xs,
              start: Gap.xs,
              end: Gap.xs,
              child: Align(
                alignment: AlignmentDirectional.topEnd,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Tooltip(
                    message: tr('已收起 {count} 项', {'count': entry.count}),
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        color: Scrims.strong,
                        borderRadius: Radii.small,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(Gap.xs),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.collections_outlined,
                              color: Scrims.onScrim,
                              size: 16,
                            ),
                            const SizedBox(width: Gap.xs),
                            Text(
                              '${entry.count}',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(color: Scrims.onScrim),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
