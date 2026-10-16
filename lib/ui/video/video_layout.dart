import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 播放器在主区顶部，作品信息自然排列；宽屏提供独立的选集与推荐栏。
class VideoLayout extends StatefulWidget {
  const VideoLayout({
    super.key,
    required this.player,
    required this.header,
    required this.details,
    this.fullscreen = false,
  });
  final Widget player;
  final Widget header;
  final Widget details;
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
      final wide = constraints.maxWidth >= 1000 && constraints.maxHeight >= 560;
      final side = wide
          ? (constraints.maxWidth * .28).clamp(300.0, 380.0)
          : 0.0;
      final playerWidth = constraints.maxWidth - side;
      final playerHeight = math.min(
        playerWidth * 9 / 16,
        constraints.maxHeight * .68,
      );
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              children: [
                SizedBox(
                  height: playerHeight,
                  width: double.infinity,
                  child: player,
                ),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [widget.header, if (!wide) widget.details],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (wide) ...[
            const VerticalDivider(width: 1),
            SizedBox(
              width: side - 1,
              child: SingleChildScrollView(child: widget.details),
            ),
          ],
        ],
      );
    },
  );
}
