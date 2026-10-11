import 'package:flutter_test/flutter_test.dart';
import 'package:hentai_park/core/models.dart';
import 'package:hentai_park/data/database.dart';
import 'package:hentai_park/library/library.dart';
import 'package:hentai_park/library/migration.dart';

ChapterState st(String id, String title, int sort, {bool read = false}) =>
    ChapterState(chapterId: id, title: title, sort: sort, read: read, dateFetch: DateTime(2026));

void main() {
  test('matchChapters prefers chapter numbers, falls back to position', () {
    final old = [st('a', '第1话', 0), st('b', '第2话', 1), st('c', '番外', 2)];
    final fresh = [Chapter('x', 'Ch.2'), Chapter('y', 'Ch.1'), Chapter('z', 'Extra')];
    expect(Migrator.matchChapters(old, fresh), {'a': 'y', 'b': 'x', 'c': 'z'});
    expect(Migrator.matchChapters([st('_', '全本', 0)], [Chapter('99', '全本')]), {'_': '99'});
    expect(Migrator.matchChapters([st('a', '第1话', 0), st('b', '番外', 1)], [Chapter('x', '1')]), {'a': 'x'});
  });

  test('migrate moves favorite, categories and read marks', () async {
    final lib = Library.instance;
    final db = AppDatabase.memory();
    await lib.open(db);
    final cat = await lib.createCategory('连载');
    final from = WorkItem({'id': '1', 'title': 'Title'}, 'jm');
    lib.addFavorite(from, categories: {cat!.id});
    await lib.syncChapters(from, [Chapter('a', '第1话'), Chapter('b', '第2话')]);
    lib.markRead(from.uid, ['a'], true);
    await lib.flush();

    final to = WorkDetail({
      'id': '77',
      'title': 'Title',
      'chapters': [
        {'id': 'p1', 'title': '第1话'},
        {'id': 'p2', 'title': '第2话'},
        {'id': 'p3', 'title': '第3话'},
      ],
    }, 'pica');
    await Migrator.migrate(lib, from: from, to: to);
    expect(lib.isFavorite('jm:1'), isFalse);
    expect(lib.isFavorite('pica:77'), isTrue);
    expect(lib.categoriesOf('pica:77'), {cat.id});
    await lib.loadChapters('pica:77');
    expect(lib.chapterState('pica:77', 'p1')!.read, isTrue);
    expect(lib.chapterState('pica:77', 'p2')!.read, isFalse);
    await db.close();
  });
}
