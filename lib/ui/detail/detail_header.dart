import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../../core/models.dart';
import '../../library/downloads.dart';
import '../../subscriptions/subscription_store.dart';
import '../../subscriptions/updater.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/content_translation.dart';
import '../widgets/cover_hero.dart';
import '../widgets/work_editions.dart';

/// Detail page header: a pinned bar whose title appears once the cover scrolls away, then the
/// cover beside a serif title, the site and a single line of quiet metadata.
class DetailHeader extends StatefulWidget {
  const DetailHeader({
    super.key,
    required this.item,
    required this.detail,
    required this.manifest,
    required this.coverHeroTag,
    this.body = const [],
  });
  final WorkItem item;
  final WorkDetail? detail;
  final SourceManifest? manifest;
  final Object? coverHeroTag;

  /// The rest of the page. It lives in the same group as the app bar, because a pinned
  /// header only stays pinned while its group is on screen.
  final List<Widget> body;

  @override
  State<DetailHeader> createState() => _DetailHeaderState();
}

class _DetailHeaderState extends State<DetailHeader> {
  late WorkItem _coverItem = widget.item;
  late WorkItem _readyItem = widget.item;
  Animation<double>? _routeAnimation;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animation = ModalRoute.of(context)?.animation;
    if (animation == _routeAnimation) return;
    _routeAnimation?.removeStatusListener(_routeChanged);
    _routeAnimation = animation;
    animation?.addStatusListener(_routeChanged);
  }

  @override
  void didUpdateWidget(DetailHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.item.cover == _readyItem.cover &&
        widget.item.source == _readyItem.source) {
      _readyItem = widget.item;
      _applyCover();
    }
  }

  void _routeChanged(AnimationStatus status) {
    if (status == AnimationStatus.completed) _applyCover();
  }

  void _coverReady(WorkItem item) {
    if (!mounted || item != widget.item || item == _readyItem) return;
    _readyItem = item;
    _applyCover();
  }

  void _applyCover() {
    // 进出场期间冻结落点，防止飞行目标在详情响应到达时移动。
    if (_routeAnimation?.isAnimating == true || _coverItem == _readyItem) {
      return;
    }
    setState(() => _coverItem = _readyItem);
  }

  @override
  void dispose() {
    _routeAnimation?.removeStatusListener(_routeChanged);
    super.dispose();
  }

  bool get _isVideo =>
      widget.manifest?.isVideo ??
      DownloadManager.instance.task(widget.item.uid)?.isVideo ??
      false;

  bool get _isNovel => widget.manifest?.isNovel == true || widget.item.isNovel;

  /// Metadata as (icon, text) pairs; rendered in one muted color.
  List<(IconData, String)> _metadata() {
    final item = widget.item;
    final d = widget.detail;
    return [
      if (item.editions.isNotEmpty)
        (Icons.video_label_outlined, workEditionLabel(item)),
      if ((d?.pages ?? item.pages ?? 0) > 0)
        (
          Icons.photo_library_outlined,
          tr('{count} 页', {'count': d?.pages ?? item.pages}),
        ),
      if ((d?.rating ?? item.rating) != null)
        (Icons.star_rounded, (d?.rating ?? item.rating)!.toStringAsFixed(2)),
      if ((d?.likes ?? item.likes ?? 0) > 0)
        (Icons.favorite_border_rounded, formatCount(d?.likes ?? item.likes)),
      if ((d?.views ?? item.views ?? 0) > 0)
        (Icons.visibility_outlined, formatCount(d?.views ?? item.views)),
      if ((d?.language ?? item.language).isNotEmpty)
        (Icons.translate_rounded, d?.language ?? item.language),
      if ((d?.uploaded ?? item.uploaded).isNotEmpty)
        (Icons.schedule_rounded, d?.uploaded ?? item.uploaded),
      if (d != null && d.size.isNotEmpty) (Icons.sd_storage_outlined, d.size),
      if (d?.comments != null && d!.comments! > 0)
        (Icons.forum_outlined, '${d.comments}'),
    ];
  }

  bool get _canSubscribe {
    final d = widget.detail;
    return d != null &&
        d.chapters?.isNotEmpty == true &&
        ((widget.manifest?.json['updateSubscriptions'] as Map?)?['dimensions']
                    as List? ??
                [])
            .whereType<Map>()
            .any((v) => v['key'] == 'work');
  }

  Future<void> _subscribe() async {
    final item = widget.item;
    await SubscriptionStore.instance.load();
    await SubscriptionStore.instance.add(
      source: item.source,
      target: item.id,
      label: item.title,
      dimension: 'work',
    );
    unawaited(SubscriptionUpdater.instance.run(force: true));
    if (mounted) context.toast(tr('已添加更新订阅'));
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final inset = ((constraints.crossAxisExtent - 1120) / 2).clamp(
          0.0,
          double.infinity,
        );
        return SliverMainAxisGroup(
          slivers: [
            SliverAppBar(
              pinned: true,
              title: _CollapsingTitle(item: item),
              actions: [
                if (_canSubscribe)
                  IconButton(
                    tooltip: tr('订阅作品更新'),
                    icon: const Icon(Icons.notifications_none_rounded),
                    onPressed: _subscribe,
                  ),
                TranslationControls(source: item.source),
                const SizedBox(width: Gap.xs),
              ],
            ),
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: inset),
              sliver: SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Gap.page,
                    Gap.xs,
                    Gap.page,
                    0,
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      if (_isNovel) return _info(context);
                      final wide = constraints.maxWidth >= 700;
                      final stacked =
                          constraints.maxWidth < 440 ||
                          constraints.maxWidth /
                                  MediaQuery.textScalerOf(context).scale(1) <
                              320;
                      final aspect =
                          _coverItem.coverAspect ?? (_isVideo ? 16 / 9 : 0.7);
                      final width = wide
                          ? (constraints.maxWidth * (aspect > 1 ? .42 : .28))
                                .clamp(240.0, aspect > 1 ? 440.0 : 320.0)
                          : constraints.maxWidth * (stacked ? .65 : .32);
                      final cover = _coverBox(context, width);
                      if (stacked) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Center(child: cover),
                            const SizedBox(height: Gap.l),
                            _info(context),
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          cover,
                          SizedBox(width: wide ? Gap.xxl : Gap.l),
                          Expanded(child: _info(context)),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: inset),
              sliver: SliverMainAxisGroup(
                slivers: [
                  const SliverToBoxAdapter(child: SizedBox(height: Gap.l)),
                  ...widget.body,
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _coverBox(BuildContext context, double width) {
    final aspect = _coverItem.coverAspect ?? (_isVideo ? 16 / 9 : 0.7);
    return SizedBox(
      width: width,
      height: width / aspect,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CoverHero(
            tag: widget.coverHeroTag,
            child: ClipRRect(
              borderRadius: Radii.small,
              child: AnimatedSwitcher(
                duration: Motion.of(context, Motion.medium),
                layoutBuilder: (current, previous) => Stack(
                  fit: StackFit.expand,
                  children: [...previous, ?current],
                ),
                child: _cover(_coverItem),
              ),
            ),
          ),
          if (_readyItem != widget.item)
            IgnorePointer(
              child: Opacity(
                opacity: 0,
                child: _cover(
                  widget.item,
                  onReady: () => _coverReady(widget.item),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _info(BuildContext context) {
    final item = widget.item;
    final d = widget.detail;
    final c = context.colors;
    final metadata = _metadata();
    final category = d?.category ?? item.category;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ContentTranslation(
          text: item.title,
          source: item.source,
          builder: (value) => SelectableText(
            value,
            minLines: 1,
            style: ParkText.serif(context.text.titleLarge)
                ?.copyWith(fontWeight: FontWeight.w600, height: 1.3),
          ),
        ),
        if (item.subtitle.isNotEmpty && item.subtitle != item.title) ...[
          const SizedBox(height: Gap.xs),
          ContentTranslation(
            text: item.subtitle,
            source: item.source,
            builder: (value) => Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.text.bodyMedium?.copyWith(
                color: c.onSurfaceVariant,
              ),
            ),
          ),
        ],
        const SizedBox(height: Gap.s),
        InkWell(
          borderRadius: Radii.small,
          onTap: () => Nav.openSource(context, item.source),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SourceAvatar(item.source, size: 18),
                const SizedBox(width: Gap.s - 2),
                Flexible(
                  child: Text(
                    widget.manifest?.name ?? item.source,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.labelLarge?.copyWith(
                      color: c.onSurfaceVariant,
                    ),
                  ),
                ),
                if (category.isNotEmpty) ...[
                  const SizedBox(width: Gap.s - 2),
                  Flexible(child: Tag(category)),
                ],
              ],
            ),
          ),
        ),
        if (metadata.isNotEmpty) ...[
          const SizedBox(height: Gap.s),
          Wrap(
            spacing: Gap.m,
            runSpacing: Gap.xs,
            children: [
              for (final (icon, text) in metadata)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 14, color: c.onSurfaceVariant),
                    const SizedBox(width: 3),
                    Flexible(
                      child: Text(
                        text,
                        style: context.text.labelMedium?.copyWith(
                          color: c.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _cover(WorkItem item, {VoidCallback? onReady}) {
    final aspect = item.coverAspect ?? (_isVideo ? 16 / 9 : 0.7);
    return AspectRatio(
      key: ValueKey((item.source, item.cover, aspect)),
      aspectRatio: aspect,
      child: SizedBox.expand(
        child: CoverImage(
          source: item.source,
          url: item.cover,
          title: item.title,
          mediaKind: item.isNovel ? MediaKind.novel : null,
          onReady: onReady,
        ),
      ),
    );
  }
}

/// The bar title fades in after the large title has scrolled under the bar.
class _CollapsingTitle extends StatefulWidget {
  const _CollapsingTitle({required this.item});
  final WorkItem item;

  @override
  State<_CollapsingTitle> createState() => _CollapsingTitleState();
}

class _CollapsingTitleState extends State<_CollapsingTitle> {
  ScrollPosition? _position;
  bool _visible = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _position?.removeListener(_update);
    _position = Scrollable.maybeOf(context)?.position;
    _position?.addListener(_update);
    _update();
  }

  void _update() {
    final visible = (_position?.pixels ?? 0) > 120;
    if (visible != _visible && mounted) setState(() => _visible = visible);
  }

  @override
  void dispose() {
    _position?.removeListener(_update);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
    opacity: _visible ? 1 : 0,
    duration: Motion.of(context, Motion.short),
    child: ContentTranslation(
      text: widget.item.title,
      source: widget.item.source,
      builder: (value) =>
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis),
    ),
  );
}
