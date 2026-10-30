/// 两种网络传输共用的重放边界。POST 必须由源确认无副作用；
/// 上传、登录和写操作不能仅根据调用页面的名称推断为只读。
bool isReplayableRead(
  String method, {
  Object? body,
  Object? bodyBase64,
  bool readOnly = false,
}) {
  if (bodyBase64 != null) return false;
  final verb = method.toUpperCase();
  return (body == null && {'GET', 'HEAD'}.contains(verb)) ||
      (readOnly && verb == 'POST' && body is String);
}
