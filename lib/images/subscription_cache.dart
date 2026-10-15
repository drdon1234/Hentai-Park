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

  final _index = <String, ({int size, DateTime modified})>{};
  String? _indexedPath;
  int _bytes = 0;

  Future<void> _ensureIndex() async {
    final path = _path(File(directory.path));
    if (_indexedPath == path) return;
    final entries = <String, ({int size, DateTime modified})>{};
    var bytes = 0;
    if (await directory.exists()) {
      await for (final file in directory.list(followLinks: false)) {
        if (file is! File) continue;
        final stat = await file.stat();
        if (stat.type != FileSystemEntityType.file) continue;
        entries[_path(file)] = (size: stat.size, modified: stat.modified);
        bytes += stat.size;
      }
    }
    _index
      ..clear()
      ..addAll(entries);
    _bytes = bytes;
    _indexedPath = path;
  }

  /// 附件原子替换或删除后仅更新该文件，热路径不再遍历目录。
  Future<void> record(File file) => _writes.run(() async {
    if (!p.isWithin(p.absolute(directory.path), _path(file))) return;
    await _ensureIndex();
    _bytes -= _index.remove(_path(file))?.size ?? 0;
    final stat = await file.stat();
    if (stat.type == FileSystemEntityType.file) {
      _index[_path(file)] = (size: stat.size, modified: stat.modified);
      _bytes += stat.size;
    }
  });

  Future<int> size() => _writes.run(() async {
    await _ensureIndex();
    return _bytes;
  });

  Future<void> trim(int budget) => _writes.run(() async {
    await _ensureIndex();
    if (_bytes <= budget) return;
    final files = _index.entries.toList()
      ..sort((a, b) => a.value.modified.compareTo(b.value.modified));
    for (final entry in files) {
      if (_bytes <= budget) break;
      if (_pins.containsKey(entry.key)) continue;
      try {
        final file = File(entry.key);
        if (await file.exists()) await file.delete();
        _bytes -= _index.remove(entry.key)?.size ?? 0;
      } on FileSystemException {
        /* 下次重试。 */
      }
    }
  });
  Future<void> clear() => trim(0);
}
