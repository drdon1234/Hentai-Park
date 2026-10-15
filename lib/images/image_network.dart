import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../core/models.dart';
import '../engine/browser_media.dart';
import '../engine/cancellation.dart';
import '../engine/domains.dart';
import '../engine/media_transport.dart';

/// 源按需声明图片浏览器传输；复用有界二进制传输，不携带账号凭据。
MediaTransport? createImageTransport(
  SourceManifest? manifest, {
  Map<String, String> headers = const {},
  String? partition,
}) {
  final declaration = manifest?.json['imageNetwork'];
  if (declaration == null) return null;
  if (declaration is! Map || declaration['mode'] != 'browser') {
    throw SourceError('CONFIG', '站点没有声明有效的媒体权限');
  }
  final domains = declaration['domains'];
  final sourceDomains = declaredDomains(manifest!.json);
  final origin = Uri.tryParse('${declaration['origin'] ?? ''}');
  if (domains is! List ||
      domains.isEmpty ||
      domains.any((d) => d is! String || !hostInDomains(d, sourceDomains)) ||
      origin == null ||
      !hostInDomains(origin.host, domains.cast<String>())) {
    throw SourceError('CONFIG', '站点没有声明有效的媒体权限');
  }
  final policy = MediaPolicy.fromManifest(
    SourceManifest({
      ...manifest.json,
      'media': Map<String, dynamic>.from(declaration),
    }),
  );
  final validatedHeaders = policy.requestHeaders(headers);
  return _ImageLease(
    imageTransportIdentity(
      manifest,
      validatedHeaders,
      partition ?? manifest.key,
    ),
    policy,
    validatedHeaders,
  );
}

String imageTransportIdentity(
  SourceManifest manifest,
  Map<String, String> headers,
  String partition,
) {
  final sorted = headers.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  return jsonEncode([
    partition,
    manifest.key,
    manifest.version,
    manifest.json['imageNetwork'],
    declaredDomains(manifest.json),
    {for (final e in sorted) e.key: e.value},
  ]);
}

final _sessions = <String, _ImageSession>{};
final _epochs = <String, int>{};
int imageTransportGeneration(String source) =>
    _epochs.putIfAbsent(source, () => 0);
Completer<void> _changed = Completer<void>();
void _wake() {
  final previous = _changed;
  _changed = Completer<void>();
  previous.complete();
}

/// 权限、设置或源发生变化时中止旧会话，等待中的旧租约也不得重新创建。
Future<void> invalidateImageTransports([String? source]) async {
  final keys = {
    ..._epochs.keys,
    ..._sessions.values.map((s) => s.media.policy.site),
  };
  for (final key in keys) {
    if (source == null || key == source) _epochs[key] = (_epochs[key] ?? 0) + 1;
  }
  final removed = _sessions.entries
      .where((e) => source == null || e.value.media.policy.site == source)
      .toList();
  for (final e in removed) {
    _sessions.remove(e.key);
    e.value.idle?.cancel();
  }
  _wake();
  await Future.wait(removed.map((e) => e.value.media.close()));
}

class _ImageSession {
  _ImageSession(this.media);
  final BrowserMedia media;
  int users = 0;
  Timer? idle;
}

class _ImageLease implements MediaTransport {
  _ImageLease(this.key, this.policy, this.headers)
    : epoch = _epochs.putIfAbsent(policy.site, () => 0);
  final String key;
  @override
  final MediaPolicy policy;
  final Map<String, String> headers;
  final int epoch;
  final _closed = CancelToken();
  @override
  void validate(Uri url) => policy.validate(url);

  void _check() {
    if (_closed.cancelError case final error?) throw error;
    if (epoch != _epochs[policy.site]) {
      throw SourceError('CANCELLED', '媒体会话已关闭');
    }
  }

  @override
  Future<MediaResponse> fetch(
    Uri url, {
    required int maxBytes,
    CancelToken? cancelToken,
  }) async {
    validate(url);
    final token = CancelToken();
    final external = cancelToken?.whenCancel.asStream().listen(token.cancel);
    final closed = _closed.whenCancel.asStream().listen(token.cancel);
    if (cancelToken?.cancelError case final error?) token.cancel(error);
    _ImageSession? session;
    try {
      while (session == null) {
        _check();
        if (token.cancelError case final error?) throw error;
        final existing = _sessions[key];
        if (existing != null && existing.media.isClosed) {
          _sessions.remove(key);
          existing.idle?.cancel();
        }
        session = _sessions[key];
        if (session == null && _sessions.length >= 4) {
          final idle = _sessions.entries
              .where((e) => e.value.users == 0)
              .firstOrNull;
          if (idle != null) {
            _sessions.remove(idle.key);
            idle.value.idle?.cancel();
            await idle.value.media.close();
            continue;
          }
          await awaitCancelled(_changed.future, token);
          continue;
        }
        session ??= _sessions.putIfAbsent(
          key,
          () => _ImageSession(
            BrowserMedia(policy, headers: headers, concurrentRequests: true),
          ),
        );
        session.idle?.cancel();
        session.users++;
      }
      final result = await session.media.fetch(
        url,
        maxBytes: maxBytes,
        cancelToken: token,
      );
      _check();
      return result;
    } finally {
      await external?.cancel();
      await closed.cancel();
      if (session != null) {
        session.users--;
        if (session.users == 0 && identical(_sessions[key], session)) {
          final owned = session;
          session.idle = Timer(const Duration(seconds: 30), () {
            if (!identical(_sessions[key], owned)) return;
            _sessions.remove(key);
            owned.media.close().ignore();
            _wake();
          });
        }
        _wake();
      }
    }
  }

  @override
  Future<void> close() async => _closed.cancel();
}
