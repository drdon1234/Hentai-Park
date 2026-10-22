import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../core/content_translation.dart';
import '../core/storage.dart';
import '../engine/background_downloads.dart';
import 'text_layout.dart';

typedef _TranslationSpan = ({
  int originalStart,
  int originalEnd,
  int translatedStart,
  int translatedEnd,
});

/// 原文始终保留；段落/片段边界精确对应，片段内部的位置按长度比例近似。
class NovelTranslationDocument {
  NovelTranslationDocument._(this.original, List<_TranslationChunk> chunks) {
    final output = StringBuffer();
    for (final chunk in chunks) {
      final start = output.length;
      output.write(chunk.result ?? original.substring(chunk.start, chunk.end));
      _spans.add((
        originalStart: chunk.start,
        originalEnd: chunk.end,
        translatedStart: start,
        translatedEnd: output.length,
      ));
    }
    text = output.toString();
  }

  final String original;
  late final String text;
  final _spans = <_TranslationSpan>[];

  int originalOffset(int offset) => _map(offset, toOriginal: true);
  int translatedOffset(int offset) => _map(offset, toOriginal: false);

  int _map(int offset, {required bool toOriginal}) {
    final from = toOriginal ? text : original;
    final to = toOriginal ? original : text;
    offset = novelSafeOffset(from, offset);
    if (offset == from.length) return to.length;
    var low = 0, high = _spans.length;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      final end = toOriginal
          ? _spans[mid].translatedEnd
          : _spans[mid].originalEnd;
      if (end <= offset) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    if (low >= _spans.length) return 0;
    final span = _spans[low];
    final (fromStart, fromEnd, toStart, toEnd) = toOriginal
        ? (
            span.translatedStart,
            span.translatedEnd,
            span.originalStart,
            span.originalEnd,
          )
        : (
            span.originalStart,
            span.originalEnd,
            span.translatedStart,
            span.translatedEnd,
          );
    return novelSafeOffset(
      to,
      toStart +
          (offset - fromStart) * (toEnd - toStart) ~/ (fromEnd - fromStart),
    );
  }
}

/// 一章顺序翻译，成功片段可复用；取消后不再请求或向阅读器交付旧结果。
class NovelTranslationSession extends ChangeNotifier {
  NovelTranslationSession({
    required this.original,
    required this.locale,
    required this.engine,
    ContentTranslationQueue? queue,
  }) : _queue = queue ?? ContentTranslationQueue.instance,
       _chunks = _split(original);

  final String original, locale, engine;
  final ContentTranslationQueue _queue;
  final List<_TranslationChunk> _chunks;
  var _generation = 0;
  var _disposed = false;
  Completer<void>? _capacityWait;
  bool busy = false, failed = false;
  int completed = 0;
  late final int total = _chunks.where((chunk) => chunk.translate).length;
  NovelTranslationDocument? document;
  bool get complete => completed == total;
  bool persist = false;
  int? _requestedOffset;
  bool _full = false;
  Future<void>? _restoring;
  int _savedCompleted = -1;

  String get _cacheName =>
      'novel_translation_${sha256.convert(utf8.encode(jsonEncode([original, locale, engine])))}.json';

  Future<void> restore() => _restoring ??= _restore().whenComplete(() {
    _restoring = null;
  });

  Future<void> _restore() async {
    if (!persist || completed != 0) return;
    try {
      final saved = jsonDecode(
        await AppPaths.dataFile(_cacheName).readAsString(),
      );
      if (_disposed ||
          completed != 0 ||
          busy ||
          saved is! List ||
          saved.length != _chunks.length) {
        return;
      }
      for (var i = 0; i < _chunks.length; i++) {
        if (_chunks[i].translate && saved[i] is String) {
          _chunks[i].result = saved[i] as String;
          completed++;
        }
      }
      if (completed > 0) {
        document = NovelTranslationDocument._(original, _chunks);
      }
      _savedCompleted = completed;
    } catch (_) {
      // 没有已保存的译文时保留原文，继续在线翻译。
    }
  }

  Future<void> _save() async {
    if (!persist || _savedCompleted == completed) return;
    final saving = completed;
    await writeFileAtomic(
      AppPaths.dataFile(_cacheName),
      utf8.encode(jsonEncode(_chunks.map((c) => c.result).toList())),
    );
    _savedCompleted = saving;
  }

  Future<void> start({int? nearOffset}) async {
    _full = nearOffset == null;
    if (nearOffset != null) {
      _requestedOffset = nearOffset;
    }
    if (_disposed || busy) return;
    if (complete) {
      document ??= NovelTranslationDocument._(original, _chunks);
      try {
        await _save();
        failed = false;
      } catch (_) {
        failed = true;
      }
      if (!_disposed) notifyListeners();
      return;
    }
    final generation = ++_generation;
    bool active() => !_disposed && generation == _generation;
    busy = true;
    failed = false;
    notifyListeners();
    DownloadLease? lease;
    try {
      if (_full) lease = await BackgroundDownloads.instance.acquire();
      while (active()) {
        if (_full && lease == null) {
          lease = await BackgroundDownloads.instance.acquire();
        }
        lease?.check();
        final offset = _requestedOffset ?? 0;
        final pending = _chunks
            .where(
              (chunk) =>
                  chunk.result == null &&
                  (_full ||
                      (chunk.end > offset - 800 &&
                          chunk.start < offset + 2400)),
            )
            .toList();
        if (pending.isEmpty) {
          if (completed > 0) await _save();
          break;
        }
        if (!_full) {
          pending.sort(
            (a, b) =>
                (a.start - offset).abs().compareTo((b.start - offset).abs()),
          );
        }
        final chunk = pending.first;
        if (!active()) return;
        await _waitForCapacity(active);
        if (!active()) return;
        final result = await _queue.request(
          original.substring(chunk.start, chunk.end),
          locale,
          engine,
          isActive: active,
        );
        if (!active()) return;
        if (result == null) {
          failed = true;
          return;
        }
        chunk.result = result;
        completed++;
        document = NovelTranslationDocument._(original, _chunks);
        await _save();
        if (active()) notifyListeners();
      }
    } catch (_) {
      if (active()) failed = true;
    } finally {
      await lease?.release();
      if (active()) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> _waitForCapacity(bool Function() active) async {
    while (active() && !_queue.hasCapacity) {
      final ready = Completer<void>();
      _capacityWait = ready;
      void check() {
        if ((!active() || _queue.hasCapacity) && !ready.isCompleted) {
          ready.complete();
        }
      }

      _queue.addListener(check);
      try {
        check();
        await ready.future;
      } finally {
        _queue.removeListener(check);
        if (identical(_capacityWait, ready)) _capacityWait = null;
      }
    }
  }

  void cancel() {
    _generation++;
    final waiting = _capacityWait;
    if (waiting != null && !waiting.isCompleted) waiting.complete();
    busy = false;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    cancel();
    super.dispose();
  }
}

class _TranslationChunk {
  _TranslationChunk(this.start, this.end, {this.result})
    : translate = result == null;
  final int start, end;
  final bool translate;
  String? result;
}

List<_TranslationChunk> _split(String text) {
  final chunks = <_TranslationChunk>[];
  void verbatim(int start, int end) {
    if (end > start) {
      chunks.add(
        _TranslationChunk(start, end, result: text.substring(start, end)),
      );
    }
  }

  void paragraph(int start, int end) {
    while (start < end) {
      var limit = novelSafeOffset(text, math.min(start + 800, end));
      if (limit < end) {
        final piece = text.substring(start, limit);
        final boundaries = RegExp(r'[.!?。！？；;]\s*|\s+').allMatches(piece);
        for (final match in boundaries) {
          if (match.end >= piece.length ~/ 2) limit = start + match.end;
        }
      }
      final piece = text.substring(start, limit);
      final left = start + piece.length - piece.trimLeft().length;
      final right = math.max(
        left,
        limit - (piece.length - piece.trimRight().length),
      );
      verbatim(start, left);
      if (right > left) chunks.add(_TranslationChunk(left, right));
      verbatim(right, limit);
      start = limit;
    }
  }

  var cursor = 0;
  for (final boundary in RegExp(r'\n\s*\n').allMatches(text)) {
    paragraph(cursor, boundary.start);
    verbatim(boundary.start, boundary.end);
    cursor = boundary.end;
  }
  paragraph(cursor, text.length);
  return chunks;
}
