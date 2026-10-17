import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../theme.dart';

/// 恢复会覆盖用户当前选择，先说明范围，写入成功后才显示完成。
Future<void> confirmReset(
  BuildContext context, {
  required String title,
  required String message,
  required Future<void> Function() reset,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr(title)),
      content: Text(tr(message)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(tr('取消')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(tr('恢复')),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  try {
    await reset();
    if (context.mounted) context.toast(tr('已恢复'));
  } catch (_) {
    if (context.mounted) context.toast(tr('恢复失败，请重试'));
  }
}
