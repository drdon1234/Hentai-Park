import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../core/storage.dart';

/// 单个播放会话的临时磁盘缓存：保存已经下载过的媒体字节，往回拖动时直接读取。
/// 文件只属于这次会话，关闭播放即删除；进程首次使用时清理上次异常退出的残留。
class _CacheFile {
  _CacheFile._(this._file, this._handle);

  static const limit = 1024 * 1024 * 1024;
  static Future<void>? _sweep;

  static Future<_CacheFile?> open() async {
    try {
      final root = Directory(p.join(AppPaths.cache.path, 'playback'));
      await (_sweep ??= () async {
        if (await root.exists()) await root.delete(recursive: true);
      }().catchError((Object _) {}));
      await root.create(recursive: true);
      final file = File(p.join(root.path, const Uuid().v4()));
      return _CacheFile._(file, await file.open(mode: FileMode.write));
    } catch (_) {
      // 缓存只是加速；无法创建时按原方式直接播放。
      return null;
    }
  }

  final File _file;
  final RandomAccessFile _handle;
  Future<void> _queue = Future.value();
  bool closed = false;

  /// 文件句柄不支持并发操作，读写按顺序执行。
  Future<T> _serial<T>(Future<T> Function() operation) {
    final result = _queue.then((_) => operation());
    _queue = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<bool> write(int offset, List<int> bytes) => _serial(() async {
    if (closed) return false;
    await _handle.setPosition(offset);
    await _handle.writeFrom(bytes);
    return true;
  });

  Future<Uint8List> read(int offset, int length) => _serial(() async {
    if (closed) throw const FileSystemException('Playback cache closed');
    await _handle.setPosition(offset);
    return _handle.read(length);
  });

  Future<void> close() {
    closed = true;
    return _serial(() async {
      try {
        await _handle.close();
      } finally {
        if (await _file.exists()) await _file.delete();
      }
    }).catchError((Object _) {});
  }
}

/// 直链文件按字节区间缓存；未缓存的空洞再向上游请求。
class ByteRangeCache {
  ByteRangeCache._(this._file);

  static Future<ByteRangeCache?> open() async {
    final file = await _CacheFile.open();
    return file == null ? null : ByteRangeCache._(file);
  }

  final _CacheFile _file;

  /// 已缓存区间，按起点排序且互不相邻，均为 [start, end)。
  final List<(int, int)> _ranges = [];
  int _bytes = 0;
  int? length;
  String? contentType;

  int get cachedBytes => _bytes;

  /// [offset] 所在缓存区间的结束位置；未缓存时返回 [offset]。
  int cachedEnd(int offset) {
    for (final (start, end) in _ranges) {
      if (start > offset) break;
      if (offset < end) return end;
    }
    return offset;
  }

  /// [offset] 之后第一个缓存区间的起点，用于限定向上游补齐的范围。
  int? nextCached(int offset) {
    for (final (start, _) in _ranges) {
      if (start > offset) return start;
    }
    return null;
  }

  Future<void> store(int offset, Uint8List bytes) async {
    if (bytes.isEmpty || _file.closed) return;
    final end = offset + bytes.length;
    if (length case final total? when end > total) return;
    if (_bytes + bytes.length > _CacheFile.limit && cachedEnd(offset) < end) {
      return;
    }
    if (!await _file.write(offset, bytes)) return;
    _add(offset, end);
  }

  Future<Uint8List> read(int offset, int length) => _file.read(offset, length);

  void _add(int start, int end) {
    final merged = <(int, int)>[];
    var s = start, e = end;
    var inserted = false;
    for (final range in _ranges) {
      if (range.$2 < s) {
        merged.add(range);
      } else if (range.$1 > e) {
        if (!inserted) {
          merged.add((s, e));
          inserted = true;
        }
        merged.add(range);
      } else {
        s = s < range.$1 ? s : range.$1;
        e = e > range.$2 ? e : range.$2;
      }
    }
    if (!inserted) merged.add((s, e));
    _ranges
      ..clear()
      ..addAll(merged);
    _bytes = _ranges.fold(0, (sum, range) => sum + range.$2 - range.$1);
  }

  Future<void> close() => _file.close();
}

/// HLS 分段按会话内路由缓存，内存淘汰后仍可从磁盘读取。
class SegmentCache {
  SegmentCache._(this._file);

  static Future<SegmentCache?> open() async {
    final file = await _CacheFile.open();
    return file == null ? null : SegmentCache._(file);
  }

  final _CacheFile _file;
  final Map<String, (int, int)> _entries = {};
  int _end = 0;

  Future<void> store(String key, Uint8List bytes) async {
    if (_file.closed ||
        _entries.containsKey(key) ||
        _end + bytes.length > _CacheFile.limit) {
      return;
    }
    final offset = _end;
    _end += bytes.length;
    if (await _file.write(offset, bytes)) {
      _entries[key] = (offset, bytes.length);
    }
  }

  Future<Uint8List?> read(String key) async {
    final entry = _entries[key];
    if (entry == null) return null;
    try {
      return await _file.read(entry.$1, entry.$2);
    } catch (_) {
      return null;
    }
  }

  void remove(String key) => _entries.remove(key);

  Future<void> close() => _file.close();
}
