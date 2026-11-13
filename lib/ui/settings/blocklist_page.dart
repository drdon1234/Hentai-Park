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
                  tr('默认关闭，按需启用。普通规则匹配明确内容；扩大范围会加入可能误判的线索。数量为当前生效的主规则数，不含别名。'),
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
        existing: config.allEntries,
        aliases: config.aliasesFor(initial),
      );

  Widget _rules(BuildContext context, {required bool strongGroup}) {
    final c = config;
    final s = AppSettings.instance;
    final rules = strongGroup ? c.strongEntries : c.entries;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (var i = 0; i < rules.length; i++)
          InputChip(
            selected: c.activeEntries.contains(rules[i]),
            showCheckmark: true,
            label: SelectionContainer.disabled(child: Text(rules[i])),
            visualDensity: VisualDensity.compact,
            onPressed: () async {
              final edit = await _edit(context, initial: rules[i]);
              if (edit == null) return;
              s.setBlockPreset(
                _id,
                entries: strongGroup
                    ? c.entries
                    : {
                        for (var j = 0; j < rules.length; j++)
                          if (j == i) edit.entry else rules[j],
                      }.toList(),
                strongEntries: strongGroup
                    ? {
                        for (var j = 0; j < rules.length; j++)
                          if (j == i) edit.entry else rules[j],
                      }.toList()
                    : c.strongEntries,
                aliases: {
                  for (final alias in c.aliases.entries)
                    if (alias.key != rules[i]) alias.key: alias.value,
                  edit.entry: edit.aliases,
                },
              );
            },
            onDeleted: () => s.setBlockPreset(
              _id,
              entries: strongGroup ? c.entries : ([...rules]..removeAt(i)),
              strongEntries: strongGroup
                  ? ([...rules]..removeAt(i))
                  : c.strongEntries,
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
              entries: strongGroup
                  ? c.entries
                  : {...rules, edit.entry}.toList(),
              strongEntries: strongGroup
                  ? {...rules, edit.entry}.toList()
                  : c.strongEntries,
              aliases: {...c.aliases, edit.entry: edit.aliases},
            );
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppSettings.instance;
    final c = config;
    return RowGroup(
      margin: EdgeInsets.zero,
      children: [
        ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: Gap.page),
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
                'value1': c.activeEntries.length,
                'value2': c.title ? tr(' · 匹配标题') : '',
              }),
              style: context.text.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(
            Gap.page,
            0,
            Gap.page,
            Gap.m,
          ),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (c.hasStrongRules)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: c.strong,
                onChanged: (v) => s.setBlockPreset(_id, strong: v ?? false),
                title: Text(tr('扩大匹配范围')),
                subtitle: Text(tr('加入宽泛关键词，可能误屏蔽无关作品')),
              ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: c.title,
              onChanged: (v) => s.setBlockPreset(_id, title: v ?? false),
              title: SelectionContainer.disabled(child: Text(tr('同时匹配标题'))),
              subtitle: SelectionContainer.disabled(
                child: Text(tr('tag: 仅匹配标签；title: 仅在开启标题匹配时生效。其余规则同时用于标题。')),
              ),
            ),
            Text(tr('普通规则')),
            _rules(context, strongGroup: false),
            if (c.hasStrongRules) ...[
              const SizedBox(height: Gap.s),
              Text(tr('扩大范围规则')),
              _rules(context, strongGroup: true),
            ],
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
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
