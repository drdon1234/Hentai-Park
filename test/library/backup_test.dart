import 'package:flutter_test/flutter_test.dart';
import 'package:hentai_park/core/models.dart';
import 'package:hentai_park/data/database.dart';
import 'package:hentai_park/library/backup.dart';
import 'package:hentai_park/library/library.dart';

WorkItem work(String id) => WorkItem({'id': id, 'title': 'W$id'}, 'jm');

void main() {
  final lib = Library.instance;

  test('encode/decode round trip and rejects foreign files', () {
    final bytes = BackupService.encode({'format': 'parkbak', 'version': 1, 'x': 1});
    expect(BackupService.decode(bytes)['x'], 1);
    expect(() => BackupService.decode([1, 2, 3]), throwsFormatException);
    expect(() => BackupService.decode(BackupService.encode({'format': 'other'})), throwsFormatException);
    expect(() => BackupService.decode(BackupService.encode({'format': 'parkbak', 'version': 99})), throwsFormatException);
  });

  test('library export merges into another database', () async {
    // Source device.
    final a = AppDatabase.memory();
    await lib.open(a);
    final cat = await lib.createCategory('连载');
    lib.addFavorite(work('1'), categories: {cat!.id});
    await lib.syncChapters(work('1'), [Chapter('c1', '1'), Chapter('c2', '2')]);
    lib.recordProgress(work('1'), chapterId: 'c1', page: 9, pageCount: 10);
    lib.recordProgress(work('1'), chapterId: 'c2', page: 2, pageCount: 10);
    await lib.flush();
    final exported = await BackupService.exportLibrary(a);

    // Target device already has its own data, including a newer position on c2.
    final b = AppDatabase.memory();
    await lib.open(b);
    lib.addFavorite(work('2'));
    await lib.syncChapters(work('1'), [Chapter('c1', '1'), Chapter('c2', '2')]);
    lib.recordProgress(work('1'), chapterId: 'c2', page: 6, pageCount: 10);
    await lib.flush();

    final report = RestoreReport();
    await BackupService.mergeLibrary(b, exported, report);
    await lib.open(b);
    expect(report.favorites, 1);
    expect(lib.isFavorite('jm:1') && lib.isFavorite('jm:2'), isTrue);
    expect(lib.categoriesOf('jm:1').map((id) => lib.category(id)!.name), ['连载']);
    await lib.loadChapters('jm:1');
    expect(lib.chapterState('jm:1', 'c1')!.read, isTrue);
    expect(lib.chapterState('jm:1', 'c2')!.lastPage, 6); // the larger value wins
    // History: the local entry (written later) is kept.
    expect(lib.historyOf('jm:1')!.page, 6);

    // Merging twice changes nothing.
    final again = RestoreReport();
    await BackupService.mergeLibrary(b, exported, again);
    expect(again.favorites, 0);
    expect(again.categories, 0);
    await a.close();
    await b.close();
  });

  test('backup file names sort chronologically', () {
    final a = BackupService.fileName(DateTime(2026, 1, 2, 3, 4, 5));
    final b = BackupService.fileName(DateTime(2026, 1, 10, 0, 0, 0));
    expect(a, 'hentaipark_20260102_030405.parkbak');
    expect(b.compareTo(a), greaterThan(0));
  });
}
