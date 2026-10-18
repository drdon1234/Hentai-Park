import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../../core/models.dart';
import '../../engine/source_manager.dart';
import '../kit/tokens.dart';
import '../theme.dart';
import 'error_view.dart';

/// Only completed, user-requested site writes notify recommendation shelves.
final sourceInteractionChanges =
    ValueNotifier<({WorkItem item, String type, Object value})?>(null);
final _activeInteractions = <String>{};

String _label(String type) => switch (type) {
  'like' => tr('原站点赞'),
  'favorite' => tr('原站收藏'),
  _ => tr('原站评分'),
};

Future<void> showSourceInteraction(
  BuildContext context,
  WorkItem item, {
  SourceManager? sourceManager,
}) async {
  if (!_activeInteractions.add(item.uid)) return;
  Future<List<Map<String, dynamic>>?>? pendingWrite;
  try {
    final manager = sourceManager ?? SourceManager.instance;
    var states = await guarded(
      context,
      item.source,
      () => manager.interaction(item.source, item.id),
    );
    if (states == null || !context.mounted) return;
    var busy = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, update) => SimpleDialog(
          title: Text(tr('原站互动')),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Gap.xl),
              child: Text(tr('使用当前登录账号，保存到原站用于表达喜好')),
            ),
            for (final state in states!)
              ListTile(
                leading: Icon(switch (state['type']) {
                  'like' =>
                    state['value'] == true
                        ? Icons.thumb_up
                        : Icons.thumb_up_outlined,
                  'favorite' =>
                    state['value'] == true
                        ? Icons.bookmark
                        : Icons.bookmark_border,
                  _ => Icons.star_outline,
                }),
                title: Text(_label(state['type'] as String)),
                subtitle: Text(
                  state['type'] == 'rating'
                      ? state['value']?.toString() ?? tr('原站未提供个人评分')
                      : tr(
                          state['value'] == true && state['canUnset'] == false
                              ? '已点赞，原站不支持取消'
                              : state['value'] == true
                              ? '已保存到原站'
                              : '未保存到原站',
                        ),
                ),
                trailing: state['type'] == 'rating'
                    ? const Icon(Icons.chevron_right)
                    : Icon(
                        state['value'] == true
                            ? Icons.check_circle_outline
                            : Icons.circle_outlined,
                      ),
                enabled:
                    !busy &&
                    !(state['value'] == true && state['canUnset'] == false),
                onTap: () async {
                  Object? value = state['value'] != true;
                  if (state['type'] == 'rating') {
                    value = await showDialog<double>(
                      context: dialogContext,
                      builder: (ctx) => SimpleDialog(
                        title: Text(tr('原站评分')),
                        children: [
                          for (var i = 10; i >= 1; i--)
                            SimpleDialogOption(
                              onPressed: () => Navigator.pop(ctx, i / 2),
                              child: Text('★ ${i / 2}'),
                            ),
                        ],
                      ),
                    );
                  }
                  if (value == null || !dialogContext.mounted || busy) return;
                  final selected = value;
                  update(() => busy = true);
                  final request = guarded(
                    dialogContext,
                    item.source,
                    () => manager.interaction(
                      item.source,
                      item.id,
                      type: state['type'] as String,
                      value: selected,
                    ),
                  );
                  pendingWrite = request;
                  final result = await request;
                  if (result != null) {
                    sourceInteractionChanges.value = (
                      item: item,
                      type: state['type'] as String,
                      value: selected,
                    );
                  }
                  if (!dialogContext.mounted) return;
                  update(() {
                    busy = false;
                    if (result != null) states = result;
                  });
                  if (result != null) {
                    if (context.mounted) context.toast(tr('原站操作已完成'));
                  }
                },
              ),
            if (busy) const LinearProgressIndicator(),
            SimpleDialogOption(
              onPressed: busy ? null : () => Navigator.pop(dialogContext),
              child: Text(tr('关闭')),
            ),
          ],
        ),
      ),
    );
  } finally {
    try {
      await pendingWrite;
    } finally {
      _activeInteractions.remove(item.uid);
    }
  }
}
