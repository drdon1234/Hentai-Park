import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../../tavern/transfer.dart';
import '../kit/adaptive_sheet.dart';
import '../theme.dart';

/// 酒馆域页的导入入口。导入动作和资源库展示分开，避免把创建任务藏在资源列表页。
Future<void> chooseAndImportTavern(BuildContext context) async {
  final hostContext = context;
  await showAdaptiveSheet<void>(
    context: context,
    builder: (context) => SafeArea(
      child: Wrap(
        children: [
          ListTile(
            leading: const Icon(Icons.person_outline_rounded),
            title: Text('${tr('导入')} ${tr('角色卡')}'),
            subtitle: Text(tr('PNG 或 JSON 角色卡')),
            onTap: () {
              Navigator.pop(context);
              _importTavernFile(hostContext, expectedKind: 'character');
            },
          ),
          ListTile(
            leading: const Icon(Icons.menu_book_outlined),
            title: Text('${tr('导入')} ${tr('世界书')}'),
            subtitle: Text(tr('JSON 世界书')),
            onTap: () {
              Navigator.pop(context);
              _importTavernFile(hostContext, expectedKind: 'lorebook');
            },
          ),
          ListTile(
            leading: const Icon(Icons.archive_outlined),
            title: Text('${tr('导入')} ${tr('会话')} / ${tr('备份')}'),
            subtitle: Text(tr('本应用导出的会话或书库备份')),
            onTap: () {
              Navigator.pop(context);
              _importTavernFile(hostContext);
            },
          ),
        ],
      ),
    ),
  );
}

Future<void> _importTavernFile(
  BuildContext context, {
  String? expectedKind,
}) async {
  try {
    final file = await FilePicker.pickFile();
    if (file == null || !context.mounted) return;
    if (await file.xFile.length() > 32 * 1024 * 1024) {
      throw const FormatException();
    }
    await TavernTransfer.importBytes(
      await file.xFile.readAsBytes(),
      file.xFile.name,
      expectedKind: expectedKind,
    );
    if (context.mounted) context.toast(tr('已导入'));
  } catch (_) {
    if (context.mounted) context.toast(tr('导入失败，请检查文件格式'));
  }
}
