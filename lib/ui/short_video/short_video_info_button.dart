import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../kit/tokens.dart';
import '../theme.dart';

/// 清屏操作始终留在右下角，与时间轴共用一行。
class ShortVideoInfoButton extends StatelessWidget {
  const ShortVideoInfoButton({
    super.key,
    required this.showInfo,
    required this.onPressed,
  });

  final bool showInfo;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    toggled: !showInfo,
    child: TextButton.icon(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: Scrims.onScrim,
        backgroundColor: Scrims.control,
        textStyle: context.text.labelSmall,
        minimumSize: const Size(48, 36),
        padding: const EdgeInsets.symmetric(horizontal: Gap.s),
        shape: const RoundedRectangleBorder(borderRadius: Radii.small),
        iconSize: 18,
      ),
      icon: Icon(
        showInfo ? Icons.subtitles_off_outlined : Icons.subtitles_outlined,
      ),
      label: Text(tr(showInfo ? '仅视频' : '带信息')),
    ),
  );
}
