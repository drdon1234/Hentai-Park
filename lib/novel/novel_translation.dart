import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../core/content_translation.dart';
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
      output.write(chunk.result!);
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

  Future<void> start() async {
    if (_disposed || busy || document != null) return;
    final generation = ++_generation;
    bool active() => !_disposed && generation == _generation;
    busy = true;
    failed = false;
    notifyListeners();
    try {
      for (final chunk in _chunks) {
        if (!active()) return;
        if (chunk.result != null) continue;
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
        notifyListeners();
      }
      if (active()) document = NovelTranslationDocument._(original, _chunks);
    } finally {
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
