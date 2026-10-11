import 'package:flutter_test/flutter_test.dart';
import 'package:hentai_park/core/models.dart';
import 'package:hentai_park/core/settings.dart';
import 'package:hentai_park/data/database.dart';
import 'package:hentai_park/library/library.dart';
import 'package:hentai_park/library/updater.dart';

WorkItem work(String id, {String source = 'jm'}) => WorkItem({'id': id, 'title': 'W$id'}, source);

void main() {
  final lib = Library.instance;
  late AppDatabase db;
  setUp(() async {
    db = AppDatabase.memory();
    await lib.open(db);
  });
  tearDown(() => db.close());

  test('reports new chapters, skips one-shots and unsupported sources, collects errors', () async {
    final site = <String, List<Chapter>>{
      'jm:1': [Chapter('a', '第1话'), Chapter('b', '第2话')],
      'jm:2': [Chapter('_', '全本')],
      'jm:3': [Chapter('x', '1')],
    };
    final fetched = <String>[];
    final updater = LibraryUpdater(
      library: lib,
      gap: Duration.zero,
      canUpdate: (s) => s == 'jm',
      fetch: (s, id) async {
        fetched.add('$s:$id');
        if (id == '3') throw SourceError('NETWORK', 'boom');
        return WorkDetail({
          'id': id,
          'title': 'W$id',
          if (id != '2') 'chapters': [for (final c in site['$s:$id']!) {'id': c.id, 'title': c.title}],
        }, s);
      },
    );
    for (final id in ['1', '2', '3']) {
      lib.addFavorite(work(id));
    }
    lib.addFavorite(work('9', source: 'hanime1'));
    await lib.syncChapters(work('1'), [Chapter('a', '第1话')]);
    await lib.syncChapters(work('2'), [Chapter('_', '全本')], oneShot: true);
    await lib.flush();

    final r = (await updater.run())!;
    expect(fetched.toSet(), {'jm:1', 'jm:3'}); // jm:2 is a synced one-shot, hanime1 unsupported
    expect(r.updated.single.item.id, '1');
    expect(r.updated.single.chapterTitles, ['第2话']);
    expect(r.errors.single.item.id, '3');
    expect(AppSettings.instance.lastLibraryUpdate, greaterThan(0));

    final feed = await lib.recentUpdates();
    expect(feed.map((e) => e.chapter.chapterId), ['b']);
  });
}
