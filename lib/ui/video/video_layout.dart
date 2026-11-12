import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/platform_capabilities.dart';

/// 播放器与作品信息保持同列，多集作品在信息区保留选集入口。
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
      final playerWidth = constraints.maxWidth;
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
        children: [widget.header, widget.details],
      );
      return PlatformCapabilities.desktop
          ? SingleChildScrollView(child: Column(children: [stage, below]))
          : Column(
              children: [
                stage,
                Expanded(child: SingleChildScrollView(child: below)),
              ],
            );
    },
  );
}
