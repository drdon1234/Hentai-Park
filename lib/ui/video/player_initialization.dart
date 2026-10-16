import 'dart:async';

import 'package:dio/dio.dart';
import 'package:video_player/video_player.dart';

import '../../engine/cancellation.dart';

/// 初始化超时或离开页面后停止等待；调用者负责释放播放器和媒体会话。
Future<void> initializePlayer(
  VideoPlayerController controller,
  CancelToken cancel,
) async {
  final deadline = CancelToken();
  final timer = Timer(
    const Duration(seconds: 30),
    () => deadline.cancel(TimeoutException('Video initialization timed out')),
  );
  try {
    await awaitCancelled(
      awaitCancelled(controller.initialize(), cancel),
      deadline,
    );
  } finally {
    timer.cancel();
  }
}
