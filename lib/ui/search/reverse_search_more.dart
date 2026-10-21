import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../../core/models.dart';
import '../kit/tokens.dart';
import '../theme.dart';
import 'reverse_search_controller.dart';

/// 按站点展开，续载失败不会替换已经显示的候选。
class ReverseSearchMore extends StatelessWidget {
  const ReverseSearchMore({
    super.key,
    required this.result,
    required this.onLoad,
  });

  final ReverseSearchSiteResult result;
  final VoidCallback onLoad;

  @override
  Widget build(BuildContext context) {
    if (!result.hasMore) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Gap.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            tr('当前显示前 {count} 条结果', {'count': '${result.matches.length}'}),
            style: context.text.bodySmall,
          ),
          const SizedBox(height: Gap.s),
          if (result.allError != null)
            Row(
              children: [
                Expanded(
                  child: Text(
                    result.allError is SourceError
                        ? (result.allError! as SourceError).message
                        : tr('加载失败'),
                    style: context.text.bodySmall?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                ),
                OutlinedButton(onPressed: onLoad, child: Text(tr('重试'))),
              ],
            )
          else if (result.loadingAll)
            Semantics(
              liveRegion: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(tr('正在加载全部结果')),
                  const SizedBox(height: Gap.s),
                  const LinearProgressIndicator(),
                ],
              ),
            )
          else
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton(
                onPressed: onLoad,
                child: Text(tr('查看全部结果')),
              ),
            ),
        ],
      ),
    );
  }
}
