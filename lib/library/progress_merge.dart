import 'dart:math' as math;

/// 漫画页码与视频位置分别选新值；已读状态以最近一次用户动作决定。
({bool comic, bool video, bool read}) selectProgress({
  required int? comic,
  required int? video,
  required int? currentComic,
  required int? currentVideo,
}) => (
  comic: comic != null && comic > (currentComic ?? -1),
  video: video != null && video > (currentVideo ?? -1),
  read:
      math.max(comic ?? -1, video ?? -1) >
      math.max(currentComic ?? -1, currentVideo ?? -1),
);
