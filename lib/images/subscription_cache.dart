import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/async_tasks.dart';
import '../core/storage.dart';

/// 使用期间计数保护，所有清理都局限于可重建的附件缓存目录。
class SubscriptionCache {
  static final instance = SubscriptionCache();
  final _writes = SerialExecutor();
  final _pins = <String, int>{};
  Directory get directory =>
      Directory(p.join(AppPaths.cache.path, 'subscription_media'));
  String _path(File file) => p.normalize(p.absolute(file.path));
  void retain(File file) {
    final path = _path(file);
    if (!p.isWithin(p.absolute(directory.path), path)) return;
    _pins[path] = (_pins[path] ?? 0) + 1;
  }

  void release(File file) {
    final path = _path(file), count = _pins[_path(file)] ?? 0;
    if (count <= 1) {
      _pins.remove(path);
    } else {
      _pins[path] = count - 1;
    }
  }

  Future<List<(File, FileStat)>> _files() async {
    if (!await directory.exists()) return [];
    final files = <(File, FileStat)>[];
    await for (final file in directory.list(followLinks: false)) {
      if (file is File) {
        final stat = await file.stat();
        if (stat.type == FileSystemEntityType.file) files.add((file, stat));
      }
    }
    return files;
  }

  Future<int> size() => _writes.run(
    () async => (await _files()).fold<int>(0, (sum, e) => sum + e.$2.size),
  );
  Future<void> trim(int budget) => _writes.run(() async {
    final files = (await _files())
      ..sort((a, b) => a.$2.modified.compareTo(b.$2.modified));
    var size = files.fold<int>(0, (sum, e) => sum + e.$2.size);
    for (final e in files) {
      if (size <= budget) break;
      if (_pins.containsKey(_path(e.$1))) continue;
      try {
        await e.$1.delete();
        size -= e.$2.size;
      } on FileSystemException {
        /* 下次重试。 */
      }
    }
  });
  Future<void> clear() => trim(0);
}
