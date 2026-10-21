import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import '../core/models.dart';
import 'hls_syntax.dart';

/// HLS 必须连同清单引用的分片一起导出，不能分享孤立 m3u8。
Future<File> exportOfflineVideo(File file, Directory destination) async {
  if (p.extension(file.path).toLowerCase() != '.m3u8') return file;
  await destination.create(recursive: true);
  final workspace = await destination.createTemp('hls-export-');
  final output = File(p.join(workspace.path, '${p.basename(file.path)}.zip'));
  final part = File('${output.path}.part');
  try {
    await Isolate.run(() async {
      final root = await file.parent.resolveSymbolicLinks();
      final segments = '${p.basename(file.path)}.part.hls';
      final paths = <String>{};
      final base = Uri.parse('https://offline.park.invalid/');
      for (final entry in hlsLines(await file.readAsString())) {
        String address;
        if (entry.startsWith('#EXT-X-MAP:')) {
          final attributes = hlsAttributes(
            entry.substring('#EXT-X-MAP:'.length),
          );
          if (attributes.length != 1 || !attributes.containsKey('URI')) {
            throw SourceError('CONFIG', '离线媒体地址无效');
          }
          address = attributes['URI']!;
        } else if (entry.startsWith('#')) {
          if (RegExp(r'\bURI\s*=', caseSensitive: false).hasMatch(entry)) {
            throw SourceError('CONFIG', '离线媒体地址无效');
          }
          continue;
        } else {
          address = entry;
        }
        final resource = base.resolve(address);
        final line = resource.path.substring(1);
        if (address.startsWith('/') ||
            Uri.tryParse(address)?.hasScheme != false ||
            resource.origin != base.origin ||
            resource.userInfo.isNotEmpty ||
            resource.hasQuery ||
            resource.hasFragment ||
            !RegExp('^${RegExp.escape(segments)}/[0-9]+\\.(?:ts|mp4)\$')
                .hasMatch(line)) {
          throw SourceError('CONFIG', '离线媒体地址无效');
        }
        paths.add(line);
      }
      if (paths.isEmpty) throw SourceError('NOT_FOUND', '离线媒体文件缺失或不可读');
      final encoder = ZipFileEncoder()..create(part.path, level: 0);
      try {
        for (final relative in [p.basename(file.path), ...paths]) {
          final entry = File(p.join(file.parent.path, relative));
          final actual = await entry.resolveSymbolicLinks();
          if (!p.isWithin(root, actual) || await entry.length() == 0) {
            throw SourceError('CONFIG', '离线媒体地址无效');
          }
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
