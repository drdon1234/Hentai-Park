import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../core/content_scope.dart';
import '../core/diagnostics.dart';
import '../core/models.dart';
import '../core/settings.dart';
import '../data/database.dart';
import '../engine/source_manager.dart';
import 'progress_merge.dart';

/// Splits a `source:id` uid (ids may themselves contain ':' or '/').
(String, String) splitUid(String uid) {
  final i = uid.indexOf(':');
  return i < 0 ? ('', uid) : (uid.substring(0, i), uid.substring(i + 1));
}

/// The chapter key used for reading state: one-shot works use their single chapter id or '_'.
String chapterKeyOf(String? chapterId) =>
    (chapterId == null || chapterId.isEmpty) ? '_' : chapterId;

class Category {
  Category(this.id, this.name, this.sort);
  final int id;
  String name;
  int sort;
}

class HistoryEntry {
  HistoryEntry({
    required this.item,
    required this.time,
    this.chapterId,
    this.chapterTitle,
    this.page = 0,
    this.pageCount = 0,
    this.position,
  });

  WorkItem item;
  DateTime time;
  String? chapterId;
  String? chapterTitle;
  int page;
  int pageCount;
  int? position; // video position in seconds

  String get uid => item.uid;

  double get progress =>
      pageCount > 0 ? ((page + 1) / pageCount).clamp(0, 1) : 0;
}

class FavoriteEntry {
  FavoriteEntry(this.item, this.added, this.categories);
  WorkItem item;
  final DateTime added;
  Set<int> categories; // empty = the default category
}

class ChapterState {
  ChapterState({
    required this.chapterId,
    required this.title,
    required this.sort,
    this.read = false,
    this.lastPage = 0,
    this.pageCount = 0,
    this.progressUpdatedAt,
    this.position = 0,
    this.duration = 0,
    this.positionUpdatedAt,
    required this.dateFetch,
    this.dateRead,
  });

  final String chapterId;
  String title;
  int sort;
  bool read;
  int lastPage;
  int pageCount;
  DateTime? progressUpdatedAt;
  int position;
  int duration;
  DateTime? positionUpdatedAt;
  DateTime dateFetch;
  DateTime? dateRead;

  factory ChapterState.fromRow(ChapterRow r) => ChapterState(
    chapterId: r.chapterId,
    title: r.title,
    sort: r.sort,
    read: r.read,
    lastPage: r.lastPage,
    pageCount: r.pageCount,
    progressUpdatedAt: r.progressUpdatedAt == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(r.progressUpdatedAt!),
    position: r.position,
    duration: r.duration,
    positionUpdatedAt: r.positionUpdatedAt == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(r.positionUpdatedAt!),
    dateFetch: DateTime.fromMillisecondsSinceEpoch(r.dateFetch),
    dateRead: r.dateRead == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(r.dateRead!),
  );
}

class UpdateEntry {
  UpdateEntry(this.item, this.chapter);
  final WorkItem item;
  final ChapterState chapter;
}

/// Aggregated chapter facts per work, kept in memory for library badges and sorting.
class WorkStats {
  const WorkStats({this.chapters = 0, this.unread = 0, this.latestFetch});
  final int chapters;
  final int unread;
  final DateTime? latestFetch;
}

/// Parts of the library a screen can listen to without rebuilding for the others.
enum LibraryCollection { favorites, categories, history, chapters }

/// Favorites (with categories), chapter reading state and history, persisted in SQLite.
/// Favorites, categories and history are mirrored in memory so the UI can query them synchronously;
/// every mutation is a small targeted write instead of rewriting a file.
class Library extends ChangeNotifier {
  Library._() {
    // Only sources whose manifests changed need their snapshots refreshed.
    SourceManager.instance.manifestChanges.listen(_captureHistoryDomains);
  }
  static final Library instance = Library._();

  static const historyLimit = 2000;
  static const defaultCategory = 0;

  late AppDatabase _db;
  final Map<String, FavoriteEntry> _favorites = {};
  final Map<String, HistoryEntry> _history = {};
  final List<Category> _categories = [];
  final Map<String, List<ChapterState>> _chapters = {};
  final Map<String, WorkStats> _stats = {};
  final Set<String> _oneShots = {};

  AppDatabase get db => _db;

  final _collections = {for (final c in LibraryCollection.values) c: _Signal()};
  final _works = <String, _Signal>{};

  /// Notifies when [collection] changes anywhere in the library.
  Listenable collection(LibraryCollection collection) =>
      _collections[collection]!;

  /// Notifies when one work's favorite state, history, progress or chapter states change.
  Listenable work(String uid) => _works[uid] ??= _Signal(
    onUnused: (signal) {
      if (identical(_works[uid], signal)) _works.remove(uid);
    },
  );

  void _changed(
    Set<LibraryCollection> collections, [
    Iterable<String> uids = const [],
    bool allWorks = false,
  ]) {
    for (final c in collections) {
      _collections[c]!.notify();
    }
    for (final signal
        in allWorks
            ? [..._works.values]
            : [for (final uid in uids) ?_works[uid]]) {
      signal.notify();
    }
    notifyListeners();
  }

  /// Pauses history, progress and read marks (Mihon's incognito mode).
  bool get _incognito => AppSettings.instance.incognito;

  Future<void> open(AppDatabase db) async {
    await flush();
    _db = db;
    _favorites.clear();
    _history.clear();
    _categories.clear();
    _chapters.clear();
    _stats.clear();
    _oneShots.clear();
    for (final c
        in await (db.select(db.categories)..orderBy([
              (c) => OrderingTerm.asc(c.sort),
              (c) => OrderingTerm.asc(c.id),
            ]))
            .get()) {
      _categories.add(Category(c.id, c.name, c.sort));
    }
    final memberships = <String, Set<int>>{};
    for (final m in await db.select(db.workCategories).get()) {
      memberships
          .putIfAbsent('${m.source}:${m.workId}', () => {})
          .add(m.categoryId);
    }
    for (final w in await (db.select(
      db.works,
    )..where((w) => w.favorite.equals(true))).get()) {
      final item = _itemOf(w);
      if (w.oneShot) _oneShots.add(item.uid);
      _favorites[item.uid] = FavoriteEntry(
        item,
        DateTime.fromMillisecondsSinceEpoch(w.favoritedAt ?? 0),
        memberships[item.uid] ?? {},
      );
    }
    final rows = await (db.select(db.history).join([
      innerJoin(
        db.works,
        db.works.source.equalsExp(db.history.source) &
            db.works.id.equalsExp(db.history.workId),
      ),
    ])..orderBy([OrderingTerm.desc(db.history.time)])).get();
    for (final r in rows) {
      final h = r.readTable(db.history);
      final item = _itemOf(r.readTable(db.works));
      _history[item.uid] = HistoryEntry(
        item: item,
        time: DateTime.fromMillisecondsSinceEpoch(h.time),
        chapterId: h.chapterId,
        chapterTitle: h.chapterTitle,
        page: h.page,
        pageCount: h.pageCount,
        position: h.position,
      );
    }
    await _loadStats();
    _captureHistoryDomains();
    _changed(LibraryCollection.values.toSet(), const [], true);
  }

  static WorkItem _itemOf(WorkRow w) {
    Map<String, dynamic> json;
    try {
      json = (jsonDecode(w.json) as Map).cast<String, dynamic>();
    } catch (_) {
      json = {};
    }
    return WorkItem.fromStored({
      'title': w.title,
      'cover': w.cover,
      ...json,
      'id': w.id,
      'source': w.source,
    });
  }

  Future<void> _loadStats([String? uid]) async {
    final where = uid == null ? '' : 'WHERE source = ? AND work_id = ?';
    final args = <Variable>[];
    if (uid != null) {
      final (s, id) = splitUid(uid);
      args.addAll([Variable.withString(s), Variable.withString(id)]);
      _stats.remove(uid);
    }
    final rows = await _db
        .customSelect(
          'SELECT source, work_id, COUNT(*) AS n, SUM(CASE WHEN "read" = 0 THEN 1 ELSE 0 END) AS unread, MAX(date_fetch) AS latest '
          'FROM chapters $where GROUP BY source, work_id',
          variables: args,
          readsFrom: {_db.chapters},
        )
        .get();
    for (final r in rows) {
      final latest = r.read<int?>('latest');
      _stats['${r.read<String>('source')}:${r.read<String>('work_id')}'] =
          WorkStats(
            chapters: r.read<int>('n'),
            unread: r.read<int?>('unread') ?? 0,
            latestFetch: latest == null || latest == 0
                ? null
                : DateTime.fromMillisecondsSinceEpoch(latest),
          );
    }
  }

  WorkStats statsOf(String uid) => _stats[uid] ?? const WorkStats();

  /// Whether the site lists no chapters for this favorite (known after its first sync).
  bool isOneShot(String uid) => _oneShots.contains(uid);

  Future<void> _writes = Future<void>.value();
  (Object, StackTrace)? _writeFailure;

  void _run(Future<void> Function() write) {
    _writes = _writes.then((_) => write()).catchError((
      Object e,
      StackTrace st,
    ) {
      _writeFailure ??= (e, st);
      debugPrint(Diagnostics.error(e));
    });
  }

  /// Inserts or refreshes the stored snapshot of a work without touching its library flags.
  Future<void> _saveWork(WorkItem item) {
    final json = jsonEncode(_domainSnapshot(item).toJson());
    return _db
        .into(_db.works)
        .insert(
          WorksCompanion.insert(
            source: item.source,
            id: item.id,
            title: Value(item.title),
            cover: Value(item.cover),
            json: Value(json),
          ),
          onConflict: DoUpdate(
            (_) => WorksCompanion(
              title: Value(item.title),
              cover: Value(item.cover),
              json: Value(json),
            ),
          ),
        );
  }

  /// Refreshes cached snapshots (e.g. a newer cover) everywhere the work is shown.
  void updateSnapshot(WorkItem item) {
    item = _domainSnapshot(item);
    final fav = _favorites[item.uid];
    final hist = _history[item.uid];
    if (fav != null) fav.item = item;
    if (hist != null) hist.item = item;
    if (fav != null || hist != null) _run(() => _saveWork(item));
  }

  // ── Categories ──

  List<Category> get categories => List.unmodifiable(_categories);

  Category? category(int id) =>
      _categories.where((c) => c.id == id).firstOrNull;

  Future<Category?> createCategory(String name) async {
    final n = name.trim();
    if (n.isEmpty || _categories.any((c) => c.name == n)) return null;
    final sort = _categories.isEmpty
        ? 0
        : _categories.map((c) => c.sort).reduce((a, b) => a > b ? a : b) + 1;
    final id = await _db
        .into(_db.categories)
        .insert(CategoriesCompanion.insert(name: n, sort: Value(sort)));
    final c = Category(id, n, sort);
    _categories.add(c);
    _changed(const {LibraryCollection.categories});
    return c;
  }

  bool renameCategory(int id, String name) {
    final n = name.trim();
    final c = category(id);
    if (c == null ||
        n.isEmpty ||
        _categories.any((x) => x.name == n && x.id != id)) {
      return false;
    }
    c.name = n;
    _run(
      () => (_db.update(_db.categories)..where((t) => t.id.equals(id))).write(
        CategoriesCompanion(name: Value(n)),
      ),
    );
    _changed(const {LibraryCollection.categories});
    return true;
  }

  void deleteCategory(int id) {
    _categories.removeWhere((c) => c.id == id);
    for (final f in _favorites.values) {
      f.categories.remove(id);
    }
    _run(
      () => (_db.delete(_db.categories)..where((t) => t.id.equals(id))).go(),
    );
    _changed(const {LibraryCollection.categories, LibraryCollection.favorites});
  }

  void reorderCategories(List<int> ids) {
    for (var i = 0; i < ids.length; i++) {
      category(ids[i])?.sort = i;
    }
    _categories.sort((a, b) => a.sort.compareTo(b.sort));
    _run(
      () => _db.batch((b) {
        for (final c in _categories) {
          b.update(
            _db.categories,
            CategoriesCompanion(sort: Value(c.sort)),
            where: (t) => t.id.equals(c.id),
          );
        }
      }),
    );
    _changed(const {LibraryCollection.categories});
  }

  // ── Favorites ──

  /// [category]: null = all favorites, [defaultCategory] = favorites without a category.
  List<FavoriteEntry> favorites({int? category, String? source}) {
    return _favorites.values
        .where(
          (f) =>
              (source == null || f.item.source == source) &&
              (category == null ||
                  (category == defaultCategory
                      ? f.categories.isEmpty
                      : f.categories.contains(category))),
        )
        .toList()
      ..sort((a, b) => b.added.compareTo(a.added));
  }

  bool isFavorite(String uid) => _favorites.containsKey(uid);
  FavoriteEntry? favorite(String uid) => _favorites[uid];
  Set<int> categoriesOf(String uid) => {...?_favorites[uid]?.categories};

  void addFavorite(
    WorkItem item, {
    Set<int> categories = const {},
    DateTime? at,
  }) {
    item = _domainSnapshot(item);
    final now = at ?? DateTime.now();
    final valid = categories.where((id) => category(id) != null).toSet();
    _favorites[item.uid] = FavoriteEntry(item, now, valid);
    _run(() async {
      await _db.transaction(() async {
        await _saveWork(item);
        await (_db.update(_db.works)..where(
              (w) => w.source.equals(item.source) & w.id.equals(item.id),
            ))
            .write(
              WorksCompanion(
                favorite: const Value(true),
                favoritedAt: Value(now.millisecondsSinceEpoch),
              ),
            );
        await _writeCategories(item.uid, valid);
      });
    });
    _changed(const {LibraryCollection.favorites}, [item.uid]);
  }

  void removeFavorite(String uid) {
    if (_favorites.remove(uid) == null) return;
    final (source, id) = splitUid(uid);
    _run(
      () => _db.transaction(() async {
        await (_db.update(
          _db.works,
        )..where((w) => w.source.equals(source) & w.id.equals(id))).write(
          const WorksCompanion(
            favorite: Value(false),
            favoritedAt: Value(null),
          ),
        );
        await _writeCategories(uid, const {});
      }),
    );
    _changed(const {LibraryCollection.favorites}, [uid]);
  }

  void setCategories(String uid, Set<int> ids) {
    final f = _favorites[uid];
    if (f == null) return;
    final valid = ids.where((id) => category(id) != null).toSet();
    f.categories = valid;
    _run(() => _db.transaction(() => _writeCategories(uid, valid)));
    _changed(const {LibraryCollection.favorites}, [uid]);
  }

  Future<void> _writeCategories(String uid, Set<int> ids) async {
    final (source, id) = splitUid(uid);
    await (_db.delete(
      _db.workCategories,
    )..where((m) => m.source.equals(source) & m.workId.equals(id))).go();
    for (final c in ids) {
      await _db
          .into(_db.workCategories)
          .insert(
            WorkCategoriesCompanion.insert(
              source: source,
              workId: id,
              categoryId: c,
            ),
            mode: InsertMode.insertOrIgnore,
          );
    }
  }

  // ── Chapters ──

  /// Chapters loaded for [uid] by [loadChapters] or [syncChapters], sorted by site order.
  List<ChapterState>? chaptersCached(String uid) => _chapters[uid];

  Future<List<ChapterState>> loadChapters(String uid) async {
    final (source, id) = splitUid(uid);
    final rows =
        await (_db.select(_db.chapters)
              ..where((c) => c.source.equals(source) & c.workId.equals(id))
              ..orderBy([(c) => OrderingTerm.asc(c.sort)]))
            .get();
    final list = rows.map(ChapterState.fromRow).toList();
    _chapters[uid] = list;
    _changed(const {LibraryCollection.chapters}, [uid]);
    return list;
  }

  ChapterState? chapterState(String uid, String? chapterId) {
    final key = chapterKeyOf(chapterId);
    return _chapters[uid]?.where((c) => c.chapterId == key).firstOrNull;
  }

  /// Reconciles the stored chapter list with what the site returned. New chapters get
  /// `dateFetch = now`; chapters that vanished are dropped unless they carry reading state.
  /// Returns the ids of chapters that are new compared with a previous non-empty sync.
  Future<List<String>> syncChapters(
    WorkItem item,
    List<Chapter> chapters, {
    bool oneShot = false,
    bool complete = true,
    DateTime? now,
  }) async {
    final uid = item.uid;
    if (complete) {
      oneShot ? _oneShots.add(uid) : _oneShots.remove(uid);
    }
    final time = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final fresh = <String>[];
    await _db.transaction(() async {
      await _saveWork(item);
      if (complete) {
        await (_db.update(_db.works)..where(
              (w) => w.source.equals(item.source) & w.id.equals(item.id),
            ))
            .write(WorksCompanion(oneShot: Value(oneShot)));
      }
      final existing = {
        for (final r
            in await (_db.select(_db.chapters)..where(
                  (c) =>
                      c.source.equals(item.source) & c.workId.equals(item.id),
                ))
                .get())
          r.chapterId: r,
      };
      final seen = <String>{};
      var nextSort =
          existing.values.fold<int>(
            -1,
            (highest, row) => row.sort > highest ? row.sort : highest,
          ) +
          1;
      for (var i = 0; i < chapters.length; i++) {
        final ch = chapters[i];
        final key = chapterKeyOf(ch.id);
        if (!seen.add(key)) continue;
        final old = existing[key];
        if (old == null) {
          if (complete && existing.isNotEmpty) fresh.add(key);
          // The first sync is not an "update" (fetch time ~0); later chapters get a slightly later
          // fetch time so the updates feed keeps site order.
          final fetched = !complete
              ? 0
              : existing.isEmpty
              ? i
              : time + i;
          final sort = complete ? i : nextSort++;
          await _db
              .into(_db.chapters)
              .insert(
                ChaptersCompanion.insert(
                  source: item.source,
                  workId: item.id,
                  chapterId: key,
                  title: Value(ch.title),
                  sort: Value(sort),
                  dateFetch: Value(fetched),
                ),
              );
        } else if (old.title != ch.title || (complete && old.sort != i)) {
          await (_db.update(_db.chapters)..where(
                (c) =>
                    c.source.equals(item.source) &
                    c.workId.equals(item.id) &
                    c.chapterId.equals(key),
              ))
              .write(
                ChaptersCompanion(
                  title: Value(ch.title),
                  sort: complete ? Value(i) : const Value.absent(),
                ),
              );
        }
      }
      for (final old in complete ? existing.values : const <ChapterRow>[]) {
        if (seen.contains(old.chapterId) ||
            old.read ||
            old.lastPage > 0 ||
            old.progressUpdatedAt != null ||
            old.positionUpdatedAt != null) {
          continue;
        }
        await (_db.delete(_db.chapters)..where(
              (c) =>
                  c.source.equals(item.source) &
                  c.workId.equals(item.id) &
                  c.chapterId.equals(old.chapterId),
            ))
            .go();
      }
    });
    await _loadStats(uid);
    await loadChapters(uid);
    return fresh;
  }

  void markRead(String uid, Iterable<String> chapterIds, bool read) {
    if (_incognito) return;
    final ids = chapterIds.toSet();
    if (ids.isEmpty) return;
    final now = DateTime.now();
    final (source, id) = splitUid(uid);
    final video = SourceManager.instance.manifest(source)?.isVideo == true;
    for (final c in _chapters[uid] ?? const <ChapterState>[]) {
      if (!ids.contains(c.chapterId)) continue;
      c.read = read;
      c.dateRead = read ? now : null;
      c.progressUpdatedAt = now;
      if (video || c.positionUpdatedAt != null) c.positionUpdatedAt = now;
      if (!read) {
        c.lastPage = 0;
        c.position = 0;
      }
    }
    _run(() async {
      await (_db.update(_db.chapters)..where(
            (c) =>
                c.source.equals(source) &
                c.workId.equals(id) &
                c.chapterId.isIn(ids),
          ))
          .write(
            ChaptersCompanion(
              read: Value(read),
              dateRead: Value(read ? now.millisecondsSinceEpoch : null),
              progressUpdatedAt: Value(now.millisecondsSinceEpoch),
              lastPage: read ? const Value.absent() : const Value(0),
              position: read ? const Value.absent() : const Value(0),
            ),
          );
      await (_db.update(_db.chapters)..where(
            (c) =>
                c.source.equals(source) &
                c.workId.equals(id) &
                c.chapterId.isIn(ids) &
                (video
                    ? const Constant(true)
                    : c.positionUpdatedAt.isNotNull()),
          ))
          .write(
            ChaptersCompanion(
              positionUpdatedAt: Value(now.millisecondsSinceEpoch),
            ),
          );
      await _loadStats(uid);
      if (read) {
        for (final l in onChaptersRead) {
          l(uid, ids.toList());
        }
      }
      _changed(const {LibraryCollection.chapters}, [uid]);
    });
    _changed(const {LibraryCollection.chapters}, [uid]);
  }

  /// Read-state listeners (e.g. "delete after reading") get every chapter that just became read.
  final List<void Function(String uid, List<String> chapterIds)>
  onChaptersRead = [];

  // ── History ──

  SourceCategory domainOf(WorkItem item) =>
      SourceManager.instance.manifest(item.source)?.category ??
      SourceCategory.fromJson(item.json['contentDomain']);

  WorkItem _domainSnapshot(WorkItem item) {
    final manifest = SourceManager.instance.manifest(item.source);
    final kind =
        item.json['mediaKind'] ??
        manifest?.kind.name ??
        _history[item.uid]?.item.json['mediaKind'] ??
        _favorites[item.uid]?.item.json['mediaKind'];
    final domain =
        manifest?.category.name ??
        item.json['contentDomain'] ??
        _history[item.uid]?.item.json['contentDomain'] ??
        _favorites[item.uid]?.item.json['contentDomain'];
    if ((domain == null || item.json['contentDomain'] == domain) &&
        (kind == null || item.json['mediaKind'] == kind)) {
      return item;
    }
    return WorkItem({
      ...item.json,
      'contentDomain': ?domain,
      'mediaKind': ?kind,
    }, item.source);
  }

  /// Stores each work's category and media type with it, so history and favorites keep their
  /// place after the source is removed. [sources] limits the pass to changed sources.
  void _captureHistoryDomains([Set<String>? sources]) {
    var changed = false;
    for (final h in _history.values) {
      if (sources != null && !sources.contains(h.item.source)) continue;
      final item = _domainSnapshot(h.item);
      if (identical(item, h.item)) continue;
      h.item = item;
      final snapshot = item;
      _run(() => _saveWork(snapshot));
      changed = true;
    }
    for (final favorite in _favorites.values) {
      if (sources != null && !sources.contains(favorite.item.source)) continue;
      final item = _domainSnapshot(favorite.item);
      if (identical(item, favorite.item)) continue;
      favorite.item = item;
      _run(() => _saveWork(item));
      changed = true;
    }
    if (changed) {
      _changed(const {LibraryCollection.history, LibraryCollection.favorites});
    }
  }

  List<HistoryEntry> history({
    String? source,
    ContentScope scope = const ContentScope.all(),
  }) =>
      _history.values
          .where(
            (h) =>
                (source == null || h.item.source == source) &&
                scope.contains(h.item.source, domainOf(h.item)),
          )
          .toList()
        ..sort((a, b) => b.time.compareTo(a.time));

  HistoryEntry? historyOf(String uid) => _history[uid];

  /// Copies matched chapter progress without making the move a new reading event.
  Future<void> copyProgress(
    WorkItem from,
    WorkItem target,
    Map<String, String> chapters,
  ) async {
    if (_incognito || from.uid == target.uid) return;
    await flush();
    final old = _chapters[from.uid] ?? await loadChapters(from.uid);
    final history = _history[from.uid];
    var copiedHistory = false;
    await _db.transaction(() async {
      for (final state in old) {
        final key = chapters[state.chapterId];
        if (key == null) continue;
        final current =
            await (_db.select(_db.chapters)..where(
                  (c) =>
                      c.source.equals(target.source) &
                      c.workId.equals(target.id) &
                      c.chapterId.equals(key),
                ))
                .getSingleOrNull();
        if (current == null) continue;
        final comicTime = state.progressUpdatedAt?.millisecondsSinceEpoch;
        final videoTime = state.positionUpdatedAt?.millisecondsSinceEpoch;
        final selection = selectProgress(
          comic: comicTime,
          video: videoTime,
          currentComic: current.progressUpdatedAt,
          currentVideo: current.positionUpdatedAt,
        );
        final copyComic = selection.comic;
        final copyVideo = selection.video;
        final copyRead = selection.read;
        if (!copyComic && !copyVideo) continue;
        await (_db.update(_db.chapters)..where(
              (c) =>
                  c.source.equals(target.source) &
                  c.workId.equals(target.id) &
                  c.chapterId.equals(key),
            ))
            .write(
              ChaptersCompanion(
                read: copyRead ? Value(state.read) : const Value.absent(),
                dateRead: copyRead
                    ? Value(state.dateRead?.millisecondsSinceEpoch)
                    : const Value.absent(),
                lastPage: copyComic
                    ? Value(state.lastPage)
                    : const Value.absent(),
                pageCount: copyComic
                    ? Value(state.pageCount)
                    : const Value.absent(),
                progressUpdatedAt: copyComic
                    ? Value(comicTime)
                    : const Value.absent(),
                position: copyVideo
                    ? Value(state.position)
                    : const Value.absent(),
                duration: copyVideo
                    ? Value(state.duration)
                    : const Value.absent(),
                positionUpdatedAt: copyVideo
                    ? Value(videoTime)
                    : const Value.absent(),
              ),
            );
      }
      if (history == null ||
          !chapters.containsKey(chapterKeyOf(history.chapterId))) {
        return;
      }
      final current = _history[target.uid];
      if (current != null && !history.time.isAfter(current.time)) return;
      final key = chapters[chapterKeyOf(history.chapterId)]!;
      final state = chapterState(target.uid, key);
      final copied = HistoryEntry(
        item: _domainSnapshot(target),
        time: history.time,
        chapterId: key,
        chapterTitle: state?.title,
        page: history.page,
        pageCount: history.pageCount,
        position: history.position,
      );
      await _db
          .into(_db.history)
          .insertOnConflictUpdate(_historySnapshot(copied));
      _history[target.uid] = copied;
      copiedHistory = true;
    });
    await loadChapters(target.uid);
    await _loadStats(target.uid);
    if (copiedHistory || chapters.isNotEmpty) {
      _changed(
        const {LibraryCollection.history, LibraryCollection.chapters},
        [target.uid],
      );
    }
  }

  void recordVisit(WorkItem item) {
    item = _domainSnapshot(item);
    updateSnapshot(item);
    if (_incognito) return;
    final h = _history[item.uid];
    if (h == null) {
      _history[item.uid] = HistoryEntry(item: item, time: DateTime.now());
    } else {
      h
        ..item = item
        ..time = DateTime.now();
    }
    _saveHistory(_history[item.uid]!);
    _changed(const {LibraryCollection.history}, [item.uid]);
  }

  /// Records the reader position. [chapterKey] identifies the chapter row ('_' / single id for one-shots);
  /// reaching the last page marks the chapter read.
  void recordProgress(
    WorkItem item, {
    String? chapterId,
    String? chapterKey,
    String? chapterTitle,
    required int page,
    required int pageCount,
  }) {
    if (_incognito) return;
    item = _domainSnapshot(item);
    final h =
        _history[item.uid] ?? HistoryEntry(item: item, time: DateTime.now());
    h
      ..item = item
      ..time = DateTime.now()
      ..chapterId = chapterId
      ..chapterTitle = chapterTitle
      ..page = page
      ..pageCount = pageCount;
    _history[item.uid] = h;
    _saveHistory(h);

    final key = chapterKeyOf(chapterKey ?? chapterId);
    final finished = pageCount > 0 && page >= pageCount - 1;
    final cached = chapterState(item.uid, key);
    final becameRead = finished && cached?.read != true;
    if (cached != null) {
      cached
        ..lastPage = page
        ..pageCount = pageCount
        ..progressUpdatedAt = h.time;
      if (finished) {
        cached
          ..read = true
          ..dateRead ??= DateTime.now();
      }
    }
    final now = h.time.millisecondsSinceEpoch;
    _run(() async {
      await _db
          .into(_db.chapters)
          .insert(
            ChaptersCompanion.insert(
              source: item.source,
              workId: item.id,
              chapterId: key,
              title: Value(chapterTitle ?? ''),
              lastPage: Value(page),
              pageCount: Value(pageCount),
              progressUpdatedAt: Value(now),
              read: Value(finished),
              dateRead: Value(finished ? now : null),
            ),
            onConflict: DoUpdate(
              (old) => ChaptersCompanion.custom(
                lastPage: Constant(page),
                pageCount: Constant(pageCount),
                progressUpdatedAt: Constant(now),
                read: finished ? const Constant(true) : old.read,
                dateRead: finished
                    ? coalesce([old.dateRead, Constant(now)])
                    : old.dateRead,
              ),
            ),
          );
      if (becameRead) {
        await _loadStats(item.uid);
        for (final l in onChaptersRead) {
          l(item.uid, [key]);
        }
        _changed(
          const {LibraryCollection.history, LibraryCollection.chapters},
          [item.uid],
        );
      }
    });
  }

  void recordVideoPosition(
    WorkItem item,
    int seconds, {
    String? episodeId,
    String? episodeTitle,
    int? duration,
  }) {
    if (_incognito) return;
    item = _domainSnapshot(item);
    final key = chapterKeyOf(episodeId);
    final now = DateTime.now();
    final position = seconds < 0 ? 0 : seconds;
    final length = duration != null && duration > 0 ? duration : 0;
    final finished = length > 0 && position >= length;
    final cached = chapterState(item.uid, key);
    if (cached != null) {
      cached.position = position;
      if (length > 0) cached.duration = length;
      cached.positionUpdatedAt = now;
      if (finished) {
        cached.read = true;
        cached.dateRead ??= now;
      }
    }
    final h = _history[item.uid] ?? HistoryEntry(item: item, time: now);
    h
      ..item = item
      ..time = now
      ..chapterId = key
      ..chapterTitle = episodeTitle
      ..page = 0
      ..pageCount = 0
      ..position = position;
    _history[item.uid] = h;
    final history = _historySnapshot(h);
    _run(() async {
      await _db.transaction(() async {
        await _saveWork(item);
        await _db.into(_db.history).insertOnConflictUpdate(history);
        await _db
            .into(_db.chapters)
            .insert(
              ChaptersCompanion.insert(
                source: item.source,
                workId: item.id,
                chapterId: key,
                title: Value(episodeTitle ?? ''),
                position: Value(position),
                duration: Value(length),
                positionUpdatedAt: Value(now.millisecondsSinceEpoch),
                read: Value(finished),
                dateRead: Value(finished ? now.millisecondsSinceEpoch : null),
              ),
              onConflict: DoUpdate(
                (old) => ChaptersCompanion.custom(
                  position: Constant(position),
                  duration: length > 0 ? Constant(length) : old.duration,
                  positionUpdatedAt: Constant(now.millisecondsSinceEpoch),
                  read: finished ? const Constant(true) : old.read,
                  dateRead: finished
                      ? coalesce([
                          old.dateRead,
                          Constant(now.millisecondsSinceEpoch),
                        ])
                      : old.dateRead,
                ),
              ),
            );
      });
      await _loadStats(item.uid);
      _changed(
        const {LibraryCollection.history, LibraryCollection.chapters},
        [item.uid],
      );
    });
    _trimHistory(item.source);
  }

  static HistoryCompanion _historySnapshot(HistoryEntry h) =>
      HistoryCompanion.insert(
        source: h.item.source,
        workId: h.item.id,
        time: h.time.millisecondsSinceEpoch,
        chapterId: Value(h.chapterId),
        chapterTitle: Value(h.chapterTitle),
        page: Value(h.page),
        pageCount: Value(h.pageCount),
        position: Value(h.position),
      );

  void _saveHistory(HistoryEntry h) {
    final item = h.item;
    final snapshot = _historySnapshot(h);
    _run(() async {
      await _db.transaction(() async {
        await _saveWork(item);
        await _db.into(_db.history).insertOnConflictUpdate(snapshot);
      });
    });
    _trimHistory(item.source);
  }

  void _trimHistory(String source) {
    final entries = _history.values
        .where((h) => h.item.source == source)
        .toList();
    if (entries.length <= historyLimit + 100) return;
    entries.sort((a, b) => b.time.compareTo(a.time));
    removeHistoryMany(entries.skip(historyLimit).map((h) => h.uid));
  }

  void removeHistory(String uid) {
    _history.remove(uid);
    final (source, id) = splitUid(uid);
    _run(
      () => (_db.delete(
        _db.history,
      )..where((t) => t.source.equals(source) & t.workId.equals(id))).go(),
    );
    _changed(const {LibraryCollection.history}, [uid]);
  }

  void removeHistoryMany(Iterable<String> uids) {
    final list = uids.toList();
    if (list.isEmpty) return;
    for (final uid in list) {
      _history.remove(uid);
    }
    _run(
      () => _db.transaction(() async {
        for (final uid in list) {
          final (source, id) = splitUid(uid);
          await (_db.delete(
            _db.history,
          )..where((t) => t.source.equals(source) & t.workId.equals(id))).go();
        }
      }),
    );
    _changed(const {LibraryCollection.history}, list);
  }

  void clearHistory({ContentScope scope = const ContentScope.all()}) {
    removeHistoryMany(history(scope: scope).map((h) => h.uid));
  }

  // ── Library updates ──

  /// Records that a library update just checked this work.
  Future<void> markChecked(String uid) {
    final (source, id) = splitUid(uid);
    return (_db.update(
      _db.works,
    )..where((w) => w.source.equals(source) & w.id.equals(id))).write(
      WorksCompanion(
        lastUpdateCheck: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  /// Chapters that appeared after their work was added to the library, newest first (the updates feed).
  Future<List<UpdateEntry>> recentUpdates({int limit = 300}) async {
    final rows =
        await (_db.select(_db.chapters).join([
                innerJoin(
                  _db.works,
                  _db.works.source.equalsExp(_db.chapters.source) &
                      _db.works.id.equalsExp(_db.chapters.workId),
                ),
              ])
              ..where(
                _db.works.favorite.equals(true) &
                    _db.chapters.dateFetch.isBiggerThan(
                      coalesce([_db.works.favoritedAt, const Constant(0)]),
                    ),
              )
              ..orderBy([OrderingTerm.desc(_db.chapters.dateFetch)])
              ..limit(limit))
            .get();
    return [
      for (final r in rows)
        UpdateEntry(
          _itemOf(r.readTable(_db.works)),
          ChapterState.fromRow(r.readTable(_db.chapters)),
        ),
    ];
  }

  // ── Per-work preferences ──

  Future<int?> readerModeOf(String uid) async {
    final (source, id) = splitUid(uid);
    final row =
        await (_db.select(_db.works)
              ..where((w) => w.source.equals(source) & w.id.equals(id)))
            .getSingleOrNull();
    return row?.readerMode;
  }

  Future<void> setReaderMode(WorkItem item, int? mode) async {
    await _saveWork(item);
    await (_db.update(_db.works)
          ..where((w) => w.source.equals(item.source) & w.id.equals(item.id)))
        .write(WorksCompanion(readerMode: Value(mode)));
  }

  /// Waits for queued writes (used before backups and in tests).
  Future<void> flush() async {
    while (true) {
      final pending = _writes;
      await pending;
      if (identical(pending, _writes)) break;
    }
    final failure = _writeFailure;
    _writeFailure = null;
    if (failure != null) {
      Error.throwWithStackTrace(failure.$1, failure.$2);
    }
  }
}

/// A listenable that forgets itself once nobody listens, so per-work signals do not pile up.
/// The check runs a microtask later: widgets swap listenables by removing and re-adding a
/// listener in one go, and that must not orphan the signal they keep using.
class _Signal extends ChangeNotifier {
  _Signal({this.onUnused});
  final void Function(_Signal signal)? onUnused;

  void notify() => notifyListeners();

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (onUnused case final onUnused?) {
      scheduleMicrotask(() {
        if (!hasListeners) onUnused(this);
      });
    }
  }
}
