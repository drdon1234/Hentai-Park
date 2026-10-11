import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/models.dart';
import '../../engine/source_manager.dart';
import '../../library/downloads.dart';
import '../../library/library.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/error_view.dart';
import '../widgets/paged_grid.dart';

class VideoPage extends StatefulWidget {
  const VideoPage({super.key, required this.work});
  final WorkDetail work;

  @override
  State<VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<VideoPage> {
  VideoPlayerController? _c;
  List<VideoSource> _sources = [];
  VideoSource? _current;
  Object? _error;
  bool _offline = false;
  bool _controls = true;
  bool _fullscreen = false;
  double _speed = 1;
  Timer? _hide;
  Timer? _savePos;
  String? _seekHint;

  static bool get _supported => Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _init();
  }

  @override
  void dispose() {
    _savePosition();
    _hide?.cancel();
    _savePos?.cancel();
    _c?.dispose();
    WakelockPlus.disable();
    SystemChrome.setPreferredOrientations([]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _init() async {
    setState(() => _error = null);
    try {
      final local = await DownloadManager.instance.localVideo(widget.work.source, widget.work.id);
      if (local != null) {
        _offline = true;
        await _open(VideoPlayerController.file(local));
        return;
      }
      final sources = await SourceManager.instance.videos(widget.work.source, widget.work.id);
      if (!mounted) return;
      _sources = sources;
      await _play(sources.firstWhere((s) => s.preferred, orElse: () => sources.first));
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _play(VideoSource s, {Duration? at}) async {
    _current = s;
    if (!_supported) {
      setState(() {});
      return;
    }
    await _open(VideoPlayerController.networkUrl(Uri.parse(s.url), httpHeaders: s.headers), at: at);
  }

  Future<void> _open(VideoPlayerController c, {Duration? at}) async {
    final old = _c;
    setState(() => _c = null);
    await old?.dispose();
    try {
      await c.initialize();
    } catch (e) {
      await c.dispose();
      if (mounted) setState(() => _error = SourceError('NETWORK', '视频加载失败：$e'));
      return;
    }
    if (!mounted) {
      await c.dispose();
      return;
    }
    final resume = at ?? _resumePoint(c.value.duration);
    if (resume != null) await c.seekTo(resume);
    await c.setPlaybackSpeed(_speed);
    await c.play();
    c.addListener(_onTick);
    setState(() => _c = c);
    _savePos = Timer.periodic(const Duration(seconds: 10), (_) => _savePosition());
    _scheduleHide();
  }

  Duration? _resumePoint(Duration total) {
    final pos = Library.instance.historyOf(widget.work.uid)?.position;
    if (pos == null || pos < 5 || pos > total.inSeconds - 10) return null;
    return Duration(seconds: pos);
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  void _savePosition() {
    final c = _c;
    if (c == null || !c.value.isInitialized) return;
    Library.instance.recordVideoPosition(widget.work.toItem(), c.value.position.inSeconds);
  }

  void _scheduleHide() {
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 3), () {
      if (mounted && (_c?.value.isPlaying ?? false)) setState(() => _controls = false);
    });
  }

  void _toggleControls() {
    setState(() => _controls = !_controls);
    if (_controls) _scheduleHide();
  }

  Future<void> _seekBy(int seconds) async {
    final c = _c;
    if (c == null) return;
    final target = c.value.position + Duration(seconds: seconds);
    await c.seekTo(target < Duration.zero ? Duration.zero : target);
    setState(() => _seekHint = seconds > 0 ? '+${seconds}s' : '${seconds}s');
    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _seekHint = null);
    });
  }

  Future<void> _toggleFullscreen() async {
    setState(() => _fullscreen = !_fullscreen);
    if (_fullscreen) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    } else {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      await SystemChrome.setPreferredOrientations([]);
    }
  }

  Future<void> _switchQuality() async {
    if (_sources.length < 2) return;
    final picked = await showModalBottomSheet<VideoSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text('清晰度', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            for (final s in _sources)
              ListTile(
                leading: Icon(s == _current ? Icons.radio_button_checked : Icons.radio_button_off),
                title: Text(s.label),
                onTap: () => Navigator.pop(ctx, s),
              ),
          ],
        ),
      ),
    );
    if (picked != null && picked != _current) {
      final pos = _c?.value.position;
      await _play(picked, at: pos);
    }
  }

  Future<void> _pickSpeed() async {
    const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
    final picked = await showModalBottomSheet<double>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text('播放速度', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            for (final s in speeds)
              ListTile(
                leading: Icon(s == _speed ? Icons.radio_button_checked : Icons.radio_button_off),
                title: Text('${s}x'),
                onTap: () => Navigator.pop(ctx, s),
              ),
          ],
        ),
      ),
    );
    if (picked != null) {
      _speed = picked;
      await _c?.setPlaybackSpeed(picked);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = _player(context);
    if (_fullscreen) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _toggleFullscreen();
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Center(child: player),
        ),
      );
    }
    final d = widget.work;
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            player,
            Expanded(
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(d.title, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 6),
                          Text(
                            [
                              if (d.authors.isNotEmpty) d.authors.join(' / '),
                              if (d.views != null) '${formatCount(d.views)} 次观看',
                              if (d.uploaded.isNotEmpty) d.uploaded,
                              if (_offline) '离线播放',
                              if (_current != null) _current!.label,
                            ].join(' · '),
                            style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (d.series.isNotEmpty)
                    SliverToBoxAdapter(
                      child: WorkCarousel(title: '同系列', items: d.series),
                    ),
                  if (d.related.isNotEmpty)
                    SliverToBoxAdapter(
                      child: WorkCarousel(title: '相关推荐', items: d.related),
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 32)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _player(BuildContext context) {
    final c = _c;
    Widget inner;
    if (_error != null) {
      inner = Theme(
        data: ParkTheme.build(Brightness.dark, context.colors.primary),
        child: SourceErrorView(error: _error!, source: widget.work.source, onRetry: _init, compact: true),
      );
    } else if (!_supported && _current != null) {
      inner = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('当前平台不支持内置播放', style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: () => launchUrl(Uri.parse(_current!.url), mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.open_in_new_rounded),
              label: Text('用外部播放器打开（${_current!.label}）'),
            ),
          ],
        ),
      );
    } else if (c == null || !c.value.isInitialized) {
      inner = Center(child: LoadingIndicator(label: _sources.isEmpty && !_offline ? '正在获取视频地址…' : '正在缓冲…', color: Colors.white70));
    } else {
      inner = Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: AspectRatio(aspectRatio: c.value.aspectRatio, child: VideoPlayer(c)),
          ),
          if (c.value.isBuffering) const Center(child: CircularProgressIndicator(color: Colors.white70)),
          // Double-tap the left/right half to seek; single tap toggles the controls.
          Row(
            children: [
              Expanded(
                child: GestureDetector(behavior: HitTestBehavior.translucent, onTap: _toggleControls, onDoubleTap: () => _seekBy(-10)),
              ),
              Expanded(
                child: GestureDetector(behavior: HitTestBehavior.translucent, onTap: _toggleControls, onDoubleTap: () => _seekBy(10)),
              ),
            ],
          ),
          if (_seekHint != null)
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
                child: Text(
                  _seekHint!,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          AnimatedOpacity(
            opacity: _controls ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            child: IgnorePointer(ignoring: !_controls, child: _controlsOverlay(c)),
          ),
        ],
      );
    }
    final box = ColoredBox(color: Colors.black, child: inner);
    if (_fullscreen) return box;
    return AspectRatio(aspectRatio: 16 / 9, child: box);
  }

  Widget _controlsOverlay(VideoPlayerController c) {
    final v = c.value;
    final total = v.duration.inMilliseconds.toDouble();
    final pos = v.position.inMilliseconds.clamp(0, total).toDouble();
    final buffered = v.buffered.isEmpty ? 0.0 : v.buffered.last.end.inMilliseconds.toDouble();
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black54, Colors.transparent, Colors.transparent, Colors.black87],
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                onPressed: () => _fullscreen ? _toggleFullscreen() : Navigator.maybePop(context),
              ),
              Expanded(
                child: Text(
                  widget.work.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ),
              if (_sources.length > 1)
                TextButton(
                  onPressed: _switchQuality,
                  child: Text(_current?.label ?? '', style: const TextStyle(color: Colors.white)),
                ),
              TextButton(
                onPressed: _pickSpeed,
                child: Text('${_speed}x', style: const TextStyle(color: Colors.white)),
              ),
            ],
          ),
          const Spacer(),
          IconButton(
            iconSize: 56,
            icon: Icon(v.isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded, color: Colors.white),
            onPressed: () {
              v.isPlaying ? c.pause() : c.play();
              _scheduleHide();
            },
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Text(_fmt(v.position), style: const TextStyle(color: Colors.white, fontSize: 12)),
                Expanded(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (total > 0)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: LinearProgressIndicator(
                            value: (buffered / total).clamp(0, 1),
                            minHeight: 2,
                            backgroundColor: Colors.white24,
                            color: Colors.white38,
                          ),
                        ),
                      Slider(
                        value: pos,
                        max: total > 0 ? total : 1,
                        onChanged: (x) {
                          c.seekTo(Duration(milliseconds: x.round()));
                          _scheduleHide();
                        },
                        activeColor: Theme.of(context).colorScheme.primary,
                        inactiveColor: Colors.transparent,
                      ),
                    ],
                  ),
                ),
                Text(_fmt(v.duration), style: const TextStyle(color: Colors.white, fontSize: 12)),
                IconButton(
                  icon: Icon(_fullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded, color: Colors.white),
                  onPressed: _toggleFullscreen,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _fmt(Duration d) {
    final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
    final mm = m.toString().padLeft(2, '0'), ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }
}
