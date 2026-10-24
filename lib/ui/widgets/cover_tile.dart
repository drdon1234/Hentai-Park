import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../../core/models.dart';
import '../../core/settings.dart';
import '../../core/tag_blocklist.dart';
import '../../engine/source_manager.dart';
import '../../library/library.dart';
import '../kit/adaptive_sheet.dart';
import '../library/favorite_actions.dart';
import '../nav.dart';
import '../short_video/short_video_sequence.dart';
import '../theme.dart';
import 'common.dart';
import 'content_translation.dart';
import 'cover_hero.dart';
import 'source_interaction.dart';
import 'work_editions.dart';

/// A library signal on a cover, with what a screen reader announces for it.
typedef CoverBadge = ({Widget tag, String label});

/// Cover-first tile used in every grid and shelf. At most one badge sits on the cover; the
/// title and a single metadata line live below it.
class CoverTile extends StatefulWidget {
  const CoverTile({
    super.key,
    required this.item,
    this.aspect,
    this.showSource = false,
    this.onTap,
    this.onLongPress,
    this.selected = false,
    this.badges = const [],
    this.imageOnly = false,
    this.sequence,
  });
  final WorkItem item;
  final double? aspect;
  final bool showSource;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool selected;

  /// Library signals (unread count, downloaded) that replace the site's own badge.
  final List<CoverBadge> badges;
  final bool imageOnly;

  /// 所在列表的播放顺序；短视频从这里按列表连续播放。
  final ShortVideoSequence Function()? sequence;

  @override
  State<CoverTile> createState() => _CoverTileState();
}

class _CoverTileState extends State<CoverTile> {
  // 动画属于列表中的这个入口，不能用可能重复或被详情规范化的作品 ID。
  final Object _coverHeroTag = Object();
  bool _hovered = false;

  /// One muted line: text values, with small glyphs for rating and likes.
  List<(IconData?, String)> _metadata(WorkItem item) => [
    if (item.editions.isNotEmpty) (null, workEditionLabel(item)),
    if (widget.showSource)
      (null, SourceManager.instance.manifest(item.source)?.name ?? item.source),
    if (item.category.isNotEmpty) (null, item.category),
    if (item.pages != null && item.pages! > 0)
      (null, tr('{value0} 页', {'value0': item.pages})),
    if (item.rating != null)
      (Icons.star_rounded, item.rating!.toStringAsFixed(1)),
    if (item.rating == null && item.likes != null && item.likes! > 0)
      (Icons.favorite_rounded, formatCount(item.likes)),
    if (item.language.isNotEmpty) (null, item.language),
  ];

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final c = context.colors;
    final history = Library.instance.historyOf(item.uid);
    final video = kindOf(item) == MediaKind.video;
    final Widget? badge = widget.badges.isNotEmpty
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final b in widget.badges) ...[
                b.tag,
                const SizedBox(width: Gap.xs),
              ],
            ],
          )
        : item.badge.isNotEmpty
        ? Tag(item.badge, onImage: true)
        : null;
    final metadata = _metadata(item);
    final onTap =
        widget.onTap ??
        () => Nav.openWork(
          context,
          item,
          coverHeroTag: _coverHeroTag,
          sequence: widget.sequence?.call(),
        );
    final onLongPress =
        widget.onLongPress ??
        () => showWorkActions(context, item, coverHeroTag: _coverHeroTag);
    return Semantics(
      button: true,
      selected: widget.selected,
      label: [
        item.title,
        if (widget.badges.isNotEmpty)
          ...widget.badges.map((b) => b.label)
        else if (item.badge.isNotEmpty)
          item.badge,
        ...metadata.map((m) => m.$2),
        if (item.duration.isNotEmpty) item.duration,
        if (history != null && history.progress > 0)
          tr('已读 {value0}%', {'value0': (history.progress * 100).round()}),
      ].join('，'),
      // The merged label replaces the child's semantics, so the actions are restated.
      onTap: onTap,
      onLongPress: onLongPress,
      excludeSemantics: true,
      child: ActionInkWell(
        borderRadius: Radii.small,
        onTap: onTap,
        onLongPress: onLongPress,
        onHover: (hovered) => setState(() => _hovered = hovered),
        child: SelectionContainer.disabled(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedScale(
                // 指针悬停时封面轻微浮起，提示可以打开。
                scale: _hovered ? 1.025 : 1,
                duration: Motion.of(context, Motion.medium),
                curve: Motion.emphasized,
                child: AspectRatio(
                  aspectRatio:
                      widget.aspect ??
                      item.coverAspect ??
                      (video ? 16 / 9 : 0.7),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CoverHero(
                        tag: _coverHeroTag,
                        child: CoverImage(
                          source: item.source,
                          url: item.cover,
                          sourceBlurred: item.json['coverBlurred'] == true,
                          title: item.title,
                          mediaKind: item.isNovel ? MediaKind.novel : null,
                        ),
                      ),
                      if (!widget.imageOnly && badge != null)
                        PositionedDirectional(
                          start: Gap.xs + 2,
                          top: Gap.xs + 2,
                          end: Gap.xs + 2,
                          child: Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: badge,
                          ),
                        ),
                      if (!widget.imageOnly && item.duration.isNotEmpty)
                        PositionedDirectional(
                          end: Gap.xs + 2,
                          bottom: Gap.xs + 2,
                          child: Tag(item.duration, onImage: true),
                        ),
                      if (!widget.imageOnly &&
                          history != null &&
                          history.progress > 0)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: ClipRRect(
                            borderRadius: const BorderRadius.vertical(
                              bottom: Radius.circular(Radii.sm),
                            ),
                            child: LinearProgressIndicator(
                              value: history.progress,
                              minHeight: 3,
                              backgroundColor: Scrims.soft,
                            ),
                          ),
                        ),
                      if (widget.selected)
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: Scrims.soft,
                            borderRadius: Radii.small,
                            border: Border.all(color: c.primary, width: 2),
                          ),
                          child: Align(
                            alignment: AlignmentDirectional.topEnd,
                            child: Padding(
                              padding: const EdgeInsets.all(Gap.xs + 2),
                              child: Icon(
                                Icons.check_circle_rounded,
                                color: c.primary,
                                size: 24,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (!widget.imageOnly) ...[
                const SizedBox(height: Gap.xs + 2),
                ContentTranslation(
                  text: item.title,
                  source: item.source,
                  builder: (value) => Text(
                    value,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodySmall?.copyWith(
                      fontWeight: FontWeight.w500,
                      height: 1.3,
                      color: c.onSurface,
                    ),
                  ),
                ),
                if (metadata.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text.rich(
                      TextSpan(
                        children: [
                          for (var i = 0; i < metadata.length; i++) ...[
                            if (i > 0) const TextSpan(text: ' · '),
                            if (metadata[i].$1 case final icon?)
                              WidgetSpan(
                                alignment: PlaceholderAlignment.middle,
                                child: Padding(
                                  padding: const EdgeInsetsDirectional.only(
                                    end: 1,
                                  ),
                                  child: Icon(
                                    icon,
                                    size: 11,
                                    color: c.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            TextSpan(text: metadata[i].$2),
                          ],
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.labelSmall?.copyWith(
                        color: c.onSurfaceVariant,
                      ),
                    ),
                  )
                else if (item.subtitle.isNotEmpty &&
                    item.subtitle != item.title)
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: ContentTranslation(
                      text: item.subtitle,
                      source: item.source,
                      builder: (value) => Text(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.labelSmall?.copyWith(
                          color: c.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Long-press quick actions on a work.
Future<void> showWorkActions(
  BuildContext context,
  WorkItem item, {
  Object? coverHeroTag,
}) async {
  final lib = Library.instance;
  await showAdaptiveSheet(
    context: context,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: SourceAvatar(item.source, size: 32),
              title: SelectionContainer.disabled(
                child: Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              subtitle: SelectionContainer.disabled(
                child: Text(
                  item.subtitle.isNotEmpty ? item.subtitle : item.id,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const Divider(height: 1),
            if (SourceManager.instance
                    .manifest(item.source)
                    ?.can('interaction') ==
                true)
              ListTile(
                leading: const Icon(Icons.thumb_up_outlined),
                title: Text(tr('原站互动')),
                onTap: () {
                  Navigator.pop(ctx);
                  showSourceInteraction(context, item);
                },
              ),
            ListTile(
              leading: const Icon(Icons.block_rounded),
              title: Text(tr('屏蔽作品')),
              onTap: () {
                AppSettings.instance.blockWork(item);
                Navigator.pop(ctx);
                context.toast(tr('已屏蔽作品'));
              },
            ),
            ListTile(
              leading: const Icon(Icons.person_off_outlined),
              title: Text(tr('屏蔽作者')),
              onTap: () async {
                Navigator.pop(ctx);
                try {
                  var authors = TagBlocklist.authorsOf(item);
                  if (authors.isEmpty) {
                    if (item.isSubscriptionPost) {
                      if (context.mounted) context.toast(tr('本站未提供作者信息'));
                      return;
                    }
                    authors = TagBlocklist.authorsOf(
                      await SourceManager.instance.detail(
                        item.source,
                        item.id,
                        preview: item,
                      ),
                    );
                    // 列表也使用已取得的真实作者，设置变更后立即重新过滤当前卡片。
                    item.authors.addAll(authors);
                  }
                  if (!context.mounted) return;
                  if (authors.isEmpty) {
                    context.toast(tr('本站未提供作者信息'));
                    return;
                  }
                  final author = await showChoiceSheet<String>(
                    context,
                    title: tr('屏蔽作者'),
                    selected: '',
                    options: authors,
                    label: (a) => a,
                  );
                  if (author != null) {
                    AppSettings.instance.blockAuthor(
                      item.source,
                      author,
                      work: item,
                    );
                    if (context.mounted) context.toast(tr('已屏蔽作者'));
                  }
                } catch (_) {
                  if (context.mounted) context.toast(tr('作者信息获取失败，请重试'));
                }
              },
            ),
            ListTile(
              leading: Icon(
                lib.isFavorite(item.uid)
                    ? Icons.bookmark_remove_outlined
                    : Icons.bookmark_add_outlined,
              ),
              title: SelectionContainer.disabled(
                child: Text(
                  lib.isFavorite(item.uid) ? tr('取消应用内收藏') : tr('应用内收藏'),
                ),
              ),
              onTap: () {
                Navigator.pop(ctx);
                toggleFavorite(context, item);
              },
            ),
            if (lib.isFavorite(item.uid))
              ListTile(
                leading: const Icon(Icons.label_outline_rounded),
                title: SelectionContainer.disabled(child: Text(tr('设置分类'))),
                onTap: () {
                  Navigator.pop(ctx);
                  editFavoriteCategories(context, item.uid);
                },
              ),
            ListTile(
              leading: const Icon(Icons.open_in_new_rounded),
              title: SelectionContainer.disabled(child: Text(tr('打开详情'))),
              onTap: () {
                Navigator.pop(ctx);
                Nav.openWork(context, item, coverHeroTag: coverHeroTag);
              },
            ),
            if (lib.historyOf(item.uid) != null)
              ListTile(
                leading: const Icon(Icons.history_toggle_off_rounded),
                title: SelectionContainer.disabled(child: Text(tr('删除阅读记录'))),
                onTap: () {
                  lib.removeHistory(item.uid);
                  Navigator.pop(ctx);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ),
  );
}

/// Height reserved under a cover for two title lines and one subtitle line. The lines are
/// measured with the user's text scaler: Android scales large fonts non-linearly, so scaling
/// one total height would under-reserve at large font sizes and clip the text.
double cardTextExtent(BuildContext context) {
  final scaler = MediaQuery.textScalerOf(context);
  double lineHeight(TextStyle? style) {
    final painter = TextPainter(
      text: TextSpan(text: 'Hg国', style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
    )..layout();
    final height = painter.height;
    painter.dispose();
    return height;
  }

  final title = context.text.bodySmall?.copyWith(
    fontWeight: FontWeight.w500,
    height: 1.3,
  );
  // Matches the spacing in CoverTile: gap, two title lines, 1 px, one metadata line.
  return Gap.xs +
      2 +
      2 * lineHeight(title) +
      1 +
      lineHeight(context.text.labelSmall) +
      2;
}

/// Picks a single grid aspect ratio from the items (median), so mixed covers still align.
double gridAspectFor(List<WorkItem> items, MediaKind kind) {
  final aspects = items.map((e) => e.coverAspect).whereType<double>().toList()
    ..sort();
  if (aspects.isEmpty) return kind == MediaKind.video ? 16 / 9 : 0.7;
  return aspects[aspects.length ~/ 2].clamp(0.5, 1.9);
}

class CoverTileSkeleton extends StatelessWidget {
  const CoverTileSkeleton({
    super.key,
    this.aspect = 0.7,
    this.imageOnly = false,
  });
  final double aspect;
  final bool imageOnly;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      AspectRatio(aspectRatio: aspect, child: const Skeleton()),
      if (!imageOnly) ...[
        const SizedBox(height: Gap.s),
        const Skeleton(height: 10, radius: 4),
        const SizedBox(height: Gap.xs + 1),
        const Skeleton(height: 10, width: 60, radius: 4),
      ],
    ],
  );
}
