import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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
  Future<void>? _writing;

  File get _file => AppPaths.dataFile(name);

  Future<Object?> load() async {
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
    final tmp = File('${file.path}.tmp');
    final write = (_writing ?? Future<void>.value()).then((_) async {
      await tmp.writeAsString(text, flush: true);
      await tmp.rename(file.path);
    });
    // Set the queue synchronously: simultaneous flushes cannot all race past the same await.
    // This tail recovers from an earlier failure; the returned write preserves this call's failure.
    _writing = write.catchError((Object _) {});
    return write;
  }
}

/// Turns an id (which may contain '/', ':' …) into a single safe path segment.
String safeFileName(String s) => s.replaceAll(RegExp(r'[^\w.-]+'), '_');
