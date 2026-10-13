import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../../core/content_scope.dart';
import '../../library/library.dart';
import '../theme.dart';
import '../widgets/work_card.dart';

/// 所选范围的记录横向单行，小说/视频与漫画共用相同海报比例。
class RecentHistory extends StatelessWidget {
  const RecentHistory({
    super.key,
    this.onOpenHistory,
    this.limit,
    this.scope = const ContentScope.all(),
  });
  final ContentScope scope;
  final VoidCallback? onOpenHistory;
  final int? limit;
  @override
  Widget build(BuildContext context) {
    final entries = Library.instance.history(scope: scope);
    final recent = limit == null ? entries : entries.take(limit!).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Wrap(
            spacing: 12,
            runSpacing: 4,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                tr('最近浏览记录'),
                style: context.text.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (onOpenHistory != null)
                TextButton.icon(
                  onPressed: onOpenHistory,
                  icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                  label: Text(tr('进入历史页')),
                ),
            ],
          ),
        ),
        if (recent.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text(
              tr('暂无浏览记录'),
              style: context.text.bodyMedium?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          )
        else
          SizedBox(
            height: 124 / .72 + cardTextExtent(context),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: recent.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) => SizedBox(
                width: 124,
                child: WorkCard(
                  item: recent[index].item,
                  aspect: .72,
                  showSource: true,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
