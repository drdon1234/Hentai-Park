import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/localization.dart';
import '../../core/models.dart';
import '../../core/settings.dart';
import '../../engine/source_manager.dart';
import '../../engine/source_updater.dart';
import '../nav.dart';
import '../theme.dart';
import '../updates/update_prompt.dart';
import '../widgets/common.dart';
import 'domain_order_page.dart';
import 'source_install.dart';

/// Enable/disable and reorder sources (order is used everywhere, including aggregated search),
/// and install new source plugins from a URL or a repository index.
class SourceManagePage extends StatefulWidget {
  const SourceManagePage({super.key, this.updater});

  final SourceUpdater? updater;

  @override
  State<SourceManagePage> createState() => _SourceManagePageState();
}

class _SourceManagePageState extends State<SourceManagePage> {
  SourceCategory? _category;

  @override
  Widget build(BuildContext context) {
    final sm = SourceManager.instance;
    final settings = AppSettings.instance;
    final updates = widget.updater ?? SourceUpdater.instance;
    return Scaffold(
      appBar: AppBar(title: Text(tr('站点管理'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _install(context),
        icon: const Icon(Icons.add_rounded),
        label: SelectionContainer.disabled(child: Text(tr('添加站点'))),
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([sm, settings, updates]),
        builder: (context, _) {
          final all = sm.all;
          final list = _category == null
              ? all
              : all
                    .where(
                      (s) =>
                          (s.manifest?.category ?? SourceCategory.other) ==
                          _category,
                    )
                    .toList();
          return ReorderableListView.builder(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 96),
            header: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                RowGroup(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.swap_vert_rounded),
                      title: SelectionContainer.disabled(
                        child: Text(tr('分类顺序')),
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Nav.push(context, const DomainOrderPage()),
                    ),
                    ListTile(
                      leading: const Icon(Icons.restore_rounded),
                      title: SelectionContainer.disabled(
                        child: Text(tr('恢复站点默认顺序')),
                      ),
                      subtitle: SelectionContainer.disabled(
                        child: Text(tr('按内容质量、站点口碑和接入完整度推荐排列。')),
                      ),
                      onTap: sm.resetOrderToDefault,
                    ),
                  ],
                ),
                RowGroup(
                  children: [
                    SwitchListTile(
                      title: SelectionContainer.disabled(
                        child: Text(tr('启动时检查插件更新')),
                      ),
                      subtitle: SelectionContainer.disabled(
                        child: Text(tr('每次启动检查官方插件，有更新时提示，确认后才安装。')),
                      ),
                      value: settings.autoSourceUpdates,
                      onChanged: (value) => settings.autoSourceUpdates = value,
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: FilledButton.tonalIcon(
                        onPressed: updates.running
                            ? null
                            : () => _update(context, updates),
                        icon: updates.running
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.system_update_alt_rounded),
                        label: SelectionContainer.disabled(
                          child: Text(
                            tr(updates.running ? '正在检查官方站点更新…' : '立即检查更新'),
                          ),
                        ),
                      ),
                    ),
                    if (updates.lastResult?.available.isNotEmpty ?? false)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: FilledButton.tonalIcon(
                          onPressed: updates.running
                              ? null
                              : () => _update(context, updates),
                          icon: const Icon(Icons.new_releases_outlined),
                          label: SelectionContainer.disabled(
                            child: Text(
                              tr('发现 {count} 个插件更新', {
                                'count': updates.lastResult!.available.length,
                              }),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: SelectionContainer.disabled(
                          child: Text(tr('全部')),
                        ),
                        selected: _category == null,
                        onSelected: (_) => setState(() => _category = null),
                      ),
                      for (final category in settings.domainOrder)
                        ChoiceChip(
                          label: SelectionContainer.disabled(
                            child: Text(category.label),
                          ),
                          selected: _category == category,
                          onSelected: (_) =>
                              setState(() => _category = category),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: Text(
                    tr('拖动调整分类内站点的顺序；发现页和全站搜索也按这个顺序。'),
                    style: context.text.bodySmall?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            itemCount: list.length,
            onReorderItem: (oldIndex, newIndex) => sm.reorder(
              all.indexOf(list[oldIndex]),
              all.indexOf(list[newIndex]),
            ),
            itemBuilder: (context, i) {
              final s = list[i];
              final m = s.manifest;
              return HairlineItem(
                key: ValueKey(s.key),
                child: ListTile(
                  contentPadding: const EdgeInsets.only(left: 12, right: 4),
                  leading: SourceAvatar(s.key, size: 40),
                  title: SelectionContainer.disabled(
                    child: Text(
                      s.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  subtitle: SelectionContainer.disabled(
                    child: Text(
                      s.loadError != null
                          ? tr('加载失败：{value0}', {'value0': s.loadError})
                          : 'v${s.version} · ${(m?.category ?? SourceCategory.other).label}${s.origin == 'official'
                                ? ' · ${tr('官方')}'
                                : s.origin == 'builtin'
                                ? ' · ${tr('内置')}'
                                : ''}${s.sha256.isNotEmpty ? ' · ${s.sha256.substring(0, 8)}' : ''}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: s.loadError != null
                          ? TextStyle(color: context.colors.error)
                          : null,
                    ),
                  ),
                  onTap: m == null
                      ? null
                      : () => Nav.openSourceSettings(context, s.key),
                  trailing: SelectionContainer.disabled(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Switch(
                          value: s.enabled,
                          onChanged: (v) => sm.setEnabled(s.key, v),
                        ),
                        ReorderableDragStartListener(
                          index: i,
                          child: const Padding(
                            padding: EdgeInsets.all(8),
                            child: Icon(Icons.drag_handle_rounded),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _update(BuildContext context, SourceUpdater updates) async {
    try {
      final result = await updates.checkNow();
      if (!context.mounted) return;
      if (result.available.isNotEmpty) {
        await showSourceUpdatePrompt(context, result, updates);
      } else {
        await showSourceUpdateResult(context, result);
      }
    } catch (_) {
      if (context.mounted) {
        context.toast(tr('无法检查官方插件更新，请检查网络后重试'));
      }
    }
  }

  Future<void> _install(BuildContext context) async {
    final c = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('添加站点')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('输入站点脚本（.js）或站点仓库（index.json）的地址。')),
            const SizedBox(height: 12),
            TextField(
              controller: c,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                hintText: tr('https://…/source.js 或 …/index.json'),
                suffixIcon: IconButton(
                  tooltip: tr('粘贴'),
                  icon: const Icon(Icons.content_paste_rounded),
                  onPressed: () async => c.text =
                      (await Clipboard.getData('text/plain'))?.text?.trim() ??
                      c.text,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              tr('只安装你信任的站点：站点脚本可以访问网络，并读取它所属站点的登录信息。'),
              style: Theme.of(ctx).textTheme.bodySmall
                  ?.copyWith(color: Theme.of(ctx).colorScheme.error),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: SelectionContainer.disabled(child: Text(tr('取消'))),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text.trim()),
            child: SelectionContainer.disabled(child: Text(tr('下一步'))),
          ),
        ],
      ),
    );
    if (url == null || url.isEmpty || !context.mounted) return;
    try {
      if (url.endsWith('.json')) {
        final entries = await SourceManager.instance.fetchRepository(url);
        if (context.mounted) {
          await Nav.push(context, _RepoPage(url: url, entries: entries));
        }
      } else {
        await installSourceFromUrl(context, url);
      }
    } catch (e) {
      if (context.mounted) {
        context.toast(tr('安装失败：{value0}', {'value0': e.asSourceError.message}));
      }
    }
  }
}

class _RepoPage extends StatefulWidget {
  const _RepoPage({required this.url, required this.entries});
  final String url;
  final List<RepoEntry> entries;

  @override
  State<_RepoPage> createState() => _RepoPageState();
}

class _RepoPageState extends State<_RepoPage> {
  final Set<String> _busy = {};

  @override
  Widget build(BuildContext context) {
    final sm = SourceManager.instance;
    return Scaffold(
      appBar: AppBar(title: Text(Uri.parse(widget.url).host)),
      body: ListenableBuilder(
        listenable: sm,
        builder: (context, _) => ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: widget.entries.length,
          itemBuilder: (context, i) {
            final e = widget.entries[i];
            final installed = sm[e.key];
            final canUpdate =
                installed != null &&
                SourceManager.isNewer(e.version, installed.version);
            return RowGroup(
              children: [
                ListTile(
                  title: SelectionContainer.disabled(
                    child: Text(
                      e.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  subtitle: SelectionContainer.disabled(
                    child: Text(
                      'v${e.version}${e.description.isNotEmpty ? ' · ${e.description}' : ''}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  trailing: SelectionContainer.disabled(
                    child: _busy.contains(e.key)
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : installed != null && !canUpdate
                        ? Tag(tr('已安装'))
                        : FilledButton.tonal(
                            onPressed: () async {
                              setState(() => _busy.add(e.key));
                              try {
                                await installSourceFromUrl(
                                  context,
                                  e.url,
                                  expectedSha256: e.sha256,
                                );
                              } finally {
                                if (mounted) {
                                  setState(() => _busy.remove(e.key));
                                }
                              }
                            },
                            child: Text(canUpdate ? tr('更新') : tr('安装')),
                          ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
