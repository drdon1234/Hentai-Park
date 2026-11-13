/// 未来记录视作时钟回拨后需要重新执行，避免任务无限期等待。
/// 直接比较经过时间，不在 DateTime 上相加，支持持久化时间戳的边界值。
bool intervalElapsed(
  int previousMilliseconds,
  Duration interval, {
  DateTime? now,
}) {
  final current = (now ?? DateTime.now()).millisecondsSinceEpoch;
  return previousMilliseconds <= 0 ||
      previousMilliseconds > current ||
      current - previousMilliseconds >= interval.inMilliseconds;
}
