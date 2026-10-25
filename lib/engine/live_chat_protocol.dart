import 'dart:convert';

import 'domains.dart';

/// 聊天权限独立于站点页面、图片和媒体权限；非标准端口须逐主机声明。
Uri liveChatUri(String value, Iterable<String> domains) {
  final uri = Uri.tryParse(value);
  if (uri == null ||
      !{'https', 'wss'}.contains(uri.scheme) ||
      uri.userInfo.isNotEmpty ||
      uri.hasFragment ||
      !publicDomainHost(uri.host) ||
      !domains.any((endpoint) => _matchesEndpoint(uri, endpoint))) {
    throw const FormatException('访问受限');
  }
  return uri;
}

List<String> liveChatDomains(Map<String, dynamic> manifest) {
  final chat = manifest['chat'];
  final domains = chat is Map ? chat['domains'] : null;
  return domains is List
      ? domains.whereType<String>().where(_chatEndpoint).toSet().toList()
      : const [];
}

bool _chatEndpoint(String value) {
  final host = value.startsWith('*.') ? value.substring(2) : value;
  final uri = Uri.tryParse('https://$host');
  return uri != null &&
      uri.authority == host &&
      uri.userInfo.isEmpty &&
      uri.path.isEmpty &&
      !uri.hasQuery &&
      !uri.hasFragment &&
      publicDomainHost(uri.host) &&
      (uri.port == 443 || (uri.port >= 1024 && uri.port <= 65535));
}

bool _matchesEndpoint(Uri uri, String endpoint) {
  if (!_chatEndpoint(endpoint)) return false;
  final wildcard = endpoint.startsWith('*.');
  final allowed = Uri.parse(
    'https://${wildcard ? endpoint.substring(2) : endpoint}',
  );
  if ((uri.hasPort ? uri.port : 443) != allowed.port) return false;
  if (!wildcard) return uri.host == allowed.host;
  final suffix = '.${allowed.host}';
  if (!uri.host.endsWith(suffix)) return false;
  final label = uri.host.substring(0, uri.host.length - suffix.length);
  return label.isNotEmpty && !label.contains('.');
}

List<String> liveChatProtocols(Object? value) {
  if (value == null) return const [];
  if (value is! List || value.length > 8) throw const FormatException();
  final result = <String>[];
  for (final protocol in value) {
    if (protocol is! String ||
        protocol.isEmpty ||
        protocol.length > 128 ||
        !RegExp(r"^[!#$%&'*+\-.^_`|~0-9A-Za-z]+$").hasMatch(protocol) ||
        result.contains(protocol)) {
      throw const FormatException();
    }
    result.add(protocol);
  }
  return result;
}

String decodeLiveChatFrame(Object? value, {required bool binary}) {
  if (binary) {
    if (value is! List<int> || value.length > 65536) {
      throw const FormatException();
    }
    return utf8.decode(value);
  }
  if (value is! String || utf8.encode(value).length > 65536) {
    throw const FormatException();
  }
  return value;
}

Object encodeLiveChatFrame(String value, {required bool binary}) {
  final bytes = utf8.encode(value);
  if (bytes.length > 65536) throw const FormatException();
  return binary ? bytes : value;
}

/// UTF-8 解码由流处理器负责；这里保留不完整行并限制单条事件大小。
class LiveChatSseParser {
  String _pending = '';
  String _event = '';
  final _data = <String>[];
  int _size = 0;
  bool _comment = false;

  List<Map<String, dynamic>> add(String chunk) {
    _pending += chunk;
    final result = <Map<String, dynamic>>[];
    while (true) {
      final end = _pending.indexOf(RegExp(r'[\r\n]'));
      if (end < 0 || (end == _pending.length - 1 && _pending[end] == '\r')) {
        break;
      }
      final line = _pending.substring(0, end);
      final skip =
          _pending[end] == '\r' &&
              _pending.length > end + 1 &&
              _pending[end + 1] == '\n'
          ? 2
          : 1;
      _pending = _pending.substring(end + skip);
      _size += line.length;
      if (_size > 65536) throw const FormatException('直播数据无效');
      if (line.isEmpty) {
        if (_data.isNotEmpty) {
          result.add({
            'type': 'message',
            'event': _event.isEmpty ? 'message' : _event,
            'data': _data.join('\n'),
          });
        } else if (_comment) {
          result.add({'type': 'heartbeat'});
        }
        _data.clear();
        _event = '';
        _size = 0;
        _comment = false;
      } else if (line.startsWith(':')) {
        _comment = true;
      } else {
        final colon = line.indexOf(':');
        final field = colon < 0 ? line : line.substring(0, colon);
        var value = colon < 0 ? '' : line.substring(colon + 1);
        if (value.startsWith(' ')) value = value.substring(1);
        if (field == 'event') _event = value;
        if (field == 'data') _data.add(value);
      }
    }
    if (_pending.length + _size > 65536) throw const FormatException('直播数据无效');
    return result;
  }
}

class LiveChatMessage {
  const LiveChatMessage({
    required this.id,
    required this.text,
    this.author = '',
  });
  final String id;
  final String text;
  final String author;
}
