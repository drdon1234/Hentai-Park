import 'dart:async';

/// 每个使用者持有独立队列；错误返回调用者，后续任务仍可继续。
class SerialExecutor {
  Future<void> _tail = Future.value();

  Future<void> get settled => _tail;

  Future<T> run<T>(FutureOr<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}

/// 在共享资源上限制并发，保留输入顺序以外的任务独立性。
Future<void> forEachConcurrent<T>(
  Iterable<T> values,
  int limit,
  Future<void> Function(T) action,
) async {
  final iterator = values.iterator;
  Future<void> worker() async {
    while (iterator.moveNext()) {
      final item = iterator.current;
      await action(item);
    }
  }

  await Future.wait(List.generate(limit, (_) => worker()));
}
