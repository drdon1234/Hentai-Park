import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hentai_park/core/models.dart';
import 'package:hentai_park/library/cbz.dart';
import 'package:hentai_park/library/downloads.dart';

final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0, 0, 0, 0, 1, 2, 3]);
final jpg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 9, 9, 9]);

void main() {
  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('park_cbz'));
  tearDown(() => tmp.delete(recursive: true));

  test('naturalCompare and imageExtension', () {
    final names = ['p10.jpg', 'p2.jpg', 'p1.jpg'];
    names.sort(naturalCompare);
    expect(names, ['p1.jpg', 'p2.jpg', 'p10.jpg']);
    expect(imageExtension(png), '.png');
    expect(imageExtension(jpg), '.jpg');
  });

  test('ComicInfo round trip escapes XML', () {
    final xml = ComicInfo(title: 'A & B <1>', writer: 'X', tags: ['t1', 't2'], pageCount: 3).toXml();
    final back = ComicInfo.parse(xml);
    expect(back.title, 'A & B <1>');
    expect(back.tags, ['t1', 't2']);
    expect(back.pageCount, 3);
  });

  test('imports a zip as a completed local task and exports it back', () async {
    final zip = Archive()
      ..addFile(ArchiveFile.bytes('dir/page10.png', png))
      ..addFile(ArchiveFile.bytes('dir/page2.jpg', jpg))
      ..addFile(ArchiveFile.bytes('__MACOSX/._page2.jpg', [1, 2]))
      ..addFile(ArchiveFile.string('ComicInfo.xml', ComicInfo(title: '本地作品', tags: ['全彩']).toXml()));
    final bytes = ZipEncoder().encodeBytes(zip);
    final task = await Cbz.importArchive('x.cbz', bytes, root: tmp);
    expect(task.item.source, localSource);
    expect(task.item.title, '本地作品');
    expect(task.item.tags, ['全彩']);
    expect(task.completed, {'_'});
    final pages = jsonDecode(File('${task.dir.path}/_/pages.json').readAsStringSync())['pages'] as List;
    expect(pages.length, 2);
    // page2 sorts before page10.
    expect(File('${task.dir.path}/_/0001.img').readAsBytesSync(), jpg);

    final again = await Cbz.importArchive('x.cbz', bytes, root: tmp);
    expect(again.item.id, task.item.id);

    final out = await Cbz.exportTask(task, Directory('${tmp.path}/out'));
    final exported = ZipDecoder().decodeBytes(out.single.readAsBytesSync());
    expect(exported.files.map((f) => f.name).toList(), ['0001.jpg', '0002.png', 'ComicInfo.xml']);
    expect(ComicInfo.parse(utf8.decode(exported.files.last.content)).title, '本地作品');
  });

  test('rejects archives without images', () async {
    final bytes = ZipEncoder().encodeBytes(Archive()..addFile(ArchiveFile.string('a.txt', 'x')));
    expect(() => Cbz.importArchive('a.zip', bytes, root: tmp), throwsFormatException);
  });

  test('chapter model unaffected', () => expect(Chapter('_', '全本').id, '_'));
}
