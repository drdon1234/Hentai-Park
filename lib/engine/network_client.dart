import 'dart:convert';
import 'dart:io';

HttpClient createHttpClient({
  required String proxy,
  Uri? target,
  String? connectAddress,
}) {
  InternetAddress? endpoint;
  if (connectAddress != null) {
    endpoint = InternetAddress.tryParse(connectAddress);
    final b = endpoint?.rawAddress;
    if (target == null ||
        target.scheme != 'https' ||
        target.port != 443 ||
        target.userInfo.isNotEmpty ||
        endpoint?.type != InternetAddressType.IPv4 ||
        b == null ||
        b[0] == 0 ||
        b[0] == 10 ||
        b[0] == 127 ||
        b[0] >= 224 ||
        (b[0] == 100 && b[1] >= 64 && b[1] <= 127) ||
        (b[0] == 169 && b[1] == 254) ||
        (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
        (b[0] == 192 &&
            (b[1] == 168 || b[1] == 0 || (b[1] == 88 && b[2] == 99))) ||
        (b[0] == 198 &&
            (b[1] == 18 || b[1] == 19 || (b[1] == 51 && b[2] == 100))) ||
        (b[0] == 203 && b[1] == 0 && b[2] == 113)) {
      throw const FormatException('访问受限');
    }
  }
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    ..maxConnectionsPerHost = 8
    ..idleTimeout = const Duration(seconds: 30)
    ..autoUncompress = true;
  final address = proxy.replaceFirst(RegExp(r'^https?://'), '');
  if (address.isNotEmpty) client.findProxy = (_) => 'PROXY $address';
  if (endpoint != null) {
    // 仅替换 TCP 目的地址；TLS 仍使用原 URI 的主机名与系统信任链。
    final direct = endpoint;
    client.connectionFactory = (uri, proxyHost, proxyPort) async {
      if (proxyHost != null) return Socket.startConnect(proxyHost, proxyPort!);
      final task = await Socket.startConnect(
        uri.host == target!.host && uri.port == target.port ? direct : uri.host,
        uri.port,
      );
      Socket? connected;
      var cancelled = false;
      final socket = task.socket.then<Socket>((plain) async {
        connected = plain;
        if (cancelled) {
          plain.destroy();
          throw const SocketException('连接已取消');
        }
        if (uri.scheme == 'https') {
          try {
            connected = await SecureSocket.secure(
              plain,
              host: uri.host,
            ).timeout(const Duration(seconds: 15));
          } catch (_) {
            plain.destroy();
            rethrow;
          }
        }
        if (cancelled) {
          connected!.destroy();
          throw const SocketException('连接已取消');
        }
        return connected!;
      });
      return ConnectionTask.fromSocket(socket, () {
        cancelled = true;
        task.cancel();
        connected?.destroy();
      });
    };
  }
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
