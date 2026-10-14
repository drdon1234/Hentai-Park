import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'translator.dart';

typedef ContentTranslate = Future<String?> Function(
  String text,
  String target,
  String engine,
);

typedef _Key = ({String text, String target, String engine});

/// 页面可见内容共享的有限翻译队列，原始内容始终由调用方保留。
class ContentTranslationQueue extends ChangeNotifier {
  ContentTranslationQueue({ContentTranslate? translate})
    : _translate = translate ?? _translateDefault;

  static final instance = ContentTranslationQueue();
  static const maxTextLength = 1000;
  static const _maxConcurrent = 2;
  static const _maxQueued = 32;
  static const _maxCached = 512;

  final ContentTranslate _translate;
  final _cache = <_Key, String>{};
  final _pending = <_Key, _Job>{};
  final _queue = Queue<_Job>();
  var _running = 0;
  var _pumpScheduled = false;
  bool get hasCapacity => _queue.length < _maxQueued;

  /// 可见页面恢复时读取已有译文，不占用网络队列容量。
  String? cached(String text, String locale, String engine) {
    final target = normalizeSearchLanguage(locale);
    if (target == null) return null;
    final key = (text: text, target: target, engine: engine);
    final value = _cache.remove(key);
    if (value != null) _cache[key] = value;
    return value;
  }

  static Future<String?> _translateDefault(
    String text,
    String target,
    String engine,
  ) async {
    final result = await Translator.instance.translateAll(text, [
      target,
    ], engine: engine);
    return result.translations[target];
  }

  /// 无有效结果、取消或队列已满时返回 null，调用方继续显示原文。
  /// 超过 [maxTextLength] 的内容须由调用方按段提交，不静默截断。
  /// [isActive] 应同时检查页面存活、目标语言和当前展示模式。
  Future<String?> request(
    String text,
    String locale,
    String engine, {
    bool Function()? isActive,
  }) {
    final waiter = _Waiter(isActive);
    final target = normalizeSearchLanguage(locale);
    if (text.trim().isEmpty ||
        text.length > maxTextLength ||
        target == null ||
        !waiter.active) {
      return Future.value();
    }
    final key = (text: text, target: target, engine: engine);
    final translated = cached(text, locale, engine);
    if (translated != null) return Future.value(translated);
    final existing = _pending[key];
    if (existing != null) {
      existing.waiters.add(waiter);
      return waiter.result.future;
    }
    _discardInactive();
    if (_queue.length >= _maxQueued) return Future.value();
    final job = _Job(key, waiter);
    _pending[key] = job;
    _queue.add(job);
    _schedulePump();
    return waiter.result.future;
  }

  void _schedulePump() {
    if (_pumpScheduled) return;
    _pumpScheduled = true;
    scheduleMicrotask(() {
      _pumpScheduled = false;
      _discardInactive();
      while (_running < _maxConcurrent && _queue.isNotEmpty) {
        final job = _queue.removeFirst();
        _running++;
        unawaited(_run(job));
      }
      if (hasCapacity) notifyListeners();
    });
  }

  void _discardInactive() {
    final discarded = _queue
        .where((job) => !job.waiters.any((waiter) => waiter.active))
        .toList();
    for (final job in discarded) {
      _queue.remove(job);
      _pending.remove(job.key);
      _complete(job, null);
    }
  }

  Future<void> _run(_Job job) async {
    String? translated;
    try {
      translated = (await _translate(
        job.key.text,
        job.key.target,
        job.key.engine,
      ))?.trim();
      if (translated == null || translated.isEmpty) {
        translated = null;
      } else {
        _cache[job.key] = translated;
        if (_cache.length > _maxCached) _cache.remove(_cache.keys.first);
      }
    } catch (_) {
      // 失败不缓存；显式重试可再次请求，日志不包含待翻译内容。
    } finally {
      _running--;
      _pending.remove(job.key);
      _complete(job, translated);
      _schedulePump();
    }
  }

  void _complete(_Job job, String? text) {
    for (final waiter in job.waiters) {
      waiter.result.complete(waiter.active ? text : null);
    }
  }
}

class _Job {
  _Job(this.key, _Waiter waiter) : waiters = [waiter];
  final _Key key;
  final List<_Waiter> waiters;
}

class _Waiter {
  _Waiter(this.isActive);
  final bool Function()? isActive;
  final result = Completer<String?>();

  bool get active {
    try {
      return isActive?.call() ?? true;
    } catch (_) {
      return false;
    }
  }
}
