import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/app_log.dart';
import '../core/async_tasks.dart';
import '../core/localization.dart';
import '../core/models.dart';
import '../core/settings.dart';
import '../engine/source_manager.dart';
import 'library.dart';

typedef DetailFetcher = Future<WorkDetail> Function(String source, String id);

class UpdatedWork {
  UpdatedWork(this.item, this.chapterIds, this.chapterTitles);
  final WorkItem item;
  final List<String> chapterIds;
  final List<String> chapterTitles;
}

class UpdateResult {
  UpdateResult(this.time);
  final DateTime time;
  final List<UpdatedWork> updated = [];
  final List<({WorkItem item, String error})> errors = [];

  int get newChapters => updated.fold(0, (n, u) => n + u.chapterIds.length);
}

/// Checks favorites for new chapters (Mihon's library update). Sources run in parallel; works of
/// the same source run one after another with a pause in between, so site rate limits hold.
class LibraryUpdater extends ChangeNotifier {
  LibraryUpdater({
    DetailFetcher? fetch,
    this.library,
    bool Function(String source)? canUpdate,
    this.gap = const Duration(milliseconds: 500),
  }) : _fetch = fetch ?? ((s, id) => SourceManager.instance.detail(s, id)),
       _canUpdate = canUpdate ?? _defaultCanUpdate;

  static final LibraryUpdater instance = LibraryUpdater();

  final DetailFetcher _fetch;

  /// The library to update; [Library.instance] when null (tests inject their own).
  final Library? library;
  final bool Function(String source) _canUpdate;
  final Duration gap;

  Library get _lib => library ?? Library.instance;

  bool _running = false;
  bool _cancel = false;
  int done = 0;
  int total = 0;
  String? current;

  bool get running => _running;

  /// Hooks run after every finished update (notifications, auto-download…).
  final List<void Function(UpdateResult result)> onFinished = [];

  /// Progress hook (notifications); called at most once per finished work.
  void Function(LibraryUpdater updater)? onProgress;

  static bool _defaultCanUpdate(String source) {
    final s = SourceManager.instance[source];
    final m = s?.manifest;
    return s != null &&
        s.enabled &&
        s.ready &&
        m != null &&
        !m.opensExternally &&
        !m.isGame;
  }

  /// Whether a favorite is checked under the current restrictions.
  bool eligible(FavoriteEntry f) {
    if (!_canUpdate(f.item.source)) return false;
    final settings = AppSettings.instance;
    final stats = _lib.statsOf(f.item.uid);
    // Unknown chapter count (never synced) is always checked once.
    if (settings.updateOnlyMultiChapter && _lib.isOneShot(f.item.uid)) {
      return false;
    }
    if (settings.updateSkipUnread && stats.unread > 0) return false;
    if (settings.updateSkipNotStarted &&
        _lib.historyOf(f.item.uid) == null &&
        (stats.chapters == 0 || stats.unread == stats.chapters)) {
      return false;
    }
    return true;
  }

  void cancel() => _cancel = true;

  /// Runs an update over all favorites, or those of [category]. Returns null when one is already running.
  Future<UpdateResult?> run({int? category}) async {
    if (_running) return null;
    _running = true;
    _cancel = false;
    final result = UpdateResult(DateTime.now());
    final targets = _lib.favorites(category: category).where(eligible).toList();
    done = 0;
    total = targets.length;
    current = null;
    notifyListeners();
    try {
      final bySource = <String, List<FavoriteEntry>>{};
      for (final f in targets) {
        bySource.putIfAbsent(f.item.source, () => []).add(f);
      }
      await forEachConcurrent(
        bySource.values,
        4,
        (list) => _runSource(list, result),
      );
      if (category == null && !_cancel) {
        AppSettings.instance.lastLibraryUpdate =
            result.time.millisecondsSinceEpoch;
      }
    } finally {
      _running = false;
      current = null;
      notifyListeners();
    }
    for (final hook in onFinished) {
      try {
        hook(result);
      } catch (e) {
        AppLog.error(e, event: 'update_hook');
      }
    }
    return result;
  }

  Future<void> _runSource(
    List<FavoriteEntry> works,
    UpdateResult result,
  ) async {
    for (var i = 0; i < works.length; i++) {
      if (_cancel) return;
      final f = works[i];
      current = f.item.title;
      try {
        final d = await _fetch(f.item.source, f.item.id);
        final item = d.toItem();
        final isVideo =
            SourceManager.instance.manifest(f.item.source)?.isVideo == true;
        final chapters = isVideo
            ? d.videoEpisodes
            : d.chapters ??
                  [Chapter(chapterKeyOf(d.singleChapterId), tr('全本'))];
        final fresh = await _lib.syncChapters(
          item,
          chapters,
          oneShot: isVideo ? !d.hasVideoEpisodes : d.chapters == null,
          complete: d.chaptersComplete,
        );
        _lib.updateSnapshot(item);
        await _lib.markChecked(item.uid);
        if (fresh.isNotEmpty) {
          final titles = {
            for (final c in chapters) chapterKeyOf(c.id): c.title,
          };
          result.updated.add(
            UpdatedWork(item, fresh, [
              for (final id in fresh) titles[id] ?? id,
            ]),
          );
        }
      } catch (e) {
        result.errors.add((
          item: f.item,
          error: e is SourceError ? e.friendly : e.toString(),
        ));
      }
      done++;
      notifyListeners();
      onProgress?.call(this);
      if (i < works.length - 1 && gap > Duration.zero) {
        await Future.delayed(gap);
      }
    }
  }

  /// Starts an automatic update when the configured interval has passed.
  Future<void> autoUpdateIfDue() async {
    final s = AppSettings.instance;
    if (s.libraryUpdateHours <= 0 || _running) return;
    final due = DateTime.fromMillisecondsSinceEpoch(s.lastLibraryUpdate)
        .add(Duration(hours: s.libraryUpdateHours));
    if (DateTime.now().isBefore(due)) return;
    await SourceManager.instance.ready;
    await run();
  }
}
