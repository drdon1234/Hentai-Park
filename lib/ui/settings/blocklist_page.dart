import 'package:flutter/material.dart';

import '../../core/block_rule.dart';
import '../../core/localization.dart';
import '../../core/settings.dart';
import '../../core/tag_blocklist.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/confirm_reset.dart';
import 'block_rule_editor.dart';

/// Tag / title blocklist (see core/tag_blocklist.dart for matching rules).
class BlocklistPage extends StatefulWidget {
  const BlocklistPage({super.key});

  @override
  State<BlocklistPage> createState() => _BlocklistPageState();
}

class _BlocklistPageState extends State<BlocklistPage> {
  final _input = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _add() {
    final v = _input.text.trim();
    if (v.isEmpty) return;
    final error = BlockRule.error(v);
    setState(() => _error = error == null ? null : tr(error));
    if (error != null) return;
    AppSettings.instance.addBlockedTag(v);
    _input.clear();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppSettings.instance;
    return Scaffold(
      appBar: AppBar(title: Text(tr('屏蔽标签'))),
      body: SettingsBody(
        child: ListenableBuilder(
          listenable: s.domain(SettingsDomain.filter),
          builder: (context, _) {
            final list = s.blockedTags;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Text(
                  tr(
                    '带有这些标签的作品会从浏览和搜索结果中隐藏；打开详情页时会给出提示。\n· 标签名（如 guro）匹配任意分类下的同名标签\n· 分类:标签（如 female:scat）只匹配该分类\n· title:关键词 匹配标题\n也可以在作品详情页长按标签直接屏蔽。',
                  ),
                  style: context.text.bodySmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  tr(
                    '* 匹配任意长度，? 匹配一个字符；regex: 使用正则。title: 只匹配标题，分类: 只匹配该分类标签。',
                  ),
                ),
                const SizedBox(height: Gap.s),
                TextField(
                  controller: _input,
                  onSubmitted: (_) => _add(),
                  decoration: InputDecoration(
                    hintText: tr('输入要屏蔽的标签'),
                    errorText: _error,
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      tooltip: tr('添加'),
                      icon: const Icon(Icons.add_rounded),
                      onPressed: _add,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (list.isEmpty)
                  EmptyState(
                    icon: Icons.block_rounded,
                    title: tr('没有屏蔽任何标签'),
                    compact: true,
                  )
                else
                  for (final e in list)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(e),
                      subtitle: Text(
                        tr('{count} 个多语言别名', {'count': s.aliasesFor(e).length}),
                      ),
                      onTap: () async {
                        final edit = await editBlockRule(
                          context,
                          initial: e,
                          aliases: s.aliasesFor(e),
                          existing: list,
                        );
                        if (edit != null) {
                          s.saveBlockedRule(e, edit.entry, edit.aliases);
                        }
                      },
                      trailing: IconButton(
                        tooltip: tr('取消屏蔽'),
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => s.blockedTags = [
                          for (final x in s.blockedTags)
                            if (x != e) x,
                        ],
                      ),
                    ),
                const SizedBox(height: 24),
                Text(tr('已屏蔽作品'), style: context.text.titleMedium),
                for (final entry in s.blockedWorks.entries)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(entry.value),
                    trailing: IconButton(
                      tooltip: tr('取消屏蔽'),
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => s.unblockWork(entry.key),
                    ),
                  ),
                const SizedBox(height: 12),
                Text(tr('已屏蔽作者'), style: context.text.titleMedium),
                for (final entry in s.blockedAuthors.entries)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(entry.value),
                    trailing: IconButton(
                      tooltip: tr('取消屏蔽'),
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => s.unblockAuthor(entry.key),
                    ),
                  ),
                const SizedBox(height: 24),
                Text(
                  tr('预设屏蔽'),
                  style: context.text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  tr(
                    '默认关闭，按需启用。每组支持多语言词、通配符与正则；标题匹配需单独开启。*妈、*母 等规则匹配范围较宽，可自行编辑。',
                  ),
                  style: context.text.bodySmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                for (final c in BlockPresetConfig.current())
                  _PresetCard(config: c),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PresetCard extends StatelessWidget {
  const _PresetCard({required this.config});
  final BlockPresetConfig config;

  String get _id => config.preset.id;

  Future<BlockRuleEdit?> _edit(BuildContext context, {String initial = ''}) =>
      editBlockRule(
        context,
        initial: initial,
        existing: config.entries,
        aliases: config.aliasesFor(initial),
      );

  @override
  Widget build(BuildContext context) {
    final s = AppSettings.instance;
    final c = config;
    return RowGroup(
      children: [
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          shape: const Border(),
          collapsedShape: const Border(),
          leading: Switch.adaptive(
            value: c.on,
            onChanged: (v) => s.setBlockPreset(_id, on: v),
          ),
          title: SelectionContainer.disabled(
            child: Text(
              c.preset.name,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          subtitle: SelectionContainer.disabled(
            child: Text(
              tr('{value0} · {value1} 项{value2}', {
                'value0': c.on ? tr('已启用') : tr('未启用'),
                'value1': c.entries.length,
                'value2': c.title ? tr(' · 匹配标题') : '',
              }),
              style: context.text.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ),
          childrenPadding: const EdgeInsets.only(bottom: Gap.m),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: c.title,
              onChanged: (v) => s.setBlockPreset(_id, title: v ?? false),
              title: SelectionContainer.disabled(child: Text(tr('同时匹配标题'))),
              subtitle: SelectionContainer.disabled(
                child: Text(tr('标题命中任意一项也会被屏蔽')),
              ),
            ),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var i = 0; i < c.entries.length; i++)
                  InputChip(
                    label: SelectionContainer.disabled(
                      child: Text(c.entries[i]),
                    ),
                    visualDensity: VisualDensity.compact,
                    onPressed: () async {
                      final edit = await _edit(context, initial: c.entries[i]);
                      if (edit == null) return;
                      s.setBlockPreset(
                        _id,
                        entries: {
                          for (var j = 0; j < c.entries.length; j++)
                            if (j == i) edit.entry else c.entries[j],
                        }.toList(),
                        aliases: {
                          for (final alias in c.aliases.entries)
                            if (alias.key != c.entries[i])
                              alias.key: alias.value,
                          edit.entry: edit.aliases,
                        },
                      );
                    },
                    onDeleted: () => s.setBlockPreset(
                      _id,
                      entries: [...c.entries]..removeAt(i),
                    ),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.add_rounded, size: 18),
                  label: SelectionContainer.disabled(child: Text(tr('添加'))),
                  visualDensity: VisualDensity.compact,
                  onPressed: () async {
                    final edit = await _edit(context);
                    if (edit == null) return;
                    s.setBlockPreset(
                      _id,
                      entries: {...c.entries, edit.entry}.toList(),
                      aliases: {...c.aliases, edit.entry: edit.aliases},
                    );
                  },
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => confirmReset(
                  context,
                  title: '恢复默认标签',
                  message: '将替换此组手动修改的标签，是否继续？',
                  reset: () async {
                    s.setBlockPreset(_id, reset: true);
                    await s.flush();
                  },
                ),
                icon: const Icon(Icons.restart_alt_rounded, size: 18),
                label: SelectionContainer.disabled(child: Text(tr('恢复默认标签'))),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
