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
    required this.episodePages,
    required this.previewPosition,
    required this.hint,
    required this.dim,
    required this.onTap,
    required this.onMouseTap,
    required this.onDoubleTap,
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
  });

  final VideoSession session;
  final bool fullscreen;
  final bool controlsVisible;

  /// The controls layer for the current player value.
  final Widget Function(VideoPlayerValue value, Widget progress) controls;
  final PageController episodePages;
  final Duration? previewPosition;
  final String? hint;

  /// Darkening applied when the platform brightness cannot be changed (0 = none).
  final double dim;
  final VoidCallback onTap;
  final VoidCallback onMouseTap;
  final VoidCallback onDoubleTap;
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
      color: Colors.black,
      child: AnimatedBuilder(
        animation: session.playerUpdates,
        builder: (context, _) => _inner(context),
      ),
    );
    final paged = session.scrollEpisodes ? _episodePager(box) : box;
    if (fullscreen) return paged;
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
      pageVertically: session.scrollEpisodes,
      showLevelControls: showControls,
      onTap: onTap,
      onMouseTap: onMouseTap,
      onDoubleTap: onDoubleTap,
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
          Center(
            child: AspectRatio(
              aspectRatio: c.value.aspectRatio,
              child: VideoPlayer(c),
            ),
          ),
          if (dim > 0)
            IgnorePointer(
              child: ColoredBox(color: Colors.black.withValues(alpha: dim)),
            ),
          if (c.value.isBuffering)
            const Center(
              child: CircularProgressIndicator(color: Colors.white70),
            ),
        ],
      ),
    );
  }

  Widget _episodePager(Widget active) {
    final episodes = session.episodes;
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.depth != 0) return false;
        if (notification is ScrollStartNotification) onInteract();
        if (notification is ScrollEndNotification) onIdle();
        return false;
      },
      child: PageView.builder(
        controller: episodePages,
        scrollDirection: Axis.vertical,
        itemCount: episodes.length,
        onPageChanged: onEpisodePage,
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
                  : Text(
                      episodes[index].title,
                      style: const TextStyle(color: Colors.white),
                    ),
            ),
          );
        },
      ),
    );
  }
}
