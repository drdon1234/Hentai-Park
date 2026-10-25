import 'dart:collection';
import 'dart:math' as math;

/// 已测量的单行弹幕；调度器只处理几何与时间，不依赖播放器或站点。
class DanmakuEntry {
  const DanmakuEntry({
    required this.id,
    required this.text,
    required this.width,
  });
  final String id, text;
  final double width;
}

class DanmakuFlight {
  DanmakuFlight(this.entry, this.lane, this.x);
  final DanmakuEntry entry;
  final int lane;
  double x;
}

class DanmakuScheduler {
  static const maxPending = 24;
  static const maxActive = 16;
  static const maxWait = Duration(seconds: 4);
  static const gap = 28.0;
  final _pending = Queue<({DanmakuEntry entry, Duration received})>();
  final _seen = <String>{};
  final _active = <DanmakuFlight>[];
  Duration _now = Duration.zero;
  double _width = 0, _height = 0, _rowHeight = 0;
  int _nextLane = 0;
  int get laneCount =>
      _rowHeight <= 0 ? 0 : (_height / _rowHeight).floor().clamp(0, 4);
  double get speed => (_width / 6).clamp(60, 140);
  double get rowHeight => _rowHeight;
  List<DanmakuFlight> get active => List.unmodifiable(_active);
  int get pendingCount => _pending.length;
  bool get hasWork => _active.isNotEmpty || _pending.isNotEmpty;
  bool contains(String id) => _seen.contains(id);

  /// 旋转或字号变化后重新排轨；旧消息不倒播，也不挤进新的窄轨。
  void configure({
    required double width,
    required double height,
    required double rowHeight,
  }) {
    if (_width == width && _height == height && _rowHeight == rowHeight) return;
    clear();
    _width = width.isFinite ? math.max(0, width) : 0;
    _height = height.isFinite ? math.max(0, height) : 0;
    _rowHeight = rowHeight.isFinite ? math.max(0, rowHeight) : 0;
  }

  bool remember(String id) {
    if (!_seen.add(id)) return false;
    if (_seen.length > 1024) _seen.remove(_seen.first);
    return true;
  }

  void add(DanmakuEntry entry) {
    if (!remember(entry.id) ||
        laneCount == 0 ||
        _width <= 0 ||
        !entry.width.isFinite ||
        entry.width <= 0) {
      return;
    }
    if (_pending.length == maxPending) _pending.removeFirst();
    _pending.add((entry: entry, received: _now));
    _dispatch();
  }

  void advance(Duration elapsed) {
    if (elapsed <= Duration.zero) return;
    _now += elapsed;
    final distance =
        speed * elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    for (final flight in _active) {
      flight.x -= distance;
    }
    _active.removeWhere((flight) => flight.x + flight.entry.width <= 0);
    _pending.removeWhere((item) => _now - item.received > maxWait);
    _dispatch();
  }

  void _dispatch() {
    if (laneCount == 0) return;
    while (_pending.isNotEmpty && _active.length < maxActive) {
      int? available;
      for (var offset = 0; offset < laneCount; offset++) {
        final lane = (_nextLane + offset) % laneCount;
        // 全部弹幕速度一致：前一条的尾端已经留出距离，之后便不会追尾。
        if (_active
            .where((flight) => flight.lane == lane)
            .every((flight) => flight.x + flight.entry.width + gap <= _width)) {
          available = lane;
          break;
        }
      }
      if (available == null) break;
      _active.add(
        DanmakuFlight(_pending.removeFirst().entry, available, _width),
      );
      _nextLane = (available + 1) % laneCount;
    }
  }

  void clear({bool forget = false}) {
    _pending.clear();
    _active.clear();
    _nextLane = 0;
    if (forget) _seen.clear();
  }
}
