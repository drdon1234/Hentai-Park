import 'dart:async';

import 'package:dio/dio.dart';

/// 只取消等待；底层操作的终止和资源释放仍由持有者负责。
Future<T> awaitCancelled<T>(Future<T> work, CancelToken? token) async {
  if (token == null) return work;
  final result = Completer<T>();
  void fail(Object error, [StackTrace? stack]) {
    if (!result.isCompleted) result.completeError(error, stack);
  }

  work.then((value) {
    if (!result.isCompleted) result.complete(value);
  }, onError: (Object error, StackTrace stack) => fail(error, stack));
  final subscription = token.whenCancel.asStream().listen(fail);
  if (token.cancelError case final error?) fail(error);
  try {
    return await result.future;
  } finally {
    await subscription.cancel();
  }
}
