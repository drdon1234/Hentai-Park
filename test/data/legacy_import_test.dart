import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hentai_park/data/database.dart';
import 'package:hentai_park/data/legacy_import.dart';
import 'package:hentai_park/library/library.dart';

void main() {
  late Directory tmp;
  late AppDatabase db;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('park_legacy');
    db = AppDatabase.memory();
  });
  tearDown(() async {
    await db.close();
    await tmp.delete(recursive: true);
  });

  Map<String, dynamic> item(String id) => {'id': id, 'source': 'jm', 'title': 'W$id', 'cover': 'c'};

  test('imports favorites, folders, history and downloads, then renames files', () async {
    File('${tmp.path}/favorites.json').writeAsStringSync(
      jsonEncode({
        'folders': ['默认收藏', '连载'],
        'items': [
          {'item': item('1'), 'added': 1000, 'folder': '默认收藏'},
          {'item': item('2'), 'added': 2000, 'folder': '连载'},
        ],
      }),
    );
    File('${tmp.path}/history.json').writeAsStringSync(
      jsonEncode([
        {'item': item('3'), 'time': 5000, 'chapterId': 'c1', 'chapterTitle': '第1话', 'page': 9, 'pageCount': 10},
      ]),
    );
    File('${tmp.path}/downloads.json').writeAsStringSync(
      jsonEncode([
        {'item': item('1'), 'chapters': [{'id': '_', 'title': '全本'}], 'status': 3, 'done': 5, 'total': 5},
      ]),
    );
    final imported = await LegacyImport.run(db, dataDir: tmp, downloadsDir: Directory('${tmp.path}/dl'));
    expect(imported, isTrue);
    expect(File('${tmp.path}/favorites.json.migrated').existsSync(), isTrue);

    final lib = Library.instance;
    await lib.open(db);
    expect(lib.categories.map((c) => c.name), ['连载']);
    expect(lib.favorites(category: Library.defaultCategory).map((f) => f.item.id), ['1']);
    expect(lib.favorites(category: lib.categories.first.id).map((f) => f.item.id), ['2']);
    expect(lib.historyOf('jm:3')!.page, 9);
    await lib.loadChapters('jm:3');
    expect(lib.chapterState('jm:3', 'c1')!.read, isTrue);
    final tasks = await db.select(db.downloadTasks).get();
    expect(tasks.single.dir, endsWith('1'));

    // A second run is a no-op.
    expect(await LegacyImport.run(db, dataDir: tmp, downloadsDir: tmp), isFalse);
  });
}
