import 'package:flutter_test/flutter_test.dart';
import 'package:hentai_park/core/models.dart';
import 'package:hentai_park/data/database.dart';
import 'package:hentai_park/library/library.dart';

WorkItem work(String id, {String source = 'jm', String title = 'T'}) => WorkItem({'id': id, 'title': title}, source);

void main() {
  late AppDatabase db;
  final lib = Library.instance;

  setUp(() async {
    db = AppDatabase.memory();
    await lib.open(db);
  });
  tearDown(() => db.close());

  test('favorites persist with categories and survive reopen', () async {
    final cat = await lib.createCategory('连载');
    lib.addFavorite(work('1'), categories: {cat!.id});
    lib.addFavorite(work('2'));
    await lib.flush();
    await lib.open(db);
    expect(lib.isFavorite('jm:1'), isTrue);
    expect(lib.favorites(category: cat.id).map((f) => f.item.id), ['1']);
    expect(lib.favorites(category: Library.defaultCategory).map((f) => f.item.id), ['2']);
    lib.deleteCategory(cat.id);
    await lib.flush();
    await lib.open(db);
    expect(lib.favorites(category: Library.defaultCategory).length, 2);
  });

  test('removing a favorite keeps the work snapshot but clears the flag', () async {
    lib.addFavorite(work('1'));
    lib.removeFavorite('jm:1');
    await lib.flush();
    await lib.open(db);
    expect(lib.isFavorite('jm:1'), isFalse);
  });

  test('syncChapters reports new chapters only after the first sync', () async {
    final w = work('9');
    expect(await lib.syncChapters(w, [Chapter('a', '第1话')]), isEmpty);
    final fresh = await lib.syncChapters(w, [Chapter('a', '第1话'), Chapter('b', '第2话')]);
    expect(fresh, ['b']);
    expect(lib.chaptersCached('jm:9')!.map((c) => c.chapterId), ['a', 'b']);
    expect(lib.statsOf('jm:9').unread, 2);
  });

  test('vanished chapters are dropped unless they carry reading state', () async {
    final w = work('9');
    await lib.syncChapters(w, [Chapter('a', '1'), Chapter('b', '2'), Chapter('c', '3')]);
    lib.markRead('jm:9', ['a'], true);
    await lib.flush();
    await lib.syncChapters(w, [Chapter('c', '3')]);
    expect(lib.chaptersCached('jm:9')!.map((c) => c.chapterId).toSet(), {'a', 'c'});
  });

  test('reaching the last page marks the chapter read; unread resets progress', () async {
    final w = work('5');
    await lib.syncChapters(w, [Chapter('x', 'X')]);
    lib.recordProgress(w, chapterId: 'x', page: 3, pageCount: 10);
    await lib.flush();
    await lib.loadChapters('jm:5');
    expect(lib.chapterState('jm:5', 'x')!.lastPage, 3);
    expect(lib.chapterState('jm:5', 'x')!.read, isFalse);
    lib.recordProgress(w, chapterId: 'x', page: 9, pageCount: 10);
    await lib.flush();
    await lib.loadChapters('jm:5');
    expect(lib.chapterState('jm:5', 'x')!.read, isTrue);
    expect(lib.statsOf('jm:5').unread, 0);
    lib.markRead('jm:5', ['x'], false);
    await lib.flush();
    await lib.loadChapters('jm:5');
    expect(lib.chapterState('jm:5', 'x')!.lastPage, 0);
  });

  test('history keeps the latest position per work', () async {
    lib.recordProgress(work('1', title: 'A'), page: 2, pageCount: 5);
    lib.recordVideoPosition(work('2', source: 'hanime1'), 90);
    await lib.flush();
    await lib.open(db);
    expect(lib.historyOf('jm:1')!.page, 2);
    expect(lib.historyOf('hanime1:2')!.position, 90);
    expect(lib.historyOf('jm:1')!.item.title, 'A');
  });
}
