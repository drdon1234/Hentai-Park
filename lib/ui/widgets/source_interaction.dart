import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../../core/models.dart';
import '../../engine/source_manager.dart';
import '../theme.dart';
import 'error_view.dart';

/// 原站偏好独立于本地书库；读写都使用源插件的当前登录态。
final _activeInteractions = <String>{};

Future<void> showSourceInteraction(BuildContext context, WorkItem item) async {
  if (!_activeInteractions.add(item.uid)) return;
  try {
    await _showSourceInteraction(context, item);
  } finally {
    _activeInteractions.remove(item.uid);
  }
}

Future<void> _showSourceInteraction(BuildContext context, WorkItem item) async {
  final manager = SourceManager.instance;
  final state = await guarded(
    context,
    item.source,
    () => manager.interaction(item.source, item.id),
  );
  if (state == null || !context.mounted) return;
  final rating = state['type'] == 'rating';
  final selected = await showDialog<Object>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text(
        tr(
          rating
              ? '原站评分'
              : state['type'] == 'like'
              ? '原站点赞'
              : '原站收藏',
        ),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(tr('使用当前登录账号，保存到原站用于表达喜好')),
        ),
        if (rating)
          for (var step = 10; step >= 1; step--)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, step / 2),
              child: Text('★ ${step / 2}'),
            )
        else
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, state['value'] != true),
            child: Text(tr(state['value'] == true ? '取消原站喜好' : '保存原站喜好')),
          ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx),
          child: Text(tr('取消')),
        ),
      ],
    ),
  );
  if (selected == null || !context.mounted) return;
  final result = await guarded(
    context,
    item.source,
    () => manager.interaction(item.source, item.id, value: selected),
  );
  if (result != null && context.mounted) context.toast(tr('原站操作已完成'));
}
