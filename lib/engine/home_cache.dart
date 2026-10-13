import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../core/async_tasks.dart';
import '../core/storage.dart';
import '../core/models.dart';

class HomeCacheResult {
  const HomeCacheResult(this.data, {this.stale = false});
  final Map<String, dynamic> data;
  final bool stale;
}

/// 仅管理可重建的主页元数据，容量和删除范围均与媒体、离线内容分离。
class HomeCache {
  HomeCache({
    Directory? directory,
    DateTime Function()? clock,
    this.budget = 32 * 1024 * 1024,
  })
    // 保留可注入的公开 directory 参数，生产环境使用独立 AppPaths 目录。
    // ignore: prefer_initializing_formals
    : _directory = directory,
       _clock = clock ?? DateTime.now;
  static final instance = HomeCache();
  static const lifetime = Duration(minutes: 15);
  final Directory? _directory;
  final DateTime Function() _clock;
  final int budget;
  final _disk = SerialExecutor();
  final _pending = <String, Future<HomeCacheResult>>{};
  final _refreshes = <String, int>{};
  int _requestSequence = 0;
  int _generation = 0;
  Directory get directory =>
      _directory ?? Directory(p.join(AppPaths.cache.path, 'home_metadata'));

  static Object? _canonical(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((k) => k.toString()).toList()..sort();
      return {for (final key in keys) key: _canonical(value[key])};
    }
    if (value is List) return value.map(_canonical).toList();
    return value;
  }

  Future<HomeCacheResult> request(
    List<Object?> identity,
    Future<Map<String, dynamic>> Function() load, {
    bool refresh = false,
    String requestGroup = 'foreground',
    bool Function(Map<String, dynamic>)? shouldCache,
    Map<String, dynamic> Function(Map<String, dynamic>)? serialize,
  }) {
    // 网络/会话原值只参与摘要，不进入文件名、正文或诊断日志。
    final key = sha256
        .convert(utf8.encode(jsonEncode(_canonical(identity))))
        .toString();
    final generation = _generation;
    final pendingKey =
        '${directory.path}/$generation/$key/$refresh/$requestGroup';
    final existing = _pending[pendingKey];
    if (existing != null) return existing;
    if (refresh || requestGroup == 'foreground') {
      _refreshes[key] = ++_requestSequence;
    }
    final sequence = _refreshes[key] ?? 0;
    return _pending[pendingKey] ??=
        _request(
          key,
          generation,
          load,
          refresh,
          shouldCache,
          serialize,
          sequence,
        ).whenComplete(() {
          _pending.remove(pendingKey);
          if (!_pending.keys.any((pending) => pending.contains('/$key/'))) {
            _refreshes.remove(key);
          }
        });
  }

  Future<HomeCacheResult> _request(
    String key,
    int generation,
    Future<Map<String, dynamic>> Function() load,
    bool refresh,
    bool Function(Map<String, dynamic>)? shouldCache,
    Map<String, dynamic> Function(Map<String, dynamic>)? serialize,
    int sequence,
  ) async {
    final root = directory;
    final file = File(p.join(root.path, '$key.json'));
    final cached = await _disk.run(() async {
      try {
        if (!await file.exists()) return null;
        if (await file.length() > budget) {
          await file.delete();
          return null;
        }
        final entry = jsonDecode(await file.readAsString());
        if (entry is! Map ||
            entry['written'] is! int ||
            entry['data'] is! Map) {
          return null;
        }
        await file.setLastModified(_clock());
        return (
          written: DateTime.fromMillisecondsSinceEpoch(entry['written']),
          data: (entry['data'] as Map).cast<String, dynamic>(),
        );
      } on FileSystemException {
        return null;
      } on FormatException {
        return null;
      }
    });
    if (!refresh &&
        cached != null &&
        _clock().difference(cached.written) < lifetime) {
      return HomeCacheResult(cached.data);
    }
    Map<String, dynamic> data;
    try {
      data = await load();
    } on SourceError catch (error) {
      if ({'NETWORK', 'TIMEOUT'}.contains(error.code) &&
          !refresh &&
          cached != null &&
          generation == _generation) {
        return HomeCacheResult(cached.data, stale: true);
      }
      rethrow;
    }
    if (shouldCache?.call(data) == false) return HomeCacheResult(data);
    final bytes = utf8.encode(
      jsonEncode({
        'written': _clock().millisecondsSinceEpoch,
        'data': serialize?.call(data) ?? data,
      }),
    );
    // 缓存写入失败不得使已成功的主页网络读取失败。
    try {
      await _disk.run(() async {
        if (generation != _generation ||
            (_refreshes[key] ?? 0) != sequence ||
            bytes.length > budget) {
          return;
        }
        await root.create(recursive: true);
        await writeFileAtomic(
          file,
          bytes,
          canCommit: () =>
              generation == _generation && (_refreshes[key] ?? 0) == sequence,
        );
        await _trim(root);
      });
    } on FileSystemException {
      /* 可重建缓存，保留网络结果。 */
    }
    return HomeCacheResult(data);
  }

  Future<List<(File, FileStat)>> _files(Directory root) async {
    if (!await root.exists()) return [];
    final files = <(File, FileStat)>[];
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        files.add((entity, await entity.stat()));
      } on FileSystemException {
        /* 并发清理。 */
      }
    }
    return files;
  }

  Future<void> _trim(Directory root) async {
    final files = await _files(root)
      ..sort((a, b) => a.$2.modified.compareTo(b.$2.modified));
    var bytes = files.fold(0, (sum, file) => sum + file.$2.size);
    for (final file in files) {
      if (bytes <= budget) break;
      await file.$1.delete();
      bytes -= file.$2.size;
    }
  }

  Future<int> size() => _disk.run(
    () async =>
        (await _files(directory))
            .fold<int>(0, (sum, file) => sum + file.$2.size),
  );

  Future<void> clear() {
    _generation++;
    final root = directory;
    return _disk.run(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
  }
}
