import 'package:flutter/material.dart';

import '../../core/settings.dart';
import '../../engine/source_manager.dart';
import '../widgets/common.dart';

/// Filter / sort / display options for the library (Mihon's three-tab sheet).
Future<void> showLibraryOptions(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => const _LibraryOptions(),
);

class _LibraryOptions extends StatelessWidget {
  const _LibraryOptions();

  static const sorts = [
    ('added', '添加时间', Icons.bookmark_added_outlined),
    ('read', '最近阅读', Icons.history_rounded),
    ('updated', '最近更新', Icons.new_releases_outlined),
    ('unread', '未读数', Icons.mark_email_unread_outlined),
    ('title', '标题', Icons.sort_by_alpha_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final s = AppSettings.instance;
    return DefaultTabController(
      length: 3,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.55,
        child: ListenableBuilder(
          listenable: s,
          builder: (context, _) => Column(
            children: [
              const TabBar(
                tabs: [
                  Tab(text: '筛选'),
                  Tab(text: '排序'),
                  Tab(text: '显示'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    ListView(
                      children: [
                        CheckboxListTile(
                          value: s.libraryFilterDownloaded,
                          title: const Text('已下载'),
                          onChanged: (v) => s.libraryFilterDownloaded = v ?? false,
                        ),
                        CheckboxListTile(value: s.libraryFilterUnread, title: const Text('有未读'), onChanged: (v) => s.libraryFilterUnread = v ?? false),
                        const SectionHeader('源站', padding: EdgeInsets.fromLTRB(16, 12, 8, 4)),
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
                                  selected: s.libraryFilterSources.contains(src.key),
                                  onSelected: (on) {
                                    final set = s.libraryFilterSources;
                                    on ? set.add(src.key) : set.remove(src.key);
                                    s.libraryFilterSources = set;
                                  },
                                ),
                              FilterChip(
                                label: const Text('本地'),
                                selected: s.libraryFilterSources.contains('local'),
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
                            trailing: s.librarySort == key ? Icon(s.librarySortAsc ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded) : null,
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
                            segments: const [
                              ButtonSegment(value: 'grid', icon: Icon(Icons.grid_view_rounded), label: Text('网格')),
                              ButtonSegment(value: 'list', icon: Icon(Icons.view_list_rounded), label: Text('列表')),
                            ],
                            selected: {s.libraryDisplay},
                            onSelectionChanged: (v) => s.libraryDisplay = v.first,
                          ),
                        ),
                        CheckboxListTile(value: s.badgeUnread, title: const Text('未读数徽标'), onChanged: (v) => s.badgeUnread = v ?? true),
                        CheckboxListTile(value: s.badgeDownloaded, title: const Text('已下载徽标'), onChanged: (v) => s.badgeDownloaded = v ?? true),
                        CheckboxListTile(value: s.badgeSource, title: const Text('源站图标'), onChanged: (v) => s.badgeSource = v ?? true),
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
