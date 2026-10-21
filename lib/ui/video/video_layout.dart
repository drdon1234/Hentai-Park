import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/platform_capabilities.dart';

/// 播放器与推荐始终位于主区；宽窗口仅将选集放入独立侧栏。
class VideoLayout extends StatefulWidget {
  const VideoLayout({
    super.key,
    required this.player,
    required this.header,
    required this.details,
    this.sidebar,
    this.fullscreen = false,
  });
  final Widget player;
  final Widget header;
  final Widget details;
  final Widget? sidebar;
  final bool fullscreen;
  @override
  State<VideoLayout> createState() => _VideoLayoutState();
}

class _VideoLayoutState extends State<VideoLayout> {
  final _playerKey = GlobalKey();
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final player = KeyedSubtree(key: _playerKey, child: widget.player);
      if (widget.fullscreen) return SizedBox.expand(child: player);
      final wide =
          widget.sidebar != null &&
          constraints.maxWidth >= 1000 &&
          constraints.maxHeight >= 560;
      final side = wide
          ? (constraints.maxWidth * .28).clamp(300.0, 380.0)
          : 0.0;
      final playerWidth = constraints.maxWidth - side;
      final playerHeight = math.min(
        playerWidth * 9 / 16,
        constraints.maxHeight * .68,
      );
      final stage = SizedBox(
        height: playerHeight,
        width: double.infinity,
        child: player,
      );
      final below = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          widget.header,
          if (!wide && widget.sidebar != null) widget.sidebar!,
          widget.details,
        ],
      );
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: PlatformCapabilities.desktop
                ? SingleChildScrollView(child: Column(children: [stage, below]))
                : Column(
                    children: [
                      stage,
                      Expanded(child: SingleChildScrollView(child: below)),
                    ],
                  ),
          ),
          if (wide) ...[
            const VerticalDivider(width: 1),
            SizedBox(
              width: side - 1,
              child: SingleChildScrollView(child: widget.sidebar!),
            ),
          ],
        ],
      );
    },
  );
}
