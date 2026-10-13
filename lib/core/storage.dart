import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'async_tasks.dart';

/// 同目录准备并提交文件；提交前可检查取消/代次，失败不改动原文件。
Future<bool> writeFileAtomic(
  File file,
  List<int> bytes, {
  FutureOr<bool> Function()? canCommit,
}) async {
  final temporary = File('${file.path}.tmp-${const Uuid().v4()}');
  try {
    await temporary.writeAsBytes(bytes, flush: true);
    if (canCommit != null && !await canCommit()) return false;
    await temporary.rename(file.path);
    return true;
  } finally {
    if (await temporary.exists()) await temporary.delete();
  }
}

/// Well-known app directories, resolved once at startup.
class AppPaths {
  static late Directory
  data; // persistent app data (sources, library, settings)
  static late Directory cache; // image cache, can be cleared
  static late Directory downloads; // offline downloads
  static late Directory
  backups; // automatic and manual backups (user-visible on Android)
  static late Directory
  downloadRoot; // new downloads and exports (user-visible on Android)

  static Future<void> init() async {
    final support = await getApplicationSupportDirectory();
    final temp = await getApplicationCacheDirectory();
    data = Directory(p.join(support.path, 'park'));
    cache = Directory(p.join(temp.path, 'park_cache'));
    downloads = Directory(p.join(support.path, 'downloads'));
    final external = await _external();
    backups = Directory(p.join(external?.path ?? support.path, 'backups'));
    downloadRoot = external == null
        ? downloads
        : Directory(p.join(external.path, 'downloads'));
    for (final d in [data, cache, downloads, backups, downloadRoot]) {
      await d.create(recursive: true);
    }
  }

  static File dataFile(String name) => File(p.join(data.path, name));

  /// App-specific external storage on Android (visible to file managers, no permission needed).
  static Future<Directory?> _external() async {
    if (!Platform.isAndroid) return null;
    try {
      return await getExternalStorageDirectory();
    } catch (_) {
      return null;
    }
  }
}

/// A JSON document persisted to disk with debounced, atomic writes.
class JsonStore {
  JsonStore(this.name, {this.debounce = const Duration(milliseconds: 400)});

  final String name;
  final Duration debounce;
  Object? _data;
  Timer? _timer;
  final _writing = SerialExecutor();

  File get _file => AppPaths.dataFile(name);

  Future<Object?> load() async {
    _data = null;
    try {
      if (await _file.exists()) _data = jsonDecode(await _file.readAsString());
    } catch (_) {
      // Corrupt file: keep a copy for diagnosis and start fresh.
      try {
        await _file.copy('${_file.path}.broken');
      } catch (_) {}
      _data = null;
    }
    return _data;
  }

  void save(Object? data) {
    _data = data;
    _timer?.cancel();
    _timer = Timer(debounce, () {
      // Deferred writes retain _data for a later retry; explicit flush callers still receive errors.
      unawaited(flush().catchError((Object _) {}));
    });
  }

  Future<void> flush() {
    _timer?.cancel();
    _timer = null;
    final text = jsonEncode(_data);
    final file = _file;
    return _writing.run(() async {
      await writeFileAtomic(file, utf8.encode(text));
    });
  }
}

/// Stable identity segment: fixed length, safe on all filesystems, and distinct
/// even when IDs differ only by punctuation, Unicode, or letter case.
String safeFileName(String s) => sha256.convert(utf8.encode(s)).toString();
