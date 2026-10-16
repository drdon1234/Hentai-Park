import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../../core/models.dart';
import '../../core/settings.dart';
import '../../engine/source_manager.dart';
import '../kit/adaptive_sheet.dart';
import '../widgets/common.dart';

/// Filter / sort / display options for the library (Mihon's three-tab sheet).
Future<void> showLibraryOptions(BuildContext context) =>
    showAdaptiveSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _LibraryOptions(),
    );

class _LibraryOptions extends StatelessWidget {
  const _LibraryOptions();

  static List<(String, String, IconData)> get sorts => [
    ('added', tr('添加时间'), Icons.bookmark_added_outlined),
    ('read', tr('最近阅读'), Icons.history_rounded),
    ('updated', tr('最近更新'), Icons.new_releases_outlined),
    ('unread', tr('未读数'), Icons.mark_email_unread_outlined),
    ('title', tr('标题'), Icons.sort_by_alpha_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final s = AppSettings.instance;
    return DefaultTabController(
      length: 3,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.55,
        child: ListenableBuilder(
          listenable: s.domain(SettingsDomain.library),
          builder: (context, _) => Column(
            children: [
              TabBar(
                tabs: [
                  Tab(text: tr('筛选')),
                  Tab(text: tr('排序')),
                  Tab(text: tr('显示')),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    ListView(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final entry in {
                                'all': tr('全部'),
                                for (final kind in MediaKind.values)
                                  kind.name: kind.label,
                              }.entries)
                                ChoiceChip(
                                  label: Text(entry.value),
                                  selected: s.libraryFilterKind == entry.key,
                                  onSelected: (_) =>
                                      s.libraryFilterKind = entry.key,
                                ),
                            ],
                          ),
                        ),
                        CheckboxListTile(
                          value: s.libraryFilterDownloaded,
                          title: Text(tr('已下载')),
                          onChanged: (v) =>
                              s.libraryFilterDownloaded = v ?? false,
                        ),
                        CheckboxListTile(
                          value: s.libraryFilterUnread,
                          title: Text(tr('有未读')),
                          onChanged: (v) => s.libraryFilterUnread = v ?? false,
                        ),
                        SectionHeader(
                          tr('站点'),
                          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final src in SourceManager.instance.all)
                                FilterChip(
                                  avatar: SourceAvatar(src.key, size: 20),
                                  label: Text(src.name),
                                  selected: s.libraryFilterSources.contains(
                                    src.key,
                                  ),
                                  onSelected: (on) {
                                    final set = s.libraryFilterSources;
                                    on ? set.add(src.key) : set.remove(src.key);
                                    s.libraryFilterSources = set;
                                  },
                                ),
                              FilterChip(
                                label: Text(tr('本地')),
                                selected: s.libraryFilterSources.contains(
                                  'local',
                                ),
                                onSelected: (on) {
                                  final set = s.libraryFilterSources;
                                  on ? set.add('local') : set.remove('local');
                                  s.libraryFilterSources = set;
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    ListView(
                      children: [
                        for (final (key, label, icon) in sorts)
                          ListTile(
                            leading: Icon(icon),
                            title: Text(label),
                            trailing: s.librarySort == key
                                ? Icon(
                                    s.librarySortAsc
                                        ? Icons.arrow_upward_rounded
                                        : Icons.arrow_downward_rounded,
                                  )
                                : null,
                            selected: s.librarySort == key,
                            onTap: () {
                              if (s.librarySort == key) {
                                s.librarySortAsc = !s.librarySortAsc;
                              } else {
                                s.librarySort = key;
                                s.librarySortAsc = key == 'title';
                              }
                            },
                          ),
                      ],
                    ),
                    ListView(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: SegmentedButton<String>(
                            segments: [
                              ButtonSegment(
                                value: 'grid',
                                icon: const Icon(Icons.grid_view_rounded),
                                label: Text(tr('网格')),
                              ),
                              ButtonSegment(
                                value: 'list',
                                icon: const Icon(Icons.view_list_rounded),
                                label: Text(tr('列表')),
                              ),
                            ],
                            selected: {s.libraryDisplay},
                            onSelectionChanged: (v) =>
                                s.libraryDisplay = v.first,
                          ),
                        ),
                        CheckboxListTile(
                          value: s.badgeUnread,
                          title: Text(tr('未读数徽标')),
                          onChanged: (v) => s.badgeUnread = v ?? true,
                        ),
                        CheckboxListTile(
                          value: s.badgeDownloaded,
                          title: Text(tr('已下载徽标')),
                          onChanged: (v) => s.badgeDownloaded = v ?? true,
                        ),
                        CheckboxListTile(
                          value: s.badgeSource,
                          title: Text(tr('站点图标')),
                          onChanged: (v) => s.badgeSource = v ?? true,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
