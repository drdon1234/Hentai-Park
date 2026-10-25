import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import '../core/models.dart';
import '../core/settings.dart';
import 'cookie_store.dart';
import 'http_service.dart';
import 'live_chat_protocol.dart';
import 'network_client.dart';

/// 聊天启动 HTTP 使用独立域名权限，每次重定向都重新校验，错误不携带票据地址。
Future<Map<String, Object?>> liveChatRequest(
  Map<String, dynamic> options, {
  required String source,
  required List<String> domains,
  required CancelToken cancelToken,
}) async {
  try {
    final uri = liveChatUri('${options['url'] ?? ''}', domains);
    if (uri.scheme != 'https' || options['mode'] == 'browser') {
      throw const FormatException();
    }
    final method = '${options['method'] ?? 'GET'}'.toUpperCase();
    if (!{'GET', 'POST'}.contains(method)) throw const FormatException();
    final body = options['body']?.toString();
    if ((body?.length ?? 0) > 65536) throw const FormatException();
    final result = await HttpService.instance.send(
      method: method,
      url: uri.toString(),
      body: body,
      headers: _headers(options['headers']),
      partition: source,
      cancelToken: cancelToken,
      maxBytes: 262144,
      timeout: const Duration(seconds: 20),
      detectCloudflare: false,
      beforeRequest: (target) async {
        liveChatUri(target.toString(), domains);
        // 临时票据绝不跟随到其他主机，即使它也在聊天白名单中。
        if (target.host != uri.host || target.port != uri.port) {
          throw const FormatException();
        }
      },
    );
    return {'status': result.status, 'body': result.text};
  } catch (_) {
    throw SourceError('NETWORK', '弹幕连接失败');
  }
}

Map<String, String> _headers(Object? value) {
  if (value is! Map) return {};
  final result = <String, String>{};
  for (final entry in value.entries) {
    final name = entry.key.toString().toLowerCase();
    final text = entry.value.toString();
    if (!{'accept', 'content-type', 'origin', 'referer'}.contains(name) ||
        text.length > 2048 ||
        text.contains(RegExp(r'[\r\n]'))) {
      throw const FormatException('访问受限');
    }
    result[name] = text;
  }
  return result;
}

abstract class LiveChatTransport {
  Stream<Map<String, dynamic>> get events;
  void send(String data);
  void close();
}

/// 只读订阅传输。手动执行 WSS 升级以禁止自动重定向携带 Cookie 或短效票据。
class NativeLiveChatTransport implements LiveChatTransport {
  NativeLiveChatTransport({
    required this.source,
    required this.domains,
    required this.descriptor,
  }) {
    unawaited(_start());
  }
  final String source;
  final List<String> domains;
  final Map<String, dynamic> descriptor;
  final _events = StreamController<Map<String, dynamic>>();
  HttpClient? _client;
  HttpClientRequest? _request;
  Socket? _socket;
  WebSocket? _webSocket;
  StreamSubscription<dynamic>? _subscription;
  bool _closed = false;
  @override
  Stream<Map<String, dynamic>> get events => _events.stream;

  Future<void> _start() async {
    try {
      final uri = liveChatUri('${descriptor['url'] ?? ''}', domains);
      final ws = descriptor['transport'] == 'websocket';
      final protocols = liveChatProtocols(descriptor['protocols']);
      if ((descriptor.containsKey('binary') && descriptor['binary'] is! bool) ||
          (!ws && (protocols.isNotEmpty || descriptor['binary'] == true))) {
        throw const FormatException();
      }
      if ((ws && uri.scheme != 'wss') ||
          (!ws &&
              (descriptor['transport'] != 'sse' || uri.scheme != 'https'))) {
        throw const FormatException();
      }
      final client = _client = createHttpClient(
        proxy: AppSettings.instance.proxy,
      );
      final target = ws ? uri.replace(scheme: 'https') : uri;
      final cookie = await CookieStore.instance.headerFor(
        target,
        partition: source,
      );
      if (_closed) return;
      final request = _request = await client.getUrl(target);
      if (_closed) {
        request.abort();
        return;
      }
      request.followRedirects = false;
      request.headers.set(
        'User-Agent',
        HttpService.instance.userAgent,
        preserveHeaderCase: true,
      );
      for (final entry in _headers(descriptor['headers']).entries) {
        const names = {
          'accept': 'Accept',
          'content-type': 'Content-Type',
          'origin': 'Origin',
          'referer': 'Referer',
        };
        request.headers.set(
          names[entry.key]!,
          entry.value,
          preserveHeaderCase: true,
        );
      }
      if (cookie.isNotEmpty) {
        request.headers.set('Cookie', cookie, preserveHeaderCase: true);
      }
      String? nonce;
      if (ws) {
        final random = Random.secure();
        nonce = base64Encode(List.generate(16, (_) => random.nextInt(256)));
        request.headers
          ..set('Connection', 'Upgrade', preserveHeaderCase: true)
          ..set('Upgrade', 'websocket', preserveHeaderCase: true)
          ..set('Sec-WebSocket-Version', '13', preserveHeaderCase: true)
          ..set('Sec-WebSocket-Key', nonce, preserveHeaderCase: true);
        if (protocols.isNotEmpty) {
          request.headers.set(
            'Sec-WebSocket-Protocol',
            protocols.join(', '),
            preserveHeaderCase: true,
          );
        }
      } else {
        request.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
      }
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      if (_closed) return;
      if (ws) {
        final expected = base64Encode(
          sha1
              .convert(
                utf8.encode('${nonce!}258EAFA5-E914-47DA-95CA-C5AB0DC85B11'),
              )
              .bytes,
        );
        final protocol = response.headers.value('sec-websocket-protocol');
        if (response.statusCode != 101 ||
            response.headers.value('sec-websocket-accept') != expected ||
            response.headers.value('upgrade')?.toLowerCase() != 'websocket' ||
            (protocols.isEmpty
                ? protocol != null
                : !protocols.contains(protocol))) {
          throw const FormatException();
        }
        final socket = _socket = await response.detachSocket();
        if (_closed) {
          socket.destroy();
          return;
        }
        final webSocket = _webSocket = WebSocket.fromUpgradedSocket(
          socket,
          serverSide: false,
          protocol: protocol,
        );
        // 已声明应用协议保活的服务可能不实现 WebSocket 控制帧的 pong。
        // 其空闲期由协议 tick 维护，实际断开由传输层 error/close 报告。
        if (descriptor['heartbeatIntervalMs'] == null) {
          webSocket.pingInterval = const Duration(seconds: 30);
        }
        _subscription = webSocket.listen(
          (dynamic value) {
            try {
              final text = decodeLiveChatFrame(
                value,
                binary: descriptor['binary'] == true,
              );
              _emit({'type': 'message', 'data': text});
            } catch (_) {
              _fail();
            }
          },
          onError: (Object _) => _fail(),
          onDone: _fail,
        );
      } else {
        if (response.statusCode != 200 ||
            response.headers.contentType?.mimeType != 'text/event-stream') {
          throw const FormatException();
        }
        final parser = LiveChatSseParser();
        _subscription = response
            .transform(utf8.decoder)
            .listen(
              (chunk) {
                try {
                  for (final event in parser.add(chunk)) {
                    _emit(event);
                  }
                } catch (_) {
                  _fail();
                }
              },
              onError: (Object _) => _fail(),
              onDone: _fail,
            );
      }
      _emit({'type': 'open'});
    } catch (_) {
      _fail();
    }
  }

  void _emit(Map<String, dynamic> event) {
    if (!_closed) _events.add(event);
  }

  void _fail() {
    if (_closed) return;
    _events.add({'type': 'error'});
    close();
  }

  @override
  void send(String data) {
    if (_closed) return;
    if (_webSocket == null) {
      _fail();
      return;
    }
    try {
      _webSocket!.add(
        encodeLiveChatFrame(data, binary: descriptor['binary'] == true),
      );
    } catch (_) {
      _fail();
    }
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _request?.abort();
    _subscription?.cancel();
    _webSocket?.close();
    _socket?.destroy();
    _client?.close(force: true);
    unawaited(_events.close());
  }
}
