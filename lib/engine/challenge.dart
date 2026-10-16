/// 仅验证浏览器中的可信验证码子框架；不授予源网络或 Cookie 权限。
bool challengeFrameNavigationAllowed(Uri uri, {required bool isForMainFrame}) =>
    !isForMainFrame &&
    uri.scheme == 'https' &&
    uri.host == 'challenges.cloudflare.com' &&
    uri.port == 443 &&
    uri.userInfo.isEmpty;

/// 只识别页面标志；HTTP 响应头、状态、导航代次和验证完成条件由调用方判断。
bool hasChallengeMarkers(String body, {String title = ''}) {
  final pageTitle = title.isNotEmpty
      ? title
      : RegExp(
              r'<title[^>]*>([^<]*)</title>',
              caseSensitive: false,
            ).firstMatch(body)?.group(1) ??
            '';
  if (RegExp(
    r'^\s*(?:Just a moment|Attention Required)(?:\b|\s|\.)',
    caseSensitive: false,
  ).hasMatch(pageTitle)) {
    return true;
  }
  // 检测脚本也会注入正常内容页，只有验证配置或验证表单才表示拦截。
  return RegExp(
        r'(?:window\.)?_cf_chl_opt\s*=|id\s*=\s*["\x27](?:challenge-form|cf-challenge-running)["\x27]',
        caseSensitive: false,
      ).hasMatch(body) ||
      (!body.contains('<') &&
          RegExp(
            r'^\s*(?:Just a moment|Attention Required)\b',
            caseSensitive: false,
          ).hasMatch(body));
}
