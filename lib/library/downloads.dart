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
import '../images/park_image.dart';
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
  }) : dir = Directory(dir ?? p.join(DownloadManager.instance.root.path, item.source, _safe(item.id))),
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
  bool get isVideo => SourceManager.instance.manifest(item.source)?.isVideo ?? item.duration.isNotEmpty;
  double get progress => total > 0 ? done / total : 0;

  Map<String, dynamic> toJson() => {
    'item': item.toJson(),
    'chapters': [
      for (final c in chapters) {'id': c.id, 'title': c.title},
    ],
    'status': status == DownloadStatus.running ? DownloadStatus.queued.index : status.index,
    'done': done,
    'total': total,
    'bytes': bytes,
    'error': error,
    'completed': completed.toList(),
  };

  factory DownloadTask.fromJson(Map<String, dynamic> j, {String? dir, DateTime? createdAt}) => DownloadTask(
    item: WorkItem.fromStored((j['item'] as Map).cast<String, dynamic>()),
    dir: dir,
    createdAt: createdAt,
    chapters: (j['chapters'] as List).cast<Map>().map((c) => Chapter(c['id'].toString(), c['title'].toString())).toList(),
    status: DownloadStatus.values[(j['status'] as num).toInt()],
    done: (j['done'] as num?)?.toInt() ?? 0,
    total: (j['total'] as num?)?.toInt() ?? 0,
    bytes: (j['bytes'] as num?)?.toInt() ?? 0,
    error: j['error'] as String?,
    completed: ((j['completed'] as List?) ?? const []).map((e) => e.toString()).toSet(),
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

  List<DownloadTask> get tasks => _tasks.values.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  DownloadTask? task(String uid) => _tasks[uid];

  Future<void> load(AppDatabase db) async {
    _db = db;
    for (final r in await db.select(db.downloadTasks).get()) {
      try {
        final t = DownloadTask.fromJson((jsonDecode(r.json) as Map).cast<String, dynamic>(), dir: r.dir, createdAt: DateTime.fromMillisecondsSinceEpoch(r.createdAt));
        // Tasks written before per-chapter tracking: a finished task has every chapter complete.
        if (t.status == DownloadStatus.done && t.completed.isEmpty) t.completed.addAll(t.chapters.map((c) => c.id));
        _tasks[t.uid] = t;
      } catch (e) {
        debugPrint('skip download ${r.uid}: $e');
      }
    }
    Library.instance.onChaptersRead.add(_onChaptersRead);
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
        if (!wifi && AppSettings.instance.downloadWifiOnly) {
          for (final t in _tasks.values.where((t) => t.status == DownloadStatus.running)) {
            t.cancel?.cancel();
          }
        }
        _pump();
        notifyListeners();
      }, onError: (Object e) => debugPrint('connectivity: $e'));
    } catch (e) {
      debugPrint('connectivity unavailable: $e');
    }
  }

  static bool _isUnmetered(List<ConnectivityResult> r) => r.any((x) => x == ConnectivityResult.wifi || x == ConnectivityResult.ethernet);

  /// False while "Wi-Fi only" is on and the device is on mobile data.
  bool get networkAllowed => !AppSettings.instance.downloadWifiOnly || _onWifi;

  /// "Delete after reading": drop downloaded chapters once they are marked read.
  void _onChaptersRead(String uid, List<String> chapterIds) {
    if (!AppSettings.instance.deleteAfterRead) return;
    final t = _tasks[uid];
    if (t == null || t.item.source == localSource) return;
    unawaited(deleteChapters(uid, chapterIds.where(t.completed.contains).toList()));
  }

  @override
  void dispose() {
    _connectivity?.cancel();
    super.dispose();
  }

  /// Persists the given tasks (all when null). Progress is saved at chapter boundaries, not per page.
  void _save([Iterable<DownloadTask>? which]) {
    final list = (which ?? _tasks.values).toList();
    unawaited(
      _db
          .batch((b) {
            for (final t in list) {
              b.insert(
                _db.downloadTasks,
                DownloadTasksCompanion.insert(uid: t.uid, source: t.item.source, json: jsonEncode(t.toJson()), dir: t.dir.path, createdAt: t.createdAt.millisecondsSinceEpoch),
                mode: InsertMode.insertOrReplace,
              );
            }
          })
          .catchError((Object e) => debugPrint('save downloads failed: $e')),
    );
    notifyListeners();
  }

  void enqueue(WorkItem item, List<Chapter> chapters) {
    if (item.source == localSource) return; // imported files are already complete
    final existing = _tasks[item.uid];
    if (existing != null) {
      final known = existing.chapters.map((c) => c.id).toSet();
      existing.chapters.addAll(chapters.where((c) => !known.contains(c.id)));
      if (existing.status != DownloadStatus.running) existing.status = DownloadStatus.queued;
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
    for (final t in _tasks.values.where((t) => t.status == DownloadStatus.running || t.status == DownloadStatus.queued).toList()) {
      pause(t.uid);
    }
  }

  void resumeAll() {
    for (final t in _tasks.values.where((t) => t.status == DownloadStatus.paused || t.status == DownloadStatus.failed).toList()) {
      resume(t.uid);
    }
  }

  /// Deletes some chapters of a task; the task itself goes when nothing is left.
  Future<void> deleteChapters(String uid, List<String> chapterIds) async {
    final t = _tasks[uid];
    if (t == null || chapterIds.isEmpty) return;
    if (t.chapters.every((c) => chapterIds.contains(c.id))) return delete(uid);
    final running = t.status == DownloadStatus.running;
    if (running) pause(uid);
    for (final id in chapterIds) {
      final dir = Directory(p.join(t.dir.path, DownloadTask._safe(id)));
      if (await dir.exists()) await dir.delete(recursive: true);
      t.completed.remove(id);
    }
    t.chapters.removeWhere((c) => chapterIds.contains(c.id));
    if (running) {
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

  Future<void> delete(String uid) async {
    final t = _tasks.remove(uid);
    t?.cancel?.cancel();
    if (t != null && await t.dir.exists()) await t.dir.delete(recursive: true);
    await (_db.delete(_db.downloadTasks)..where((r) => r.uid.equals(uid))).go();
    notifyListeners();
    _pump();
  }

  void _pump() {
    if (!networkAllowed) return;
    for (final next in _tasks.values.where((t) => t.status == DownloadStatus.queued).toList()) {
      final source = next.item.source;
      if (_active.containsKey(source)) continue;
      _active[source] = next;
      unawaited(
        _run(next).whenComplete(() {
          _active.remove(source);
          _save([next]);
          _pump();
        }),
      );
    }
  }

  Future<void> _run(DownloadTask t) async {
    t
      ..status = DownloadStatus.running
      ..error = null
      ..cancel = CancelToken();
    notifyListeners();
    try {
      // Tasks resumed at launch must not decide comic-vs-video before the source manifests exist.
      await SourceManager.instance.ready;
      await t.dir.create(recursive: true);
      await File(p.join(t.dir.path, 'work.json')).writeAsString(jsonEncode(t.item.toJson()));
      if (t.isVideo) {
        await _runVideo(t);
      } else {
        await _runComic(t);
      }
      if (t.status == DownloadStatus.running) t.status = DownloadStatus.done;
    } catch (e) {
      if (t.status == DownloadStatus.paused) return;
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

  Future<void> _runComic(DownloadTask t) async {
    final sm = SourceManager.instance;
    // Resolve every chapter first so the progress total is known up front.
    final plans = <(Chapter, ChapterImages)>[];
    for (final c in t.chapters.where((c) => !t.completed.contains(c.id))) {
      final chapterId = c.id == '_' ? null : c.id;
      plans.add((c, await sm.chapter(t.item.source, t.item.id, chapterId)));
    }
    t.total = plans.fold(0, (n, e) => n + e.$2.pages.length);
    t.done = 0;
    if (plans.isEmpty) return;
    notifyListeners();
    for (final (chapter, images) in plans) {
      final dir = Directory(p.join(t.dir.path, DownloadTask._safe(chapter.id)));
      await dir.create(recursive: true);
      final manifest = <Map<String, dynamic>>[];
      final chapterId = chapter.id == '_' ? null : chapter.id;
      var next = 0;
      Future<void> worker() async {
        while (next < images.pages.length) {
          if (t.status != DownloadStatus.running) return;
          final i = next++;
          final page = images.pages[i];
          final name = '${(i + 1).toString().padLeft(4, '0')}.img';
          final file = File(p.join(dir.path, name));
          if (!await file.exists() || await file.length() == 0) {
            final bytes = await ParkImage.page(t.item.source, t.item.id, chapterId, i, page).loadBytes();
            await file.writeAsBytes(bytes);
            t.bytes += bytes.length;
          }
          manifest.add({'index': i, 'file': name, if (page.transform != null) 'transform': page.transform, 'width': page.width, 'height': page.height});
          t.done++;
          notifyListeners();
        }
      }

      await Future.wait(List.generate(AppSettings.instance.downloadConcurrency.clamp(1, 8), (_) => worker()));
      if (t.status != DownloadStatus.running) return;
      manifest.sort((a, b) => (a['index'] as int).compareTo(b['index'] as int));
      await File(p.join(dir.path, 'pages.json')).writeAsString(jsonEncode({'title': chapter.title, 'pages': manifest}));
      t.completed.add(chapter.id);
      _save([t]);
    }
  }

  Future<void> _runVideo(DownloadTask t) async {
    final sources = await SourceManager.instance.videos(t.item.source, t.item.id);
    final wanted = t.chapters.first.id;
    final src = sources.firstWhere((s) => '${s.quality}' == wanted, orElse: () => sources.firstWhere((s) => s.preferred, orElse: () => sources.first));
    final file = File(p.join(t.dir.path, 'video_${src.quality}p.mp4'));
    final part = File('${file.path}.part');
    t
      ..total = 100
      ..done = 0;
    var lastNotify = DateTime.now();
    await HttpService.instance.download(
      url: src.url,
      savePath: part.path,
      headers: src.headers,
      partition: t.item.source,
      cancelToken: t.cancel,
      onProgress: (received, total) {
        t.bytes = received;
        if (total > 0) t.done = (received * 100 ~/ total);
        if (DateTime.now().difference(lastNotify).inMilliseconds > 300) {
          lastNotify = DateTime.now();
          notifyListeners();
        }
      },
    );
    await part.rename(file.path);
    t.done = 100;
    t.completed.add(wanted);
  }

  /// Locally downloaded pages for a chapter, or null when not (fully) downloaded.
  Future<List<PageImage>?> localChapter(String source, String id, String? chapterId) async {
    final t = _tasks['$source:$id'];
    if (t == null) return null;
    final f = File(p.join(t.dir.path, DownloadTask._safe(chapterId ?? '_'), 'pages.json'));
    if (!await f.exists()) return null;
    final data = jsonDecode(await f.readAsString()) as Map;
    return (data['pages'] as List).cast<Map>().map((e) {
      final m = e.cast<String, dynamic>();
      return PageImage({...m, 'url': 'file://${p.join(f.parent.path, m['file'] as String)}'});
    }).toList();
  }

  Future<File?> localVideo(String source, String id) async {
    final t = _tasks['$source:$id'];
    if (t == null || t.status != DownloadStatus.done || !await t.dir.exists()) return null;
    await for (final e in t.dir.list()) {
      if (e is File && e.path.endsWith('.mp4')) return e;
    }
    return null;
  }

  /// A detail built from what was downloaded, so offline users can still open and read a work.
  WorkDetail? offlineDetail(String source, String id) {
    final t = _tasks['$source:$id'];
    if (t == null || (t.status != DownloadStatus.done && t.completed.isEmpty)) return null;
    final single = t.chapters.length == 1;
    return WorkDetail({
      ...t.item.json,
      'id': t.item.id,
      'chapters': single || t.isVideo
          ? null
          : [
              for (final c in t.chapters) {'id': c.id, 'title': c.title},
            ],
      'singleChapterId': single && t.chapters.first.id != '_' ? t.chapters.first.id : null,
    }, source);
  }

  bool isChapterDownloaded(String uid, String chapterId) => _tasks[uid]?.completed.contains(chapterId) ?? false;

  /// Queues new chapters found by a library update (auto-download).
  void enqueueNewChapters(WorkItem item, List<Chapter> chapters) {
    if (chapters.isNotEmpty) enqueue(item, chapters);
  }
}
