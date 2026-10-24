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

typedef _PdfPage = ({String path, int width, int height, bool jpeg, int bytes});

/// 将已下载的图片章节分别导出为 PDF。
///
/// PDF 在内存中组装后一次写出；章节过长时按页数上限或体积预算（先到者为准）
/// 拆成多个文件，避免大图集导出时内存不足。
class ComicPdf {
  /// 单个文件内图片数据的上限；组装时还需要同等量级的内存。
  static const volumeBytes = 160 * 1024 * 1024;

  static Future<List<File>> exportTask(
    DownloadTask task,
    Directory outDir, {
    int maxPages = 0,
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
        final name = chapters.length > 1
            ? '$base - ${exportFileName(chapter.title)}'
            : base;
        final title = chapters.length > 1
            ? '${task.item.title} - ${chapter.title}'
            : task.item.title;
        final volumes = <List<_PdfPage>>[[]];
        var volumeSize = 0;
        for (var i = 0; i < manifests[ci].length; i++) {
          final page = manifests[ci][i];
          final relative = page['file'] as String;
          final path = p.normalize(p.join(directory.path, relative));
          if (p.isAbsolute(relative) || !p.isWithin(directory.path, path)) {
            throw FormatException(tr('图片文件路径无效'));
          }
          final prepared = await _page(
            File(path),
            page['transform'],
            File(p.join(staging.path, '$ci-$i.png')),
          );
          final current = volumes.last;
          if (current.isNotEmpty &&
              ((maxPages > 0 && current.length >= maxPages) ||
                  volumeSize + prepared.bytes > volumeBytes)) {
            volumes.add([]);
            volumeSize = 0;
          }
          volumes.last.add(prepared);
          volumeSize += prepared.bytes;
          onProgress?.call(++done, total);
        }
        for (var vi = 0; vi < volumes.length; vi++) {
          final pdf = File(p.join(staging.path, '$ci-$vi.pdf'));
          final pages = volumes[vi];
          final part = volumes.length > 1
              ? ' (${tr('第 {value0} 部分', {'value0': vi + 1})})'
              : '';
          await Isolate.run(() => _encode(pdf.path, pages, '$title$part'));
          for (final page in pages) {
            if (!page.jpeg) await File(page.path).delete();
          }
          staged.add((pdf, '$name$part.pdf'));
        }
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

  /// JPEG 原样嵌入；其他格式或需要还原切片的图片用阅读器同一解码器取第一帧转为 PNG，
  /// 覆盖 GIF、WebP、APNG。
  static Future<_PdfPage> _page(
    File source,
    Object? transform,
    File output,
  ) async {
    final bytes = await source.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    late ui.FrameInfo frame;
    try {
      frame = await codec.getNextFrame();
    } finally {
      codec.dispose();
    }
    var image = frame.image;
    try {
      final scrambled =
          transform is Map &&
          transform['type'] == 'unscramble-strips' &&
          ((transform['segments'] as num?) ?? 0) > 1;
      if (!scrambled &&
          bytes.length > 2 &&
          bytes[0] == 0xFF &&
          bytes[1] == 0xD8) {
        return (
          path: source.path,
          width: image.width,
          height: image.height,
          jpeg: true,
          bytes: bytes.length,
        );
      }
      if (scrambled) {
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
      return (
        path: output.path,
        width: image.width,
        height: image.height,
        jpeg: false,
        bytes: png.lengthInBytes,
      );
    } finally {
      image.dispose();
    }
  }

  static Future<void> _encode(
    String path,
    List<_PdfPage> pages,
    String title,
  ) async {
    final document = PdfDocument();
    PdfInfo(document, title: title, creator: 'HentaiPark');
    for (final entry in pages) {
      final bytes = await File(entry.path).readAsBytes();
      final image = entry.jpeg
          ? PdfImage.jpeg(document, image: bytes)
          : PdfImage.file(document, bytes: bytes);
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
