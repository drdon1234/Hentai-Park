import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../../core/models.dart';
import '../../engine/ranking_details.dart';
import '../../engine/source_manager.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// 站点选择决定详情与搜索的去向，不参与榜单内容筛选。
class RankingSettingsPage extends StatefulWidget {
  const RankingSettingsPage({
    super.key,
    required this.category,
    required this.manager,
    required this.onDetailChanged,
    required this.onSearchChanged,
    this.origin,
    this.detailSource = '',
    this.searchSource = '',
  });

  final SourceCategory category;
  final SourceManager manager;
  final String? origin;
  final String detailSource, searchSource;
  final ValueChanged<String> onDetailChanged, onSearchChanged;

  @override
  State<RankingSettingsPage> createState() => _RankingSettingsPageState();
}

class _RankingSettingsPageState extends State<RankingSettingsPage> {
  late String _detail = widget.detailSource;
  late String _search = widget.searchSource;

  Future<void> _choose({
    required String title,
    required Map<String, String> options,
    required String selected,
    required bool detail,
  }) async {
    final value = await showChoiceSheet<String>(
      context,
      title: title,
      options: options.keys.toList(),
      selected: selected,
      label: (key) => options[key]!,
    );
    if (!mounted || value == null) return;
    setState(() {
      if (detail) {
        _detail = value;
      } else {
        _search = value;
      }
    });
    (detail ? widget.onDetailChanged : widget.onSearchChanged)(value);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr('排行榜配置'))),
    body: ListenableBuilder(
      listenable: widget.manager,
      builder: (context, _) {
        final details = {
          '': tr('源站优先'),
          for (final source in rankingDetailSources(
            widget.manager,
            widget.category,
            origin: widget.origin,
          ))
            source.key: source.manifest!.name,
        };
        final searches = {
          '': tr('全部'),
          'preferred': tr('域首选项'),
          for (final source in widget.manager.displayEnabled.where(
            (source) =>
                source.manifest!.category == widget.category &&
                source.manifest!.can('search') &&
                !source.manifest!.metadataOnly &&
                !source.manifest!.rankingOnly,
          ))
            source.key: source.manifest!.name,
        };
        final detail = details.containsKey(_detail) ? _detail : '';
        final search = searches.containsKey(_search) ? _search : '';
        return SettingsBody(
          child: ListView(
            padding: const EdgeInsets.only(bottom: Gap.page),
            children: [
              RowGroup(
                title: widget.category.label,
                children: [
                  _row(
                    title: tr('详情站点'),
                    value: details[detail]!,
                    onTap: () => _choose(
                      title: tr('详情站点'),
                      options: details,
                      selected: detail,
                      detail: true,
                    ),
                  ),
                  _row(
                    title: tr('搜索站点'),
                    value: searches[search]!,
                    onTap: () => _choose(
                      title: tr('搜索站点'),
                      options: searches,
                      selected: search,
                      detail: false,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    ),
  );

  Widget _row({
    required String title,
    required String value,
    required VoidCallback onTap,
  }) => ListTile(
    contentPadding: const EdgeInsets.symmetric(
      horizontal: Gap.page,
      vertical: Gap.xs,
    ),
    title: Text(title),
    subtitle: Text(
      value,
      style: context.text.bodyMedium?.copyWith(
        color: context.colors.onSurfaceVariant,
      ),
    ),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: onTap,
  );
}
