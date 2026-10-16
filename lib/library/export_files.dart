import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/async_tasks.dart';

String exportFileName(String value) {
  final name = value
      .replaceAll(RegExp(r'[\\/:*?"<>|\r\n]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return name.length > 80
      ? name.substring(0, 80).trim()
      : (name.isEmpty ? 'untitled' : name);
}

final _publishing = SerialExecutor();

/// 暂存文件完成后再发布；同名导出按序加后缀，不覆盖已有文件。
Future<File> publishExport(File staged, Directory directory, String name) =>
    _publishing.run(() async {
      var target = File(p.join(directory.path, name));
      for (
        var suffix = 2;
        await FileSystemEntity.type(target.path) !=
            FileSystemEntityType.notFound;
        suffix++
      ) {
        target = File(
          p.join(
            directory.path,
            '${p.basenameWithoutExtension(name)} ($suffix)${p.extension(name)}',
          ),
        );
      }
      // 独占创建还可防止其他文件写入者恰好占用已选择的名称。
      await target.create(exclusive: true);
      try {
        return await staged.rename(target.path);
      } catch (_) {
        await target.delete();
        rethrow;
      }
    });
