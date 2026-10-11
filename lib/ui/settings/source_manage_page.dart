import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/settings.dart';
import '../../engine/source_manager.dart';
import '../../engine/source_updater.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'source_install.dart';
import '../../core/localization.dart';

/// Enable/disable and reorder sources (order is used everywhere, including aggregated search),
/// and install new source plugins from a URL or a repository index.
class SourceManagePage extends StatelessWidget {
  const SourceManagePage({super.key, this.updater});

  final SourceUpdater? updater;

  @override
  Widget build(BuildContext context) {
    AppLocalizations.of(context);
    final sm = SourceManager.instance;
    final settings = AppSettings.instance;
    final updates = updater ?? SourceUpdater.instance;
    return Scaffold(
      appBar: AppBar(title: Text(tr('源站管理'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _install(context),
        icon: const Icon(Icons.add_rounded),
        label: Text(tr('添加源')),
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([sm, settings, updates]),
        builder: (context, _) {
          final list = sm.all;
          return ReorderableListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
            header: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SwitchListTile(
                        title: Text(tr('自动更新官方源')),
                        subtitle: Text(tr('定期检查并更新官方源，保留登录状态与设置。')),
                        value: settings.autoSourceUpdates,
                        onChanged: (value) =>
                            settings.autoSourceUpdates = value,
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
                          label: Text(
                            tr(updates.running ? '正在检查官方源更新…' : '立即检查更新'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: Text(
                    tr('拖动调整顺序；顺序也决定聚合搜索结果的排列。'),
                    style: context.text.bodySmall?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            itemCount: list.length,
            onReorderItem: sm.reorder,
            itemBuilder: (context, i) {
              final s = list[i];
              final m = s.manifest;
              return Card(
                key: ValueKey(s.key),
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  contentPadding: const EdgeInsets.only(left: 12, right: 4),
                  leading: SourceAvatar(s.key, size: 40),
                  title: Text(
                    s.name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    s.loadError != null
                        ? tr('加载失败：{value0}', {'value0': s.loadError})
                        : 'v${s.version} · ${tr(m?.isVideo == true ? '视频' : '漫画')}${s.origin == 'official'
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
                  onTap: m == null
                      ? null
                      : () => Nav.openSourceSettings(context, s.key),
                  trailing: Row(
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
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _update(BuildContext context, SourceUpdater updates) async {
    try {
      final result = await updates.updateNow();
      if (!context.mounted) return;
      if (result.failures.isNotEmpty) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(tr('官方源更新失败')),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (result.updated.isNotEmpty) ...[
                    Text(
                      tr('已更新 {count} 个官方源', {'count': result.updated.length}),
                    ),
                    const SizedBox(height: 12),
                  ],
                  for (final failure in result.failures.entries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        '${failure.key == '官方源仓库' ? tr('官方源仓库') : failure.key}\n${tr(failure.value)}',
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(tr('关闭')),
              ),
            ],
          ),
        );
      } else {
        context.toast(
          result.updated.isNotEmpty
              ? tr('已更新 {count} 个官方源', {'count': result.updated.length})
              : tr(result.checked == 0 ? '没有可检查的官方源' : '官方源已是最新版本'),
        );
      }
    } catch (e) {
      if (context.mounted) {
        context.toast(
          tr('官方源更新失败：{value0}', {'value0': e.asSourceError.message}),
        );
      }
    }
  }

  Future<void> _install(BuildContext context) async {
    final c = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('添加源')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('输入源脚本（.js）或源仓库（index.json）的地址。')),
            const SizedBox(height: 12),
            TextField(
              controller: c,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                hintText: tr('https://…/source.js 或 …/index.json'),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.content_paste_rounded),
                  onPressed: () async => c.text =
                      (await Clipboard.getData('text/plain'))?.text?.trim() ??
                      c.text,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              tr('只安装你信任的源：源脚本可以访问网络并读取它所属站点的登录信息。'),
              style: Theme.of(ctx).textTheme.bodySmall
                  ?.copyWith(color: Theme.of(ctx).colorScheme.error),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text.trim()),
            child: Text(tr('下一步')),
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
    AppLocalizations.of(context);
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
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(
                  e.name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  'v${e.version}${e.description.isNotEmpty ? ' · ${e.description}' : ''}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: _busy.contains(e.key)
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : installed != null && !canUpdate
                    ? Pill(tr('已安装'))
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
                            if (mounted) setState(() => _busy.remove(e.key));
                          }
                        },
                        child: Text(canUpdate ? tr('更新') : tr('安装')),
                      ),
              ),
            );
          },
        ),
      ),
    );
  }
}
