/// Domain helpers for per-source isolation: which sites a source declares, and whether a host
/// belongs to them.
library;

/// Two-label public suffixes common on the sites this app deals with. Hosts under them keep three labels.
const _multiLabelSuffixes = {
  'co.jp',
  'ne.jp',
  'or.jp',
  'com.cn',
  'net.cn',
  'org.cn',
  'com.tw',
  'net.tw',
  'com.hk',
  'co.kr',
  'co.uk',
  'com.au',
  'com.br', //
};

bool _isIp(String host) =>
    RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(host) || host.contains(':');

/// "www.e-hentai.org" → "e-hentai.org", "a.b.example.co.jp" → "example.co.jp". IPs are returned unchanged.
String registrableDomain(String host) {
  final h = host.toLowerCase().replaceAll(RegExp(r'\.$'), '');
  if (h.isEmpty || _isIp(h)) return h;
  final parts = h.split('.');
  if (parts.length <= 2) return h;
  final lastTwo = parts.sublist(parts.length - 2).join('.');
  final keep = _multiLabelSuffixes.contains(lastTwo) ? 3 : 2;
  return parts.sublist(parts.length - keep).join('.');
}

/// Whether [host] is one of [domains] or a subdomain of one.
bool hostInDomains(String host, Iterable<String> domains) {
  final h = host.toLowerCase();
  for (final d in domains) {
    final dd = d.toLowerCase();
    if (dd.isEmpty) continue;
    if (h == dd || h.endsWith('.$dd')) return true;
  }
  return false;
}

/// 站点文档与资源共用地址边界，具体路径和查询语义由插件判断。
bool httpsDomainAddressAllowed(Uri? uri, Iterable<String> domains) =>
    uri != null &&
    uri.scheme == 'https' &&
    uri.port == 443 &&
    uri.userInfo.isEmpty &&
    publicDomainHost(uri.host) &&
    hostInDomains(uri.host, domains);

bool publicDomainHost(String host) =>
    RegExp(r'^[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?\.[a-z]{2,}$').hasMatch(host) &&
    !host
        .split('.')
        .any(
          (label) =>
              label.isEmpty || label.startsWith('-') || label.endsWith('-'),
        ) &&
    host != 'localhost' &&
    !host.endsWith('.localhost') &&
    !host.endsWith('.local');

/// 仅识别评论中的站点引用；网络请求仍使用 HTTPS 权限策略。
bool contentLinkDomainAllowed(Uri uri, Iterable<String> domains) =>
    (uri.scheme == 'https' && uri.port == 443 ||
        uri.scheme == 'http' && uri.port == 80) &&
    uri.userInfo.isEmpty &&
    publicDomainHost(uri.host) &&
    hostInDomains(uri.host, domains);

/// The sites a source may use cookies / browser pages for: its explicit `domains`, otherwise
/// the registrable domains of its homepage, network origin and account URLs.
List<String> declaredDomains(Map<String, dynamic> manifest) {
  final explicit = manifest['domains'];
  if (explicit is List && explicit.isNotEmpty) {
    return {for (final d in explicit) d.toString().toLowerCase().trim()}
        .where((d) => d.isNotEmpty)
        .toList();
  }
  final account = manifest['account'] is Map
      ? (manifest['account'] as Map)
      : const {};
  final network = manifest['network'] is Map
      ? (manifest['network'] as Map)
      : const {};
  final urls = [
    manifest['homepage'],
    network['origin'],
    account['cookieUrl'],
    account['loginUrl'],
  ];
  final out = <String>{};
  for (final u in urls) {
    final host = Uri.tryParse('${u ?? ''}')?.host ?? '';
    if (host.isNotEmpty) out.add(registrableDomain(host));
  }
  return out.toList();
}

/// 登录页额外允许的授权主机；源站 Cookie 权限保持独立。
bool loginNavigationAllowed(Uri uri, Iterable<String> domains) =>
    httpsDomainAddressAllowed(uri, domains);
