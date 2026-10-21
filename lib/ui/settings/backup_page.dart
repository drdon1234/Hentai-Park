import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/localization.dart';
import '../../core/settings.dart';
import '../../core/storage.dart';
import '../../library/backup.dart';
import '../kit/adaptive_sheet.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/file_drop_region.dart';
import '../widgets/platform_share.dart';
import 'source_install.dart';

class BackupPage extends StatefulWidget {
  const BackupPage({super.key});

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  final s = AppSettings.instance;
  List<File> _files = [];
  bool _busy = false;
  bool _reading = false;
  bool get _unavailable => _busy || _reading;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final files = await BackupService.instance.listBackups();
    if (mounted) setState(() => _files = files);
  }

  Future<void> _create() async {
    final options = await showDialog<BackupOptions>(
      context: context,
      builder: (_) => const _OptionsDialog(),
    );
    if (options == null) return;
    await _guard(() async {
      final file = await BackupService.instance.writeTo(
        AppPaths.backups,
        options,
      );
      await _refresh();
      if (!mounted) return;
      context.toast(tr('备份已保存'));
      await shareContent(
        context,
        files: [XFile(file.path)],
        subject: p.basename(file.path),
      );
    });
  }

  Future<void> _restoreBytes(List<int> bytes) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('恢复备份？')),
        content: Text(tr('备份会与当前数据合并：收藏取并集，已读进度保留较新的一方，设置会被备份中的值覆盖。')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: SelectionContainer.disabled(child: Text(tr('取消'))),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: SelectionContainer.disabled(child: Text(tr('恢复'))),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _guard(() async {
      final report = await BackupService.instance.restore(bytes);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr('恢复完成')),
          content: Text(
            report.summary.isEmpty
                ? tr('没有需要合并的新数据')
                : tr('已合并：{value0}', {'value0': report.summary}),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: SelectionContainer.disabled(child: Text(tr('好'))),
            ),
          ],
        ),
      );
      if (!mounted) return;
      for (final missing in report.sourcesToInstall) {
        if (!mounted) break;
        final key = await installSourceFromUrl(
          context,
          missing.url,
          expectedKey: missing.key,
        );
        if (key == null && mounted) context.toast(tr('未安装站点的设置已保留，安装后自动恢复'));
      }
    });
  }

  Future<void> _pickAndRestore() async {
    final file = await FilePicker.pickFile(dialogTitle: tr('选择备份文件'));
    if (file == null || !mounted) return;
    await _restoreFile(file.xFile);
  }

  Future<void> _drop(List<DropItem> files) async {
    if (_unavailable || files.isEmpty) return;
    if (files.length != 1 || files.single is DropItemDirectory) {
      context.toast(tr('请选择 {value0} 文件', {'value0': BackupService.extension}));
      return;
    }
    await _restoreFile(files.single);
  }

  Future<void> _restoreFile(XFile file) async {
    if (_unavailable) return;
    if (!file.name.toLowerCase().endsWith(BackupService.extension)) {
      context.toast(tr('请选择 {value0} 文件', {'value0': BackupService.extension}));
      return;
    }
    setState(() => _reading = true);
    try {
      final bytes = await file.readAsBytes();
      if (mounted) await _restoreBytes(bytes);
    } catch (_) {
      if (mounted) context.toast(tr('无法读取文件，请重试'));
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  Future<void> _guard(Future<void> Function() body) async {
    setState(() => _busy = true);
    try {
      await body();
    } on FormatException catch (e) {
      if (mounted) context.toast(e.message);
    } catch (e) {
      if (mounted) context.toast(tr('操作失败：{value0}', {'value0': e}));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _fileMenu(File f) async {
    final action = await showAdaptiveSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: SelectionContainer.disabled(
                child: Text(
                  p.basename(f.path),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.restore_rounded),
              title: SelectionContainer.disabled(child: Text(tr('从此备份恢复'))),
              onTap: () => Navigator.pop(ctx, 'restore'),
            ),
            ListTile(
              leading: const Icon(Icons.share_rounded),
              title: SelectionContainer.disabled(child: Text(tr('分享 / 另存'))),
              onTap: () => Navigator.pop(ctx, 'share'),
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
    if (!mounted) return;
    switch (action) {
      case 'restore':
        await _restoreBytes(await f.readAsBytes());
      case 'share':
        await shareContent(context, files: [XFile(f.path)]);
      case 'delete':
        await f.delete();
        await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final last = s.lastAutoBackup;
    return ListenableBuilder(
      listenable: s.domain(SettingsDomain.maintenance),
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: Text(tr('备份与恢复')),
          bottom: _busy
              ? const PreferredSize(
                  preferredSize: Size.fromHeight(2),
                  child: LinearProgressIndicator(minHeight: 2),
                )
              : null,
        ),
        body: FileDropRegion(
          enabled: !_unavailable,
          message: tr('松开以选择此备份，确认后恢复'),
          onDrop: _drop,
          child: SettingsBody(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 32),
              children: [
                RowGroup(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.backup_outlined),
                      title: SelectionContainer.disabled(
                        child: Text(tr('创建备份')),
                      ),
                      subtitle: SelectionContainer.disabled(
                        child: Text(
                          tr('收藏、分类、阅读进度、历史、标注、订阅、设置与站点列表；不包含下载内容或 Cookie'),
                        ),
                      ),
                      onTap: _unavailable ? null : _create,
                    ),
                    ListTile(
                      leading: const Icon(
                        Icons.settings_backup_restore_rounded,
                      ),
                      title: SelectionContainer.disabled(
                        child: Text(tr('从文件恢复')),
                      ),
                      subtitle: SelectionContainer.disabled(
                        child: Text(tr('选择 .parkbak 文件，与当前数据合并')),
                      ),
                      onTap: _unavailable ? null : _pickAndRestore,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                RowGroup(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.schedule_rounded),
                      title: SelectionContainer.disabled(
                        child: Text(tr('自动备份')),
                      ),
                      subtitle: SelectionContainer.disabled(
                        child: Text(
                          last == 0
                              ? tr('尚未自动备份过')
                              : tr('上次：{value0}', {
                                  'value0': timeAgo(
                                    DateTime.fromMillisecondsSinceEpoch(last),
                                  ),
                                }),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                        72,
                        0,
                        16,
                        12,
                      ),
                      child: SelectionContainer.disabled(
                        child: DropdownButton<int>(
                          value: s.autoBackupHours,
                          isExpanded: true,
                          underline: const SizedBox.shrink(),
                          items:
                              [
                                    (0, tr('关闭')),
                                    (12, tr('每 12 小时')),
                                    (24, tr('每天')),
                                    (72, tr('每 3 天')),
                                    (168, tr('每周')),
                                  ]
                                  .map(
                                    (e) => DropdownMenuItem(
                                      value: e.$1,
                                      child: SelectionContainer.disabled(
                                        child: Text(
                                          e.$2,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                          onChanged: (v) => s.autoBackupHours = v ?? 24,
                        ),
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.layers_outlined),
                      title: SelectionContainer.disabled(
                        child: Text(tr('保留份数')),
                      ),
                      subtitle: SelectionContainer.disabled(
                        child: Text(tr('仅清理自动备份，手工备份保留')),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Text(tr('打开应用或回到前台时检查备份间隔；应用关闭时不会执行后台定时备份')),
                    ),
                    Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                        72,
                        0,
                        16,
                        12,
                      ),
                      child: SelectionContainer.disabled(
                        child: DropdownButton<int>(
                          value: s.autoBackupKeep,
                          isExpanded: true,
                          underline: const SizedBox.shrink(),
                          items: const [1, 2, 3, 5, 10]
                              .map(
                                (v) => DropdownMenuItem(
                                  value: v,
                                  child: SelectionContainer.disabled(
                                    child: Text('$v'),
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) => s.autoBackupKeep = v ?? 3,
                        ),
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.folder_outlined),
                      title: SelectionContainer.disabled(
                        child: Text(tr('备份目录')),
                      ),
                      subtitle: SelectionContainer.disabled(
                        child: SelectableText(
                          AppPaths.backups.path,
                          style: context.text.bodySmall,
                        ),
                      ),
                    ),
                  ],
                ),
                if (_files.isNotEmpty) ...[
                  RowGroup(
                    title: tr('本机备份'),
                    children: [
                      for (final f in _files)
                        ListTile(
                          leading: const Icon(Icons.description_outlined),
                          title: SelectionContainer.disabled(
                            child: Text(p.basename(f.path)),
                          ),
                          subtitle: SelectionContainer.disabled(
                            child: Text(formatBytes(f.lengthSync())),
                          ),
                          onTap: _unavailable ? null : () => _fileMenu(f),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OptionsDialog extends StatefulWidget {
  const _OptionsDialog();

  @override
  State<_OptionsDialog> createState() => _OptionsDialogState();
}

class _OptionsDialogState extends State<_OptionsDialog> {
  bool library = true, settings = true, sources = true, credentials = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr('备份内容')),
      contentPadding: const EdgeInsets.fromLTRB(8, 16, 8, 0),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CheckboxListTile(
            value: library,
            title: SelectionContainer.disabled(child: Text(tr('书库'))),
            subtitle: SelectionContainer.disabled(
              child: Text(tr('收藏、分类、阅读进度、历史')),
            ),
            onChanged: (v) => setState(() => library = v!),
          ),
          CheckboxListTile(
            value: settings,
            title: SelectionContainer.disabled(child: Text(tr('应用设置'))),
            onChanged: (v) => setState(() => settings = v!),
          ),
          CheckboxListTile(
            value: sources,
            title: SelectionContainer.disabled(child: Text(tr('站点列表与站点设置'))),
            onChanged: (v) => setState(() => sources = v!),
          ),
          CheckboxListTile(
            value: credentials,
            title: SelectionContainer.disabled(child: Text(tr('站点登录数据'))),
            subtitle: SelectionContainer.disabled(
              child: Text(
                tr('包含 Token 等凭据，请妥善保管备份文件；基于 Cookie 的登录（如 E-Hentai）需要重新登录'),
              ),
            ),
            onChanged: sources ? (v) => setState(() => credentials = v!) : null,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: SelectionContainer.disabled(child: Text(tr('取消'))),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            BackupOptions(
              library: library,
              settings: settings,
              sources: sources,
              credentials: sources && credentials,
            ),
          ),
          child: SelectionContainer.disabled(child: Text(tr('创建'))),
        ),
      ],
    );
  }
}
