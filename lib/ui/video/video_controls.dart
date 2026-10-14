import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../core/localization.dart';
import '../../core/models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/paged_grid.dart';
import 'video_gestures.dart';

String formatPlaybackTime(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  final mm = m.toString().padLeft(2, '0'), ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
}

/// The control layer over the player: title, quality and speed on top, play in the middle,
/// time and screen modes at the bottom (the progress bar is drawn by the page above it).
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
    this.episodes,
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
  final Widget? episodes;

  @override
  Widget build(BuildContext context) {
    const fg = Scrims.onScrim;
    final landscape = displayMode == VideoDisplayMode.landscape;
    return ReaderChrome(
      visible: true,
      title: title,
      onBack: onBack,
      actions: [
        if (quality != null)
          TextButton(
            onPressed: onQuality,
            style: TextButton.styleFrom(foregroundColor: fg),
            child: Text(quality!),
          ),
        TextButton(
          onPressed: onSpeed,
          style: TextButton.styleFrom(foregroundColor: fg),
          child: Text('${speed}x'),
        ),
      ],
      bottom: Padding(
        padding: const EdgeInsets.only(bottom: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ?episodes,
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${formatPlaybackTime(position)} / ${formatPlaybackTime(value.duration)}',
                    style: context.text.labelMedium?.copyWith(
                      color: fg,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                IconButton(
                  tooltip: tr(landscape ? '竖屏展开' : '横屏播放'),
                  icon: Icon(
                    landscape
                        ? Icons.stay_current_portrait_rounded
                        : Icons.screen_rotation_rounded,
                  ),
                  onPressed: () => onDisplayMode(
                    landscape
                        ? VideoDisplayMode.portrait
                        : VideoDisplayMode.landscape,
                  ),
                ),
                IconButton(
                  tooltip: tr(fullscreen ? '退出全屏' : '竖屏展开'),
                  icon: Icon(
                    fullscreen
                        ? Icons.fullscreen_exit_rounded
                        : Icons.fullscreen_rounded,
                  ),
                  onPressed: onFullscreen,
                ),
              ],
            ),
          ],
        ),
      ),
      child: Stack(
        children: [
          Center(
            child: IconButton(
              tooltip: tr(value.isPlaying ? '暂停' : '播放'),
              iconSize: 48,
              icon: Icon(
                value.isPlaying
                    ? Icons.pause_circle_filled_rounded
                    : Icons.play_circle_fill_rounded,
                color: fg,
              ),
              onPressed: onPlayPause,
            ),
          ),
        ],
      ),
    );
  }
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
  });
  final WorkDetail work;
  final bool offline;
  final String? quality;

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
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Gap.page, Gap.m, Gap.page, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  d.title,
                  style: ParkText.serif(context.text.titleMedium),
                ),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: Gap.xs),
                  Text(
                    meta.join(' · '),
                    style: context.text.bodySmall?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (d.series.isNotEmpty)
          SliverToBoxAdapter(
            child: WorkCarousel(title: tr('同系列'), items: d.series),
          ),
        if (d.related.isNotEmpty)
          SliverToBoxAdapter(
            child: WorkCarousel(title: tr('相关推荐'), items: d.related),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: Gap.xxl)),
      ],
    );
  }
}
