const officialRawBase =
    'https://raw.githubusercontent.com/drdon1234/Hentai-Park';
final _digest = RegExp(r'^[a-fA-F0-9]{64}$');
final _commit = RegExp(r'^[a-fA-F0-9]{40}$');

bool isSha256(Object? value) =>
    value is String && _digest.stringMatch(value) == value;

/// 固定官方仓库提交；具体资产路径由调用方提供，禁止查询参数及重定向地址。
bool isOfficialAsset(Object? value, String relativePath) {
  if (value is! String) return false;
  final url = Uri.tryParse(value);
  if (url == null ||
      url.scheme != 'https' ||
      url.host != 'raw.githubusercontent.com' ||
      url.userInfo.isNotEmpty ||
      url.hasQuery ||
      url.hasFragment ||
      url.port != 443) {
    return false;
  }
  final parts = url.pathSegments;
  return parts.length >= 4 &&
      parts[0] == 'drdon1234' &&
      parts[1] == 'Hentai-Park' &&
      _commit.stringMatch(parts[2]) == parts[2] &&
      value == '$officialRawBase/${parts[2]}/$relativePath';
}
