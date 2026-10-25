import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../core/danmaku.dart';
import '../../core/localization.dart';
import '../../engine/live_chat.dart';
import '../../engine/live_chat_protocol.dart';
import '../kit/tokens.dart';
import '../theme.dart';
import 'danmaku_scheduler.dart';

/// 只读滚动弹幕；独立完成出屏，不受会话短期消息缓存清理影响。
class LiveChatOverlay extends StatefulWidget {
  const LiveChatOverlay({
    super.key,
    required this.session,
    this.vpnHint = false,
    this.area = DanmakuArea.topHalf,
  });
  final LiveChatSession session;
  final bool vpnHint;
  final DanmakuArea area;

  @override
  State<LiveChatOverlay> createState() => _LiveChatOverlayState();
}

class _LiveChatOverlayState extends State<LiveChatOverlay>
    with SingleTickerProviderStateMixin {
  final _scheduler = DanmakuScheduler();
  late final Ticker _ticker = createTicker(_tick);
  Duration _lastTick = Duration.zero;
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_changed);
  }

  @override
  void didUpdateWidget(covariant LiveChatOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      oldWidget.session.removeListener(_changed);
      widget.session.addListener(_changed);
      _clear(forget: true);
    } else if (oldWidget.area != widget.area) {
      _clear();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible = TickerMode.valuesOf(context).enabled;
    if (!_visible || MediaQuery.disableAnimationsOf(context)) _clear();
  }

  void _clear({bool forget = false}) {
    _scheduler.clear(forget: forget);
    _ticker.stop();
    _lastTick = Duration.zero;
  }

  void _changed() {
    if (widget.session.status != LiveChatStatus.connected) _clear();
    if (!_visible) {
      for (final message in widget.session.messages) {
        _scheduler.remember(message.id);
      }
    }
    setState(() {});
  }

  void _tick(Duration elapsed) {
    _scheduler.advance(elapsed - _lastTick);
    _lastTick = elapsed;
    if (!_scheduler.hasWork) {
      _ticker.stop();
      _lastTick = Duration.zero;
    }
    setState(() {});
  }

  @override
  void dispose() {
    widget.session.removeListener(_changed);
    _ticker.dispose();
    super.dispose();
  }

  String _statusLabel(String key) =>
      widget.vpnHint ? '${tr(key)} · ${tr('在中国大陆访问可能需要 VPN 或代理')}' : tr(key);

  String _text(LiveChatMessage message) {
    String compact(String value, int limit) {
      final text = value.replaceAll(RegExp(r'\s+'), ' ').trim();
      return text.characters.length > limit
          ? '${text.characters.take(limit)}…'
          : text;
    }

    final body = compact(message.text, 160),
        author = compact(message.author, 6);
    return author.isEmpty ? body : '$author: $body';
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.session.status;
    if (!_visible || status == LiveChatStatus.idle) {
      return const SizedBox.shrink();
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth, height = constraints.maxHeight;
        if (!width.isFinite ||
            !height.isFinite ||
            width <= 0 ||
            height <= 112) {
          _clear();
          return const SizedBox.shrink();
        }
        if (status != LiveChatStatus.connected) return _status(context);
        final style = context.text.bodyMedium!.copyWith(
          color: Scrims.onScrim,
          shadows: const [
            Shadow(blurRadius: 2, offset: Offset(1, 1)),
            Shadow(blurRadius: 2, offset: Offset(-1, -1)),
          ],
        );
        final scaler = MediaQuery.textScalerOf(context);
        final direction = Directionality.of(context);
        final measure = TextPainter(
          text: TextSpan(text: '弹幕 Ag', style: style),
          textDirection: direction,
          textScaler: scaler,
          maxLines: 1,
        )..layout();
        final rowHeight = measure.height + Gap.s;
        measure.dispose();
        // 区域按扣除控制栏后的可用画面计算，大字号至少保留一条完整轨道。
        final availableHeight = height - 112;
        final bandHeight = math.min(
          availableHeight,
          math.max(rowHeight, availableHeight * widget.area.fraction),
        );
        final bandTop = widget.area == DanmakuArea.bottomHalf
            ? height - 56 - bandHeight
            : 56.0;
        if (MediaQuery.disableAnimationsOf(context)) {
          for (final message in widget.session.messages) {
            _scheduler.remember(message.id);
          }
          return _reducedMotion(
            context,
            style,
            (bandHeight / rowHeight).floor().clamp(0, 4),
            bandTop,
            bandHeight,
          );
        }
        _scheduler.configure(
          width: width,
          height: bandHeight,
          rowHeight: rowHeight,
        );
        final lanePitch = _scheduler.laneCount > 1
            ? (bandHeight - rowHeight) / (_scheduler.laneCount - 1)
            : 0.0;
        for (final message in widget.session.messages) {
          if (_scheduler.contains(message.id)) continue;
          final text = _text(message);
          final painter = TextPainter(
            text: TextSpan(text: text, style: style),
            textDirection: direction,
            textScaler: scaler,
            maxLines: 1,
            ellipsis: '…',
          )..layout(maxWidth: width * 2);
          _scheduler.add(
            DanmakuEntry(
              id: message.id,
              text: text,
              width: painter.width.ceilToDouble() + 2,
            ),
          );
          painter.dispose();
        }
        if (_scheduler.hasWork && !_ticker.isActive) {
          _lastTick = Duration.zero;
          _ticker.start();
        }
        return IgnorePointer(
          child: RepaintBoundary(
            child: ClipRect(
              child: Stack(
                children: [
                  for (final flight in _scheduler.active)
                    Positioned(
                      key: ValueKey(flight.entry.id),
                      left: flight.x,
                      top: bandTop + flight.lane * lanePitch,
                      width: flight.entry.width,
                      height: rowHeight,
                      child: Text(
                        flight.entry.text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: style,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _status(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Gap.m, 56, Gap.m, 56),
    child: Align(
      alignment: AlignmentDirectional.topStart,
      child: widget.session.status == LiveChatStatus.failed
          ? TextButton.icon(
              onPressed: widget.session.retry,
              style: TextButton.styleFrom(
                foregroundColor: Scrims.onScrim,
                backgroundColor: Scrims.strong,
              ),
              icon: Tooltip(
                message: '${tr('重试弹幕')}\n${_statusLabel('弹幕连接失败')}',
                child: const Icon(Icons.refresh_rounded),
              ),
              label: Text(
                _statusLabel('弹幕连接失败'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            )
          : IgnorePointer(
              child: Tooltip(
                message: _statusLabel('弹幕连接中'),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Gap.s,
                    vertical: Gap.xs,
                  ),
                  decoration: const BoxDecoration(
                    color: Scrims.strong,
                    borderRadius: Radii.small,
                  ),
                  child: Text(
                    _statusLabel('弹幕连接中'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodySmall?.copyWith(
                      color: Scrims.onScrim,
                    ),
                  ),
                ),
              ),
            ),
    ),
  );

  Widget _reducedMotion(
    BuildContext context,
    TextStyle style,
    int lines,
    double top,
    double height,
  ) => IgnorePointer(
    child: Stack(
      children: [
        Positioned(
          top: top,
          height: height,
          left: Gap.m,
          right: Gap.m,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final message
                  in widget.session.messages.reversed
                      .take(lines)
                      .toList()
                      .reversed)
                Flexible(
                  child: Text(
                    _text(message),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: style,
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}
