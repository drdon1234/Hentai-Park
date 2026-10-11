import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../../core/settings.dart';
import '../../core/storage.dart';
import '../../library/backup.dart';
import '../theme.dart';
import '../widgets/common.dart';
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
    final options = await showDialog<BackupOptions>(context: context, builder: (_) => const _OptionsDialog());
    if (options == null) return;
    await _guard(() async {
      final file = await BackupService.instance.writeTo(AppPaths.backups, options);
      await _refresh();
      if (!mounted) return;
      context.toast('备份已保存');
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], subject: p.basename(file.path)));
    });
  }

  Future<void> _restoreBytes(List<int> bytes) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('恢复备份？'),
        content: const Text('备份会与当前数据合并：收藏取并集，已读进度保留较新的一方，设置会被备份中的值覆盖。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('恢复')),
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
          title: const Text('恢复完成'),
          content: Text(report.summary.isEmpty ? '没有需要合并的新数据' : '已合并：${report.summary}'),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('好'))],
        ),
      );
      if (!mounted) return;
      for (final missing in report.sourcesToInstall) {
        if (!mounted) break;
        await installSourceFromUrl(context, missing.url);
      }
    });
  }

  Future<void> _pickAndRestore() async {
    final file = await FilePicker.pickFile(dialogTitle: '选择备份文件');
    if (file == null) return;
    if (!file.name.endsWith(BackupService.extension) && mounted) {
      context.toast('请选择 ${BackupService.extension} 文件');
      return;
    }
    await _restoreBytes(await file.xFile.readAsBytes());
  }

  Future<void> _guard(Future<void> Function() body) async {
    setState(() => _busy = true);
    try {
      await body();
    } on FormatException catch (e) {
      if (mounted) context.toast(e.message);
    } catch (e) {
      if (mounted) context.toast('操作失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _fileMenu(File f) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(p.basename(f.path), style: const TextStyle(fontWeight: FontWeight.w700))),
            ListTile(leading: const Icon(Icons.restore_rounded), title: const Text('从此备份恢复'), onTap: () => Navigator.pop(ctx, 'restore')),
            ListTile(leading: const Icon(Icons.share_rounded), title: const Text('分享 / 另存'), onTap: () => Navigator.pop(ctx, 'share')),
            ListTile(leading: const Icon(Icons.delete_outline_rounded), title: const Text('删除'), onTap: () => Navigator.pop(ctx, 'delete')),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'restore':
        await _restoreBytes(await f.readAsBytes());
      case 'share':
        await SharePlus.instance.share(ShareParams(files: [XFile(f.path)]));
      case 'delete':
        await f.delete();
        await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final last = s.lastAutoBackup;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: const Text('备份与恢复'),
          bottom: _busy ? const PreferredSize(preferredSize: Size.fromHeight(2), child: LinearProgressIndicator(minHeight: 2)) : null,
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
          children: [
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.backup_outlined),
                    title: const Text('创建备份'),
                    subtitle: const Text('收藏、分类、阅读进度、历史、设置与源列表'),
                    onTap: _busy ? null : _create,
                  ),
                  ListTile(
                    leading: const Icon(Icons.settings_backup_restore_rounded),
                    title: const Text('从文件恢复'),
                    subtitle: const Text('选择 .parkbak 文件，与当前数据合并'),
                    onTap: _busy ? null : _pickAndRestore,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.schedule_rounded),
                    title: const Text('自动备份'),
                    subtitle: Text(last == 0 ? '尚未自动备份过' : '上次：${timeAgo(DateTime.fromMillisecondsSinceEpoch(last))}'),
                    trailing: DropdownButton<int>(
                      value: s.autoBackupHours,
                      underline: const SizedBox.shrink(),
                      items: const [
                        (0, '关闭'),
                        (12, '每 12 小时'),
                        (24, '每天'),
                        (72, '每 3 天'),
                        (168, '每周'),
                      ].map((e) => DropdownMenuItem(value: e.$1, child: Text(e.$2))).toList(),
                      onChanged: (v) => s.autoBackupHours = v ?? 24,
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.layers_outlined),
                    title: const Text('保留份数'),
                    trailing: DropdownButton<int>(
                      value: s.autoBackupKeep,
                      underline: const SizedBox.shrink(),
                      items: const [1, 2, 3, 5, 10].map((v) => DropdownMenuItem(value: v, child: Text('$v'))).toList(),
                      onChanged: (v) => s.autoBackupKeep = v ?? 3,
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.folder_outlined),
                    title: const Text('备份目录'),
                    subtitle: SelectableText(AppPaths.backups.path, style: context.text.bodySmall),
                  ),
                ],
              ),
            ),
            if (_files.isNotEmpty) ...[
              const SectionHeader('本机备份'),
              Card(
                child: Column(
                  children: [
                    for (final f in _files)
                      ListTile(
                        leading: const Icon(Icons.description_outlined),
                        title: Text(p.basename(f.path)),
                        subtitle: Text(formatBytes(f.lengthSync())),
                        onTap: _busy ? null : () => _fileMenu(f),
                      ),
                  ],
                ),
              ),
            ],
          ],
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
      title: const Text('备份内容'),
      contentPadding: const EdgeInsets.fromLTRB(8, 16, 8, 0),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CheckboxListTile(value: library, title: const Text('书库'), subtitle: const Text('收藏、分类、阅读进度、历史'), onChanged: (v) => setState(() => library = v!)),
          CheckboxListTile(value: settings, title: const Text('应用设置'), onChanged: (v) => setState(() => settings = v!)),
          CheckboxListTile(value: sources, title: const Text('源列表与源设置'), onChanged: (v) => setState(() => sources = v!)),
          CheckboxListTile(
            value: credentials,
            title: const Text('源登录数据'),
            subtitle: const Text('包含 Token 等凭据，请妥善保管备份文件；基于 Cookie 的登录（如 E-Hentai）需要重新登录'),
            onChanged: sources ? (v) => setState(() => credentials = v!) : null,
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          onPressed: () => Navigator.pop(context, BackupOptions(library: library, settings: settings, sources: sources, credentials: sources && credentials)),
          child: const Text('创建'),
        ),
      ],
    );
  }
}
