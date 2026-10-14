import 'package:flutter/material.dart';

import '../../core/content_scope.dart';
import '../../core/localization.dart';
import '../../library/library.dart';
import '../widgets/common.dart';
import '../widgets/cover_tile.dart';

/// 继续看: the most recent history in the selected scope as one horizontal row. Hidden when
/// there is nothing to continue.
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
    if (recent.isEmpty) return const SizedBox.shrink();
    const width = 112.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          tr('继续看'),
          trailing: onOpenHistory == null
              ? null
              : TextButton(onPressed: onOpenHistory, child: Text(tr('全部'))),
        ),
        SizedBox(
          height: width / .72 + cardTextExtent(context),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Gap.page),
            itemCount: recent.length,
            separatorBuilder: (_, _) => const SizedBox(width: Gap.m),
            itemBuilder: (context, index) => SizedBox(
              width: width,
              child: CoverTile(
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
