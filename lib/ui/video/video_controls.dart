import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../core/localization.dart';
import '../../core/models.dart';
import '../../engine/source_manager.dart';
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
    this.onPrevious,
    this.onNext,
    this.onInteractionChanged,
    this.progress,
    this.live = false,
    this.recordingAction,
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
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final ValueChanged<bool>? onInteractionChanged;
  final Widget? progress;
  final bool live;
  final Widget? recordingAction;

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
        Widget action(String label, VoidCallback? callback) => Padding(
          padding: const EdgeInsetsDirectional.only(start: Gap.xs),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 96),
            child: Tooltip(
              message: label,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: fg,
                  side: BorderSide(color: fg.withValues(alpha: .65)),
                  minimumSize: const Size(48, 32),
                  padding: const EdgeInsets.symmetric(horizontal: Gap.s),
                  textStyle: context.text.labelMedium,
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
                        IconButton(
                          color: fg,
                          disabledColor: fg.withValues(alpha: .38),
                          tooltip: tr('上一集'),
                          onPressed: onPrevious,
                          icon: const Icon(Icons.skip_previous_rounded),
                        ),
                      if (showEpisodeControls) const SizedBox(width: Gap.xl),
                      IconButton.filled(
                        style: IconButton.styleFrom(
                          backgroundColor: Scrims.medium,
                          foregroundColor: fg,
                          minimumSize: const Size(56, 56),
                          iconSize: 32,
                        ),
                        tooltip: tr(value.isPlaying ? '暂停' : '播放'),
                        onPressed: onPlayPause,
                        icon: Icon(
                          !live && value.isCompleted
                              ? Icons.replay_rounded
                              : value.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                        ),
                      ),
                      if (showEpisodeControls) const SizedBox(width: Gap.xl),
                      if (showEpisodeControls)
                        IconButton(
                          color: fg,
                          disabledColor: fg.withValues(alpha: .38),
                          tooltip: tr('下一集'),
                          onPressed: onNext,
                          icon: const Icon(Icons.skip_next_rounded),
                        ),
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
                              style: context.text.titleSmall?.copyWith(
                                color: fg,
                              ),
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
                                    child: Text(
                                      live
                                          ? tr('直播')
                                          : '${formatPlaybackTime(position)} / ${formatPlaybackTime(value.duration)}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: context.text.labelMedium?.copyWith(
                                        color: fg,
                                        fontFeatures: const [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                    ),
                                  ),
                                  if (!compact &&
                                      quality != null &&
                                      onQuality != null)
                                    action(quality!, onQuality),
                                  if (!compact && !live)
                                    action('${speed}x', onSpeed),
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
                                        case 'orientation':
                                          onDisplayMode(
                                            landscape
                                                ? VideoDisplayMode.portrait
                                                : VideoDisplayMode.landscape,
                                          );
                                      }
                                    },
                                    itemBuilder: (context) => [
                                      if (compact && !live)
                                        PopupMenuItem(
                                          value: 'speed',
                                          child: Text(
                                            '${tr('播放速度')} · ${speed}x',
                                          ),
                                        ),
                                      if (compact &&
                                          quality != null &&
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
                                      PopupMenuItem(
                                        value: 'orientation',
                                        child: Text(
                                          tr(landscape ? '竖屏展开' : '横屏播放'),
                                        ),
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
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: top ? Alignment.topCenter : Alignment.bottomCenter,
        end: top ? Alignment.bottomCenter : Alignment.topCenter,
        colors: [Scrims.strong, Colors.transparent],
      ),
    ),
    child: child,
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
        padding: const EdgeInsets.symmetric(horizontal: Gap.m, vertical: Gap.s),
        decoration: const BoxDecoration(
          color: Scrims.medium,
          borderRadius: Radii.large,
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
  });
  final WorkDetail work;
  final bool offline;
  final String? quality;
  final bool showHeader;
  final bool showRelated;

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
