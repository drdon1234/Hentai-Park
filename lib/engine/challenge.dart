/// 只识别页面标志；HTTP 响应头、状态、导航代次和验证完成条件由调用方判断。
bool hasChallengeMarkers(String body, {String title = ''}) => [title, body].any(
  (text) => const [
    'Just a moment',
    'Attention Required',
    'challenge-platform',
    'cf-chl',
  ].any(text.contains),
);
