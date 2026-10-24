import '../core/models.dart';

/// 仅验证浏览器中的可信验证码子框架；不授予源网络或 Cookie 权限。
bool challengeFrameNavigationAllowed(Uri uri, {required bool isForMainFrame}) =>
    !isForMainFrame &&
    uri.scheme == 'https' &&
    uri.host == 'challenges.cloudflare.com' &&
    uri.port == 443 &&
    uri.userInfo.isEmpty;

/// Cloudflare 防火墙按网络拒绝访问的错误页（“you have been blocked”）。
/// 它不是可通过的验证，浏览器重试也无法通过，需要用户更换网络或代理。
bool hasFirewallBlockMarkers(String body) =>
    body.contains('cf-error-details') &&
    RegExp(
      r'you have been blocked|why have i been blocked|error code:?\s*10(?:0[69]|20)\b',
      caseSensitive: false,
    ).hasMatch(body);

/// 站点防火墙拒绝当前网络时的统一错误。
SourceError firewallBlocked(String host, {String? url}) => SourceError(
  'BLOCKED',
  '站点拒绝了当前网络的访问，请更换网络或代理后重试',
  url: url,
  diagnostics: {'host': host, 'reason': 'FIREWALL_BLOCKED'},
);

/// 只识别页面标志；HTTP 响应头、状态、导航代次和验证完成条件由调用方判断。
/// 防火墙拦截页不算验证页。
bool hasChallengeMarkers(String body, {String title = ''}) {
  if (hasFirewallBlockMarkers(body)) return false;
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
  if (body.toLowerCase().contains('cloudflare') &&
      RegExp(
        r'^\s*(?:请稍候|請稍候|请稍等|請稍等|しばらくお待ちください|잠시만 기다리세요|Un momento|Einen Moment|Один момент|لحظة واحدة)(?:[\s.…!！]|$)',
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
