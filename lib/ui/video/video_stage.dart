import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../core/localization.dart';
import '../../core/settings.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/error_view.dart';
import 'adaptive_video_progress.dart';
import 'video_controls.dart';
import 'video_episode_pager.dart';
import 'video_gesture_surface.dart';
import 'video_session.dart';

/// The black player area: video, loading and error states, gestures, the controls
/// layer and progress bar, and vertical episode paging for AI dramas. It rebuilds on
/// every player tick, so everything that does not change with playback stays outside.
class VideoStage extends StatelessWidget {
  const VideoStage({
    super.key,
    required this.session,
    required this.fullscreen,
    required this.controlsVisible,
    required this.controls,
    required this.surfaceKey,
    required this.previewPosition,
    required this.hint,
    required this.dim,
    this.brightness = 1,
    this.volume = 1,
    required this.onTap,
    required this.onMouseTap,
    required this.onDoubleTap,
    this.onDoubleTapSeek,
    required this.onLongPressStart,
    required this.onLongPressEnd,
    required this.onLongPressCancel,
    required this.onGestureStart,
    required this.onGestureUpdate,
    required this.onGestureEnd,
    required this.onGestureCancel,
    required this.onShowControls,
    required this.onInteract,
    required this.onIdle,
    required this.onEpisodePage,
    this.liveChat,
    this.subtitles,
    this.pageHorizontally = false,
  });

  final VideoSession session;
  final bool fullscreen;
  final bool pageHorizontally;
  final bool controlsVisible;
  final Widget? subtitles;

  /// The controls layer for the current player value.
  final Widget Function(VideoPlayerValue value, Widget progress) controls;
  final GlobalKey surfaceKey;
  final Duration? previewPosition;
  final String? hint;

  /// Darkening applied when the platform brightness cannot be changed (0 = none).
  final double dim;
  final double brightness;
  final double volume;
  final VoidCallback onTap;
  final VoidCallback onMouseTap;
  final VoidCallback onDoubleTap;
  final ValueChanged<int>? onDoubleTapSeek;
  final VoidCallback onLongPressStart;
  final VoidCallback onLongPressEnd;
  final VoidCallback onLongPressCancel;
  final void Function(Offset point, Size viewport) onGestureStart;
  final ValueChanged<Offset> onGestureUpdate;
  final VoidCallback onGestureEnd;
  final VoidCallback onGestureCancel;

  /// The progress bar was touched; controls show and stay.
  final VoidCallback onShowControls;

  /// Scrubbing or episode paging started; controls must not hide meanwhile.
  final VoidCallback onInteract;

  /// The interaction ended; controls may hide again.
  final VoidCallback onIdle;
  final ValueChanged<int> onEpisodePage;
  final Widget? liveChat;

  @override
  Widget build(BuildContext context) {
    final box = ColoredBox(
      key: surfaceKey,
      color: Colors.black,
      child: AnimatedBuilder(
        animation: session.playerUpdates,
        builder: (context, _) => _inner(context),
      ),
    );
    final paged = fullscreen && session.scrollEpisodes
        ? _episodePager(box)
        : box;
    if (fullscreen || pageHorizontally) return paged;
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = (constraints.maxWidth * 9 / 16).clamp(
          0.0,
          MediaQuery.sizeOf(context).height * 0.6,
        );
        return SizedBox(width: double.infinity, height: height, child: paged);
      },
    );
  }

  Widget _inner(BuildContext context) {
    final c = session.controller;
    final current = session.current;
    if (session.error case final error?) {
      return Theme(
        data: ParkTheme.of(
          Brightness.dark,
          Color(AppSettings.instance.seedColor),
        ),
        child: SourceErrorView(
          error: error,
          source: session.work.source,
          onRetry: session.init,
          compact: true,
        ),
      );
    }
    if (!VideoSession.supported && current != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              tr('当前平台不支持内置播放'),
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: () => launchUrl(
                Uri.parse(current.url),
                mode: LaunchMode.externalApplication,
              ),
              icon: const Icon(Icons.open_in_new_rounded),
              label: SelectionContainer.disabled(
                child: Text(
                  tr('用外部播放器打开（{quality}）', {'quality': current.label}),
                ),
              ),
            ),
          ],
        ),
      );
    }
    if (c == null || !c.value.isInitialized) {
      return const Center(child: LoadingIndicator(color: Colors.white70));
    }
    final showControls =
        controlsVisible || (!session.isLive && c.value.isCompleted);
    return VideoGestureSurface(
      pageHorizontally: pageHorizontally,
      pageVertically: fullscreen && session.scrollEpisodes,
      showLevelControls: showControls,
      brightness: brightness,
      volume: volume,
      onTap: onTap,
      onMouseTap: onMouseTap,
      onDoubleTap: onDoubleTap,
      onDoubleTapSeek: session.isLive ? null : onDoubleTapSeek,
      onLongPressStart: onLongPressStart,
      onLongPressEnd: onLongPressEnd,
      onLongPressCancel: onLongPressCancel,
      onStart: onGestureStart,
      onUpdate: onGestureUpdate,
      onEnd: onGestureEnd,
      onCancel: onGestureCancel,
      overlay: Stack(
        fit: StackFit.expand,
        children: [
          ?subtitles,
          ?liveChat,
          AnimatedOpacity(
            opacity: showControls ? 1 : 0,
            duration: Motion.of(context, Motion.short),
            child: ExcludeSemantics(
              excluding: !showControls,
              child: ExcludeFocus(
                excluding: !showControls,
                child: IgnorePointer(
                  ignoring: !showControls,
                  child: controls(
                    c.value,
                    Listener(
                      onPointerDown: (_) => onShowControls(),
                      child: AdaptiveVideoProgress(
                        position: c.value.position,
                        duration: c.value.duration,
                        buffered: c.value.buffered.isEmpty
                            ? Duration.zero
                            : c.value.buffered.last.end,
                        onScrubbingChanged: (scrubbing) {
                          if (scrubbing) {
                            onGestureCancel();
                            onInteract();
                          } else {
                            onIdle();
                          }
                        },
                        onSeek: (position) => c.seekTo(position),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (hint case final hint?) VideoHint(hint),
        ],
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (session.isAudio)
            const Center(
              child: Icon(
                Icons.headphones_rounded,
                color: Colors.white70,
                size: 64,
              ),
            )
          else
            Center(
              child: AspectRatio(
                aspectRatio: c.value.aspectRatio,
                child: VideoPlayer(c, key: ObjectKey(c)),
              ),
            ),
          if (dim > 0)
            IgnorePointer(
              child: ColoredBox(color: Colors.black.withValues(alpha: dim)),
            ),
          if (c.value.isBuffering)
            const Center(child: LoadingIndicator(color: Colors.white70)),
        ],
      ),
    );
  }

  Widget _episodePager(Widget active) {
    final episodes = session.episodes;
    return VideoEpisodePager(
      index: session.episodeIndex,
      count: episodes.length,
      onSettled: onEpisodePage,
      onInteractionChanged: (active) {
        if (active) {
          onInteract();
        } else {
          onIdle();
        }
      },
      itemBuilder: (_, index) {
        if (index == session.episodeIndex) return active;
        final preview = session.nextPreview;
        return ColoredBox(
          color: Colors.black,
          child: Center(
            child:
                session.preloadedEpisode == episodes[index] && preview != null
                ? AspectRatio(
                    aspectRatio: preview.controller.value.aspectRatio,
                    child: VideoPlayer(preview.controller),
                  )
                : const LoadingIndicator(color: Colors.white70),
          ),
        );
      },
    );
  }
}
