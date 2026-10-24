import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/async_tasks.dart';
import '../core/localization.dart';
import '../core/settings.dart';
import '../engine/background_downloads.dart';
import 'cbz.dart';
import 'comic_pdf.dart';
import 'downloads.dart';

enum ExportFormat { pdf, cbz }

enum ExportStatus { queued, running, done, failed }

class ExportJob {
  ExportJob._(this.uid, this.title, this.format);
  final String uid, title;
  final ExportFormat format;
  ExportStatus status = ExportStatus.queued;
  int done = 0, total = 0;
  List<File> files = const [];
  Object? error;
}

/// 图片导出在后台依次执行，不阻塞界面；安卓上与下载共用前台服务，切到后台不会中断。
/// 导出的文件保存在下载目录的 exports 中，可在下载页的“导出文件”里查看和管理。
class ExportManager extends ChangeNotifier {
  ExportManager._();
  static final instance = ExportManager._();

  final List<ExportJob> jobs = [];
  final _queue = SerialExecutor();

  Directory get directory =>
      Directory(p.join(DownloadManager.instance.root.path, 'exports'));

  bool get busy => jobs.any(
    (job) =>
        job.status == ExportStatus.queued || job.status == ExportStatus.running,
  );

  ExportJob? active(String uid, ExportFormat format) => jobs
      .where(
        (job) =>
            job.uid == uid &&
            job.format == format &&
            (job.status == ExportStatus.queued ||
                job.status == ExportStatus.running),
      )
      .firstOrNull;

  /// 加入队列并立即返回；同一作品同一格式正在导出时不重复加入。
  ExportJob start(DownloadTask task, ExportFormat format) {
    if (active(task.uid, format) case final job?) return job;
    final job = ExportJob._(task.uid, task.item.title, format);
    jobs.insert(0, job);
    notifyListeners();
    unawaited(_queue.run(() => _run(job, task)));
    return job;
  }

  Future<void> _run(ExportJob job, DownloadTask task) async {
    job.status = ExportStatus.running;
    notifyListeners();
    var lastNotify = DateTime.fromMillisecondsSinceEpoch(0);
    void progress(int done, int total) {
      job
        ..done = done
        ..total = total;
      final now = DateTime.now();
      if (now.difference(lastNotify).inMilliseconds > 250 || done == total) {
        lastNotify = now;
        notifyListeners();
      }
    }

    try {
      job.files = await BackgroundDownloads.instance.run(
        (_) => switch (job.format) {
          ExportFormat.pdf => ComicPdf.exportTask(
            task,
            directory,
            maxPages: AppSettings.instance.pdfPagesPerFile,
            onProgress: progress,
          ),
          ExportFormat.cbz => Cbz.exportTask(
            task,
            directory,
            onProgress: progress,
          ),
        },
      );
      job.status = ExportStatus.done;
    } catch (error) {
      job
        ..status = ExportStatus.failed
        ..error = error;
    }
    notifyListeners();
  }

  void dismiss(ExportJob job) {
    if (job.status == ExportStatus.queued ||
        job.status == ExportStatus.running) {
      return;
    }
    jobs.remove(job);
    notifyListeners();
  }

  /// 已导出的文件，按修改时间从新到旧；正在写入的暂存目录不列出。
  Future<List<File>> files() async {
    final dir = directory;
    if (!await dir.exists()) return const [];
    final files = <(File, DateTime)>[];
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File || p.basename(entity.path).startsWith('.')) continue;
      files.add((entity, (await entity.stat()).modified));
    }
    files.sort((a, b) => b.$2.compareTo(a.$2));
    return [for (final (file, _) in files) file];
  }

  Future<void> delete(File file) async {
    if (!p.isWithin(directory.path, file.path)) {
      throw ArgumentError(tr('只能删除导出目录中的文件'));
    }
    if (await file.exists()) await file.delete();
    notifyListeners();
  }
}
