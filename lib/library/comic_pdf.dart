import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';

import '../core/localization.dart';
import '../core/storage.dart';
import '../images/park_image.dart';
import 'downloads.dart';
import 'export_files.dart';

/// 将已下载的图片章节分别导出为 PDF。
class ComicPdf {
  static Future<List<File>> exportTask(
    DownloadTask task,
    Directory outDir, {
    void Function(int done, int total)? onProgress,
  }) async {
    if (task.isVideo || task.isNovel) {
      throw ArgumentError('Only downloaded image chapters can be exported');
    }
    final chapters = task.chapters
        .where((chapter) => task.completed.contains(chapter.id))
        .toList();
    if (chapters.isEmpty) throw StateError(tr('没有可导出的已完成图片章节'));
    // 先读取完整目录，任何已完成章节缺失或损坏都不能被静默跳过。
    final manifests = <List<Map<String, dynamic>>>[];
    for (final chapter in chapters) {
      final manifest = File(
        p.join(task.dir.path, safeFileName(chapter.id), 'pages.json'),
      );
      final json = jsonDecode(await manifest.readAsString()) as Map;
      final pages = (json['pages'] as List)
          .map((page) => (page as Map).cast<String, dynamic>())
          .toList();
      if (pages.isEmpty) throw FormatException(tr('章节没有可导出的图片'));
      manifests.add(pages);
    }
    final total = manifests.fold(0, (sum, pages) => sum + pages.length);
    var done = 0;
    await outDir.create(recursive: true);
    final staging = await outDir.createTemp('.park-pdf-');
    final staged = <(File, String)>[];
    final published = <File>[];
    try {
      final base = exportFileName(task.item.title);
      for (var ci = 0; ci < chapters.length; ci++) {
        final chapter = chapters[ci];
        final directory = Directory(
          p.join(task.dir.path, safeFileName(chapter.id)),
        );
        final pages = <({String path, int width, int height})>[];
        for (var i = 0; i < manifests[ci].length; i++) {
          final page = manifests[ci][i];
          final relative = page['file'] as String;
          final path = p.normalize(p.join(directory.path, relative));
          if (p.isAbsolute(relative) || !p.isWithin(directory.path, path)) {
            throw FormatException(tr('图片文件路径无效'));
          }
          final normalized = File(p.join(staging.path, '$ci-$i.png'));
          final size = await _firstFrame(
            File(path),
            page['transform'],
            normalized,
          );
          pages.add((path: normalized.path, width: size.$1, height: size.$2));
          onProgress?.call(++done, total);
        }
        final pdf = File(p.join(staging.path, '$ci.pdf'));
        final title = chapters.length > 1
            ? '${task.item.title} - ${chapter.title}'
            : task.item.title;
        await Isolate.run(() => _encodeChapter(pdf.path, pages, title));
        for (final page in pages) {
          await File(page.path).delete();
        }
        staged.add((
          pdf,
          chapters.length > 1
              ? '$base - ${exportFileName(chapter.title)}.pdf'
              : '$base.pdf',
        ));
      }
      for (final (file, name) in staged) {
        published.add(await publishExport(file, outDir, name));
      }
      return published;
    } catch (_) {
      for (final file in published) {
        if (await file.exists()) await file.delete();
      }
      rethrow;
    } finally {
      await staging.delete(recursive: true);
    }
  }

  /// Flutter 与阅读器使用同一个解码器；只请求第一帧，覆盖 GIF、WebP、APNG。
  static Future<(int, int)> _firstFrame(
    File source,
    Object? transform,
    File output,
  ) async {
    final codec = await ui.instantiateImageCodec(await source.readAsBytes());
    late ui.FrameInfo frame;
    try {
      frame = await codec.getNextFrame();
    } finally {
      codec.dispose();
    }
    var image = frame.image;
    try {
      if (transform is Map &&
          transform['type'] == 'unscramble-strips' &&
          ((transform['segments'] as num?) ?? 0) > 1) {
        image = await unscrambleStrips(
          image,
          (transform['segments'] as num).toInt(),
        );
      }
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      if (png == null) throw StateError(tr('图片无法编码'));
      await output.writeAsBytes(
        png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
      );
      return (image.width, image.height);
    } finally {
      image.dispose();
    }
  }

  static Future<void> _encodeChapter(
    String path,
    List<({String path, int width, int height})> pages,
    String title,
  ) async {
    final document = PdfDocument();
    PdfInfo(document, title: title, creator: 'HentaiPark');
    for (final entry in pages) {
      final image = PdfImage.file(
        document,
        bytes: await File(entry.path).readAsBytes(),
      );
      // 长图等比缩小页面坐标，避免超出 PDF 页面尺寸限制；原始像素保持完整。
      final longest = entry.width > entry.height ? entry.width : entry.height;
      final scale = longest > 14400 ? 14400 / longest : 1.0;
      final width = entry.width * scale;
      final height = entry.height * scale;
      PdfPage(
        document,
        pageFormat: PdfPageFormat(width, height),
      ).getGraphics().drawImage(image, 0, 0, width, height);
    }
    await File(path).writeAsBytes(await document.save(), flush: true);
  }
}
