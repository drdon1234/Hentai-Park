import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../../core/reverse_search_history.dart';
import '../kit/adaptive_sheet.dart';
import '../widgets/common.dart';

Future<Map<String, dynamic>?> showReverseSearchHistory(
  BuildContext context,
) async {
  final history = ReverseSearchHistory.instance;
  await history.load();
  if (!context.mounted) return null;
  return showAdaptiveSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(ctx).height * .7,
        child: ListenableBuilder(
          listenable: history,
          builder: (ctx, _) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(Gap.page),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        tr('反搜历史'),
                        style: Theme.of(ctx).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: tr('清空'),
                      icon: const Icon(Icons.delete_sweep_outlined),
                      onPressed: history.entries.isEmpty
                          ? null
                          : () async {
                              if (await confirmAction(
                                ctx,
                                title: tr('清空反搜历史'),
                                confirmLabel: tr('清空'),
                                destructive: true,
                              )) {
                                history.clear();
                              }
                            },
                    ),
                  ],
                ),
              ),
              Expanded(
                child: history.entries.isEmpty
                    ? Center(child: Text(tr('暂无反搜历史')))
                    : ListView.builder(
                        itemCount: history.entries.length,
                        itemBuilder: (ctx, index) {
                          final entry = history.entries[index];
                          return ListTile(
                            leading: Image.memory(
                              base64Decode(entry['image'] as String),
                              width: 48,
                              height: 48,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) =>
                                  const Icon(Icons.broken_image_outlined),
                            ),
                            title: Text(
                              MaterialLocalizations.of(ctx).formatMediumDate(
                                DateTime.tryParse(
                                      entry['time'] as String? ?? '',
                                    )?.toLocal() ??
                                    DateTime.now(),
                              ),
                            ),
                            subtitle: Text(tr('载入图片后可重新搜索')),
                            onTap: () => Navigator.pop(ctx, entry),
                            trailing: IconButton(
                              tooltip: tr('删除'),
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () =>
                                  history.remove(entry['id'] as String),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
