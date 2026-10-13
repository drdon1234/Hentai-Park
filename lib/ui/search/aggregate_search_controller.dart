import 'dart:async';
import 'dart:collection';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/models.dart';

typedef AggregateLoader = Future<WorkPage> Function(
  String source,
  CancelToken token,
);

class AggregateResult {
  WorkPage? page;
  Object? error;
  bool loading = true;
}

/// 提交即调度全部站点，与列表构建无关。每轮持有自己的取消和并发状态。
class AggregateSearchController extends ChangeNotifier {
  final results = <String, AggregateResult>{};
  _SearchRun? _run;
  bool _disposed = false;

  void start(Iterable<String> sources, AggregateLoader loader) {
    if (_disposed) return;
    reset();
    final run = _SearchRun(loader, sources.toSet());
    _run = run;
    for (final source in run.queue) {
      results[source] = AggregateResult();
    }
    notifyListeners();
    _pump(run);
  }

  void reset() {
    _run?.token.cancel();
    _run = null;
    results.clear();
  }

  void retry(String source) {
    final run = _run;
    if (_disposed || run == null || results[source]?.loading != false) return;
    results[source] = AggregateResult();
    run.queue.add(source);
    notifyListeners();
    _pump(run);
  }

  bool _current(_SearchRun run) => !_disposed && identical(run, _run);
  void _pump(_SearchRun run) {
    while (_current(run) && run.active < 4 && run.queue.isNotEmpty) {
      final source = run.queue.removeFirst();
      run.active++;
      unawaited(_load(run, source));
    }
  }

  Future<void> _load(_SearchRun run, String source) async {
    try {
      final page = await run.loader(source, run.token);
      if (_current(run)) results[source]!.page = page;
    } catch (e) {
      if (_current(run)) results[source]!.error = e;
    } finally {
      run.active--;
      if (_current(run)) {
        results[source]!.loading = false;
        notifyListeners();
        _pump(run);
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    reset();
    super.dispose();
  }
}

class _SearchRun {
  _SearchRun(this.loader, Iterable<String> sources) : queue = Queue.of(sources);
  final AggregateLoader loader;
  final Queue<String> queue;
  final token = CancelToken();
  int active = 0;
}
