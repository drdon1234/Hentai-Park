import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/content_scope.dart';
import '../../core/localization.dart';
import '../../core/models.dart';
import '../../core/settings.dart';
import '../../core/titles.dart';
import '../../engine/source_manager.dart';
import '../../game/downloads.dart';
import '../../library/cbz.dart';
import '../../library/downloads.dart';
import '../../library/exports.dart';
import '../../library/library.dart';
import '../../library/live_recordings.dart';
import '../../video/offline_video_export.dart';
import '../detail/detail_page.dart';
import '../game/game_resources.dart';
import '../kit/adaptive_sheet.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/content_scope_selector.dart';
import '../widgets/cover_tile.dart';
import '../widgets/file_drop_region.dart';
import '../widgets/platform_share.dart';
import 'category_manage_page.dart';
import 'download_progress.dart';
import 'download_settings.dart';
import 'exports_page.dart';
import 'favorite_actions.dart';
import 'recording_tile.dart';

class DownloadsPage extends StatefulWidget {
  const DownloadsPage({super.key});

  @override
  State<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends State<DownloadsPage> {
  final _query = TextEditingController();
  final Set<String> _selectedDownloads = {};
  bool _importing = false;
  bool _searching = false;
  ContentScope _scope = const ContentScope.all();
  int? _category;
  String _kind = 'all';
  String _status = 'all';

  int? get _activeCategory =>
      _category != null &&
          _category != Library.defaultCategory &&
          Library.instance.category(_category!) == null
      ? null
      : _category;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _import(BuildContext context) async {
    if (_importing) return;
    setState(() => _importing = true);
    try {
      final files = await FilePicker.pickFiles(
        dialogTitle: tr('导入 CBZ / ZIP'),
        type: FileType.custom,
        allowedExtensions: const ['cbz', 'zip'],
      );
      if (files.isEmpty || !context.mounted) return;
      await _importFiles(context, files.map((file) => file.xFile).toList());
    } catch (_) {
      if (context.mounted) context.toast(tr('无法读取文件，请重试'));
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _drop(BuildContext context, List<DropItem> files) async {
    if (_importing || files.isEmpty) return;
    if (files.any(
      (file) =>
          file is DropItemDirectory ||
          !const [
            '.cbz',
            '.zip',
          ].contains(p.extension(file.name).toLowerCase()),
    )) {
      context.toast(tr('请选择 CBZ / ZIP 文件'));
      return;
    }
    setState(() => _importing = true);
    try {
      await _importFiles(context, files);
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _importFiles(BuildContext context, List<XFile> files) async {
    var ok = 0;
    final errors = <String>[];
    for (final f in files) {
      try {
        final task = await Cbz.importArchive(
          f.name,
          await f.readAsBytes(),
          root: DownloadManager.instance.root,
        );
        DownloadManager.instance.addCompleted(task);
        ok++;
      } catch (e) {
        errors.add('${f.name}：${e is FormatException ? e.message : e}');
      }
    }
    if (!context.mounted) return;
    context.toast(
      [
        tr('已导入 {value0} 个文件', {'value0': ok}),
        ...errors,
      ].join('\n'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dm = DownloadManager.instance;
    final games = GameDownloadManager.instance;
    return Scaffold(
      appBar: _selectedDownloads.isEmpty ? _appBar(context) : _selectionBar(),
      body: FileDropRegion(
        enabled: !_importing,
        message: tr('松开以导入本地漫画'),
        onDrop: (files) => _drop(context, files),
        child: ListenableBuilder(
          listenable: Listenable.merge([
            dm,
            games,
            AppSettings.instance,
            LiveRecordings.instance,
            SourceManager.instance,
            Library.instance.collection(LibraryCollection.categories),
            Library.instance.collection(LibraryCollection.favorites),
          ]),
          builder: (context, _) {
            final tasks = dm.tasks;
            _selectedDownloads.removeWhere(
              (uid) => !tasks.any((task) => task.uid == uid),
            );
            final gameTasks = games.tasks;
            final failures = dm.restoreFailures;
            final recordings = LiveRecordings.instance.tasks;
            final visibleTasks = tasks
                .where((task) => _matches(task.item, task.uid))
                .where(
                  (task) => _status == 'all' || task.status.name == _status,
                )
                .toList();
            final visibleGameTasks = gameTasks
                .where((task) => _matches(task.item, task.item.uid))
                .where(
                  (task) => _status == 'all' || task.status.name == _status,
                )
                .toList();
            final visibleRecordings = recordings
                .where((task) => _matches(task.item, task.item.uid))
                .toList();
            final visibleFailures = failures
                .where(
                  (failure) =>
                      _matchesSource(failure.source) &&
                      (_status == 'all' ||
                          _status == DownloadStatus.failed.name),
                )
                .toList();
            final scopeItems = [
              for (final task in tasks) task.item,
              for (final task in gameTasks) task.item,
              for (final task in recordings) task.item,
            ];
            return Column(
              children: [
                if (!dm.networkAllowed)
                  MaterialBanner(
                    leading: const Icon(Icons.wifi_off_rounded),
                    content: Text(tr('已开启"仅在 Wi-Fi 下下载"，连接 Wi-Fi 后自动继续')),
                    actions: [const SizedBox.shrink()],
                  ),
                _toolbar(context),
                ContentScopeSelector(
                  scope: _scope,
                  onChanged: (scope) => setState(() => _scope = scope),
                  categoryId: _activeCategory,
                  onCategoryChanged: (category) =>
                      setState(() => _category = category),
                  items: scopeItems,
                ),
                Expanded(
                  child:
                      visibleTasks.isEmpty &&
                          visibleGameTasks.isEmpty &&
                          visibleFailures.isEmpty &&
                          visibleRecordings.isEmpty
                      ? EmptyState(
                          icon: Icons.download_for_offline_outlined,
                          title:
                              tasks.isEmpty &&
                                  gameTasks.isEmpty &&
                                  recordings.isEmpty &&
                                  failures.isEmpty
                              ? tr('没有下载任务')
                              : tr('没有符合条件的作品'),
                          message:
                              tasks.isEmpty &&
                                  gameTasks.isEmpty &&
                                  recordings.isEmpty &&
                                  failures.isEmpty
                              ? tr(
                                  '在作品详情页点击下载按钮，下载后可离线阅读或观看\n也可以导入本地的 CBZ / ZIP 漫画',
                                )
                              : tr('调整搜索或筛选条件试试'),
                        )
                      : _content(
                          context,
                          visibleTasks,
                          visibleGameTasks,
                          visibleFailures,
                          visibleRecordings,
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  PreferredSizeWidget _appBar(BuildContext context) => PageHeader(
    titleWidget: _searching
        ? TextField(
            controller: _query,
            autofocus: true,
            decoration: InputDecoration(
              hintText: tr('搜索作品'),
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
            onChanged: (_) => setState(() {}),
          )
        : null,
    title: _searching ? null : tr('下载'),
    actions: [
      IconButton(
        tooltip: _searching ? tr('关闭搜索') : tr('搜索'),
        icon: Icon(_searching ? Icons.close_rounded : Icons.search_rounded),
        onPressed: () => setState(() {
          _searching = !_searching;
          if (!_searching) _query.clear();
        }),
      ),
      ListenableBuilder(
        listenable: AppSettings.instance.watch(const {'downloadDisplay'}),
        builder: (context, _) {
          final grid = AppSettings.instance.downloadDisplay == 'grid';
          return IconButton(
            tooltip: tr(grid ? '切换为列表' : '切换为网格'),
            icon: Icon(
              grid ? Icons.view_list_rounded : Icons.grid_view_rounded,
            ),
            onPressed: () =>
                AppSettings.instance.downloadDisplay = grid ? 'list' : 'grid',
          );
        },
      ),
      IconButton(
        tooltip: tr('筛选'),
        icon: const Icon(Icons.filter_list_rounded),
        onPressed: () => _showFilters(context),
      ),
      PopupMenuButton<String>(
        tooltip: tr('更多'),
        onSelected: (value) {
          switch (value) {
            case 'import':
              _import(context);
            case 'exports':
              Nav.push(context, const ExportsPage());
            case 'concurrency':
              showDownloadConcurrencySettings(context);
            case 'categories':
              Nav.push(context, const CategoryManagePage());
          }
        },
        itemBuilder: (_) => [
          PopupMenuItem(
            value: 'import',
            child: SelectionContainer.disabled(child: Text(tr('导入本地漫画'))),
          ),
          PopupMenuItem(
            value: 'exports',
            child: SelectionContainer.disabled(child: Text(tr('导出文件'))),
          ),
          PopupMenuItem(
            value: 'concurrency',
            child: SelectionContainer.disabled(child: Text(tr('下载并发设置'))),
          ),
          PopupMenuItem(
            value: 'categories',
            child: SelectionContainer.disabled(child: Text(tr('管理分类'))),
          ),
        ],
      ),
    ],
  );

  PreferredSizeWidget _selectionBar() => AppBar(
    leading: IconButton(
      tooltip: tr('取消选择'),
      icon: const Icon(Icons.close_rounded),
      onPressed: () => setState(_selectedDownloads.clear),
    ),
    title: Text(tr('已选 {value0}', {'value0': _selectedDownloads.length})),
    actions: [
      IconButton(
        tooltip: tr('暂停'),
        icon: const Icon(Icons.pause_rounded),
        onPressed: () {
          for (final uid in _selectedDownloads) {
            DownloadManager.instance.pause(uid);
          }
        },
      ),
      IconButton(
        tooltip: tr('继续'),
        icon: const Icon(Icons.play_arrow_rounded),
        onPressed: () {
          for (final uid in _selectedDownloads) {
            DownloadManager.instance.resume(uid);
          }
        },
      ),
      IconButton(
        tooltip: tr('删除'),
        icon: const Icon(Icons.delete_outline_rounded),
        onPressed: _deleteSelected,
      ),
    ],
  );

  void _toggleDownload(String uid) => setState(() {
    if (!_selectedDownloads.add(uid)) _selectedDownloads.remove(uid);
  });

  Future<void> _deleteSelected() async {
    final selected = List<String>.of(_selectedDownloads);
    if (selected.isEmpty) return;
    final confirmed = await confirmAction(
      context,
      title: tr('删除下载？'),
      message: tr('已下载的文件也会一并删除。'),
      confirmLabel: tr('删除'),
      destructive: true,
    );
    if (!confirmed) return;
    for (final uid in selected) {
      try {
        await DownloadManager.instance.delete(uid);
      } catch (_) {
        if (mounted) context.toast(tr('删除失败，请重试'));
      }
    }
    if (mounted) setState(_selectedDownloads.clear);
  }

  Future<void> _showFilters(BuildContext context) => showAdaptiveSheet<void>(
    context: context,
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setSheetState) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(Gap.page, Gap.m, Gap.page, Gap.l),
          children: [
            SectionHeader(tr('类型')),
            Wrap(
              spacing: Gap.s,
              runSpacing: Gap.s,
              children: [
                for (final value in {
                  'all': tr('全部'),
                  for (final kind in MediaKind.values) kind.name: kind.label,
                }.entries)
                  SelectionChip(
                    label: value.value,
                    selected: _kind == value.key,
                    onSelected: (_) => setSheetState(() {
                      _kind = value.key;
                      setState(() {});
                    }),
                  ),
              ],
            ),
            const SizedBox(height: Gap.l),
            SectionHeader(tr('下载状态')),
            Wrap(
              spacing: Gap.s,
              runSpacing: Gap.s,
              children: [
                for (final value in {
                  'all': tr('全部'),
                  for (final status in DownloadStatus.values)
                    status.name: _statusLabelFor(status),
                }.entries)
                  SelectionChip(
                    label: value.value,
                    selected: _status == value.key,
                    onSelected: (_) => setSheetState(() {
                      _status = value.key;
                      setState(() {});
                    }),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  String _statusLabelFor(DownloadStatus status) => switch (status) {
    DownloadStatus.queued => tr('等待中'),
    DownloadStatus.running => tr('正在下载'),
    DownloadStatus.paused => tr('已暂停'),
    DownloadStatus.done => tr('已完成'),
    DownloadStatus.failed => tr('下载失败'),
  };

  Widget _toolbar(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      DownloadManager.instance,
      GameDownloadManager.instance,
    ]),
    builder: (context, _) {
      final dm = DownloadManager.instance;
      final games = GameDownloadManager.instance;
      final canPause =
          [
            ...dm.tasks.map((t) => t.status),
            ...games.tasks.map((t) => t.status),
          ].any(
            (status) =>
                status == DownloadStatus.running ||
                status == DownloadStatus.queued,
          );
      final canResume =
          [
            ...dm.tasks.map((t) => t.status),
            ...games.tasks.map((t) => t.status),
          ].any(
            (status) =>
                status == DownloadStatus.paused ||
                status == DownloadStatus.failed,
          );
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Gap.page, Gap.s, Gap.page, Gap.s),
          child: Wrap(
            spacing: Gap.s,
            runSpacing: Gap.s,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (dm.tasks.isNotEmpty || games.tasks.isNotEmpty) ...[
                IconButton(
                  onPressed: !canPause
                      ? null
                      : () {
                          dm.pauseAll();
                          for (final task in games.tasks) {
                            if (task.status == DownloadStatus.running ||
                                task.status == DownloadStatus.queued) {
                              games.cancel(task.key);
                            }
                          }
                        },
                  icon: const Icon(Icons.pause_rounded),
                  tooltip: tr('全部暂停'),
                ),
                IconButton(
                  onPressed: !canResume
                      ? null
                      : () {
                          dm.resumeAll();
                          for (final task in games.tasks) {
                            if (task.status == DownloadStatus.paused ||
                                task.status == DownloadStatus.failed) {
                              games.retry(task.key);
                            }
                          }
                        },
                  icon: const Icon(Icons.play_arrow_rounded),
                  tooltip: tr('全部继续'),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );

  bool _matches(WorkItem item, String uid) {
    final query = normalizeTitle(_query.text.trim());
    if (!_scope.contains(item.source, Library.instance.domainOf(item))) {
      return false;
    }
    if (query.isNotEmpty && !normalizeTitle(item.title).contains(query)) {
      return false;
    }
    if (_kind != 'all' && kindOf(item).name != _kind) return false;
    final categories = Library.instance.categoriesOf(uid);
    if (_activeCategory == Library.defaultCategory && categories.isNotEmpty) {
      return false;
    }
    if (_activeCategory != null &&
        _activeCategory != Library.defaultCategory &&
        !categories.contains(_activeCategory)) {
      return false;
    }
    return true;
  }

  bool _matchesSource(String source) {
    if (_scope.sourceKey != null && _scope.sourceKey != source) return false;
    final category = SourceManager.instance.manifest(source)?.category;
    return _scope.category == null || category == _scope.category;
  }

  Widget _content(
    BuildContext context,
    List<DownloadTask> tasks,
    List<GameDownloadTask> gameTasks,
    List<({String uid, String source})> failures,
    List<LiveRecording> recordings,
  ) {
    final grid = AppSettings.instance.downloadDisplay == 'grid';
    if (grid) {
      final specialRows = <Widget>[
        ...recordings.map((task) => RecordingTile(task: task)),
        ...failures.map(
          (failure) =>
              _RestoreFailureTile(uid: failure.uid, source: failure.source),
        ),
        ...gameTasks.map((task) => GameDownloadTile(task: task)),
      ];
      final slivers = <Widget>[
        if (specialRows.isNotEmpty)
          SliverList.list(
            children: [
              for (var i = 0; i < specialRows.length; i++) ...[
                if (i > 0) const Divider(indent: Gap.page, endIndent: Gap.page),
                specialRows[i],
              ],
            ],
          ),
        if (tasks.isNotEmpty) _gridSliver(context, tasks),
        const SliverToBoxAdapter(child: SizedBox(height: Gap.l)),
      ];
      return CustomScrollView(slivers: slivers);
    }
    return Column(
      children: [
        Expanded(
          child: ReadableWidth(
            child: ListView.separated(
              padding: const EdgeInsets.only(bottom: Gap.l),
              itemCount:
                  recordings.length +
                  failures.length +
                  gameTasks.length +
                  tasks.length,
              separatorBuilder: (_, _) =>
                  const Divider(indent: Gap.page, endIndent: Gap.page),
              itemBuilder: (context, i) {
                if (i < recordings.length) {
                  return RecordingTile(task: recordings[i]);
                }
                i -= recordings.length;
                if (i < failures.length) {
                  return _RestoreFailureTile(
                    uid: failures[i].uid,
                    source: failures[i].source,
                  );
                }
                i -= failures.length;
                return i < gameTasks.length
                    ? GameDownloadTile(task: gameTasks[i])
                    : _TaskTile(
                        task: tasks[i - gameTasks.length],
                        selecting: _selectedDownloads.isNotEmpty,
                        selected: _selectedDownloads.contains(
                          tasks[i - gameTasks.length].uid,
                        ),
                        onToggle: () =>
                            _toggleDownload(tasks[i - gameTasks.length].uid),
                      );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _gridSliver(BuildContext context, List<DownloadTask> tasks) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final cols = gridColumnsFor(context, constraints.crossAxisExtent);
        final width =
            (constraints.crossAxisExtent - Gap.page * 2 - (cols - 1) * Gap.m) /
            cols;
        return SliverPadding(
          padding: const EdgeInsets.fromLTRB(Gap.page, Gap.s, Gap.page, 0),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              crossAxisSpacing: Gap.m,
              mainAxisSpacing: Gap.l,
              mainAxisExtent:
                  width / 0.7 +
                  cardTextExtent(
                    context,
                    items: tasks.map((t) => t.item),
                    width: width,
                    showSource: true,
                  ),
            ),
            delegate: SliverChildBuilderDelegate((context, index) {
              final task = tasks[index];
              return CoverTile(
                item: task.item,
                aspect: 0.7,
                coverFrame: (child) => DownloadCoverProgress(
                  status: task.status,
                  label: _statusLabel(task),
                  progress: task.total > 0 ? task.progress : null,
                  child: child,
                ),
                showSource: true,
                onTap: () => _selectedDownloads.isNotEmpty
                    ? _toggleDownload(task.uid)
                    : _openTask(context, task),
                onTextTap: () => Nav.push(
                  context,
                  DetailPage(
                    source: task.item.source,
                    id: task.item.id,
                    preview: task.item,
                  ),
                ),
                onLongPress: () => _toggleDownload(task.uid),
                selected: _selectedDownloads.contains(task.uid),
              );
            }, childCount: tasks.length),
          ),
        );
      },
    );
  }

  String _statusLabel(DownloadTask task) => switch (task.status) {
    DownloadStatus.queued => tr(
      DownloadManager.instance.networkAllowed ? '等待下载' : '等待 Wi-Fi',
    ),
    DownloadStatus.running => tr(task.total > 0 ? '正在下载' : '准备中…'),
    DownloadStatus.paused => tr('已暂停'),
    DownloadStatus.done => tr('已完成'),
    DownloadStatus.failed => tr('下载失败'),
  };

  Future<void> _openTask(BuildContext context, DownloadTask task) {
    if (task.chapters.length > 1) {
      return _TaskTile(task: task)._chapters(context);
    }
    return Nav.openChapter(
      context,
      task.item,
      null,
      downloadedOnly: !task.canReadWhileDownloading,
    );
  }
}

class _RestoreFailureTile extends StatelessWidget {
  const _RestoreFailureTile({required this.uid, required this.source});
  final String uid, source;

  Future<void> _retry(BuildContext context) async {
    try {
      await DownloadManager.instance.retryRestore(uid);
    } catch (_) {
      if (context.mounted) context.toast(tr('下载记录恢复失败，请前往下载页处理'));
    }
  }

  Future<void> _remove(BuildContext context) async {
    final confirmed = await confirmAction(
      context,
      title: tr('移除损坏的下载记录？'),
      message: tr('只移除无法恢复的下载记录，保留本地文件。'),
      confirmLabel: tr('移除记录'),
      destructive: true,
    );
    if (!confirmed) return;
    try {
      await DownloadManager.instance.removeRestoreFailure(uid);
    } catch (_) {
      if (context.mounted) context.toast(tr('删除失败，请重试'));
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(Gap.page),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(tr('下载记录恢复失败'), style: context.text.titleMedium),
        const SizedBox(height: Gap.s),
        Text(source, style: context.text.bodyMedium),
        Text(tr('原始记录和本地文件已保留，可以重试或仅移除记录。')),
        Wrap(
          spacing: Gap.s,
          children: [
            TextButton(
              onPressed: () => _retry(context),
              child: SelectionContainer.disabled(child: Text(tr('重试'))),
            ),
            TextButton(
              onPressed: () => _remove(context),
              child: SelectionContainer.disabled(child: Text(tr('移除记录'))),
            ),
          ],
        ),
      ],
    ),
  );
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({
    required this.task,
    this.selected = false,
    this.selecting = false,
    this.onToggle,
  });
  final DownloadTask task;
  final bool selected;
  final bool selecting;
  final VoidCallback? onToggle;

  Future<void> _chapters(BuildContext context) async {
    final t = DownloadManager.instance.task(task.uid);
    if (!context.mounted || t == null) return;
    return showAdaptiveSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ChapterSheet(
        task: t,
        onOpen: (chapter) => Nav.openChapter(
          context,
          t.item,
          chapter.id,
          downloadedOnly:
              !t.canReadWhileDownloading || t.completed.contains(chapter.id),
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    final t = DownloadManager.instance.task(task.uid);
    if (!context.mounted || t == null) return;
    if (t.chapters.length > 1) {
      return _chapters(context);
    }
    return Nav.openChapter(
      context,
      t.item,
      null,
      downloadedOnly: !t.canReadWhileDownloading,
    );
  }

  Future<void> _menu(BuildContext context) async {
    final t = DownloadManager.instance.task(task.uid);
    if (!context.mounted || t == null) return;
    final canExport = !t.isVideo && !t.isNovel && t.completed.isNotEmpty;
    final action = await showAdaptiveSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: SelectionContainer.disabled(
                child: Text(
                  t.item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
            if (t.chapters.length > 1)
              ListTile(
                leading: const Icon(Icons.list_rounded),
                title: SelectionContainer.disabled(
                  child: Text(tr(t.isVideo ? '管理分集' : '管理章节')),
                ),
                onTap: () => Navigator.pop(ctx, 'chapters'),
              ),
            ListTile(
              leading: const Icon(Icons.label_outline_rounded),
              title: SelectionContainer.disabled(child: Text(tr('分类'))),
              onTap: () => Navigator.pop(ctx, 'categories'),
            ),
            if (canExport)
              ListTile(
                leading: const Icon(Icons.archive_outlined),
                title: SelectionContainer.disabled(child: Text(tr('导出为 CBZ'))),
                onTap: () => Navigator.pop(ctx, 'cbz'),
              ),
            if (canExport)
              ListTile(
                leading: const Icon(Icons.picture_as_pdf_outlined),
                title: SelectionContainer.disabled(child: Text(tr('导出为 PDF'))),
                subtitle: SelectionContainer.disabled(
                  child: Text(tr('按已完成章节导出，动图仅保留第一帧')),
                ),
                onTap: () => Navigator.pop(ctx, 'pdf'),
              ),
            if (t.isVideo &&
                t.chapters.length == 1 &&
                t.completed.contains(t.chapters.first.id))
              ListTile(
                leading: const Icon(Icons.ios_share_rounded),
                title: SelectionContainer.disabled(child: Text(tr('导出视频文件'))),
                onTap: () => Navigator.pop(ctx, 'video'),
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded),
              title: SelectionContainer.disabled(child: Text(tr('删除'))),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    switch (action) {
      case 'chapters':
        await _chapters(context);
      case 'categories':
        final picked = await pickCategories(
          context,
          selected: Library.instance.categoriesOf(t.item.uid),
        );
        if (picked != null) {
          Library.instance.setWorkCategories(t.item, picked);
        }
      case 'cbz':
        await _exportImages(context);
      case 'pdf':
        await _exportImages(context, pdf: true);
      case 'video':
        final file = await DownloadManager.instance.localVideo(
          t.item.source,
          t.item.id,
          episodeId: t.chapters.first.id,
        );
        if (file != null && context.mounted) {
          final exported = await exportOfflineVideo(
            file,
            Directory(p.join(DownloadManager.instance.root.path, 'exports')),
          );
          if (!context.mounted) return;
          await shareContent(context, files: [XFile(exported.path)]);
        }
      case 'delete':
        await _confirmDelete(context);
    }
  }

  Future<void> _exportImages(BuildContext context, {bool pdf = false}) async {
    if (pdf && !await _choosePdfPages(context)) return;
    if (!context.mounted) return;
    ExportManager.instance.start(
      task,
      pdf ? ExportFormat.pdf : ExportFormat.cbz,
    );
    context.toast(
      tr('已在后台导出，可在“导出文件”中查看'),
      action: SnackBarAction(
        label: tr('查看'),
        onPressed: () => Nav.push(context, const ExportsPage()),
      ),
    );
  }

  /// 长图集按页数上限拆成多个 PDF；体积过大时也会自动拆分。
  Future<bool> _choosePdfPages(BuildContext context) async {
    var pages = AppSettings.instance.pdfPagesPerFile;
    const choices = [100, 300, 1000, 0];
    if (!choices.contains(pages)) pages = 300;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(tr('导出 PDF')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('每个文件最多页数')),
              const SizedBox(height: Gap.s),
              Wrap(
                spacing: Gap.s,
                runSpacing: Gap.s,
                children: [
                  for (final value in choices)
                    ChoiceChip(
                      label: Text(
                        value == 0
                            ? tr('不限')
                            : tr('{value0} 页', {'value0': value}),
                      ),
                      selected: pages == value,
                      onSelected: (_) => setState(() => pages = value),
                    ),
                ],
              ),
              const SizedBox(height: Gap.m),
              Text(
                tr('超过页数或单个文件过大时自动分成多个文件；导出在后台进行。'),
                style: context.text.bodySmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: SelectionContainer.disabled(child: Text(tr('取消'))),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: SelectionContainer.disabled(child: Text(tr('导出'))),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return false;
    AppSettings.instance.pdfPagesPerFile = pages;
    return true;
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await confirmAction(
      context,
      title: tr('删除下载？'),
      message: task.item.source == localSource
          ? tr('导入的本地文件会被删除。')
          : tr('已下载的文件也会一并删除。'),
      confirmLabel: tr('删除'),
      destructive: true,
    );
    if (!ok) return;
    try {
      await DownloadManager.instance.delete(task.uid);
    } catch (_) {
      if (context.mounted) context.toast(tr('删除失败，请重试'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = task;
    final waitingWifi =
        t.status == DownloadStatus.queued &&
        !DownloadManager.instance.networkAllowed;
    final (statusText, statusColor) = switch (t.status) {
      _ when waitingWifi => (tr('等待 Wi-Fi'), c.onSurfaceVariant),
      DownloadStatus.queued => (tr('等待中'), c.onSurfaceVariant),
      DownloadStatus.running => (
        t.total > 0
            ? (t.isVideo
                  ? '${(t.progress * 100).clamp(0, 100).round()}% · ${formatBytes(t.bytes)}'
                  : tr(
                      t.isNovel ? '{value0}/{value1} 章' : '{value0}/{value1} 页',
                      {'value0': t.done, 'value1': t.total},
                    ))
            : tr('准备中…'),
        c.primary,
      ),
      DownloadStatus.paused => (
        tr('已暂停 {value0}', {
          'value0': t.total > 0
              ? (t.isVideo
                    ? '${(t.progress * 100).clamp(0, 100).round()}%'
                    : '${t.done}/${t.total}')
              : '',
        }),
        c.onSurfaceVariant,
      ),
      DownloadStatus.done => (
        t.item.source == localSource
            ? tr('本地导入{value0}', {
                'value0': t.bytes > 0 ? ' · ${formatBytes(t.bytes)}' : '',
              })
            : tr('已完成{value0}', {
                'value0': t.bytes > 0 ? ' · ${formatBytes(t.bytes)}' : '',
              }),
        c.onSurfaceVariant,
      ),
      DownloadStatus.failed => (
        tr('失败：{value0}', {'value0': t.error ?? ''}),
        c.error,
      ),
    };
    return ActionInkWell(
      onTap: () => selecting ? onToggle?.call() : _open(context),
      onLongPress: onToggle ?? () => _menu(context),
      child: SelectionContainer.disabled(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Gap.page, Gap.m, Gap.page, Gap.m),
          child: Row(
            children: [
              SizedBox(
                width: 56,
                height: 78,
                child: ActionInkWell(
                  onTap: () => Nav.push(
                    context,
                    DetailPage(
                      source: t.item.source,
                      id: t.item.id,
                      preview: t.item,
                    ),
                  ),
                  child: CoverImage(
                    source: t.item.source,
                    url: t.item.cover,
                    sourceBlurred: t.item.json['coverBlurred'] == true,
                    title: t.item.title,
                    mediaKind: t.isNovel ? MediaKind.novel : null,
                  ),
                ),
              ),
              if (onToggle != null)
                Semantics(
                  selected: selected,
                  child: IgnorePointer(
                    child: Checkbox(value: selected, onChanged: (_) {}),
                  ),
                ),
              const SizedBox(width: Gap.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    WorkMetadataSummary(item: t.item),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        SourceAvatar(t.item.source, size: 16),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            statusText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.labelMedium?.copyWith(
                              color: statusColor,
                            ),
                          ),
                        ),
                        if (t.chapters.length > 1)
                          Text(
                            tr(
                              t.isVideo
                                  ? '{value0}/{value1} 集'
                                  : '{value0}/{value1} 章',
                              {
                                'value0': t.completed.length,
                                'value1': t.chapters.length,
                              },
                            ),
                            style: context.text.labelSmall,
                          ),
                      ],
                    ),
                    if (t.status == DownloadStatus.running ||
                        t.status == DownloadStatus.paused && t.total > 0) ...[
                      const SizedBox(height: 8),
                      DownloadProgressLine(
                        status: t.status,
                        progress: t.total > 0 ? t.progress : null,
                      ),
                    ],
                    if (t.status == DownloadStatus.running ||
                        t.status == DownloadStatus.paused ||
                        t.status == DownloadStatus.failed) ...[
                      const SizedBox(height: Gap.s),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 36),
                            padding: const EdgeInsets.symmetric(
                              horizontal: Gap.m,
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                          icon: Icon(
                            t.status == DownloadStatus.running
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            size: 18,
                          ),
                          label: Text(
                            tr(
                              t.status == DownloadStatus.running ? '暂停' : '继续',
                            ),
                          ),
                          onPressed: () => t.status == DownloadStatus.running
                              ? DownloadManager.instance.pause(t.uid)
                              : DownloadManager.instance.resume(t.uid),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: tr('更多'),
                icon: const Icon(Icons.more_vert_rounded),
                onPressed: () => _menu(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChapterSheet extends StatefulWidget {
  const _ChapterSheet({required this.task, required this.onOpen});
  final DownloadTask task;
  final ValueChanged<Chapter> onOpen;

  @override
  State<_ChapterSheet> createState() => _ChapterSheetState();
}

class _ChapterSheetState extends State<_ChapterSheet> {
  final Set<String> _selected = {};

  @override
  Widget build(BuildContext context) {
    final t = widget.task;
    return ListenableBuilder(
      listenable: DownloadManager.instance,
      builder: (context, _) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.75,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: SelectionContainer.disabled(
                  child: Text(
                    tr(t.isVideo ? '下载的分集' : '下载的章节'),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                trailing: SelectionContainer.disabled(
                  child: FilledButton.tonalIcon(
                    onPressed: _selected.isEmpty
                        ? null
                        : () async {
                            final chapters = _selected.toList();
                            final confirmed = await confirmAction(
                              context,
                              title: tr('删除下载？'),
                              message: tr('已下载的文件也会一并删除。'),
                              confirmLabel: tr('删除'),
                              destructive: true,
                            );
                            if (!confirmed || !context.mounted) return;
                            try {
                              await DownloadManager.instance.deleteChapters(
                                t.uid,
                                chapters,
                              );
                              if (context.mounted) Navigator.pop(context);
                            } catch (_) {
                              if (context.mounted) {
                                context.toast(tr('删除失败，请重试'));
                              }
                            }
                          },
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: Text(
                      tr('删除 {value0}', {'value0': _selected.length}),
                    ),
                  ),
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final ch in t.chapters)
                      CheckboxListTile(
                        value: _selected.contains(ch.id),
                        title: SelectionContainer.disabled(
                          child: Text(ch.title),
                        ),
                        subtitle: SelectionContainer.disabled(
                          child: Text(
                            t.completed.contains(ch.id) ? tr('已下载') : tr('未完成'),
                          ),
                        ),
                        secondary: SelectionContainer.disabled(
                          child: IconButton(
                            tooltip: tr(t.isVideo ? '播放' : '阅读'),
                            icon: const Icon(Icons.play_circle_outline_rounded),
                            onPressed:
                                (!t.isVideo && !t.isNovel) ||
                                    t.completed.contains(ch.id)
                                ? () {
                                    Navigator.pop(context);
                                    widget.onOpen(ch);
                                  }
                                : null,
                          ),
                        ),
                        onChanged: (v) => setState(
                          () => v == true
                              ? _selected.add(ch.id)
                              : _selected.remove(ch.id),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
