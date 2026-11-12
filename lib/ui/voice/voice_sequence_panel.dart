import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../video/video_session.dart';
import 'voice_subtitles.dart';

/// 播放模式只改变时间轴展示，不预先打开其他曲目的媒体会话。
class VoiceSequencePanel extends StatelessWidget {
  const VoiceSequencePanel({super.key, required this.session});
  final VideoSession session;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: session,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: PopupMenuButton<bool>(
            tooltip: tr('播放设置'),
            onSelected: session.setJoinedVoice,
            itemBuilder: (_) => [
              for (final value in [false, true])
                CheckedPopupMenuItem(
                  value: value,
                  checked: session.joinedVoice == value,
                  child: Text(tr(value ? '拼接播放' : '分集播放')),
                ),
            ],
            icon: const Icon(Icons.tune_rounded),
          ),
        ),
        VoiceSubtitles(session: session),
      ],
    ),
  );
}
