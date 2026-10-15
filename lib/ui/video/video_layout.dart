import 'package:flutter/material.dart';

/// 等高的信息区域让播放器保持居中；切换全屏时保留播放器的元素位置。
class VideoLayout extends StatelessWidget {
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
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (!fullscreen &&
          constraints.maxWidth >= 1000 &&
          constraints.maxHeight >= 480) {
        return Row(
          children: [
            Expanded(
              child: Center(
                child: AspectRatio(aspectRatio: 16 / 9, child: player),
              ),
            ),
            SizedBox(
              width: (constraints.maxWidth * .32).clamp(320.0, 440.0),
              child: Column(
                children: [
                  Expanded(child: header),
                  Expanded(child: details),
                ],
              ),
            ),
          ],
        );
      }
      final playerHeight = (constraints.maxWidth * 9 / 16).clamp(
        0.0,
        constraints.maxHeight * .6,
      );
      final informationHeight = fullscreen
          ? 0.0
          : (constraints.maxHeight - playerHeight) / 2;
      return Column(
        children: [
          SizedBox(
            height: informationHeight,
            child: fullscreen ? null : header,
          ),
          Expanded(child: player),
          SizedBox(
            height: informationHeight,
            child: fullscreen ? null : details,
          ),
        ],
      );
    },
  );
}
