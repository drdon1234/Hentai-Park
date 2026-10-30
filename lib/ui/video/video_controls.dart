import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../core/localization.dart';
import '../../core/models.dart';
import '../../engine/source_manager.dart';
import '../comments/comments_page.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/content_translation.dart';
import '../widgets/expandable_description.dart';
import '../widgets/paged_grid.dart';
import '../widgets/related_works.dart';
import 'video_gestures.dart';

String formatPlaybackTime(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  final mm = m.toString().padLeft(2, '0'), ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
}

/// 标题、中央播放键与底部时间轴各司其职，窄屏将次要操作收进菜单。
class VideoControls extends StatelessWidget {
  const VideoControls({
    super.key,
    required this.value,
    required this.position,
    required this.title,
    required this.fullscreen,
    required this.displayMode,
    required this.speed,
    required this.onBack,
    required this.onPlayPause,
    required this.onSpeed,
    required this.onDisplayMode,
    required this.onFullscreen,
    this.quality,
    this.onQuality,
    this.onEpisodes,
    this.onSeries,
    this.onPrevious,
    this.onNext,
    this.onInteractionChanged,
    this.progress,
    this.live = false,
    this.recordingAction,
    this.chatEnabled = false,
    this.onToggleChat,
    this.chatAreaLabel,
    this.onChatArea,
  });
  final VideoPlayerValue value;

  /// The position to show: the live one, or the preview while seeking with a gesture.
  final Duration position;
  final String title;
  final bool fullscreen;
  final VideoDisplayMode displayMode;
  final double speed;
  final VoidCallback onBack;
  final VoidCallback onPlayPause;
  final VoidCallback onSpeed;
  final ValueChanged<VideoDisplayMode> onDisplayMode;
  final VoidCallback onFullscreen;

  /// Current quality, shown only when there is more than one to pick from.
  final String? quality;
  final VoidCallback? onQuality;
  final VoidCallback? onEpisodes;
  final VoidCallback? onSeries;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final ValueChanged<bool>? onInteractionChanged;
  final Widget? progress;
  final bool live;
  final Widget? recordingAction;
  final bool chatEnabled;
  final VoidCallback? onToggleChat;
  final String? chatAreaLabel;
  final VoidCallback? onChatArea;

  @override
  Widget build(BuildContext context) {
    const fg = Scrims.onScrim;
    final landscape = displayMode == VideoDisplayMode.landscape;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxWidth < 360 ||
            MediaQuery.textScalerOf(context).scale(1) > 1.3;
        final showEpisodeControls =
            fullscreen &&
            constraints.maxHeight >= 260 &&
            !live &&
            (onPrevious != null || onNext != null);
        // 画面上的次级操作是半透明胶囊，不画描边，避免在亮画面上形成生硬的框。
        Widget action(String label, VoidCallback? callback) => Padding(
          padding: const EdgeInsetsDirectional.only(start: Gap.xs),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 96),
            child: Tooltip(
              message: label,
              child: TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: fg,
                  backgroundColor: Scrims.control,
                  minimumSize: const Size(48, 32),
                  padding: const EdgeInsets.symmetric(horizontal: Gap.m),
                  tapTargetSize: MaterialTapTargetSize.padded,
                  textStyle: context.text.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onPressed: callback,
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
        );
        Widget skip(String tooltip, IconData icon, VoidCallback? callback) =>
            IconButton(
              style: IconButton.styleFrom(
                backgroundColor: Scrims.soft,
                foregroundColor: fg,
                disabledForegroundColor: fg.withValues(alpha: .38),
                disabledBackgroundColor: Scrims.faint,
                minimumSize: const Size(48, 48),
                iconSize: 28,
              ),
              tooltip: tooltip,
              onPressed: callback,
              icon: Icon(icon),
            );
        return SelectionContainer.disabled(
          child: Material(
            type: MaterialType.transparency,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (showEpisodeControls)
                        skip(
                          tr('上一集'),
                          Icons.skip_previous_rounded,
                          onPrevious,
                        ),
                      if (showEpisodeControls) const SizedBox(width: Gap.xxl),
                      IconButton.filled(
                        style: IconButton.styleFrom(
                          backgroundColor: Scrims.medium,
                          foregroundColor: fg,
                          minimumSize: const Size(64, 64),
                          iconSize: 36,
                        ),
                        tooltip: tr(value.isPlaying ? '暂停' : '播放'),
                        onPressed: onPlayPause,
                        icon: AnimatedSwitcher(
                          duration: Motion.of(context, Motion.short),
                          transitionBuilder: (child, animation) =>
                              ScaleTransition(scale: animation, child: child),
                          child: Icon(
                            key: ValueKey((value.isPlaying, value.isCompleted)),
                            !live && value.isCompleted
                                ? Icons.replay_rounded
                                : value.isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                          ),
                        ),
                      ),
                      if (showEpisodeControls) const SizedBox(width: Gap.xxl),
                      if (showEpisodeControls)
                        skip(tr('下一集'), Icons.skip_next_rounded, onNext),
                    ],
                  ),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: _VideoScrim(
                    top: true,
                    child: SafeArea(
                      bottom: false,
                      child: Row(
                        children: [
                          BackButton(color: fg, onPressed: onBack),
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  (fullscreen
                                          ? context.text.titleMedium
                                          : context.text.titleSmall)
                                      ?.copyWith(color: fg),
                            ),
                          ),
                          ?recordingAction,
                          const SizedBox(width: Gap.s),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: _VideoScrim(
                    top: false,
                    child: SafeArea(
                      top: false,
                      child: SizedBox(
                        height: progress == null ? 48 : 78,
                        child: Stack(
                          children: [
                            if (progress != null)
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: 30,
                                height: 48,
                                child: progress!,
                              ),
                            Positioned(
                              left: Gap.m,
                              right: Gap.xs,
                              bottom: 0,
                              height: 48,
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Align(
                                      alignment:
                                          AlignmentDirectional.centerStart,
                                      child: live
                                          ? const _LiveBadge()
                                          : Text.rich(
                                              TextSpan(
                                                text: formatPlaybackTime(
                                                  position,
                                                ),
                                                children: [
                                                  TextSpan(
                                                    text:
                                                        '  /  ${formatPlaybackTime(value.duration)}',
                                                    style: TextStyle(
                                                      color: fg.withValues(
                                                        alpha: .7,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: context.text.labelMedium
                                                  ?.copyWith(
                                                    color: fg,
                                                    fontWeight: FontWeight.w600,
                                                    fontFeatures: const [
                                                      FontFeature.tabularFigures(),
                                                    ],
                                                  ),
                                            ),
                                    ),
                                  ),
                                  if (onToggleChat != null)
                                    IconButton(
                                      tooltip: tr(
                                        chatEnabled ? '关闭弹幕' : '开启弹幕',
                                      ),
                                      onPressed: onToggleChat,
                                      color: fg,
                                      icon: Icon(
                                        chatEnabled
                                            ? Icons.subtitles_rounded
                                            : Icons.subtitles_off_rounded,
                                      ),
                                    ),
                                  if (!compact &&
                                      quality != null &&
                                      onQuality != null)
                                    action(quality!, onQuality),
                                  if (!compact && !live)
                                    action('${speed}x', onSpeed),
                                  IconButton(
                                    color: fg,
                                    tooltip: tr(landscape ? '竖屏展开' : '横屏播放'),
                                    icon: const Icon(
                                      Icons.screen_rotation_rounded,
                                    ),
                                    onPressed: () => onDisplayMode(
                                      landscape
                                          ? VideoDisplayMode.portrait
                                          : VideoDisplayMode.landscape,
                                    ),
                                  ),
                                  if (onSeries != null)
                                    IconButton(
                                      color: fg,
                                      tooltip: tr('同系列'),
                                      icon: const Icon(
                                        Icons.video_library_outlined,
                                      ),
                                      onPressed: onSeries,
                                    ),
                                  if (!live ||
                                      onEpisodes != null ||
                                      onChatArea != null ||
                                      (quality != null && onQuality != null))
                                    PopupMenuButton<String>(
                                      tooltip: tr('更多'),
                                      icon: const Icon(
                                        Icons.more_horiz_rounded,
                                        color: fg,
                                      ),
                                      onOpened: () =>
                                          onInteractionChanged?.call(true),
                                      onCanceled: () =>
                                          onInteractionChanged?.call(false),
                                      onSelected: (choice) {
                                        onInteractionChanged?.call(false);
                                        switch (choice) {
                                          case 'speed':
                                            onSpeed();
                                          case 'quality':
                                            onQuality?.call();
                                          case 'episodes':
                                            onEpisodes?.call();
                                          case 'chatArea':
                                            onChatArea?.call();
                                        }
                                      },
                                      itemBuilder: (context) => [
                                        if (onChatArea != null)
                                          PopupMenuItem(
                                            value: 'chatArea',
                                            child: Text(
                                              '${tr('弹幕显示区域')} · $chatAreaLabel',
                                            ),
                                          ),
                                        if (!live)
                                          PopupMenuItem(
                                            value: 'speed',
                                            child: Text(
                                              '${tr('播放速度')} · ${speed}x',
                                            ),
                                          ),
                                        if (quality != null &&
                                            onQuality != null)
                                          PopupMenuItem(
                                            value: 'quality',
                                            child: Text(quality!),
                                          ),
                                        if (onEpisodes != null)
                                          PopupMenuItem(
                                            value: 'episodes',
                                            child: Text(tr('选集')),
                                          ),
                                      ],
                                    ),
                                  IconButton(
                                    color: fg,
                                    tooltip: tr(fullscreen ? '退出全屏' : '全屏'),
                                    icon: Icon(
                                      fullscreen
                                          ? Icons.fullscreen_exit_rounded
                                          : Icons.fullscreen_rounded,
                                    ),
                                    onPressed: onFullscreen,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _VideoScrim extends StatelessWidget {
  const _VideoScrim({required this.top, required this.child});
  final bool top;
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      // 渐隐留白只负责绘制，不能挡住下层的播放按钮或手势。
      Positioned.fill(
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: top ? Alignment.topCenter : Alignment.bottomCenter,
                end: top ? Alignment.bottomCenter : Alignment.topCenter,
                colors: const [
                  Scrims.strong,
                  Scrims.medium,
                  Scrims.faint,
                  Colors.transparent,
                ],
                stops: const [0, .4, .75, 1],
              ),
            ),
          ),
        ),
      ),
      Padding(
        padding: EdgeInsets.only(
          top: top ? 0 : Gap.xl,
          bottom: top ? Gap.l : 0,
        ),
        child: child,
      ),
    ],
  );
}

/// A small red-dot badge in place of the timeline while watching live.
class _LiveBadge extends StatelessWidget {
  const _LiveBadge();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: Gap.s, vertical: 2),
    decoration: const BoxDecoration(
      color: Scrims.control,
      borderRadius: Radii.tiny,
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: context.colors.error,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: Gap.xs + 2),
        Text(
          tr('直播'),
          style: context.text.labelMedium?.copyWith(
            color: Scrims.onScrim,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

/// Previous / current / next episode, and the episode list.
class VideoEpisodeBar extends StatelessWidget {
  const VideoEpisodeBar({
    super.key,
    required this.title,
    required this.onPick,
    this.onPrevious,
    this.onNext,
    this.overlay = false,
  });
  final String title;
  final VoidCallback onPick;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  /// Drawn over the video instead of on the page surface.
  final bool overlay;

  @override
  Widget build(BuildContext context) {
    final fg = overlay ? Scrims.onScrim : null;
    final disabled = overlay ? Scrims.onScrim.withValues(alpha: .38) : null;
    return Row(
      children: [
        IconButton(
          tooltip: tr('上一集'),
          color: fg,
          disabledColor: disabled,
          onPressed: onPrevious,
          icon: const Icon(Icons.skip_previous_rounded),
        ),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: fg),
          ),
        ),
        IconButton(
          tooltip: tr('下一集'),
          color: fg,
          disabledColor: disabled,
          onPressed: onNext,
          icon: const Icon(Icons.skip_next_rounded),
        ),
        IconButton(
          tooltip: tr('选集'),
          color: fg,
          onPressed: onPick,
          icon: const Icon(Icons.playlist_play_rounded),
        ),
      ],
    );
  }
}

/// The transient hint in the middle of the player while seeking or changing levels.
class VideoHint extends StatelessWidget {
  const VideoHint(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Center(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Gap.l,
          vertical: Gap.s + 2,
        ),
        decoration: const ShapeDecoration(
          color: Scrims.strong,
          shape: StadiumBorder(),
        ),
        child: Text(
          text,
          style: context.text.titleSmall?.copyWith(color: Scrims.onScrim),
        ),
      ),
    ),
  );
}

/// What sits below the inline player: title, metadata, series and related videos.
class VideoDetails extends StatelessWidget {
  const VideoDetails({
    super.key,
    required this.work,
    this.offline = false,
    this.quality,
    this.showHeader = true,
    this.showRelated = true,
    this.episodeId,
  });
  final WorkDetail work;
  final bool offline;
  final String? quality;
  final bool showHeader;
  final bool showRelated;
  final String? episodeId;

  @override
  Widget build(BuildContext context) {
    final d = work;
    final meta = [
      if (d.authors.isNotEmpty) d.authors.join(' / '),
      if (d.views != null) tr('{count} 次观看', {'count': formatCount(d.views)}),
      if (d.uploaded.isNotEmpty) d.uploaded,
      if (offline) tr('离线播放'),
      ?quality,
    ];
    return CustomScrollView(
      shrinkWrap: true,
      primary: false,
      physics: const NeverScrollableScrollPhysics(),
      slivers: [
        if (showHeader)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Gap.page, Gap.m, Gap.page, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ContentTranslation(
                    text: d.title,
                    source: d.source,
                    builder: (value) => SelectableText(
                      value,
                      style: ParkText.serif(context.text.titleMedium),
                    ),
                  ),
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: Gap.xs),
                    ContentTranslation(
                      text: meta.join(' · '),
                      source: d.source,
                      builder: (value) => Text(
                        value,
                        style: context.text.bodySmall?.copyWith(
                          color: context.colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        if (showHeader && !offline)
          SliverToBoxAdapter(
            child: CommentsEntry(
              source: d.source,
              workId: d.id,
              count: d.comments,
              available: d.commentsAvailable,
              context: {
                'url': d.url,
                if (episodeId != null) 'episodeId': episodeId,
              },
            ),
          ),
        if (showRelated && d.description.isNotEmpty)
          SliverToBoxAdapter(
            child: ExpandableDescription(
              key: ValueKey(d.uid),
              text: d.description,
            ),
          ),
        if (showRelated && d.series.isNotEmpty)
          SliverToBoxAdapter(
            child: WorkRecommendations(title: tr('同系列'), items: d.series),
          ),
        if (showRelated &&
            (d.related.isNotEmpty ||
                d.relatedSections.isNotEmpty ||
                SourceManager.instance.manifest(d.source)?.can('related') ==
                    true))
          SliverToBoxAdapter(
            child: RelatedWorks(key: ObjectKey(d), detail: d),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: Gap.xxl)),
      ],
    );
  }
}
