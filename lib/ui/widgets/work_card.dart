import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../library/library.dart';
import '../library/favorite_actions.dart';
import '../nav.dart';
import '../theme.dart';
import 'common.dart';
import 'cover_hero.dart';
import 'content_translation.dart';
import '../../core/localization.dart';

/// Cover-first card used in every grid and carousel.
class WorkCard extends StatefulWidget {
  const WorkCard({
    super.key,
    required this.item,
    this.aspect,
    this.showSource = false,
    this.onTap,
    this.onLongPress,
    this.selected = false,
    this.badges = const [],
  });
  final WorkItem item;
  final double? aspect;
  final bool showSource;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool selected;

  /// Extra badges shown at the top-left of the cover (library unread / downloaded counts).
  final List<Widget> badges;

  @override
  State<WorkCard> createState() => _WorkCardState();
}

class _WorkCardState extends State<WorkCard> {
  // 动画属于列表中的这个入口，不能用可能重复或被详情规范化的作品 ID。
  final Object _coverHeroTag = Object();

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final aspect = widget.aspect;
    final showSource = widget.showSource;
    final onTap = widget.onTap;
    final onLongPress = widget.onLongPress;
    final selected = widget.selected;
    final badges = widget.badges;
    AppLocalizations.of(context);
    final c = context.colors;
    final history = Library.instance.historyOf(item.uid);
    final badgeColor = item.badgeColor.isNotEmpty
        ? parseHexColor(item.badgeColor)
        : null;
    return Semantics(
      button: true,
      label: item.title,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap:
            onTap ??
            () => Nav.openWork(context, item, coverHeroTag: _coverHeroTag),
        onLongPress:
            onLongPress ??
            () => showWorkActions(context, item, coverHeroTag: _coverHeroTag),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio:
                  aspect ??
                  item.coverAspect ??
                  (kindOf(item) == MediaKind.video ? 16 / 9 : 0.7),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CoverHero(
                    tag: _coverHeroTag,
                    child: CoverImage(
                      source: item.source,
                      url: item.cover,
                      title: item.title,
                      mediaKind: item.json['mediaKind'] == 'novel'
                          ? MediaKind.novel
                          : null,
                    ),
                  ),
                  Positioned(
                    left: 6,
                    top: 6,
                    right: 6,
                    child: Row(
                      children: [
                        if (showSource) ...[
                          SourceAvatar(item.source, size: 20),
                          const SizedBox(width: 4),
                        ],
                        for (final b in badges) ...[
                          b,
                          const SizedBox(width: 4),
                        ],
                        // The category takes whatever the badge leaves (a Spacer would cap it at half).
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: item.category.isEmpty
                                ? const SizedBox.shrink()
                                : Pill(
                                    item.category,
                                    color: badgeColor ?? Colors.black54,
                                    solid: true,
                                  ),
                          ),
                        ),
                        if (item.badge.isNotEmpty)
                          Pill(tr(item.badge), color: c.primary, solid: true),
                      ],
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    // 渐变高度跟随元数据换行，不依赖固定字号或行数。
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(12),
                        ),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.55),
                          ],
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(7, 12, 7, 5),
                        child: DefaultTextStyle(
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            shadows: [Shadow(blurRadius: 4)],
                          ),
                          child: Wrap(
                            spacing: 4,
                            runSpacing: 2,
                            children: [
                              if (item.pages != null && item.pages! > 0)
                                _CoverMetadata(
                                  text: '${item.pages}',
                                  icon: Icons.photo_library_outlined,
                                  iconSize: 12,
                                ),
                              if (item.duration.isNotEmpty)
                                _CoverMetadata(
                                  text: item.duration,
                                  icon: Icons.play_arrow_rounded,
                                  iconSize: 14,
                                ),
                              if (item.rating != null)
                                _CoverMetadata(
                                  text: item.rating!.toStringAsFixed(1),
                                  icon: Icons.star_rounded,
                                  iconSize: 13,
                                  color: const Color(0xFFFFC94D),
                                ),
                              if (item.rating == null &&
                                  item.likes != null &&
                                  item.likes! > 0)
                                _CoverMetadata(
                                  text: formatCount(item.likes),
                                  icon: Icons.favorite_rounded,
                                  iconSize: 11,
                                  color: const Color(0xFFFF6B8B),
                                ),
                              if (item.language.isNotEmpty)
                                Text(
                                  item.language,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (selected)
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: c.primary.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: c.primary, width: 3),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.check_circle_rounded,
                          color: Colors.white,
                          size: 36,
                        ),
                      ),
                    ),
                  if (history != null && history.progress > 0)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(12),
                        ),
                        child: LinearProgressIndicator(
                          value: history.progress,
                          minHeight: 3,
                          backgroundColor: Colors.transparent,
                          color: c.primary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: ContentTranslation(
                text: item.title,
                source: item.source,
                builder: (value) => Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                    color: c.onSurface,
                  ),
                ),
              ),
            ),
            if (item.subtitle.isNotEmpty && item.subtitle != item.title)
              Padding(
                padding: const EdgeInsets.only(left: 2, right: 2, top: 1),
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
        ),
      ),
    );
  }
}

/// 图标与值保持同组；组间按可用宽度换行，单个长值按约束省略。
class _CoverMetadata extends StatelessWidget {
  const _CoverMetadata({
    required this.text,
    required this.icon,
    required this.iconSize,
    this.color = Colors.white,
  });

  final String text;
  final IconData icon;
  final double iconSize;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: iconSize, color: color),
      const SizedBox(width: 2),
      Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis)),
    ],
  );
}

/// Long-press quick actions on a work.
Future<void> showWorkActions(
  BuildContext context,
  WorkItem item, {
  Object? coverHeroTag,
}) async {
  final lib = Library.instance;
  await showModalBottomSheet(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: SourceAvatar(item.source, size: 32),
            title: Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              item.subtitle.isNotEmpty ? item.subtitle : item.id,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(
              lib.isFavorite(item.uid)
                  ? Icons.bookmark_remove_outlined
                  : Icons.bookmark_add_outlined,
            ),
            title: Text(lib.isFavorite(item.uid) ? tr('取消收藏') : tr('加入收藏')),
            onTap: () {
              Navigator.pop(ctx);
              toggleFavorite(context, item);
            },
          ),
          if (lib.isFavorite(item.uid))
            ListTile(
              leading: const Icon(Icons.label_outline_rounded),
              title: Text(tr('设置分类')),
              onTap: () {
                Navigator.pop(ctx);
                editFavoriteCategories(context, item.uid);
              },
            ),
          ListTile(
            leading: const Icon(Icons.open_in_new_rounded),
            title: Text(tr('打开详情')),
            onTap: () {
              Navigator.pop(ctx);
              Nav.openWork(context, item, coverHeroTag: coverHeroTag);
            },
          ),
          if (lib.historyOf(item.uid) != null)
            ListTile(
              leading: const Icon(Icons.history_toggle_off_rounded),
              title: Text(tr('删除阅读记录')),
              onTap: () {
                lib.removeHistory(item.uid);
                Navigator.pop(ctx);
              },
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// Height reserved under a cover for two title lines and one subtitle line, honouring the
/// user's font scale so cards never overflow.
double cardTextExtent(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(56) + 6;

/// Picks a single grid aspect ratio from the items (median), so mixed covers still align.
double gridAspectFor(List<WorkItem> items, MediaKind kind) {
  final aspects = items.map((e) => e.coverAspect).whereType<double>().toList()
    ..sort();
  if (aspects.isEmpty) return kind == MediaKind.video ? 16 / 9 : 0.7;
  return aspects[aspects.length ~/ 2].clamp(0.5, 1.9);
}

class WorkCardSkeleton extends StatelessWidget {
  const WorkCardSkeleton({super.key, this.aspect = 0.7});
  final double aspect;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      AspectRatio(aspectRatio: aspect, child: const Skeleton()),
      const SizedBox(height: 8),
      const Skeleton(height: 10, radius: 4),
      const SizedBox(height: 5),
      const Skeleton(height: 10, width: 60, radius: 4),
    ],
  );
}
