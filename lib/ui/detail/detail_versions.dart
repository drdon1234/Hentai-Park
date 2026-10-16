import 'package:flutter/material.dart';

import '../../core/content_scope.dart';
import '../../core/localization.dart';
import '../../core/models.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/work_editions.dart';

/// 仅展示插件确认的版本；不同版本保持各自的进度、收藏与下载身份。
class DetailVersions extends StatelessWidget {
  const DetailVersions({super.key, required this.work, required this.manifest});
  final WorkDetail work;
  final SourceManifest? manifest;

  @override
  Widget build(BuildContext context) {
    final keyword = work.workCode;
    final searchable = manifest?.can('search') == true;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Gap.page,
        vertical: Gap.s,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('其他版本'), style: context.text.titleSmall),
          const SizedBox(height: Gap.s),
          Wrap(
            spacing: Gap.s,
            runSpacing: Gap.s,
            children: [
              for (final variant in work.variants)
                ActionChip(
                  label: SelectionContainer.disabled(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.sizeOf(context).width * .7,
                      ),
                      child: Text(
                        variant.editions.isNotEmpty
                            ? workEditionLabel(variant)
                            : variant.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  onPressed: () => Nav.openWork(context, variant),
                ),
              if (keyword.isNotEmpty && searchable)
                ActionChip(
                  label: SelectionContainer.disabled(child: Text(tr('站内查找版本'))),
                  onPressed: () => Nav.openSourceSearch(
                    context,
                    work.source,
                    keyword: keyword,
                  ),
                ),
              if (keyword.isNotEmpty && manifest != null)
                ActionChip(
                  label: SelectionContainer.disabled(child: Text(tr('跨站查找版本'))),
                  onPressed: () => Nav.openAggregateSearch(
                    context,
                    keyword: keyword,
                    scope: ContentScope.domain(manifest!.category),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
