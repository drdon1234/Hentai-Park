import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../../tavern/store.dart';
import '../kit/kit.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets/content_translation.dart';
import 'tavern_chat_page.dart';

class TavernLibraryPage extends StatefulWidget {
  const TavernLibraryPage({
    super.key,
    this.initialTab = 0,
    this.selectSession = false,
  });
  final int initialTab;
  final bool selectSession;
  @override
  State<TavernLibraryPage> createState() => _TavernLibraryPageState();
}

class _TavernLibraryPageState extends State<TavernLibraryPage> {
  late int _tab = widget.initialTab;
  bool _tree = false;
  bool _byName = false;
  final _search = TextEditingController();
  String _query = '';
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<(TavernSession, int)> _sessionRows(List<TavernSession> items) {
    if (!_tree) return [for (final row in items) (row, 0)];
    final ids = items.map((row) => row.id).toSet();
    final children = <String, List<TavernSession>>{};
    for (final row in items) {
      (children[row.parentId ?? ''] ??= []).add(row);
    }
    final roots = items.where((row) => !ids.contains(row.parentId));
    final seen = <String>{};
    final rows = <(TavernSession, int)>[];
    for (final root in [...roots, ...items]) {
      final pending = [(root, 0)];
      while (pending.isNotEmpty) {
        final (row, depth) = pending.removeLast();
        if (!seen.add(row.id)) continue;
        rows.add((row, depth));
        for (final child in (children[row.id] ?? <TavernSession>[]).reversed) {
          pending.add((child, depth + 1));
        }
      }
    }
    return rows;
  }

  Widget _retry() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(tr('加载失败')),
        TextButton(onPressed: () => setState(() {}), child: Text(tr('重试'))),
      ],
    ),
  );

  Future<void> _deleteResource(String uid) async {
    final confirmed = await confirmAction(
      context,
      title: tr('删除已保存的资源？'),
      message: tr('使用此资源的会话需要先删除。'),
      confirmLabel: tr('删除'),
      destructive: true,
    );
    if (!confirmed) return;
    try {
      await TavernStore.instance.removeResource(uid);
    } on StateError {
      if (mounted) context.toast(tr('请先删除使用此资源的会话'));
    } catch (_) {
      if (mounted) context.toast(tr('删除失败，请重试'));
    }
  }

  Future<void> _deleteSession(TavernSession session) async {
    final confirmed = await confirmAction(
      context,
      title: tr('删除会话？'),
      message: tr('会话中的消息将被删除。'),
      confirmLabel: tr('删除'),
      destructive: true,
    );
    if (!confirmed) return;
    try {
      await TavernStore.instance.removeSession(session.id);
    } catch (_) {
      if (mounted) context.toast(tr('删除失败，请重试'));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: PageHeader(
      title: tr('已保存与会话'),
      actions: [
        if (_tab == 1)
          IconButton(
            tooltip: tr('分支会话'),
            isSelected: _tree,
            icon: const Icon(Icons.account_tree_outlined),
            onPressed: () => setState(() => _tree = !_tree),
          ),
      ],
    ),
    body: ReadableWidth(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.page),
            child: HeaderTabs(
              tabs: [HeaderTab(tr('已保存')), HeaderTab(tr('会话'))],
              selected: _tab,
              onSelected: (value) => setState(() => _tab = value),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.page, Gap.s, Gap.page, 0),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                labelText: tr('搜索'),
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.isEmpty
                    ? (_tab == 0
                          ? PopupMenuButton<bool>(
                              tooltip: tr('排序'),
                              icon: const Icon(Icons.sort_rounded),
                              initialValue: _byName,
                              onSelected: (value) =>
                                  setState(() => _byName = value),
                              itemBuilder: (_) => [
                                PopupMenuItem(
                                  value: false,
                                  child: Text(tr('最近更新')),
                                ),
                                PopupMenuItem(
                                  value: true,
                                  child: Text(tr('名称')),
                                ),
                              ],
                            )
                          : null)
                    : IconButton(
                        tooltip: tr('清除'),
                        onPressed: () {
                          _search.clear();
                          setState(() => _query = '');
                        },
                        icon: const Icon(Icons.clear_rounded),
                      ),
              ),
              onChanged: (value) => setState(() => _query = value.trim()),
            ),
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: TavernStore.instance,
              builder: (context, _) {
                if (_tab == 0) {
                  return FutureBuilder(
                    future: TavernStore.instance.resources(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return _retry();
                      }
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final items = snapshot.data!
                          .where(
                            (item) => [item.title, ...item.tags]
                                .join(' ')
                                .toLowerCase()
                                .contains(_query.toLowerCase()),
                          )
                          .toList();
                      if (_byName) {
                        items.sort(
                          (a, b) => a.title.toLowerCase().compareTo(
                            b.title.toLowerCase(),
                          ),
                        );
                      }
                      final pinned = items
                          .where((item) => item.json['tavernPinned'] == 1)
                          .toList();
                      items.removeWhere(
                        (item) => item.json['tavernPinned'] == 1,
                      );
                      items.insertAll(0, pinned);
                      if (items.isEmpty) {
                        return Center(
                          child: Text(
                            _query.isEmpty ? tr('还没有保存角色卡或世界书') : tr('没有找到'),
                          ),
                        );
                      }
                      return ListView.builder(
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final item = items[index];
                          return ListTile(
                            title: TranslatedText(
                              item.title,
                              source: item.source,
                            ),
                            subtitle: Text(
                              item.json['tavernKind'] == 'lorebook'
                                  ? tr('世界书')
                                  : tr('角色卡'),
                            ),
                            leading: IconButton(
                              tooltip: item.json['tavernPinned'] == 1
                                  ? tr('取消置顶')
                                  : tr('置顶'),
                              icon: Icon(
                                item.json['tavernPinned'] == 1
                                    ? Icons.push_pin
                                    : Icons.push_pin_outlined,
                              ),
                              onPressed: () async {
                                try {
                                  await TavernStore.instance.pinResource(
                                    item.uid,
                                    item.json['tavernPinned'] != 1,
                                  );
                                } catch (_) {
                                  if (context.mounted) {
                                    context.toast(tr('保存失败，请重试'));
                                  }
                                }
                              },
                            ),
                            onTap: () => Nav.openWork(context, item),
                            trailing: IconButton(
                              tooltip: tr('删除'),
                              icon: const Icon(Icons.delete_outline_rounded),
                              onPressed: () => _deleteResource(item.uid),
                            ),
                          );
                        },
                      );
                    },
                  );
                }
                return FutureBuilder(
                  future: TavernStore.instance.sessions(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) return _retry();
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final sessions = _sessionRows(
                      snapshot.data!
                          .where(
                            (session) =>
                                [session.title, session.tags, session.notes]
                                    .join(' ')
                                    .toLowerCase()
                                    .contains(_query.toLowerCase()),
                          )
                          .toList(),
                    );
                    if (sessions.isEmpty) {
                      return Center(
                        child: Text(_query.isEmpty ? tr('还没有会话') : tr('没有找到')),
                      );
                    }
                    return ListView.builder(
                      itemCount: sessions.length,
                      itemBuilder: (context, index) {
                        final (session, depth) = sessions[index];
                        return ListTile(
                          contentPadding: EdgeInsetsDirectional.only(
                            start: Gap.page + depth.clamp(0, 4) * Gap.m,
                            end: Gap.page,
                          ),
                          title: Text(session.title),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                session.inputDraft.isNotEmpty
                                    ? '${tr('草稿')} · ${session.inputDraft}'
                                    : session.messages.isEmpty
                                    ? tr('还没有消息')
                                    : session.messages.last['content'] ?? '',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: Gap.xs),
                              Text(
                                '${tr('{count} 条消息', {'count': session.messages.length})} · ${MaterialLocalizations.of(context).formatCompactDate(DateTime.fromMillisecondsSinceEpoch(session.updatedAt))} ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(DateTime.fromMillisecondsSinceEpoch(session.updatedAt)))}',
                              ),
                              if (session.parentId != null) Text(tr('分支会话')),
                            ],
                          ),
                          leading: Icon(
                            session.parentId == null
                                ? Icons.chat_bubble_outline_rounded
                                : Icons.fork_right_rounded,
                          ),
                          onTap: () {
                            if (widget.selectSession) {
                              Navigator.pop(context, session);
                            } else {
                              Nav.push(
                                context,
                                TavernChatPage(session: session),
                              );
                            }
                          },
                          trailing: widget.selectSession
                              ? null
                              : IconButton(
                                  tooltip: tr('删除'),
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                  ),
                                  onPressed: () => _deleteSession(session),
                                ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}
