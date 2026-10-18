import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/error_view.dart';
import 'reverse_search_controller.dart';

/// 只有返回候选的站点才进入切换区，失败信息通过独立入口查看。
class ReverseSearchResultsHeader extends StatelessWidget {
  const ReverseSearchResultsHeader({
    super.key,
    required this.controller,
    required this.source,
    required this.sourceName,
    required this.onSelected,
  });

  final ReverseSearchController controller;
  final String? source;
  final String Function(String) sourceName;
  final ValueChanged<String> onSelected;

  void _showFailures(BuildContext context) {
    final failures = {
      for (final key in controller.failedSources)
        key: controller.results[key]!.error!,
    };
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 640,
            maxHeight: MediaQuery.sizeOf(dialogContext).height * .8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: IconButton(
                  tooltip: tr('关闭'),
                  onPressed: () => Navigator.pop(dialogContext),
                  icon: const Icon(Icons.close),
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(Gap.page),
                  children: [
                    for (final entry in failures.entries) ...[
                      Text(
                        sourceName(entry.key),
                        style: context.text.titleMedium,
                      ),
                      SourceErrorView(
                        error: entry.value,
                        source: entry.key,
                        compact: true,
                        onRetry: () {
                          if (!dialogContext.mounted) return;
                          Navigator.pop(dialogContext);
                          if (context.mounted) controller.retry(entry.key);
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final results = controller.results;
    final successful = controller.successfulSources;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            tr('识别结果'),
            style: ParkText.serif(context.text.headlineSmall),
          ),
        ),
        const SizedBox(height: Gap.s),
        if (results.isNotEmpty) ...[
          Text(
            tr('已完成 {done}/{total} 个站点', {
              'done': '${controller.completed}',
              'total': '${results.length}',
            }),
            style: context.text.bodyMedium,
          ),
          const SizedBox(height: Gap.s),
          if (controller.busy) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: Gap.s),
          ],
        ],
        if (controller.failedSources.isNotEmpty)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () => _showFailures(context),
              icon: const Icon(Icons.info_outline, size: 18),
              label: Text(
                tr('{count} 个站点搜索失败', {
                  'count': '${controller.failedSources.length}',
                }),
              ),
            ),
          ),
        if (successful.isNotEmpty) ...[
          const SizedBox(height: Gap.s),
          LayoutBuilder(
            builder: (context, constraints) => Wrap(
              spacing: Gap.s,
              runSpacing: Gap.xs,
              children: [
                for (final key in successful)
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                    child: ChoiceChip(
                      key: ValueKey('reverse-result-$key'),
                      label: SelectionContainer.disabled(
                        child: Text(
                          '${sourceName(key)} · ${results[key]!.matches.length}',
                        ),
                      ),
                      selected: key == source,
                      showCheckmark: false,
                      onSelected: (_) => onSelected(key),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: Gap.m),
          Text(
            tr('识别结果仅供核对；分数由各服务提供，不代表已确认出处'),
            style: context.text.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
        ] else if (controller.busy)
          EmptyState(
            icon: Icons.image_search_outlined,
            title: tr('正在识别，服务繁忙时可能需要排队'),
            compact: true,
          )
        else if (results.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Gap.xxl),
            child: EmptyState(
              icon: Icons.image_search_outlined,
              title: tr('等待识别'),
              message: tr('选择图片和服务后开始反搜'),
            ),
          )
        else
          EmptyState(
            icon: Icons.search_off_outlined,
            title: controller.cancelled
                ? tr('已取消')
                : controller.failedSources.length == results.length
                ? tr('加载失败')
                : tr('服务未返回候选结果'),
            message: tr('尝试裁剪主体、使用更清晰的原图或切换服务'),
          ),
      ],
    );
  }
}
