import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/localization.dart';
import '../../core/storage.dart';
import '../../engine/cookie_store.dart';
import '../../engine/home_cache.dart';
import '../../engine/source_manager.dart';
import '../../game/downloads.dart';
import '../../images/image_store.dart';
import '../../library/downloads.dart';
import '../../library/library.dart';
import '../kit/adaptive_sheet.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Where the space goes, and ways to get it back.
class StoragePage extends StatefulWidget {
  const StoragePage({super.key});

  @override
  State<StoragePage> createState() => _StoragePageState();
}

class _StoragePageState extends State<StoragePage> {
  int? _cache;
  int? _homeCache;
  int? _database;
  int? _backups;
  Map<String, int>? _downloads; // source → bytes
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _measure();
  }

  static Future<int> _dirSize(Directory d) async {
    if (!await d.exists()) return 0;
    var total = 0;
    try {
      await for (final e in d.list(recursive: true, followLinks: false)) {
        if (e is File) {
          try {
            total += await e.length();
          } catch (_) {}
        }
      }
    } on FileSystemException {
      /* 下载/缓存可能在统计时被删除。 */
    }
    return total;
  }

  Future<void> _measure() async {
    final cache = await ImageStore.instance.cacheSize();
    final homeCache = await HomeCache.instance.size();
    var db = 0;
    for (final name in ['park.db', 'park.db-wal', 'park.db-shm']) {
      final f = AppPaths.dataFile(name);
      if (await f.exists()) db += await f.length();
    }
    final backups = await _dirSize(AppPaths.backups);
    final downloads = <String, int>{};
    for (final t in DownloadManager.instance.tasks) {
      downloads[t.item.source] =
          (downloads[t.item.source] ?? 0) + await _dirSize(t.dir);
    }
    for (final t in GameDownloadManager.instance.tasks) {
      downloads[t.item.source] =
          (downloads[t.item.source] ?? 0) +
          await _dirSize(Directory(t.directory));
    }
    if (!mounted) return;
    setState(() {
      _cache = cache;
      _homeCache = homeCache;
      _database = db;
      _backups = backups;
      _downloads = downloads;
    });
  }

  Future<void> _run(Future<void> Function() body, String done) async {
    setState(() => _busy = true);
    try {
      await body();
      if (mounted && done.isNotEmpty) context.toast(done);
    } catch (e) {
      if (mounted) context.toast(tr('操作失败：{value0}', {'value0': e}));
    } finally {
      if (mounted) setState(() => _busy = false);
      await _measure();
    }
  }

  /// Deletes downloaded chapters that are marked read (local imports are kept).
  Future<int> _deleteRead() async {
    var removed = 0;
    for (final t in DownloadManager.instance.tasks.toList()) {
      if (t.item.source == localSource || t.media != DownloadMedia.comic) {
        continue;
      }
      final states = await Library.instance.loadChapters(t.uid);
      final read = {
        for (final c in states)
          if (c.read) c.chapterId,
      };
      final ids = t.completed.where(read.contains).toList();
      if (ids.isEmpty) continue;
      await DownloadManager.instance.deleteChapters(t.uid, ids);
      removed += ids.length;
    }
    return removed;
  }

  Future<void> _clearCookies() async {
    final sources = SourceManager.instance.all;
    final key = await showAdaptiveSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: SelectionContainer.disabled(
                child: Text(
                  tr('清除哪个站点的 Cookie？'),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              subtitle: SelectionContainer.disabled(
                child: Text(tr('会退出该站点基于 Cookie 的登录，Cloudflare 验证也需要重新通过')),
              ),
            ),
            for (final s in sources)
              ListTile(
                leading: SourceAvatar(s.key, size: 28),
                title: SelectionContainer.disabled(child: Text(s.name)),
                onTap: () => Navigator.pop(ctx, s.key),
              ),
          ],
        ),
      ),
    );
    if (key == null) return;
    await _run(
      () async {
        await CookieStore.instance.clearPartition(key);
        await SourceManager.instance.refreshAccount(key);
      },
      tr('已清除 {value0} 的 Cookie', {
        'value0': SourceManager.instance.manifest(key)?.name ?? key,
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    String size(int? v) => v == null ? tr('计算中…') : formatBytes(v);
    final downloads = _downloads;
    final dlTotal = downloads?.values.fold(0, (a, b) => a + b);
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('存储空间')),
        bottom: _busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
      ),
      body: SettingsBody(
        child: AbsorbPointer(
          absorbing: _busy,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 32),
            children: [
              RowGroup(
                children: [
                  ListTile(
                    leading: const Icon(Icons.home_outlined),
                    title: SelectionContainer.disabled(
                      child: Text(tr('主页数据缓存')),
                    ),
                    subtitle: SelectionContainer.disabled(
                      child: Text(size(_homeCache)),
                    ),
                    trailing: SelectionContainer.disabled(
                      child: OutlinedButton(
                        onPressed: () =>
                            _run(HomeCache.instance.clear, tr('缓存已清除')),
                        child: Text(tr('清除')),
                      ),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.image_outlined),
                    title: SelectionContainer.disabled(child: Text(tr('媒体缓存'))),
                    subtitle: SelectionContainer.disabled(
                      child: Text(size(_cache)),
                    ),
                    trailing: SelectionContainer.disabled(
                      child: OutlinedButton(
                        onPressed: () => _run(() async {
                          await ImageStore.instance.clear();
                          imageCache.clear();
                        }, tr('缓存已清除')),
                        child: Text(tr('清除')),
                      ),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.storage_rounded),
                    title: SelectionContainer.disabled(
                      child: Text(tr('书库数据库')),
                    ),
                    subtitle: SelectionContainer.disabled(
                      child: Text(size(_database)),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.backup_outlined),
                    title: SelectionContainer.disabled(child: Text(tr('备份文件'))),
                    subtitle: SelectionContainer.disabled(
                      child: Text(size(_backups)),
                    ),
                  ),
                ],
              ),
              RowGroup(
                title: tr('下载'),
                children: [
                  ListTile(
                    leading: const Icon(Icons.download_done_rounded),
                    title: SelectionContainer.disabled(child: Text(tr('全部下载'))),
                    subtitle: SelectionContainer.disabled(
                      child: Text(size(dlTotal)),
                    ),
                  ),
                  if (downloads != null)
                    for (final e
                        in downloads.entries.toList()
                          ..sort((a, b) => b.value.compareTo(a.value)))
                      ListTile(
                        dense: true,
                        leading: SourceAvatar(e.key, size: 24),
                        title: SelectionContainer.disabled(
                          child: Text(
                            e.key == localSource
                                ? tr('本地导入')
                                : SourceManager.instance
                                          .manifest(e.key)
                                          ?.name ??
                                      e.key,
                          ),
                        ),
                        trailing: SelectionContainer.disabled(
                          child: Text(formatBytes(e.value)),
                        ),
                      ),
                  ListTile(
                    leading: const Icon(Icons.auto_delete_outlined),
                    title: SelectionContainer.disabled(
                      child: Text(tr('删除已读章节的下载')),
                    ),
                    subtitle: SelectionContainer.disabled(
                      child: Text(tr('只删除标记为已读的漫画章节，本地导入不受影响')),
                    ),
                    onTap: () async {
                      var n = 0;
                      await _run(() async => n = await _deleteRead(), '');
                      if (context.mounted) {
                        context.toast(tr('已删除 {value0} 个章节', {'value0': n}));
                      }
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.folder_outlined),
                    title: SelectionContainer.disabled(child: Text(tr('下载位置'))),
                    subtitle: SelectionContainer.disabled(
                      child: SelectableText(
                        p.normalize(DownloadManager.instance.root.path),
                        style: context.text.bodySmall,
                      ),
                    ),
                  ),
                ],
              ),
              RowGroup(
                title: tr('站点数据'),
                children: [
                  ListTile(
                    leading: const Icon(Icons.cookie_outlined),
                    title: SelectionContainer.disabled(
                      child: Text(tr('清除某个站点的 Cookie')),
                    ),
                    onTap: _clearCookies,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
