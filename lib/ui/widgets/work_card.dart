import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../library/library.dart';
import '../library/favorite_actions.dart';
import '../nav.dart';
import '../theme.dart';
import 'common.dart';
import '../../core/localization.dart';

/// Cover-first card used in every grid and carousel.
class WorkCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
    AppLocalizations.of(context);
    final c = context.colors;
    final history = Library.instance.historyOf(item.uid);
    final badgeColor = item.badgeColor.isNotEmpty ? parseHexColor(item.badgeColor) : null;
    return Semantics(
      button: true,
      label: item.title,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap ?? () => Nav.openWork(context, item),
        onLongPress: onLongPress ?? () => showWorkActions(context, item),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: aspect ?? item.coverAspect ?? (kindOf(item.source) == MediaKind.video ? 16 / 9 : 0.7),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Hero(
                    tag: 'cover-${item.uid}',
                    child: CoverImage(source: item.source, url: item.cover),
                  ),
                  // Bottom scrim keeps overlay badges legible on bright covers.
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 36,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.55)],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 6,
                    top: 6,
                    right: 6,
                    child: Row(
                      children: [
                        if (showSource) ...[SourceAvatar(item.source, size: 20), const SizedBox(width: 4)],
                        for (final b in badges) ...[b, const SizedBox(width: 4)],
                        // The category takes whatever the badge leaves (a Spacer would cap it at half).
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: item.category.isEmpty ? const SizedBox.shrink() : Pill(item.category, color: badgeColor ?? Colors.black54, solid: true),
                          ),
                        ),
                        if (item.badge.isNotEmpty) Pill(tr(item.badge), color: c.primary, solid: true),
                      ],
                    ),
                  ),
                  Positioned(
                    left: 7,
                    right: 7,
                    bottom: 5,
                    child: DefaultTextStyle(
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600, shadows: [Shadow(blurRadius: 4)]),
                      child: Row(
                        children: [
                          if (item.pages != null && item.pages! > 0) ...[
                            const Icon(Icons.photo_library_outlined, size: 12, color: Colors.white),
                            const SizedBox(width: 2),
                            Text('${item.pages}'),
                          ],
                          if (item.duration.isNotEmpty) ...[const Icon(Icons.play_arrow_rounded, size: 14, color: Colors.white), Text(item.duration)],
                          const Spacer(),
                          if (item.rating != null) ...[
                            const Icon(Icons.star_rounded, size: 13, color: Color(0xFFFFC94D)),
                            Text(item.rating!.toStringAsFixed(1)),
                          ],
                          if (item.rating == null && item.likes != null && item.likes! > 0) ...[
                            const Icon(Icons.favorite_rounded, size: 11, color: Color(0xFFFF6B8B)),
                            const SizedBox(width: 2),
                            Text(formatCount(item.likes)),
                          ],
                          if (item.language.isNotEmpty) ...[const SizedBox(width: 4), Text(item.language)],
                        ],
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
                      child: const Center(child: Icon(Icons.check_circle_rounded, color: Colors.white, size: 36)),
                    ),
                  if (history != null && history.progress > 0)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                        child: LinearProgressIndicator(value: history.progress, minHeight: 3, backgroundColor: Colors.transparent, color: c.primary),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text(
                item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: context.text.bodySmall?.copyWith(fontWeight: FontWeight.w600, height: 1.3, color: c.onSurface),
              ),
            ),
            if (item.subtitle.isNotEmpty && item.subtitle != item.title)
              Padding(
                padding: const EdgeInsets.only(left: 2, right: 2, top: 1),
                child: Text(
                  item.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.labelSmall?.copyWith(color: c.onSurfaceVariant),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Long-press quick actions on a work.
Future<void> showWorkActions(BuildContext context, WorkItem item) async {
  final lib = Library.instance;
  await showModalBottomSheet(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: SourceAvatar(item.source, size: 32),
            title: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text(item.subtitle.isNotEmpty ? item.subtitle : item.id, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(lib.isFavorite(item.uid) ? Icons.bookmark_remove_outlined : Icons.bookmark_add_outlined),
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
              Nav.openWork(context, item);
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
double cardTextExtent(BuildContext context) => MediaQuery.textScalerOf(context).scale(56) + 6;

/// Picks a single grid aspect ratio from the items (median), so mixed covers still align.
double gridAspectFor(List<WorkItem> items, MediaKind kind) {
  final aspects = items.map((e) => e.coverAspect).whereType<double>().toList()..sort();
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
