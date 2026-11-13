import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../../core/settings.dart';
import '../../core/voice_timeline.dart';
import '../kit/tokens.dart';
import '../video/video_controls.dart' show formatPlaybackTime;
import '../video/video_session.dart';
import '../widgets/content_translation.dart';
import '../widgets/error_view.dart';
import 'voice_subtitles.dart';

/// 音频保留一套控制区，剩余空间交给字幕；只有实际打开的曲目贡献时长。
class VoiceAudioView extends StatefulWidget {
  const VoiceAudioView({
    super.key,
    required this.session,
    required this.onSpeed,
    required this.onEpisodes,
    required this.onDetails,
  });
  final VideoSession session;
  final VoidCallback onSpeed, onEpisodes, onDetails;
  @override
  State<VoiceAudioView> createState() => _VoiceAudioViewState();
}

class _VoiceAudioViewState extends State<VoiceAudioView> {
  double? _drag;
  @override
  void didUpdateWidget(VoiceAudioView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) _drag = null;
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    return AnimatedBuilder(
      animation: Listenable.merge([session, session.playerUpdates]),
      child: VoiceSubtitles(session: session, height: null),
      builder: (context, child) {
        final value = session.controller?.value;
        final lengths = [
          for (final e in session.episodes) session.voiceDurations[e.id],
        ];
        final joined = session.joinedVoice && lengths.every((d) => d != null);
        final timeline = joined
            ? VoiceTimeline(lengths.cast<Duration>())
            : null;
        final total = timeline?.duration ?? value?.duration ?? Duration.zero;
        final position =
            (timeline?.offsets[session.episodeIndex] ?? Duration.zero) +
            (value?.position ?? Duration.zero);
        final activeId = session.episode.id;
        Future<void> select(int index) async {
          if (index < 0 || index >= session.episodes.length) return;
          await session.selectEpisode(
            session.episodes[index],
            at: Duration.zero,
            wantsPlayback: session.wantsPlayback,
          );
        }

        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Gap.page),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TranslatedText(
                      session.work.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (session.episodes.length > 1)
                      TranslatedText(
                        session.episode.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    Row(
                      children: [
                        IconButton(
                          tooltip: tr('上一集'),
                          onPressed: session.episodeIndex > 0
                              ? () =>
                                    unawaited(select(session.episodeIndex - 1))
                              : null,
                          icon: const Icon(Icons.skip_previous_rounded),
                        ),
                        IconButton.filled(
                          tooltip: tr(session.wantsPlayback ? '暂停' : '播放'),
                          onPressed: value?.isInitialized == true
                              ? session.togglePlayback
                              : null,
                          icon: Icon(
                            session.wantsPlayback
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                          ),
                        ),
                        IconButton(
                          tooltip: tr('下一集'),
                          onPressed:
                              session.episodeIndex < session.episodes.length - 1
                              ? () =>
                                    unawaited(select(session.episodeIndex + 1))
                              : null,
                          icon: const Icon(Icons.skip_next_rounded),
                        ),
                        const Spacer(),
                        if (session.episodes.length > 1)
                          IconButton(
                            tooltip: tr('选集'),
                            onPressed: widget.onEpisodes,
                            icon: const Icon(Icons.playlist_play_rounded),
                          ),
                        PopupMenuButton<String>(
                          tooltip: tr('播放设置'),
                          onSelected: (choice) {
                            if (choice == 'joined') {
                              setState(() => _drag = null);
                              session.setJoinedVoice(!session.joinedVoice);
                            } else if (choice == 'background') {
                              setState(
                                () =>
                                    AppSettings
                                        .instance
                                        .voiceBackgroundPlayback = !AppSettings
                                        .instance
                                        .voiceBackgroundPlayback,
                              );
                            } else if (choice == 'speed') {
                              widget.onSpeed();
                            } else if (choice == 'details') {
                              widget.onDetails();
                            }
                          },
                          itemBuilder: (_) => [
                            PopupMenuItem(
                              value: 'speed',
                              child: Text('${tr('播放速度')} · ${session.speed}x'),
                            ),
                            if (session.episodes.length > 1)
                              CheckedPopupMenuItem(
                                value: 'joined',
                                checked: session.joinedVoice,
                                child: Text(tr('拼接播放')),
                              ),
                            CheckedPopupMenuItem(
                              value: 'background',
                              checked:
                                  AppSettings.instance.voiceBackgroundPlayback,
                              child: Text(tr('后台播放')),
                            ),
                            PopupMenuItem(
                              value: 'details',
                              child: Text(tr('作品详情')),
                            ),
                          ],
                          icon: const Icon(Icons.more_vert_rounded),
                        ),
                      ],
                    ),
                    Slider(
                      value: (_drag ?? position.inMilliseconds.toDouble())
                          .clamp(
                            0,
                            total.inMilliseconds.toDouble().clamp(
                              1,
                              double.infinity,
                            ),
                          ),
                      max: total.inMilliseconds.toDouble().clamp(
                        1,
                        double.infinity,
                      ),
                      onChanged: value?.isInitialized == true
                          ? (v) => setState(() => _drag = v)
                          : null,
                      onChangeEnd: value?.isInitialized == true
                          ? (v) {
                              setState(() => _drag = null);
                              if (session.episode.id != activeId) return;
                              final at = Duration(milliseconds: v.round());
                              if (timeline == null) {
                                unawaited(session.controller!.seekTo(at));
                              } else {
                                final target = timeline.locate(at);
                                if (target.index == session.episodeIndex) {
                                  unawaited(
                                    session.controller!.seekTo(target.position),
                                  );
                                } else {
                                  unawaited(
                                    session.selectEpisode(
                                      session.episodes[target.index],
                                      at: target.position,
                                      wantsPlayback: session.wantsPlayback,
                                    ),
                                  );
                                }
                              }
                            }
                          : null,
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${formatPlaybackTime(position)} / ${formatPlaybackTime(total)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        Text(
                          tr(joined ? '拼接播放' : '当前曲目'),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                    if (session.error != null)
                      SourceErrorView(
                        error: session.error!,
                        source: session.work.source,
                        compact: true,
                        onRetry: () => session.selectEpisode(session.episode),
                      ),
                    if (session.error == null &&
                        (value == null || value.isBuffering))
                      const LinearProgressIndicator(),
                  ],
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: Gap.s)),
            SliverFillRemaining(child: child!),
          ],
        );
      },
    );
  }
}
