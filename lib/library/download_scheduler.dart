import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/settings.dart';

/// 所有作品下载共用站点和任务额度，取消中的任务在退出前继续占用额度。
class DownloadScheduler extends ChangeNotifier {
  DownloadScheduler({required this.siteLimit, required this.taskLimit});

  static final instance = DownloadScheduler(
    siteLimit: () => AppSettings.instance.downloadSiteConcurrency,
    taskLimit: () => AppSettings.instance.downloadTaskConcurrency,
  );

  final int Function() siteLimit;
  final int Function() taskLimit;
  final _active = <String, int>{};

  DownloadSlot? tryAcquire(String source) {
    final count = _active[source] ?? 0;
    if (count >= taskLimit() || count == 0 && _active.length >= siteLimit()) {
      return null;
    }
    _active[source] = count + 1;
    return DownloadSlot._(() {
      final remaining = _active[source]! - 1;
      if (remaining == 0) {
        _active.remove(source);
      } else {
        _active[source] = remaining;
      }
      // 等调用方移除旧任务和 Future 后再补位，避免完成回调重入。
      scheduleMicrotask(notifyListeners);
    });
  }
}

class DownloadSlot {
  DownloadSlot._(this._release);
  void Function()? _release;

  void release() {
    final release = _release;
    _release = null;
    release?.call();
  }
}
