import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../../core/models.dart';
import '../../core/settings.dart';
import '../../core/tag_blocklist.dart';
import '../../engine/source_manager.dart';
import '../../images/park_image.dart';
import '../../library/library.dart';
import '../kit/adaptive_sheet.dart';
import '../library/favorite_actions.dart';
import '../nav.dart';
import '../short_video/short_video_sequence.dart';
import '../theme.dart';
import '../voice/voice_labels.dart';
import 'common.dart';
import 'content_translation.dart';
import 'cover_hero.dart';
import 'source_interaction.dart';
import 'work_editions.dart';

/// 列表摘要只展示结构化元信息；标签留在详情页。
List<String> workMetadata(WorkItem item, {bool showSource = false}) => [
  ?voiceFormLabel(item.voiceMediaForm),
  ?voiceLanguageLabel(item.voiceLanguageStatus),
  if (item.language.isNotEmpty) item.language,
  if (showSource)
    SourceManager.instance.manifest(item.source)?.name ?? item.source,
  if (item.category.isNotEmpty) item.category,
  if (item.editions.isNotEmpty) workEditionLabel(item),
  if (item.pages != null && item.pages! > 0)
    tr('{value0} 页', {'value0': item.pages}),
  if (item.rating != null)
    tr('评分 {rating}', {'rating': item.rating!.toStringAsFixed(1)}),
  if (item.rating == null && item.likes != null && item.likes! > 0)
    '${tr('点赞数')} ${formatCount(item.likes)}',
  if (item.views != null) tr('{count} 次观看', {'count': formatCount(item.views)}),
];

/// 收藏、历史与下载列表共用的完整结构化摘要。
class WorkMetadataSummary extends StatelessWidget {
  const WorkMetadataSummary({super.key, required this.item});

  final WorkItem item;

  @override
  Widget build(BuildContext context) {
    final metadata = workMetadata(item);
    if (metadata.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: Gap.xs),
      child: Text(
        metadata.join(' · '),
        style: context.text.labelSmall?.copyWith(
          color: context.colors.onSurfaceVariant,
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }
}

/// A library signal on a cover, with what a screen reader announces for it.
typedef CoverBadge = ({Widget tag, String label});

/// Cover-first tile used in every grid and shelf. At most one badge sits on the cover; the
/// title and complete metadata live below it.
class CoverTile extends StatefulWidget {
  const CoverTile({
    super.key,
    required this.item,
    this.aspect,
    this.showSource = false,
    this.onTap,
    this.onLongPress,
    this.onTextTap,
    this.selected = false,
    this.badges = const [],
    this.imageOnly = false,
    this.sequence,
    this.coverFrame,
  });
  final WorkItem item;
  final double? aspect;
  final bool showSource;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// 下载网格等场景中，文字区拥有独立于封面的入口。
  final VoidCallback? onTextTap;
  final bool selected;

  /// Library signals (unread count, downloaded) that replace the site's own badge.
  final List<CoverBadge> badges;

  /// 沿封面边缘显示下载等状态，避免覆盖图片内容。
  final Widget Function(Widget child)? coverFrame;
  final bool imageOnly;

  /// 所在列表的播放顺序；短视频从这里按列表连续播放。
  final ShortVideoSequence Function()? sequence;

  @override
  State<CoverTile> createState() => _CoverTileState();
}

class _CoverTileState extends State<CoverTile> {
  Widget _frame(Widget child) => widget.coverFrame?.call(child) ?? child;
  // 动画属于列表中的这个入口，不能用可能重复或被详情规范化的作品 ID。
  final Object _coverHeroTag = Object();
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final c = context.colors;
    final history = Library.instance.historyOf(item.uid);
    final video = kindOf(item).isPlayable;
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
    final metadata = workMetadata(item, showSource: widget.showSource);
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
      button: widget.onTextTap == null,
      selected: widget.selected,
      label: widget.onTextTap != null
          ? null
          : [
              item.title,
              if (widget.badges.isNotEmpty)
                ...widget.badges.map((b) => b.label)
              else if (item.badge.isNotEmpty)
                item.badge,
              ...metadata,
              if (item.duration.isNotEmpty) item.duration,
              if (history != null && history.progress > 0)
                tr('已读 {value0}%', {
                  'value0': (history.progress * 100).round(),
                }),
            ].join('，'),
      // The merged label replaces the child's semantics, so the actions are restated.
      onTap: widget.onTextTap == null ? onTap : null,
      onLongPress: widget.onTextTap == null ? onLongPress : null,
      excludeSemantics: widget.onTextTap == null,
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
                      _frame(
                        CoverHero(
                          tag: _coverHeroTag,
                          child:
                              (item.json['cover'] ?? '').toString().isEmpty &&
                                  item.coverImages.isNotEmpty
                              ? AdaptivePostCover(
                                  source: item.source,
                                  urls: item.coverImages,
                                  fallback: item.cover,
                                  sourceBlurred:
                                      item.json['coverBlurred'] == true,
                                  title: item.title,
                                )
                              : CoverImage(
                                  source: item.source,
                                  url: item.cover,
                                  sourceBlurred:
                                      item.json['coverBlurred'] == true,
                                  title: item.title,
                                  mediaKind: item.mediaKind,
                                ),
                        ),
                      ),
                      if (!widget.imageOnly &&
                          badge != null &&
                          widget.coverFrame == null)
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
                          widget.coverFrame == null &&
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
              if (!widget.imageOnly)
                ActionInkWell(
                  onTap: widget.onTextTap ?? onTap,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: Gap.xs + 2),
                      ContentTranslation(
                        text: item.title,
                        source: item.source,
                        builder: (value) => Text(
                          workDisplayTitle(item, value),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: ParkText.serif(
                            context.text.bodySmall?.copyWith(
                              fontWeight: FontWeight.w500,
                              height: 1.3,
                              color: c.onSurface,
                            ),
                          ),
                        ),
                      ),
                      if (metadata.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Text(
                            metadata.join(' · '),
                            style: context.text.labelSmall?.copyWith(
                              color: c.onSurfaceVariant,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        )
                      else if (SourceManager.instance
                                  .manifest(item.source)
                                  ?.category !=
                              SourceCategory.doujin &&
                          item.subtitle.isNotEmpty &&
                          item.subtitle != item.title)
                        ContentTranslation(
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
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class AdaptivePostCover extends StatefulWidget {
  const AdaptivePostCover({
    super.key,
    required this.source,
    required this.urls,
    required this.fallback,
    required this.title,
    this.sourceBlurred = false,
  });

  final String source;
  final List<String> urls;
  final String fallback;
  final String title;
  final bool sourceBlurred;

  @override
  State<AdaptivePostCover> createState() => _AdaptivePostCoverState();
}

class _AdaptivePostCoverState extends State<AdaptivePostCover> {
  ImageStream? _stream;
  ImageStreamListener? _listener;
  double? _aspect;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(AdaptivePostCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source ||
        oldWidget.urls.firstOrNull != widget.urls.firstOrNull) {
      _aspect = null;
      _resolve();
    }
  }

  void _resolve() {
    _detach();
    if (widget.urls.isEmpty) return;
    final stream = ParkImage.url(
      widget.source,
      widget.urls.first,
    ).resolve(createLocalImageConfiguration(context));
    _stream = stream;
    _listener = ImageStreamListener((info, _) {
      final aspect = info.image.width / info.image.height;
      info.dispose();
      if (!mounted || _aspect == aspect) return;
      setState(() => _aspect = aspect);
    }, onError: (Object _, StackTrace? _) {});
    stream.addListener(_listener!);
  }

  void _detach() {
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final aspect = _aspect;
    final urls = widget.urls;
    if (aspect == null || aspect > 1.12 || urls.length < 2) {
      return CoverImage(
        source: widget.source,
        url: widget.fallback.isNotEmpty
            ? widget.fallback
            : urls.firstOrNull ?? '',
        sourceBlurred: widget.sourceBlurred,
        title: widget.title,
      );
    }
    final count = aspect >= 0.82 ? 2 : 3;
    final selected = urls.take(count).toList();
    if (selected.length < 2) {
      return CoverImage(
        source: widget.source,
        url: widget.fallback,
        sourceBlurred: widget.sourceBlurred,
        title: widget.title,
      );
    }
    return ClipRRect(
      borderRadius: const BorderRadius.all(Radius.circular(Radii.sm)),
      child: Row(
        children: [
          for (final url in selected)
            Expanded(
              child: Padding(
                padding: const EdgeInsetsDirectional.only(end: 1),
                child: CoverImage(
                  source: widget.source,
                  url: url,
                  fit: BoxFit.cover,
                  sourceBlurred: widget.sourceBlurred,
                  title: widget.title,
                ),
              ),
            ),
        ],
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
                child: ContentTranslation(
                  text: item.title,
                  source: item.source,
                  builder: (value) =>
                      Text(value, maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
              ),
              subtitle: SelectionContainer.disabled(
                child: item.subtitle.isNotEmpty
                    ? TranslatedText(
                        item.subtitle,
                        source: item.source,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )
                    : Text(
                        item.id,
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

/// Height reserved under a cover for two title lines and the complete metadata. The lines are
/// measured with the user's text scaler: Android scales large fonts non-linearly, so scaling
/// one total height would under-reserve at large font sizes and clip the text.
final _metadataHeights = <Object, double>{};

double cardTextExtent(
  BuildContext context, {
  Iterable<WorkItem> items = const [],
  double? width,
  bool showSource = false,
}) {
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

  final title = ParkText.serif(
    context.text.bodySmall?.copyWith(fontWeight: FontWeight.w500, height: 1.3),
  );
  final metadataStyle = context.text.labelSmall?.copyWith(
    fontWeight: FontWeight.w400,
  );
  var metadataHeight = lineHeight(metadataStyle);
  if (width != null) {
    for (final item in items) {
      final text = workMetadata(item, showSource: showSource).join(' · ');
      final key = (
        text,
        metadataStyle,
        width,
        scaler,
        Directionality.of(context),
      );
      final cached = _metadataHeights[key];
      if (cached != null) {
        if (cached > metadataHeight) metadataHeight = cached;
        continue;
      }
      final painter = TextPainter(
        text: TextSpan(text: text, style: metadataStyle),
        textDirection: Directionality.of(context),
        textScaler: scaler,
      )..layout(maxWidth: width);
      // 使用与实际摘要相同的字体、宽度和缩放计算完整高度。
      if (painter.height > metadataHeight) metadataHeight = painter.height;
      if (_metadataHeights.length >= 2048) _metadataHeights.clear();
      _metadataHeights[key] = painter.height;
      painter.dispose();
    }
  }
  // 与 CoverTile 的间距、两行标题和完整摘要保持一致。
  return Gap.xs + 2 + 2 * lineHeight(title) + 1 + metadataHeight + 2;
}

/// Picks a single grid aspect ratio from the items (median), so mixed covers still align.
double gridAspectFor(List<WorkItem> items, MediaKind kind) {
  if (kind == MediaKind.novel || (items.isNotEmpty && items.first.isNovel)) {
    return .7;
  }
  final aspects = items.map((e) => e.coverAspect).whereType<double>().toList()
    ..sort();
  if (aspects.isEmpty) {
    return kind.isPlayable || kind == MediaKind.article ? 16 / 9 : 0.7;
  }
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
