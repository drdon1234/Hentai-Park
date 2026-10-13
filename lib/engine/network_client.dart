import 'dart:convert';
import 'dart:io';

HttpClient createHttpClient({required String proxy}) {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    ..maxConnectionsPerHost = 8
    ..idleTimeout = const Duration(seconds: 30)
    ..autoUncompress = true;
  final address = proxy.replaceFirst(RegExp(r'^https?://'), '');
  if (address.isNotEmpty) client.findProxy = (_) => 'PROXY $address';
  return client;
}

/// 独立客户端不继承源 Cookie/认证；禁重定向、限制解压后大小并净化错误。
Future<String> readPublicText(
  String url, {
  required int maxBytes,
  required String proxy,
}) async {
  if (maxBytes < 1) throw ArgumentError.value(maxBytes, 'maxBytes');
  final client = createHttpClient(proxy: proxy);
  const timeout = Duration(seconds: 20);
  try {
    final uri = Uri.parse(url);
    if (!['https', 'http'].contains(uri.scheme) || uri.userInfo.isNotEmpty) {
      throw const FormatException('公开资源地址无效');
    }
    final request = await client.getUrl(uri).timeout(timeout);
    request.followRedirects = false;
    final response = await request.close().timeout(timeout);
    if (response.statusCode != 200 || response.contentLength > maxBytes) {
      throw const FormatException('公开资源下载失败');
    }
    final bytes = <int>[];
    await for (final chunk in response.timeout(timeout)) {
      if (bytes.length + chunk.length > maxBytes) {
        throw const FormatException('公开资源过大');
      }
      bytes.addAll(chunk);
    }
    return utf8.decode(bytes);
  } catch (_) {
    throw const FormatException('公开资源网络请求失败');
  } finally {
    client.close(force: true);
  }
}
