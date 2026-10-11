import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show InsertMode;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/models.dart';
import '../core/settings.dart';
import '../core/storage.dart';
import '../data/database.dart';
import '../engine/http_service.dart';
import '../engine/source_manager.dart';
import '../engine/browser_media.dart';
import '../images/park_image.dart';
import '../video/hls_download.dart';
import 'library.dart';

enum DownloadStatus { queued, running, paused, done, failed }

/// Pseudo source key of works imported from local CBZ / ZIP files.
const localSource = 'local';

class DownloadTask {
  DownloadTask({
    required this.item,
    required this.chapters,
    String? dir,
    this.status = DownloadStatus.queued,
    this.done = 0,
    this.total = 0,
    this.error,
    this.bytes = 0,
    DateTime? createdAt,
    Set<String>? completed,
  }) : dir = Directory(
         dir ??
             p.join(
               DownloadManager.instance.root.path,
               item.source,
               _safe(item.id),
             ),
       ),
       createdAt = createdAt ?? DateTime.now(),
       completed = completed ?? {};

  final WorkItem item;
  final List<Chapter> chapters; // a single pseudo-chapter for one-shot works; videos use the quality label
  DownloadStatus status;
  int done;
  int total;
  int bytes;
  String? error;
  CancelToken? cancel;
  final DateTime createdAt;

  /// Chapters whose files are complete (pages.json written), so they can be read offline even
  /// while other chapters of the task are still queued.
  final Set<String> completed;

  /// Where this task's files live. Recorded per task so changing the download root never orphans old downloads.
  final Directory dir;

  String get uid => item.uid;
  bool get isVideo =>
      SourceManager.instance.manifest(item.source)?.isVideo ??
      item.duration.isNotEmpty;
  double get progress => total > 0 ? done / total : 0;

  Map<String, dynamic> toJson() => {
    'item': item.toJson(),
    'chapters': [
      for (final c in chapters) {'id': c.id, 'title': c.title},
    ],
    'status': status == DownloadStatus.running
        ? DownloadStatus.queued.index
        : status.index,
    'done': done,
    'total': total,
    'bytes': bytes,
    'error': error,
    'completed': completed.toList(),
  };

  factory DownloadTask.fromJson(
    Map<String, dynamic> j, {
    String? dir,
    DateTime? createdAt,
  }) => DownloadTask(
    item: WorkItem.fromStored((j['item'] as Map).cast<String, dynamic>()),
    dir: dir,
    createdAt: createdAt,
    chapters: (j['chapters'] as List)
        .cast<Map>()
        .map((c) => Chapter(c['id'].toString(), c['title'].toString()))
        .toList(),
    status: DownloadStatus.values[(j['status'] as num).toInt()],
    done: (j['done'] as num?)?.toInt() ?? 0,
    total: (j['total'] as num?)?.toInt() ?? 0,
    bytes: (j['bytes'] as num?)?.toInt() ?? 0,
    error: j['error'] as String?,
    completed: ((j['completed'] as List?) ?? const [])
        .map((e) => e.toString())
        .toSet(),
  );

  static String _safe(String s) => safeFileName(s);

  /// Directory name used for a chapter inside the task directory.
  static String safeName(String chapterId) => safeFileName(chapterId);
}

/// Offline downloads. Comic pages are stored raw together with their transform descriptors
/// (JM pages are unscrambled at display time); videos are streamed to an mp4 file.
class DownloadManager extends ChangeNotifier {
  DownloadManager._();
  static final DownloadManager instance = DownloadManager._();

  late AppDatabase _db;
  final Map<String, DownloadTask> _tasks = {};

  /// Root directory for new downloads (user-visible app storage on Android).
  Directory get root => AppPaths.downloadRoot;

  StreamSubscription<List<ConnectivityResult>>? _connectivity;
  bool _onWifi = true;

  /// Running task per source. Different sites download in parallel; one site runs one task at a time
  /// so per-site rate limits (E-Hentai bans, image quotas) are respected.
  final Map<String, DownloadTask> _active = {};
  final Map<DownloadTask, Future<void>> _runs = {};
  final Map<String, Future<void>> _deletions = {};
  Future<void> _writes = Future<void>.value();
  bool _disposed = false;

  List<DownloadTask> get tasks =>
      _tasks.values.toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  DownloadTask? task(String uid) => _tasks[uid];

  Future<void> load(AppDatabase db) async {
    _db = db;
    for (final r in await db.select(db.downloadTasks).get()) {
      try {
        final t = DownloadTask.fromJson(
          (jsonDecode(r.json) as Map).cast<String, dynamic>(),
          dir: r.dir,
          createdAt: DateTime.fromMillisecondsSinceEpoch(r.createdAt),
        );
        // Tasks written before per-chapter tracking: a finished task has every chapter complete.
        if (t.status == DownloadStatus.done && t.completed.isEmpty) {
          t.completed.addAll(t.chapters.map((c) => c.id));
        }
        _tasks[t.uid] = t;
      } catch (e) {
        debugPrint('skip download ${r.uid}: $e');
      }
    }
    Library.instance.onChaptersRead.add(_onChaptersRead);
    AppSettings.instance.addListener(_settingsChanged);
    await _watchNetwork();
    _pump();
  }

  Future<void> _watchNetwork() async {
    try {
      final c = Connectivity();
      _onWifi = _isUnmetered(await c.checkConnectivity());
      _connectivity = c.onConnectivityChanged.listen((r) {
        final wifi = _isUnmetered(r);
        if (wifi == _onWifi) return;
        _onWifi = wifi;
        _settingsChanged();
        notifyListeners();
      }, onError: (Object e) => debugPrint('connectivity: $e'));
    } catch (e) {
      debugPrint('connectivity unavailable: $e');
    }
  }

  static bool _isUnmetered(List<ConnectivityResult> r) => r.any(
    (x) => x == ConnectivityResult.wifi || x == ConnectivityResult.ethernet,
  );

  /// False while "Wi-Fi only" is on and the device is on mobile data.
  bool get networkAllowed => !AppSettings.instance.downloadWifiOnly || _onWifi;

  void _settingsChanged() {
    if (_disposed) return;
    if (!networkAllowed) {
      for (final t in _active.values) {
        if (t.status != DownloadStatus.running) continue;
        t.status = DownloadStatus.queued;
        t.cancel?.cancel('waiting for Wi-Fi');
        _save([t]);
      }
    }
    _pump();
  }

  /// "Delete after reading": drop downloaded chapters once they are marked read.
  void _onChaptersRead(String uid, List<String> chapterIds) {
    if (!AppSettings.instance.deleteAfterRead) return;
    final t = _tasks[uid];
    if (t == null || t.item.source == localSource) return;
    unawaited(
      deleteChapters(uid, chapterIds.where(t.completed.contains).toList()),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _connectivity?.cancel();
    AppSettings.instance.removeListener(_settingsChanged);
    Library.instance.onChaptersRead.remove(_onChaptersRead);
    for (final t in _active.values) {
      t.status = DownloadStatus.paused;
      t.cancel?.cancel('download manager disposed');
    }
    super.dispose();
  }

  /// Persists the given tasks (all when null). Progress is saved at chapter boundaries, not per page.
  void _save([Iterable<DownloadTask>? which]) {
    if (_disposed) return;
    final rows = [
      for (final t in which ?? _tasks.values)
        if (identical(_tasks[t.uid], t))
          DownloadTasksCompanion.insert(
            uid: t.uid,
            source: t.item.source,
            json: jsonEncode(t.toJson()),
            dir: t.dir.path,
            createdAt: t.createdAt.millisecondsSinceEpoch,
          ),
    ];
    _writes = _writes
        .then(
          (_) => _db.batch((b) {
            for (final row in rows) {
              b.insert(
                _db.downloadTasks,
                row,
                mode: InsertMode.insertOrReplace,
              );
            }
          }),
        )
        .catchError((Object e) => debugPrint('save downloads failed: $e'));
    notifyListeners();
  }

  void enqueue(WorkItem item, List<Chapter> chapters) {
    if (_disposed) return;
    if (item.source == localSource) {
      return; // imported files are already complete
    }
    final deleting = _deletions[item.uid];
    if (deleting != null) {
      unawaited(deleting.then((_) => enqueue(item, chapters)));
      return;
    }
    final existing = _tasks[item.uid];
    if (existing != null) {
      final known = existing.chapters.map((c) => c.id).toSet();
      existing.chapters.addAll(chapters.where((c) => !known.contains(c.id)));
      if (existing.status != DownloadStatus.running) {
        existing.status = DownloadStatus.queued;
      }
    } else {
      _tasks[item.uid] = DownloadTask(item: item, chapters: chapters);
    }
    _save([_tasks[item.uid]!]);
    _pump();
  }

  void pause(String uid) {
    final t = _tasks[uid];
    if (t == null) return;
    t.status = DownloadStatus.paused;
    t.cancel?.cancel();
    _save([t]);
  }

  void resume(String uid) {
    final t = _tasks[uid];
    if (t == null || t.status == DownloadStatus.done) return;
    t
      ..status = DownloadStatus.queued
      ..error = null;
    _save([t]);
    _pump();
  }

  void pauseAll() {
    for (final t
        in _tasks.values
            .where(
              (t) =>
                  t.status == DownloadStatus.running ||
                  t.status == DownloadStatus.queued,
            )
            .toList()) {
      pause(t.uid);
    }
  }

  void resumeAll() {
    for (final t
        in _tasks.values
            .where(
              (t) =>
                  t.status == DownloadStatus.paused ||
                  t.status == DownloadStatus.failed,
            )
            .toList()) {
      resume(t.uid);
    }
  }

  /// Deletes some chapters of a task; the task itself goes when nothing is left.
  Future<void> deleteChapters(String uid, List<String> chapterIds) async {
    final t = _tasks[uid];
    if (t == null || chapterIds.isEmpty) return;
    if (t.chapters.every((c) => chapterIds.contains(c.id))) return delete(uid);
    final restart =
        t.status == DownloadStatus.running || t.status == DownloadStatus.queued;
    if (restart) pause(uid);
    final pending = _runs[t];
    if (pending != null) await pending;
    if (!identical(_tasks[uid], t)) return;
    for (final id in chapterIds) {
      final dir = Directory(p.join(t.dir.path, DownloadTask._safe(id)));
      if (await dir.exists()) await dir.delete(recursive: true);
      t.completed.remove(id);
    }
    t.chapters.removeWhere((c) => chapterIds.contains(c.id));
    if (restart) {
      resume(uid);
    } else {
      _save([t]);
    }
  }

  /// Registers an already complete task (local imports).
  void addCompleted(DownloadTask t) {
    _tasks[t.uid] = t;
    _save([t]);
  }

  Future<void> delete(String uid) {
    final pending = _deletions[uid];
    if (pending != null) return pending;
    final t = _tasks.remove(uid);
    if (t != null) {
      t.status = DownloadStatus.paused;
      t.cancel?.cancel('download deleted');
    }
    final deletion = _delete(uid, t).whenComplete(() {
      _deletions.remove(uid);
    });
    _deletions[uid] = deletion;
    return deletion;
  }

  Future<void> _delete(String uid, DownloadTask? t) async {
    final pending = _runs[t];
    if (pending != null) await pending;
    if (t != null && await t.dir.exists()) await t.dir.delete(recursive: true);
    final deletion = _writes.then(
      (_) =>
          (_db.delete(_db.downloadTasks)..where((r) => r.uid.equals(uid))).go(),
    );
    _writes = deletion
        .then<void>((_) {})
        .catchError((Object e) => debugPrint('delete download failed: $e'));
    await deletion;
    notifyListeners();
    _pump();
  }

  void _pump() {
    if (_disposed || !networkAllowed) return;
    for (final next
        in _tasks.values
            .where((t) => t.status == DownloadStatus.queued)
            .toList()) {
      final source = next.item.source;
      if (_active.containsKey(source)) continue;
      _active[source] = next;
      final run = _run(next).whenComplete(() {
        if (identical(_active[source], next)) _active.remove(source);
        _runs.remove(next);
        if (identical(_tasks[next.uid], next)) _save([next]);
        _pump();
      });
      _runs[next] = run;
      unawaited(run);
    }
  }

  Future<void> _run(DownloadTask t) async {
    final token = CancelToken();
    t
      ..status = DownloadStatus.running
      ..error = null
      ..cancel = token;
    notifyListeners();
    try {
      // Tasks resumed at launch must not decide comic-vs-video before the source manifests exist.
      await _cancellable(SourceManager.instance.ready, token);
      _checkRunning(t, token);
      await t.dir.create(recursive: true);
      _checkRunning(t, token);
      await File(p.join(t.dir.path, 'work.json'))
          .writeAsString(jsonEncode(t.item.toJson()));
      _checkRunning(t, token);
      if (t.isVideo) {
        await _runVideo(t, token);
      } else {
        await _runComic(t, token);
      }
      _checkRunning(t, token);
      t.status = t.chapters.every((c) => t.completed.contains(c.id))
          ? DownloadStatus.done
          : DownloadStatus.queued;
    } catch (e) {
      if (!identical(_tasks[t.uid], t) ||
          !identical(t.cancel, token) ||
          t.status != DownloadStatus.running) {
        return;
      }
      if (!networkAllowed) {
        // Lost Wi-Fi with "Wi-Fi only" on: wait for it instead of failing.
        t.status = DownloadStatus.queued;
        return;
      }
      t
        ..status = DownloadStatus.failed
        ..error = e is SourceError ? e.friendly : e.toString();
    }
  }

  static Future<T> _cancellable<T>(Future<T> work, CancelToken token) =>
      Future.any([work, token.whenCancel.then<T>((error) => throw error)]);

  void _checkRunning(DownloadTask t, CancelToken token) {
    if (!networkAllowed && t.status == DownloadStatus.running) {
      t.status = DownloadStatus.queued;
      token.cancel('waiting for Wi-Fi');
    }
    if (!identical(_tasks[t.uid], t) ||
        !identical(t.cancel, token) ||
        t.status != DownloadStatus.running ||
        token.isCancelled) {
      if (!token.isCancelled) token.cancel('download stopped');
      throw token.cancelError!;
    }
  }

  Future<void> _runComic(DownloadTask t, CancelToken token) async {
    final sm = SourceManager.instance;
    // Resolve every chapter first so the progress total is known up front.
    final plans = <(Chapter, ChapterImages)>[];
    for (final c
        in t.chapters.where((c) => !t.completed.contains(c.id)).toList()) {
      _checkRunning(t, token);
      final chapterId = c.id == '_' ? null : c.id;
      plans.add((
        c,
        await _cancellable(
          sm.chapter(t.item.source, t.item.id, chapterId, cancelToken: token),
          token,
        ),
      ));
      _checkRunning(t, token);
    }
    t.total = plans.fold(0, (n, e) => n + e.$2.pages.length);
    t.done = 0;
    if (plans.isEmpty) return;
    notifyListeners();
    for (final (chapter, images) in plans) {
      _checkRunning(t, token);
      final dir = Directory(p.join(t.dir.path, DownloadTask._safe(chapter.id)));
      await dir.create(recursive: true);
      _checkRunning(t, token);
      final manifest = <Map<String, dynamic>>[];
      final chapterId = chapter.id == '_' ? null : chapter.id;
      var next = 0;
      Future<void> worker() async {
        while (next < images.pages.length) {
          _checkRunning(t, token);
          final i = next++;
          final page = images.pages[i];
          final name = '${(i + 1).toString().padLeft(4, '0')}.img';
          final file = File(p.join(dir.path, name));
          if (!await file.exists() || await file.length() == 0) {
            final bytes = await ParkImage.page(
              t.item.source,
              t.item.id,
              chapterId,
              i,
              page,
            ).loadBytes(cancelToken: token);
            _checkRunning(t, token);
            final part = File('${file.path}.part');
            await part.writeAsBytes(bytes, flush: true);
            _checkRunning(t, token);
            await part.rename(file.path);
            t.bytes += bytes.length;
          }
          _checkRunning(t, token);
          manifest.add({
            'index': i,
            'file': name,
            if (page.transform != null) 'transform': page.transform,
            'width': page.width,
            'height': page.height,
          });
          t.done++;
          notifyListeners();
        }
      }

      await Future.wait(
        List.generate(
          AppSettings.instance.downloadConcurrency.clamp(1, 8),
          (_) => worker(),
        ),
      );
      _checkRunning(t, token);
      manifest.sort((a, b) => (a['index'] as int).compareTo(b['index'] as int));
      final file = File(p.join(dir.path, 'pages.json'));
      final part = File('${file.path}.part');
      await part.writeAsString(
        jsonEncode({'title': chapter.title, 'pages': manifest}),
        flush: true,
      );
      _checkRunning(t, token);
      await part.rename(file.path);
      t.completed.add(chapter.id);
      _save([t]);
    }
  }

  Future<void> _runVideo(DownloadTask t, CancelToken token) async {
    final sources = await _cancellable(
      SourceManager.instance.videos(
        t.item.source,
        t.item.id,
        cancelToken: token,
      ),
      token,
    );
    _checkRunning(t, token);
    final wanted = t.chapters.first.id;
    final src = sources.firstWhere(
      (s) => '${s.quality}' == wanted,
      orElse: () =>
          sources.firstWhere((s) => s.preferred, orElse: () => sources.first),
    );
    final file = File(p.join(t.dir.path, 'video_${src.quality}p.mp4'));
    final part = File('${file.path}.part');
    t
      ..total = 100
      ..done = 0;
    var lastNotify = DateTime.now();
    if (src.format == 'hls') {
      final manifest = SourceManager.instance.manifest(t.item.source);
      if (manifest == null) throw SourceError('CONFIG', '视频源未加载');
      if (!Platform.isAndroid) {
        throw SourceError('UNSUPPORTED', 'HLS 下载封装目前仅支持安卓');
      }
      await HlsDownload(BrowserMedia(BrowserMediaPolicy.fromManifest(manifest)))
          .run(
            Uri.parse(src.url),
            output: part,
            cancelToken: token,
            onProgress: (done, total, bytes) {
              t
                ..done = done
                ..total = total
                ..bytes = bytes;
              if (DateTime.now().difference(lastNotify).inMilliseconds > 300 ||
                  done == total) {
                lastNotify = DateTime.now();
                notifyListeners();
              }
            },
          );
    } else {
      await HttpService.instance.download(
        url: src.url,
        savePath: part.path,
        headers: src.headers,
        partition: t.item.source,
        cancelToken: token,
        onProgress: (received, total) {
          t.bytes = received;
          if (total > 0) t.done = (received * 100 ~/ total);
          if (DateTime.now().difference(lastNotify).inMilliseconds > 300) {
            lastNotify = DateTime.now();
            notifyListeners();
          }
        },
      );
    }
    _checkRunning(t, token);
    await part.rename(file.path);
    t.done = t.total;
    t.completed.add(wanted);
  }

  /// Locally downloaded pages for a chapter, or null when not (fully) downloaded.
  Future<List<PageImage>?> localChapter(
    String source,
    String id,
    String? chapterId,
  ) async {
    final t = _tasks['$source:$id'];
    if (t == null) return null;
    final f = File(
      p.join(t.dir.path, DownloadTask._safe(chapterId ?? '_'), 'pages.json'),
    );
    if (!await f.exists()) return null;
    final data = jsonDecode(await f.readAsString()) as Map;
    return (data['pages'] as List).cast<Map>().map((e) {
      final m = e.cast<String, dynamic>();
      return PageImage({
        ...m,
        'url': File(p.join(f.parent.path, m['file'] as String)).uri.toString(),
      });
    }).toList();
  }

  Future<File?> localVideo(String source, String id) async {
    final t = _tasks['$source:$id'];
    if (t == null || t.status != DownloadStatus.done || !await t.dir.exists()) {
      return null;
    }
    await for (final e in t.dir.list()) {
      if (e is File && e.path.endsWith('.mp4')) return e;
    }
    return null;
  }

  /// A detail built from what was downloaded, so offline users can still open and read a work.
  WorkDetail? offlineDetail(String source, String id) {
    final t = _tasks['$source:$id'];
    if (t == null || (t.status != DownloadStatus.done && t.completed.isEmpty)) {
      return null;
    }
    final single = t.chapters.length == 1;
    return WorkDetail({
      ...t.item.json,
      'id': t.item.id,
      'chapters': single || t.isVideo
          ? null
          : [
              for (final c in t.chapters) {'id': c.id, 'title': c.title},
            ],
      'singleChapterId': single && t.chapters.first.id != '_'
          ? t.chapters.first.id
          : null,
    }, source);
  }

  bool isChapterDownloaded(String uid, String chapterId) =>
      _tasks[uid]?.completed.contains(chapterId) ?? false;

  /// Queues new chapters found by a library update (auto-download).
  void enqueueNewChapters(WorkItem item, List<Chapter> chapters) {
    if (chapters.isNotEmpty) enqueue(item, chapters);
  }
}
