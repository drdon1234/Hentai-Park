import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../core/localization.dart';
import '../../core/models.dart';
import '../../core/timed_subtitles.dart';
import '../../engine/media_transport_factory.dart';
import '../../engine/source_manager.dart';
import '../kit/tokens.dart';
import '../video/video_session.dart';
import '../widgets/error_view.dart';

class VoiceSubtitles extends StatefulWidget {
  const VoiceSubtitles({
    super.key,
    required this.session,
    this.overlay = false,
  });
  final VideoSession session;
  final bool overlay;

  @override
  State<VoiceSubtitles> createState() => _VoiceSubtitlesState();
}

class _VoiceSubtitlesState extends State<VoiceSubtitles> {
  final _scroll = ItemScrollController();
  CancelToken? _cancel;
  TimedSubtitles? _timeline;
  Object? _error;
  String? _episode;
  String? _subtitle;
  List<String> _subtitles = const [];
  int? _current;

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_changed);
    _changed();
  }

  @override
  void didUpdateWidget(VoiceSubtitles oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      oldWidget.session.removeListener(_changed);
      widget.session.addListener(_changed);
      _episode = null;
      _changed();
    }
  }

  void _changed() {
    final episode = widget.session.episode.id;
    if (_episode == episode) return;
    _episode = episode;
    _subtitles = widget.session.work.voiceSubtitles[episode] ?? const [];
    _subtitle = _subtitles.firstOrNull;
    _timeline = null;
    _error = null;
    _current = null;
    _cancel?.cancel();
    if (_subtitle != null) {
      unawaited(_load());
    } else if (mounted) {
      setState(() {});
    }
  }

  Future<void> _load() async {
    final subtitle = _subtitle;
    if (subtitle == null) return;
    _cancel?.cancel();
    final cancel = _cancel = CancelToken();
    setState(() {
      _timeline = null;
      _error = null;
      _current = null;
    });
    try {
      final work = widget.session.work;
      final source = SourceManager.instance.manifest(work.source);
      if (source == null) throw SourceError('CONFIG', '媒体数据无效');
      final resource = await SourceManager.instance.voiceResource(
        work.source,
        work.id,
        subtitle,
        cancelToken: cancel,
      );
      final transport = createMediaTransport(source, initialUrl: resource.url);
      try {
        final result = await transport.fetch(
          resource.url,
          maxBytes: 2 * 1024 * 1024,
          cancelToken: cancel,
        );
        final timeline = TimedSubtitles.parse(
          utf8.decode(result.bytes),
          format: resource.format,
        );
        if (timeline.cues.isEmpty) throw SourceError('PARSE', '媒体数据无效');
        if (mounted && !cancel.isCancelled) {
          setState(() => _timeline = timeline);
        }
      } finally {
        await transport.close();
      }
    } catch (error) {
      if (mounted && !cancel.isCancelled) setState(() => _error = error);
    }
  }

  @override
  void dispose() {
    _cancel?.cancel();
    widget.session.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_subtitle == null) return const SizedBox.shrink();
    final timeline = _timeline;
    if (widget.overlay) {
      if (timeline == null) return const SizedBox.shrink();
      return IgnorePointer(
        child: AnimatedBuilder(
          animation: widget.session.playerUpdates,
          builder: (context, _) => VoiceSubtitleOverlay(
            cues: [
              for (final index in timeline.activeAt(
                widget.session.controller?.value.position ?? Duration.zero,
              ))
                timeline.cues[index].text,
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  tr('字幕'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (_subtitles.length > 1)
                PopupMenuButton<String>(
                  tooltip: tr('字幕'),
                  initialValue: _subtitle,
                  onSelected: (value) {
                    if (value == _subtitle) return;
                    _subtitle = value;
                    _current = null;
                    unawaited(_load());
                  },
                  itemBuilder: (context) => [
                    for (final subtitle in _subtitles)
                      PopupMenuItem(
                        value: subtitle,
                        child: Text(subtitle.split('/').last),
                      ),
                  ],
                  icon: const Icon(Icons.subtitles_outlined),
                ),
            ],
          ),
        ),
        if (_error case final error?)
          SizedBox(
            height: 200,
            child: SourceErrorView(
              error: error,
              source: widget.session.work.source,
              onRetry: _load,
              compact: true,
            ),
          )
        else if (timeline == null)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          SizedBox(
            height: 240,
            child: Material(
              type: MaterialType.transparency,
              clipBehavior: Clip.hardEdge,
              child: AnimatedBuilder(
                animation: widget.session.playerUpdates,
                builder: (context, _) {
                  final active = timeline.activeAt(
                    widget.session.controller?.value.position ?? Duration.zero,
                  );
                  final selected = active.firstOrNull;
                  if (selected != _current) {
                    _current = selected;
                    if (selected != null) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted &&
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
                  return ScrollablePositionedList.builder(
                    key: ValueKey(_subtitle),
                    itemScrollController: _scroll,
                    itemCount: timeline.cues.length,
                    itemBuilder: (context, index) => ListTile(
                      selected: active.contains(index),
                      title: Text(timeline.cues[index].text),
                      onTap: () => widget.session.controller?.seekTo(
                        timeline.cues[index].start,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}

/// 全屏播放保留当前字幕；普通播放页提供完整的同步滚动列表。
class VoiceSubtitleOverlay extends StatelessWidget {
  const VoiceSubtitleOverlay({super.key, required this.cues});
  final List<String> cues;

  @override
  Widget build(BuildContext context) {
    if (cues.isEmpty) return const SizedBox.shrink();
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: Scrims.strong,
            borderRadius: Radii.small,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Gap.m,
              vertical: Gap.xs,
            ),
            child: Text(
              cues.join('\n'),
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ),
    );
  }
}
