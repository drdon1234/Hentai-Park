import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../core/async_tasks.dart';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../core/models.dart';
import '../core/storage.dart';
import '../images/park_image.dart';
import 'downloads.dart';
import '../core/localization.dart';

/// Comic metadata written to / read from ComicInfo.xml (the de-facto CBZ metadata format).
class ComicInfo {
  ComicInfo({
    this.title = '',
    this.series = '',
    this.writer = '',
    this.tags = const [],
    this.summary = '',
    this.web = '',
    this.pageCount = 0,
  });
  final String title;
  final String series;
  final String writer;
  final List<String> tags;
  final String summary;
  final String web;
  final int pageCount;

  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  String toXml() {
    final b = StringBuffer(
      '<?xml version="1.0" encoding="utf-8"?>\n<ComicInfo xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">\n',
    );
    void el(String name, String value) {
      if (value.isNotEmpty) b.writeln('  <$name>${_esc(value)}</$name>');
    }

    el('Title', title);
    el('Series', series);
    el('Writer', writer);
    el('Tags', tags.join(', '));
    el('Summary', summary);
    el('Web', web);
    if (pageCount > 0) el('PageCount', '$pageCount');
    b.write('</ComicInfo>\n');
    return b.toString();
  }

  static ComicInfo parse(String xml) {
    String get(String name) {
      final m = RegExp('<$name>([\\s\\S]*?)</$name>').firstMatch(xml);
      if (m == null) return '';
      return m
          .group(1)!
          .replaceAll('&lt;', '<')
          .replaceAll('&gt;', '>')
          .replaceAll('&quot;', '"')
          .replaceAll('&amp;', '&')
          .trim();
    }

    final tags = [get('Tags'), get('Genre')]
        .expand((s) => s.split(RegExp(r'[,，]')))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    return ComicInfo(
      title: get('Title'),
      series: get('Series'),
      writer: get('Writer'),
      tags: tags,
      summary: get('Summary'),
      web: get('Web'),
      pageCount: int.tryParse(get('PageCount')) ?? 0,
    );
  }
}

/// "page2.jpg" < "page10.jpg".
int naturalCompare(String a, String b) {
  final re = RegExp(r'(\d+)|(\D+)');
  final pa = re.allMatches(a.toLowerCase()).map((m) => m.group(0)!).toList();
  final pb = re.allMatches(b.toLowerCase()).map((m) => m.group(0)!).toList();
  for (var i = 0; i < pa.length && i < pb.length; i++) {
    final x = int.tryParse(pa[i]), y = int.tryParse(pb[i]);
    final c = (x != null && y != null)
        ? x.compareTo(y)
        : pa[i].compareTo(pb[i]);
    if (c != 0) return c;
  }
  return pa.length.compareTo(pb.length);
}

const _imageExtensions = {
  '.jpg',
  '.jpeg',
  '.png',
  '.webp',
  '.gif',
  '.avif',
  '.bmp',
};

/// File extension from the image's magic bytes (downloads are stored as `.img`).
String imageExtension(Uint8List b) {
  if (b.length > 3 && b[0] == 0xFF && b[1] == 0xD8) return '.jpg';
  if (b.length > 3 && b[0] == 0x89 && b[1] == 0x50) return '.png';
  if (b.length > 3 && b[0] == 0x47 && b[1] == 0x49) return '.gif';
  if (b.length > 12 && b[0] == 0x52 && b[1] == 0x49 && b[8] == 0x57) {
    return '.webp';
  }
  if (b.length > 12 &&
      b[4] == 0x66 &&
      b[5] == 0x74 &&
      b[6] == 0x79 &&
      b[7] == 0x70) {
    return '.avif';
  }
  if (b.length > 2 && b[0] == 0x42 && b[1] == 0x4D) return '.bmp';
  return '.jpg';
}

String _fileSafe(String s) {
  final t = s
      .replaceAll(RegExp(r'[\\/:*?"<>|\r\n]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return t.length > 80
      ? t.substring(0, 80).trim()
      : (t.isEmpty ? 'untitled' : t);
}

class Cbz {
  static final _publishing = SerialExecutor();

  static Future<File> _publish(String staged, Directory outDir, String name) {
    return _publishing.run(() async {
      var file = File(p.join(outDir.path, name));
      for (var suffix = 2; await file.exists(); suffix++) {
        file = File(
          p.join(
            outDir.path,
            '${p.basenameWithoutExtension(name)} ($suffix).cbz',
          ),
        );
      }
      return File(staged).rename(file.path);
    });
  }

  /// Writes one .cbz per completed chapter of a downloaded comic into [outDir]. Pages that need a
  /// transform (JM strip scrambling) are restored and re-encoded as PNG.
  static Future<List<File>> exportTask(
    DownloadTask t,
    Directory outDir, {
    void Function(int done, int total)? onProgress,
  }) async {
    await outDir.create(recursive: true);
    final chapters = t.chapters
        .where((c) => t.completed.contains(c.id))
        .toList();
    final out = <File>[];
    final base = _fileSafe(t.item.title);
    for (var ci = 0; ci < chapters.length; ci++) {
      final ch = chapters[ci];
      final manifest = File(
        p.join(t.dir.path, safeFileName(ch.id), 'pages.json'),
      );
      if (!await manifest.exists()) continue;
      final pages =
          ((jsonDecode(await manifest.readAsString()) as Map)['pages'] as List)
              .cast<Map>();
      final info = ComicInfo(
        title: chapters.length > 1 ? ch.title : t.item.title,
        series: t.item.title,
        writer: (t.item.json['authors'] as List?)?.join(', ') ?? '',
        tags: t.item.tags,
        web: (t.item.json['url'] ?? '').toString(),
        pageCount: pages.length,
      );
      final name = chapters.length > 1
          ? '$base - ${_fileSafe(ch.title)}.cbz'
          : '$base.cbz';
      final staging = await outDir.createTemp('.park-export-');
      final entries = <(String path, String name)>[];
      try {
        for (var i = 0; i < pages.length; i++) {
          final page = pages[i].cast<String, dynamic>();
          var file = File(p.join(manifest.parent.path, page['file'] as String));
          var extension = '';
          final transform = page['transform'];
          if (transform is Map &&
              transform['type'] == 'unscramble-strips' &&
              ((transform['segments'] as num?) ?? 0) > 1) {
            final bytes = await _unscrambleToPng(
              await file.readAsBytes(),
              (transform['segments'] as num).toInt(),
            );
            file = File(p.join(staging.path, '$i.png'));
            await file.writeAsBytes(bytes);
            extension = '.png';
          } else {
            final input = await file.open();
            try {
              extension = imageExtension(await input.read(16));
            } finally {
              await input.close();
            }
          }
          entries.add((
            file.path,
            '${(i + 1).toString().padLeft(4, '0')}$extension',
          ));
          onProgress?.call(i + 1, pages.length);
        }
        final staged = p.join(staging.path, 'chapter.cbz');
        final xml = info.toXml();
        await Isolate.run(() => _encodeChapter(staged, entries, xml));
        out.add(await _publish(staged, outDir, name));
      } finally {
        await staging.delete(recursive: true);
      }
    }
    return out;
  }

  static void _encodeChapter(
    String path,
    List<(String path, String name)> entries,
    String xml,
  ) {
    final output = OutputFileStream(path);
    final encoder = ZipEncoder()..startEncode(output);
    try {
      for (final entry in entries) {
        final file = ArchiveFile.stream(entry.$2, InputFileStream(entry.$1))
          ..compression = CompressionType.none;
        try {
          encoder.add(file, autoClose: false);
        } finally {
          file.closeSync();
        }
      }
      encoder.add(ArchiveFile.string('ComicInfo.xml', xml));
      encoder.endEncode();
    } finally {
      output.closeSync();
    }
  }

  static Future<Uint8List> _unscrambleToPng(
    Uint8List bytes,
    int segments,
  ) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    codec.dispose();
    final restored = await unscrambleStrips(frame.image, segments);
    final data = await restored.toByteData(format: ui.ImageByteFormat.png);
    restored.dispose();
    return data!.buffer.asUint8List();
  }

  /// Unpacks a .cbz / .zip into a completed task of the `local` source under [root].
  /// The id is derived from the content, so importing the same file twice yields the same work.
  static Future<DownloadTask> importArchive(
    String fileName,
    List<int> bytes, {
    required Directory root,
  }) async {
    final archive = ZipDecoder().decodeBytes(bytes);
    final images =
        archive.files
            .where(
              (f) =>
                  f.isFile &&
                  _imageExtensions.contains(
                    p.extension(f.name).toLowerCase(),
                  ) &&
                  !p.basename(f.name).startsWith('.'),
            )
            .toList()
          ..sort((a, b) => naturalCompare(a.name, b.name));
    if (images.isEmpty) throw FormatException(tr('压缩包里没有图片'));
    final infoFile = archive.files
        .where(
          (f) =>
              f.isFile && p.basename(f.name).toLowerCase() == 'comicinfo.xml',
        )
        .firstOrNull;
    final info = infoFile == null
        ? ComicInfo()
        : ComicInfo.parse(utf8.decode(infoFile.content, allowMalformed: true));
    final id = sha1.convert(bytes).toString().substring(0, 16);
    final dir = Directory(
      p.join(root.path, safeFileName(localSource), safeFileName(id)),
    );
    final chapterDir = Directory(p.join(dir.path, safeFileName('_')));
    await chapterDir.create(recursive: true);
    final manifest = <Map<String, dynamic>>[];
    for (var i = 0; i < images.length; i++) {
      final name = '${(i + 1).toString().padLeft(4, '0')}.img';
      await File(p.join(chapterDir.path, name)).writeAsBytes(images[i].content);
      manifest.add({'index': i, 'file': name});
    }
    final title = info.title.isNotEmpty
        ? info.title
        : p.basenameWithoutExtension(fileName);
    await File(p.join(chapterDir.path, 'pages.json'))
        .writeAsString(jsonEncode({'title': title, 'pages': manifest}));
    final item = WorkItem({
      'id': id,
      'title': title,
      'cover': File(p.join(chapterDir.path, '0001.img')).uri.toString(),
      'pages': images.length,
      'tags': info.tags,
      if (info.writer.isNotEmpty)
        'authors': info.writer.split(RegExp(r'\s*,\s*')),
      if (info.summary.isNotEmpty) 'description': info.summary,
      'subtitle': info.writer,
    }, localSource);
    await File(p.join(dir.path, 'work.json'))
        .writeAsString(jsonEncode(item.toJson()));
    return DownloadTask(
      media: DownloadMedia.comic,
      item: item,
      chapters: [Chapter('_', tr('全本'))],
      dir: dir.path,
      status: DownloadStatus.done,
      done: images.length,
      total: images.length,
      bytes: images.fold(0, (n, f) => n + f.size),
      completed: {'_'},
    );
  }
}
