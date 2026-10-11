import 'package:flutter/material.dart';

import '../../core/settings.dart';
import '../../core/tag_blocklist.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../../core/localization.dart';

/// Tag / title blocklist (see core/tag_blocklist.dart for matching rules).
class BlocklistPage extends StatefulWidget {
  const BlocklistPage({super.key});

  @override
  State<BlocklistPage> createState() => _BlocklistPageState();
}

class _BlocklistPageState extends State<BlocklistPage> {
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _add() {
    final v = _input.text.trim();
    if (v.isEmpty) return;
    AppSettings.instance.addBlockedTag(v);
    _input.clear();
  }

  @override
  Widget build(BuildContext context) {
    AppLocalizations.of(context);
    final s = AppSettings.instance;
    return Scaffold(
      appBar: AppBar(title: Text(tr('屏蔽标签'))),
      body: ListenableBuilder(
        listenable: s,
        builder: (context, _) {
          final list = s.blockedTags;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Text(
                tr('带有这些标签的作品会从浏览、搜索与聚合搜索结果中隐藏；打开详情页时会给出提示。\n· 标签名（如 guro）匹配任意分类下的同名标签\n· 分类:标签（如 female:scat）只匹配该分类\n· title:关键词 匹配标题\n也可以在作品详情页长按标签直接屏蔽。'),
                style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _input,
                onSubmitted: (_) => _add(),
                decoration: InputDecoration(
                  hintText: tr('输入要屏蔽的标签'),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(icon: const Icon(Icons.add_rounded), onPressed: _add),
                ),
              ),
              const SizedBox(height: 12),
              if (list.isEmpty)
                MessageView(icon: Icons.block_rounded, title: tr('没有屏蔽任何标签'), compact: true)
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final e in list)
                      InputChip(
                        label: Text(e),
                        onDeleted: () => s.blockedTags = [for (final x in list) if (x != e) x],
                      ),
                  ],
                ),
              const SizedBox(height: 24),
              Text(tr('预设屏蔽'), style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                tr('默认都不启用，按需开启。每组的标签可以增删改；开启「标题正则匹配」后，每一项也会作为正则表达式匹配标题（纯英文单词按整词匹配）。'),
                style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              for (final c in BlockPresetConfig.current()) _PresetCard(config: c),
            ],
          );
        },
      ),
    );
  }
}

class _PresetCard extends StatelessWidget {
  const _PresetCard({required this.config});
  final BlockPresetConfig config;

  String get _id => config.preset.id;

  Future<String?> _edit(BuildContext context, {String initial = ''}) {
    final text = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(initial.isEmpty ? tr('添加到「{value0}」', {'value0': config.preset.name}) : tr('修改')),
        content: TextField(
          controller: text,
          autofocus: true,
          decoration: InputDecoration(hintText: tr('标签或标题正则')),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('取消'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, text.text), child: Text(tr('确定'))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    AppLocalizations.of(context);
    final s = AppSettings.instance;
    final c = config;
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        leading: Switch(value: c.on, onChanged: (v) => s.setBlockPreset(_id, on: v)),
        title: Text(c.preset.name, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
          tr('{value0} · {value1} 项{value2}', {'value0': c.on ? tr('已启用') : tr('未启用'), 'value1': c.entries.length, 'value2': c.title ? tr(' · 匹配标题') : ''}),
          style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: c.title,
            onChanged: (v) => s.setBlockPreset(_id, title: v ?? false),
            title: Text(tr('标题正则匹配')),
            subtitle: Text(tr('标题命中任意一项也会被屏蔽')),
          ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0; i < c.entries.length; i++)
                InputChip(
                  label: Text(c.entries[i]),
                  visualDensity: VisualDensity.compact,
                  onPressed: () async {
                    final v = (await _edit(context, initial: c.entries[i]))?.trim();
                    if (v == null || v.isEmpty) return;
                    s.setBlockPreset(_id, entries: [...c.entries]..[i] = v);
                  },
                  onDeleted: () => s.setBlockPreset(_id, entries: [...c.entries]..removeAt(i)),
                ),
              ActionChip(
                avatar: const Icon(Icons.add_rounded, size: 18),
                label: Text(tr('添加')),
                visualDensity: VisualDensity.compact,
                onPressed: () async {
                  final v = (await _edit(context))?.trim();
                  if (v == null || v.isEmpty || c.entries.contains(v)) return;
                  s.setBlockPreset(_id, entries: [...c.entries, v]);
                },
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => s.setBlockPreset(_id, reset: true),
              icon: const Icon(Icons.restart_alt_rounded, size: 18),
              label: Text(tr('恢复默认标签')),
            ),
          ),
        ],
      ),
    );
  }
}
