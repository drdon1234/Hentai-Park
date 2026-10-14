import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/localization.dart';

/// 视觉轨道保持轻量，但整个56像素底部区域始终可触摸拖动。
class AdaptiveVideoProgress extends StatefulWidget {
  const AdaptiveVideoProgress({
    super.key,
    required this.position,
    required this.duration,
    this.buffered = Duration.zero,
    required this.onSeek,
    this.onScrubbingChanged,
  });
  final Duration position, duration, buffered;
  final ValueChanged<Duration> onSeek;
  final ValueChanged<bool>? onScrubbingChanged;
  @override
  State<AdaptiveVideoProgress> createState() => _AdaptiveVideoProgressState();
}

class _AdaptiveVideoProgressState extends State<AdaptiveVideoProgress> {
  bool _expanded = false, _hovered = false, _scrubbing = false;
  double? _preview;
  Timer? _collapse;

  void _expand() {
    _collapse?.cancel();
    if (!_expanded) setState(() => _expanded = true);
  }

  void _release() {
    _collapse?.cancel();
    _collapse = Timer(const Duration(milliseconds: 1200), () {
      if (mounted && !_hovered && !_scrubbing) {
        setState(() => _expanded = false);
      }
    });
  }

  void _cancel() {
    if (_scrubbing) {
      setState(() {
        _scrubbing = false;
        _preview = null;
      });
      widget.onScrubbingChanged?.call(false);
    }
    _release();
  }

  @override
  void dispose() {
    _collapse?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.duration.inMilliseconds.toDouble();
    final position = (_preview ?? widget.position.inMilliseconds.toDouble())
        .clamp(0.0, total > 0 ? total : 1.0);
    final buffered = widget.buffered.inMilliseconds.toDouble().clamp(
      0.0,
      total > 0 ? total : 1.0,
    );
    return MouseRegion(
      onEnter: (_) {
        _hovered = true;
        _expand();
      },
      onExit: (_) {
        _hovered = false;
        _release();
      },
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => _expand(),
        onPointerUp: (_) => _release(),
        onPointerCancel: (_) => _cancel(),
        child: SizedBox(
          height: 56,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: _expanded ? 8 : 2,
              thumbShape: RoundSliderThumbShape(
                enabledThumbRadius: _expanded ? 9 : 3,
              ),
              overlayShape: const RoundSliderOverlayShape(),
              activeTrackColor: Colors.white,
              inactiveTrackColor: Colors.white24,
              secondaryActiveTrackColor: Colors.white54,
              thumbColor: Colors.white,
              overlayColor: Colors.white24,
              showValueIndicator: ShowValueIndicator.onDrag,
            ),
            child: Slider(
              value: position,
              max: total > 0 ? total : 1,
              secondaryTrackValue: buffered > position ? buffered : position,
              label:
                  '${(position / 60000).floor()}:${((position / 1000).floor() % 60).toString().padLeft(2, '0')}',
              semanticFormatterCallback: (value) =>
                  tr('播放进度 {seconds} 秒', {'seconds': (value / 1000).round()}),
              onChangeStart: total <= 0
                  ? null
                  : (_) {
                      _scrubbing = true;
                      _expand();
                      widget.onScrubbingChanged?.call(true);
                    },
              onChanged: total <= 0
                  ? null
                  : (value) => setState(() => _preview = value),
              onChangeEnd: total <= 0
                  ? null
                  : (value) {
                      widget.onSeek(Duration(milliseconds: value.round()));
                      setState(() {
                        _preview = null;
                        _scrubbing = false;
                      });
                      widget.onScrubbingChanged?.call(false);
                      _release();
                    },
            ),
          ),
        ),
      ),
    );
  }
}
