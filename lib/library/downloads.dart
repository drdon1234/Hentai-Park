import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show InsertMode;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/models.dart';
import '../core/localization.dart';
import '../core/settings.dart';
import '../core/storage.dart';
import '../data/database.dart';
import '../engine/http_service.dart';
import '../engine/source_manager.dart';
import '../engine/media_transport.dart';
import '../images/park_image.dart';
import '../video/hls_download.dart';
import 'library.dart';

enum DownloadStatus { queued, running, paused, done, failed }
enum DownloadMedia { comic, video }

/// Pseudo source key of works imported from local CBZ / ZIP files.
const localSource = 'local';

class DownloadTask {
  DownloadTask({
    required this.item,
    required List<Chapter> chapters,
    String? dir,
    this.status = DownloadStatus.queued,
    this.done = 0,
    this.total = 0,
    this.error,
    this.bytes = 0,
    DateTime? createdAt,
    Set<String>? completed,
    DownloadMedia? media,
    this.videoQuality,
    Map<String, String>? videoFiles,
  }) : dir = Directory(
         dir ??
             p.join(
               DownloadManager.instance.root.path,
               item.source,
               _safe(item.id),
             ),
       ),
       createdAt = createdAt ?? DateTime.now(),
       chapters = List.of(chapters),
       completed = completed ?? {},
       media = media ?? (videoQuality == null ? null : DownloadMedia.video),
       videoFiles = videoFiles ?? {};

  final WorkItem item;
  final List<Chapter> chapters;
  DownloadMedia? media;
  int? videoQuality; // 0 selects the source's preferred quality.
  final Map<String, String> videoFiles; // episode id -> MP4 path relative to dir.
  Future<bool>? _normalization;
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
      media == DownloadMedia.video ||
      (media == null &&
          (SourceManager.instance.manifest(item.source)?.isVideo ??
              item.duration.isNotEmpty));
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
    if (media != null) 'media': media!.name,
    if (videoQuality != null) 'videoQuality': videoQuality,
    if (videoFiles.isNotEmpty) 'videoFiles': videoFiles,
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
    media: DownloadMedia.values.where((v) => v.name == j['media']).firstOrNull,
    videoQuality: (j['videoQuality'] as num?)?.toInt(),
    videoFiles: (j['videoFiles'] as Map? ?? const {}).map(
      (k, v) => MapEntry(k.toString(), v.toString()),
    ),
  );

  /// One-time normalization after installed source types are available. Files stay in place.
  Future<bool> normalizeMedia(SourceManifest? manifest) {
    final pending = _normalization;
    if (pending != null) return pending;
    if (media != null) return Future.value(false);
    return _normalization = _normalizeMedia(manifest).whenComplete(() {
      _normalization = null;
    });
  }

  Future<bool> _normalizeMedia(SourceManifest? manifest) async {
    if (media != null) return false;
    final files = <File>[];
    if (await dir.exists()) {
      await for (final entry in dir.list(followLinks: false)) {
        if (entry is File && p.extension(entry.path).toLowerCase() == '.mp4') {
          files.add(entry);
        }
      }
    }
    if (manifest == null && item.duration.isEmpty && files.isEmpty && item.source != localSource) {
      return false; // Preserve unidentifiable tasks until their source is installed.
    }
    final video = manifest?.isVideo ?? (item.duration.isNotEmpty || files.isNotEmpty);
    if (!video) {
      media = DownloadMedia.comic;
      return true;
    }
    final quality = chapters.isEmpty ? 0 : int.tryParse(chapters.first.id) ?? 0;
    final key = chapterKeyOf(item.json['singleChapterId']?.toString());
    files.sort((a, b) => a.path.compareTo(b.path));
    final wanted = 'video_${quality}p.mp4';
    final file = files.where((f) => p.basename(f.path) == wanted).firstOrNull ?? files.firstOrNull;
    final complete = file != null && await file.length() > 0;
    // Publish the normalized identity and mapping together after all file I/O.
    media = DownloadMedia.video;
    videoQuality = quality;
    chapters
      ..clear()
      ..add(Chapter(key, tr('正片')));
    completed.clear();
    if (complete) {
      videoFiles[key] = p.relative(file.path, from: dir.path);
      completed.add(key);
    }
    return true;
  }

  static String _safe(String s) => safeFileName(s);

  /// Single videos retain their root output; explicit episode catalogs use isolated directories.
  Directory videoDirectory(String episodeId) {
    final detail = WorkDetail(item.json, item.source);
    if (!detail.hasVideoEpisodes && episodeId == detail.videoEpisodes.single.id) {
      return dir;
    }
    return Directory(p.join(dir.path, 'episode_${crypto.sha256.convert(utf8.encode(episodeId))}'));
  }

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

  /// Resolve stored media identities before exposing a task's directory to navigation.
  Future<DownloadTask?> normalizeTask(String uid) async {
    final t = _tasks[uid];
    if (t == null || _disposed) return null;
    if (await t.normalizeMedia(SourceManager.instance.manifest(t.item.source))) {
      if (identical(_tasks[uid], t)) _save([t]);
    }
    return !_disposed && identical(_tasks[uid], t) ? t : null;
  }

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
    unawaited(SourceManager.instance.ready.then((_) async {
      for (final t in _tasks.values.toList()) {
        if (_disposed || !identical(_tasks[t.uid], t)) continue;
        if (await t.normalizeMedia(SourceManager.instance.manifest(t.item.source))) {
          if (identical(_tasks[t.uid], t)) _save([t]);
        }
      }
    }).catchError((Object e) => debugPrint('normalize downloads failed: $e')));
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

  void enqueue(WorkItem item, List<Chapter> chapters, {int? videoQuality}) {
    if (_disposed || chapters.isEmpty) return;
    if (item.source == localSource) {
      return; // imported files are already complete
    }
    final deleting = _deletions[item.uid];
    if (deleting != null) {
      final existing = _tasks[item.uid];
      final requested = List<Chapter>.of(chapters);
      if (existing != null) {
        existing.status = DownloadStatus.queued;
        _save([existing]);
      }
      unawaited(deleting.then((_) {
        if (existing == null) {
          enqueue(item, requested, videoQuality: videoQuality);
        } else if (!_disposed && identical(_tasks[item.uid], existing)) {
          _addChapters(existing, requested, videoQuality: videoQuality);
          _save([existing]);
          _pump();
        }
      }));
      return;
    }
    final existing = _tasks[item.uid];
    if (existing != null) {
      if (videoQuality != null && existing.media == null) {
        final requested = List<Chapter>.of(chapters);
        if (existing.status != DownloadStatus.running) {
          existing.status = DownloadStatus.queued;
        }
        _save([existing]);
        unawaited(existing.normalizeMedia(
          SourceManager.instance.manifest(item.source) ??
              SourceManifest({'key': item.source, 'type': 'video'}),
        ).then((_) {
          if (!_disposed && identical(_tasks[item.uid], existing)) {
            _addChapters(existing, requested, videoQuality: videoQuality);
            _save([existing]);
            _pump();
          }
        }).catchError((Object e) => debugPrint('normalize video download failed: $e')));
        return;
      }
      _addChapters(existing, chapters, videoQuality: videoQuality);
      if (existing.status != DownloadStatus.running) {
        existing.status = DownloadStatus.queued;
      }
    } else {
      _tasks[item.uid] = DownloadTask(
        item: item,
        chapters: chapters,
        media: videoQuality == null ? DownloadMedia.comic : DownloadMedia.video,
        videoQuality: videoQuality,
      );
    }
    _save([_tasks[item.uid]!]);
    _pump();
  }

  static void _addChapters(DownloadTask task, List<Chapter> chapters, {int? videoQuality}) {
    final known = task.chapters.map((c) => c.id).toSet();
    task.chapters.addAll(chapters.where((c) => known.add(c.id)));
    if (videoQuality != null) {
      task.media = DownloadMedia.video;
      task.videoQuality = videoQuality;
    }
  }

  void enqueueVideo(WorkItem item, List<Chapter> episodes, {int quality = 0}) =>
      enqueue(item, episodes, videoQuality: quality);

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
  Future<void> deleteChapters(String uid, List<String> chapterIds) {
    final deleting = _deletions[uid];
    if (deleting != null) {
      return deleting.then((_) => deleteChapters(uid, chapterIds));
    }
    final t = _tasks[uid];
    if (t == null || chapterIds.isEmpty) return Future.value();
    if (t.chapters.every((c) => chapterIds.contains(c.id))) return delete(uid);
    // Stop the current writer while retaining the latest queued/paused intent.
    if (t.status == DownloadStatus.running) {
      t.status = DownloadStatus.queued;
      t.cancel?.cancel('chapters deleted');
    }
    late final Future<void> deletion;
    deletion = _deleteChapters(t, List.of(chapterIds)).whenComplete(() {
      if (identical(_deletions[uid], deletion)) _deletions.remove(uid);
      _pump();
    });
    _deletions[uid] = deletion;
    return deletion;
  }

  Future<void> _deleteChapters(DownloadTask t, List<String> chapterIds) async {
    final pending = _runs[t];
    if (pending != null) await pending;
    if (!identical(_tasks[t.uid], t)) return;
    for (final id in chapterIds) {
      final relative = t.videoFiles.remove(id);
      if (relative != null) {
        final file = await _videoFile(t, relative);
        if (file != null) await file.delete();
      }
      final dir = t.isVideo
          ? t.videoDirectory(id)
          : Directory(p.join(t.dir.path, DownloadTask._safe(id)));
      final root = p.normalize(p.absolute(t.dir.path));
      final target = p.normalize(p.absolute(dir.path));
      if (p.isWithin(root, target) && await dir.exists()) {
        final actualRoot = await t.dir.resolveSymbolicLinks();
        final actual = await dir.resolveSymbolicLinks();
        if (p.isWithin(actualRoot, actual)) await dir.delete(recursive: true);
      }
      t.completed.remove(id);
    }
    t.chapters.removeWhere((c) => chapterIds.contains(c.id));
    _save([t]);
  }

  /// Registers an already complete task (local imports).
  void addCompleted(DownloadTask t) {
    _tasks[t.uid] = t;
    _save([t]);
  }

  Future<void> delete(String uid) {
    final pending = _deletions[uid];
    if (pending != null && !_tasks.containsKey(uid)) return pending;
    final t = _tasks.remove(uid);
    if (t != null) {
      t.status = DownloadStatus.paused;
      t.cancel?.cancel('download deleted');
    }
    late final Future<void> deletion;
    deletion = (pending == null ? _delete(uid, t) : pending.then((_) => _delete(uid, t))).whenComplete(() {
      if (identical(_deletions[uid], deletion)) _deletions.remove(uid);
      _pump();
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
      if (_active.containsKey(source) || _deletions.containsKey(next.uid)) continue;
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
      await t.normalizeMedia(SourceManager.instance.manifest(t.item.source));
      _checkRunning(t, token);
      if (t.media == null) throw SourceError('CONFIG', '视频源未加载');
      _save([t]);
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
    t.total = t.chapters.length * 1000;
    t.done = 0;
    t.bytes = 0;
    for (var index = 0; index < t.chapters.length; index++) {
      _checkRunning(t, token);
      final episode = t.chapters[index];
      final local = await localVideo(t.item.source, t.item.id, episodeId: episode.id);
      _checkRunning(t, token);
      if (local != null) {
        t.done += 1000;
        t.bytes += await local.length();
        continue;
      }
      t.completed.remove(episode.id);
      t.videoFiles.remove(episode.id);
      final sources = await _cancellable(
        SourceManager.instance.videos(
          t.item.source, t.item.id, episodeId: episode.id, cancelToken: token,
        ), token,
      );
      _checkRunning(t, token);
      if (sources.isEmpty) throw SourceError('NOT_FOUND', '视频源未加载');
      final src = sources.firstWhere(
        (s) => t.videoQuality != 0 && s.quality == t.videoQuality,
        orElse: () => sources.firstWhere((s) => s.preferred, orElse: () => sources.first),
      );
      // Preserve the single-video output location so existing validated HLS parts remain reusable.
      final directory = t.videoDirectory(episode.id);
      await directory.create(recursive: true);
      _checkRunning(t, token);
      final file = File(p.join(directory.path, 'video_${src.quality}p.mp4'));
      final part = File('${file.path}.part');
      final beforeDone = t.done;
      final beforeBytes = t.bytes;
      var lastNotify = DateTime.now();
      void progress(int done, int total, int bytes) {
        if (token.isCancelled || !identical(_tasks[t.uid], t)) return;
        t.total = t.chapters.length * 1000;
        t.done = beforeDone + (total > 0 ? (done * 1000 ~/ total).clamp(0, 999) : 0);
        t.bytes = beforeBytes + bytes;
        if (DateTime.now().difference(lastNotify).inMilliseconds > 300) {
          lastNotify = DateTime.now();
          notifyListeners();
        }
      }
      if (src.format == 'hls') {
        final manifest = SourceManager.instance.manifest(t.item.source);
        if (manifest == null) throw SourceError('CONFIG', '视频源未加载');
        if (!Platform.isAndroid) {
          throw SourceError('UNSUPPORTED', 'HLS 下载封装目前仅支持安卓');
        }
        await HlsDownload(createMediaTransport(manifest, headers: src.headers)).run(
          Uri.parse(src.url), output: part, cancelToken: token, onProgress: progress,
        );
      } else {
        await HttpService.instance.download(
          url: src.url, savePath: part.path, headers: src.headers,
          partition: t.item.source, cancelToken: token,
          onProgress: (received, total) => progress(received, total, received),
        );
        _checkRunning(t, token);
        final prefix = await part.openRead(0, 64).fold<List<int>>([], (a, b) => a..addAll(b));
        final text = utf8.decode(prefix, allowMalformed: true).trimLeft();
        if (prefix.isEmpty || text.startsWith('<') || text.startsWith('{') || text.startsWith('#EXTM3U')) {
          throw SourceError('PARSE', '视频响应不是可下载的媒体文件');
        }
      }
      _checkRunning(t, token);
      await part.rename(file.path);
      _checkRunning(t, token);
      t.videoFiles[episode.id] = p.relative(file.path, from: t.dir.path);
      t.completed.add(episode.id);
      t.bytes = beforeBytes + await file.length();
      t.done = beforeDone + 1000;
      _save([t]);
    }
    t.total = t.chapters.length * 1000;
  }

  static Future<File?> _videoFile(DownloadTask task, String relative) async {
    if (p.isAbsolute(relative)) return null;
    final root = p.normalize(p.absolute(task.dir.path));
    final target = p.normalize(p.join(root, relative));
    if (!p.isWithin(root, target) || p.extension(target).toLowerCase() != '.mp4') return null;
    final file = File(target);
    if (!await file.exists() || await file.length() == 0) return null;
    final actualRoot = await task.dir.resolveSymbolicLinks();
    final actual = await file.resolveSymbolicLinks();
    return p.isWithin(actualRoot, actual) ? file : null;
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

  Future<File?> localVideo(String source, String id, {String? episodeId}) async {
    final t = await normalizeTask('$source:$id');
    if (t == null) return null;
    final key = chapterKeyOf(episodeId);
    if (!t.completed.contains(key)) return null;
    final relative = t.videoFiles[key];
    return relative == null ? null : _videoFile(t, relative);
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
      'chaptersComplete': false,
      'chapters': single && !t.isVideo
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
    if (chapters.isEmpty) return;
    if (SourceManager.instance.manifest(item.source)?.isVideo == true) {
      enqueueVideo(item, chapters, quality: _tasks[item.uid]?.videoQuality ?? 0);
    } else {
      enqueue(item, chapters);
    }
  }
}
