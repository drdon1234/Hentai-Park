import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../engine/source_manager.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'source_install.dart';

/// Enable/disable and reorder sources (order is used everywhere, including aggregated search),
/// and install new source plugins from a URL or a repository index.
class SourceManagePage extends StatelessWidget {
  const SourceManagePage({super.key});

  @override
  Widget build(BuildContext context) {
    final sm = SourceManager.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('源站管理')),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _install(context), icon: const Icon(Icons.add_rounded), label: const Text('添加源')),
      body: ListenableBuilder(
        listenable: sm,
        builder: (context, _) {
          final list = sm.all;
          return ReorderableListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
            header: Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Text('拖动调整顺序；顺序也决定聚合搜索结果的排列。', style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant)),
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
                  title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(
                    s.loadError != null
                        ? '加载失败：${s.loadError}'
                        : 'v${s.version} · ${m?.isVideo == true ? '视频' : '漫画'}${s.origin == 'builtin' ? ' · 内置' : ''}${s.sha256.isNotEmpty ? ' · ${s.sha256.substring(0, 8)}' : ''}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: s.loadError != null ? TextStyle(color: context.colors.error) : null,
                  ),
                  onTap: m == null ? null : () => Nav.openSourceSettings(context, s.key),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(value: s.enabled, onChanged: (v) => sm.setEnabled(s.key, v)),
                      ReorderableDragStartListener(
                        index: i,
                        child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.drag_handle_rounded)),
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

  Future<void> _install(BuildContext context) async {
    final c = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加源'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('输入源脚本（.js）或源仓库（index.json）的地址。'),
            const SizedBox(height: 12),
            TextField(
              controller: c,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                hintText: 'https://…/source.js 或 …/index.json',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.content_paste_rounded),
                  onPressed: () async => c.text = (await Clipboard.getData('text/plain'))?.text?.trim() ?? c.text,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text('只安装你信任的源：源脚本可以访问网络并读取它所属站点的登录信息。', style: Theme.of(ctx).textTheme.bodySmall?.copyWith(color: Theme.of(ctx).colorScheme.error)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('下一步')),
        ],
      ),
    );
    if (url == null || url.isEmpty || !context.mounted) return;
    try {
      if (url.endsWith('.json')) {
        final entries = await SourceManager.instance.fetchRepository(url);
        if (context.mounted) await Nav.push(context, _RepoPage(url: url, entries: entries));
      } else {
        await installSourceFromUrl(context, url);
      }
    } catch (e) {
      if (context.mounted) context.toast('安装失败：${e.asSourceError.message}');
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
            final canUpdate = installed != null && SourceManager.isNewer(e.version, installed.version);
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(e.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('v${e.version}${e.description.isNotEmpty ? ' · ${e.description}' : ''}', maxLines: 2, overflow: TextOverflow.ellipsis),
                trailing: _busy.contains(e.key)
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : installed != null && !canUpdate
                    ? const Pill('已安装')
                    : FilledButton.tonal(
                        onPressed: () async {
                          setState(() => _busy.add(e.key));
                          try {
                            await installSourceFromUrl(context, e.url, expectedSha256: e.sha256);
                          } finally {
                            if (mounted) setState(() => _busy.remove(e.key));
                          }
                        },
                        child: Text(canUpdate ? '更新' : '安装'),
                      ),
              ),
            );
          },
        ),
      ),
    );
  }
}
