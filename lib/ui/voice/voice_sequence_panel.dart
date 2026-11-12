import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../core/localization.dart';
import '../../core/models.dart';
import '../../core/timed_subtitles.dart';
import '../../core/voice_timeline.dart';
import '../../engine/media_transport_factory.dart';
import '../../engine/source_manager.dart';
import '../video/video_session.dart';
import '../widgets/error_view.dart';
import 'voice_subtitles.dart';

class VoiceSequencePanel extends StatefulWidget {
  const VoiceSequencePanel({super.key, required this.session});
  final VideoSession session;
  @override
  State<VoiceSequencePanel> createState() => _VoiceSequencePanelState();
}

class _VoiceSequencePanelState extends State<VoiceSequencePanel> {
  bool _enabled = false;
  CancelToken? _cancel;
  VoiceTimeline? _timeline;
  List<TimedSubtitleCue> _cues = const [];
  Object? _error;
  int _loaded = 0;
  int _seek = 0;
  int? _current;
  double? _drag;
  final _scroll = ItemScrollController();

  @override
  void initState() {
    super.initState();
    _enabled = widget.session.joinedVoice;
    _timeline = widget.session.voiceSequence?.timeline;
    _cues = widget.session.voiceSequence?.cues ?? const [];
    widget.session.addListener(_sessionChanged);
    if (_enabled && _timeline == null) unawaited(_prepare());
  }

  @override
  void didUpdateWidget(VoiceSequencePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.session, widget.session)) return;
    oldWidget.session.removeListener(_sessionChanged);
    _cancel?.cancel();
    _seek++;
    _enabled = widget.session.joinedVoice;
    _timeline = widget.session.voiceSequence?.timeline;
    _cues = widget.session.voiceSequence?.cues ?? const [];
    _error = null;
    _current = null;
    _drag = null;
    _loaded = 0;
    widget.session.addListener(_sessionChanged);
    if (_enabled && _timeline == null) unawaited(_prepare());
  }

  void _sessionChanged() {
    if (!widget.session.visible &&
        _cancel?.isCancelled == false &&
        _timeline == null) {
      _cancel?.cancel();
      if (mounted) setState(() => _error = SourceError('CANCELLED', '请求已取消'));
    }
  }

  Future<void> _prepare() async {
    _cancel?.cancel();
    final cancel = _cancel = CancelToken();
    setState(() {
      _error = null;
      _timeline = null;
      _loaded = 0;
      _current = null;
      _drag = null;
    });
    final session = widget.session;
    final durations = <Duration>[];
    final subtitles = <List<TimedSubtitleCue>>[];
    try {
      for (final episode in session.episodes) {
        if (cancel.isCancelled) return;
        if (episode.id == session.episode.id &&
            session.controller?.value.isInitialized == true) {
          durations.add(session.controller!.value.duration);
        } else {
          final prepared = await session.prepareVideo(
            session.work,
            episode,
            cancel,
          );
          try {
            durations.add(prepared.controller.value.duration);
          } finally {
            await prepared.close();
          }
        }
        final subtitle = session.work.voiceSubtitles[episode.id]?.firstOrNull;
        if (subtitle == null) {
          subtitles.add(const []);
        } else {
          final source = SourceManager.instance.manifest(session.work.source);
          if (source == null) throw SourceError('CONFIG', '媒体数据无效');
          final resource = await SourceManager.instance.voiceResource(
            session.work.source,
            session.work.id,
            subtitle,
            cancelToken: cancel,
          );
          final transport = createMediaTransport(
            source,
            initialUrl: resource.url,
          );
          try {
            final response = await transport.fetch(
              resource.url,
              maxBytes: 2 * 1024 * 1024,
              cancelToken: cancel,
            );
            final parsed = TimedSubtitles.parse(
              utf8.decode(response.bytes),
              format: resource.format,
            );
            if (parsed.cues.isEmpty) throw SourceError('PARSE', '媒体数据无效');
            subtitles.add(parsed.cues);
          } finally {
            await transport.close();
          }
        }
        if (!mounted || cancel.isCancelled) return;
        setState(() => _loaded++);
      }
      final timeline = VoiceTimeline(durations);
      if (mounted && !cancel.isCancelled) {
        setState(() {
          _timeline = timeline;
          _cues = timeline.subtitles(subtitles);
          session.voiceSequence = (timeline: timeline, cues: _cues);
        });
      }
    } catch (error) {
      if (mounted && !cancel.isCancelled) setState(() => _error = error);
    }
  }

  Future<void> _seekTo(Duration position) async {
    final target = _timeline!.locate(position);
    final generation = ++_seek;
    final session = widget.session;
    final episode = session.episodes[target.index];
    final wantsPlayback = session.wantsPlayback;
    try {
      if (session.episode.id != episode.id || session.controller == null) {
        await session.selectEpisode(
          episode,
          at: target.position,
          wantsPlayback: wantsPlayback,
        );
      } else {
        await session.controller!.seekTo(target.position);
      }
    } catch (error) {
      if (mounted && generation == _seek) setState(() => _error = error);
    }
  }

  @override
  void dispose() {
    widget.session.removeListener(_sessionChanged);
    _cancel?.cancel();
    _seek++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final timeline = _timeline;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile.adaptive(
          title: Text(tr('拼接播放')),
          subtitle: Text(tr('合并曲目时间轴与字幕')),
          value: _enabled,
          onChanged: (value) {
            setState(() {
              _enabled = value;
              session.joinedVoice = value;
              _current = null;
              _drag = null;
              _error = null;
            });
            if (value) {
              if (_timeline == null) unawaited(_prepare());
            } else {
              _cancel?.cancel();
              _seek++;
            }
          },
        ),
        if (!_enabled)
          VoiceSubtitles(session: session)
        else if (_error != null)
          SourceErrorView(
            error: _error!,
            source: session.work.source,
            onRetry: _prepare,
            compact: true,
          )
        else if (timeline == null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                LinearProgressIndicator(
                  value: _loaded / session.episodes.length,
                ),
                Text(
                  tr('正在准备曲目 {current}/{total}', {
                    'current': _loaded,
                    'total': session.episodes.length,
                  }),
                ),
              ],
            ),
          )
        else
          AnimatedBuilder(
            animation: session.playerUpdates,
            builder: (context, _) {
              final position =
                  timeline.offsets[session.episodeIndex] +
                  (session.controller?.value.position ?? Duration.zero);
              final selected = _cues.indexWhere(
                (cue) =>
                    cue.start <= position &&
                    (cue.end == null || position < cue.end!),
              );
              if (_current != selected) {
                _current = selected;
                if (selected >= 0) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted &&
                        _enabled &&
                        identical(_timeline, timeline) &&
                        _scroll.isAttached &&
                        _current == selected) {
                      unawaited(
                        _scroll.scrollTo(
                          index: selected,
                          duration: const Duration(milliseconds: 250),
                          alignment: .3,
                        ),
                      );
                    }
                  });
                }
              }
              String time(Duration value) =>
                  '${value.inMinutes}:${(value.inSeconds % 60).toString().padLeft(2, '0')}';
              return Column(
                children: [
                  Text('${time(position)} / ${time(timeline.duration)}'),
                  Slider(
                    value: (_drag ?? position.inMilliseconds.toDouble()).clamp(
                      0,
                      timeline.duration.inMilliseconds.toDouble(),
                    ),
                    max: timeline.duration.inMilliseconds.toDouble(),
                    onChanged: (value) => setState(() => _drag = value),
                    onChangeEnd: (value) {
                      setState(() => _drag = null);
                      unawaited(_seekTo(Duration(milliseconds: value.round())));
                    },
                  ),
                  if (_cues.isNotEmpty)
                    SizedBox(
                      height: 240,
                      child: Material(
                        type: MaterialType.transparency,
                        clipBehavior: Clip.hardEdge,
                        child: ScrollablePositionedList.builder(
                          key: ObjectKey(timeline),
                          itemScrollController: _scroll,
                          itemCount: _cues.length,
                          itemBuilder: (context, index) => ListTile(
                            selected:
                                _cues[index].start <= position &&
                                position < _cues[index].end!,
                            title: Text(_cues[index].text),
                            onTap: () => unawaited(_seekTo(_cues[index].start)),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }
}
