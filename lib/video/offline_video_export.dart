import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import 'local_hls_media.dart';

/// HLS 必须连同清单引用的分片一起导出，不能分享孤立 m3u8。
Future<File> exportOfflineVideo(File file, Directory destination) async {
  if (p.extension(file.path).toLowerCase() != '.m3u8') return file;
  await destination.create(recursive: true);
  final workspace = await destination.createTemp('hls-export-');
  final output = File(p.join(workspace.path, '${p.basename(file.path)}.zip'));
  final part = File('${output.path}.part');
  try {
    await Isolate.run(() async {
      final files = await LocalHlsMedia(file).files();
      final encoder = ZipFileEncoder()..create(part.path, level: 0);
      try {
        for (final entry in files) {
          final relative = p
              .relative(entry.path, from: file.parent.path)
              .replaceAll(p.separator, '/');
          await encoder.addFile(entry, relative);
        }
      } finally {
        await encoder.close();
      }
    });
    return await part.rename(output.path);
  } finally {
    if (await part.exists()) await part.delete();
    if (!await output.exists() && await workspace.exists()) {
      await workspace.delete();
    }
  }
}
