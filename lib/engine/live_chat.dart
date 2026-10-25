import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'live_chat_protocol.dart';
import 'live_chat_transport.dart';
import 'source_manager.dart';

enum LiveChatStatus { idle, connecting, connected, failed }

typedef LiveChatBootstrap = Future<Map<String, dynamic>> Function(
  CancelToken token,
);
typedef LiveChatDecode = Future<Map<String, dynamic>> Function(
  Map<String, dynamic> state,
  Map<String, dynamic> event,
  CancelToken token,
);

/// 每个播放器实例拥有一个会话；票据、协议状态与消息仅存在于内存。
class LiveChatSession extends ChangeNotifier {
  LiveChatSession({
    required this.source,
    required this.room,
    required this.domains,
    LiveChatBootstrap? bootstrap,
    LiveChatDecode? decode,
    LiveChatTransport Function(Map<String, dynamic>)? connect,
  }) : _bootstrap =
           bootstrap ??
           ((token) => SourceManager.instance.liveChat(
             source,
             room,
             cancelToken: token,
           )),
       _decode =
           decode ??
           ((state, event, token) => SourceManager.instance.liveChatEvent(
             source,
             state,
             event,
             cancelToken: token,
           )),
       _connect =
           connect ??
           ((descriptor) => NativeLiveChatTransport(
             source: source,
             domains: domains,
             descriptor: descriptor,
           ));
  final String source;
  final String room;
  final List<String> domains;
  final LiveChatBootstrap _bootstrap;
  final LiveChatDecode _decode;
  final LiveChatTransport Function(Map<String, dynamic>) _connect;
  LiveChatStatus status = LiveChatStatus.idle;
  final _messages = <LiveChatMessage>[];
  List<LiveChatMessage> get messages => List.unmodifiable(_messages);
  final _seen = <String>{};
  Map<String, dynamic> _state = {};
  LiveChatTransport? _transport;
  StreamSubscription<Map<String, dynamic>>? _subscription;
  CancelToken? _cancel;
  Timer? _retry;
  Timer? _deadline;
  Timer? _expiry;
  Timer? _heartbeat;
  final _receivedAt = <String, DateTime>{};
  bool _active = false;
  bool _disposed = false;
  bool _websocket = false;
  int _generation = 0;
  int _attempts = 0;
  int _pending = 0;
  Future<void> _queue = Future.value();

  void setActive(bool value) {
    if (_disposed || value == _active) return;
    _active = value;
    _stop();
    if (value) {
      _attempts = 0;
      unawaited(_start());
    } else {
      _messages.clear();
      _receivedAt.clear();
      status = LiveChatStatus.idle;
      notifyListeners();
    }
  }

  void retry() {
    if (!_active || _disposed) return;
    _stop();
    _attempts = 0;
    unawaited(_start());
  }

  bool _current(int generation) =>
      !_disposed && _active && generation == _generation;
  Future<void> _start() async {
    final generation = ++_generation;
    final token = _cancel = CancelToken();
    status = LiveChatStatus.connecting;
    notifyListeners();
    _deadline = Timer(const Duration(seconds: 25), () => _failed(generation));
    try {
      final descriptor = await _bootstrap(token);
      if (!_current(generation)) return;
      liveChatUri('${descriptor['url'] ?? ''}', domains);
      _websocket = descriptor['transport'] == 'websocket';
      final heartbeat = descriptor['heartbeatIntervalMs'];
      if (heartbeat != null &&
          (heartbeat is! int || heartbeat < 10000 || heartbeat > 60000)) {
        throw const FormatException();
      }
      _state = _boundedState(descriptor['state']);
      final transport = _transport = _connect(descriptor);
      _queue = Future.value();
      _pending = 0;
      void enqueue(Map<String, dynamic> event) {
        if (!_current(generation)) return;
        if (event['type'] == 'error' || _pending >= 32) {
          _failed(generation);
          return;
        }
        if (event['type'] != 'tick') _armDeadline(generation);
        if (event['type'] == 'heartbeat') return;
        _pending++;
        _queue = _queue
            .then((_) => _event(generation, event, token))
            .catchError((Object _) {
              _failed(generation);
            })
            .whenComplete(() {
              if (_current(generation)) _pending--;
            });
      }

      _subscription = transport.events.listen(
        enqueue,
        onError: (Object _) => _failed(generation),
        onDone: () => _failed(generation),
      );
      if (heartbeat is int) {
        _heartbeat = Timer.periodic(Duration(milliseconds: heartbeat), (_) {
          if (_current(generation) && status == LiveChatStatus.connected) {
            enqueue({'type': 'tick'});
          }
        });
      }
      _expiry ??= Timer.periodic(const Duration(seconds: 1), (_) => _expire());
    } catch (_) {
      _failed(generation);
    }
  }

  Map<String, dynamic> _boundedState(Object? state) {
    if (state is! Map || jsonEncode(state).length > 131072) {
      throw const FormatException();
    }
    return state.cast<String, dynamic>();
  }

  void _armDeadline(int generation) {
    // 未完成订阅的握手截止时间固定，心跳或通知不能无限延长它。
    if (status != LiveChatStatus.connected) return;
    _deadline?.cancel();
    // WebSocket 由传输层的 ping/pong 检查存活；安静房间没有聊天消息并非断线。
    if (_websocket) {
      _deadline = null;
      return;
    }
    _deadline = Timer(const Duration(seconds: 90), () => _failed(generation));
  }

  Future<void> _event(
    int generation,
    Map<String, dynamic> event,
    CancelToken token,
  ) async {
    if (!_current(generation)) return;
    final result = await _decode(_state, event, token);
    if (!_current(generation)) return;
    if (result['error'] == true) {
      _failed(generation);
      return;
    }
    _state = _boundedState(result['state']);
    final send = result['send'];
    if (send is List) {
      if (send.length > 10) throw const FormatException();
      for (final frame in send) {
        if (frame is! String || frame.length > 65536) {
          throw const FormatException();
        }
        _transport?.send(frame);
      }
    }
    if (result['connected'] == true) {
      status = LiveChatStatus.connected;
      _armDeadline(generation);
    }
    final messages = result['messages'];
    if (messages is List) {
      if (messages.length > 100) throw const FormatException();
      for (final row in messages.whereType<Map>()) {
        final id = row['id'], text = row['text'];
        if (id is! String ||
            id.isEmpty ||
            id.length > 4096 ||
            text is! String ||
            text.trim().isEmpty ||
            text.length > 2000 ||
            !_seen.add(id)) {
          continue;
        }
        if (_seen.length > 512) _seen.remove(_seen.first);
        if (row['isHistory'] == true) continue;
        final author = row['author'];
        _messages.add(
          LiveChatMessage(
            id: id,
            text: text,
            author: author is String && author.length <= 100 ? author : '',
          ),
        );
        _receivedAt[id] = DateTime.now();
        if (_messages.length > 40) {
          _receivedAt.remove(_messages.removeAt(0).id);
        }
      }
    }
    notifyListeners();
  }

  void _expire() {
    final cutoff = DateTime.now().subtract(const Duration(seconds: 12));
    final old = _messages.length;
    _messages.removeWhere(
      (message) => _receivedAt[message.id]?.isBefore(cutoff) ?? true,
    );
    _receivedAt.removeWhere((_, time) => time.isBefore(cutoff));
    if (_messages.length != old && !_disposed) notifyListeners();
  }

  void _failed(int generation) {
    if (!_current(generation)) return;
    _stop();
    _messages.clear();
    _receivedAt.clear();
    status = LiveChatStatus.failed;
    notifyListeners();
    if (_attempts < 3) {
      final seconds = [1, 3, 7][_attempts++];
      _retry = Timer(Duration(seconds: seconds), () {
        if (_active && !_disposed) unawaited(_start());
      });
    }
  }

  void _stop() {
    ++_generation;
    _cancel?.cancel('live chat stopped');
    _cancel = null;
    _retry?.cancel();
    _deadline?.cancel();
    _expiry?.cancel();
    _expiry = null;
    _heartbeat?.cancel();
    _heartbeat = null;
    _subscription?.cancel();
    _subscription = null;
    _transport?.close();
    _transport = null;
    _state = {};
  }

  @override
  void dispose() {
    _disposed = true;
    _active = false;
    _stop();
    _messages.clear();
    _seen.clear();
    _receivedAt.clear();
    super.dispose();
  }
}
