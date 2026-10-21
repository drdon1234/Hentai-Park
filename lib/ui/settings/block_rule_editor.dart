import 'package:flutter/material.dart';

import '../../core/block_rule.dart';
import '../../core/block_suggestions.dart';
import '../../core/localization.dart';
import '../kit/tokens.dart';
import '../theme.dart';

class BlockRuleEdit {
  const BlockRuleEdit(this.entry, this.aliases);
  final String entry;
  final List<String> aliases;
}

Future<BlockRuleEdit?> editBlockRule(
  BuildContext context, {
  String initial = '',
  List<String> aliases = const [],
  List<String> existing = const [],
  BlockSuggestionService? service,
}) => showDialog<BlockRuleEdit>(
  context: context,
  builder: (_) => _BlockRuleEditor(
    initial: initial,
    aliases: aliases,
    existing: existing,
    service: service,
  ),
);

class _BlockRuleEditor extends StatefulWidget {
  const _BlockRuleEditor({
    required this.initial,
    required this.aliases,
    required this.existing,
    this.service,
  });
  final String initial;
  final List<String> aliases;
  final List<String> existing;
  final BlockSuggestionService? service;

  @override
  State<_BlockRuleEditor> createState() => _BlockRuleEditorState();
}

class _BlockRuleEditorState extends State<_BlockRuleEditor> {
  final _form = GlobalKey<FormState>();
  late final _entry = TextEditingController(text: widget.initial);
  late final _aliases = TextEditingController(text: widget.aliases.join('\n'));
  late final _service = widget.service ?? BlockSuggestionService();
  bool _busy = false;
  int _revision = 0;
  String? _status;

  @override
  void dispose() {
    _entry.dispose();
    _aliases.dispose();
    super.dispose();
  }

  List<String> get _words => _aliases.text
      .split('\n')
      .map((v) => v.trim())
      .where((v) => v.isNotEmpty)
      .toSet()
      .toList();

  void _save() {
    if (!_form.currentState!.validate()) return;
    Navigator.pop(
      context,
      BlockRuleEdit(
        _entry.text.trim(),
        BlockRule(_entry.text).translatable ? _words : [],
      ),
    );
  }

  Future<void> _suggest() async {
    if (_busy || !_form.currentState!.validate()) return;
    final revision = _revision;
    final entry = _entry.text.trim();
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final result = await _service.suggest(entry);
      if (!mounted || revision != _revision) return;
      setState(() {
        _busy = false;
        _status = result.failedLanguages > 0
            ? tr('已生成 {count} 个候选词，{failed} 种语言翻译失败，可重试', {
                'count': result.candidates.length,
                'failed': result.failedLanguages,
              })
            : tr('已生成 {count} 个候选词', {'count': result.candidates.length});
      });
      if (result.candidates.isEmpty) return;
      final selected = await _chooseCandidates(context, result.candidates);
      if (!mounted || revision != _revision || selected == null) return;
      final words = _words;
      final seen = words.map((word) => word.toLowerCase()).toSet();
      _aliases.text = [
        ...words,
        for (final word in selected)
          if (seen.add(word.toLowerCase())) word,
      ].join('\n');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final translatable = BlockRule(_entry.text).translatable;
    return AlertDialog(
      title: Text(tr('编辑屏蔽规则')),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _entry,
                  autofocus: true,
                  maxLength: 256,
                  decoration: InputDecoration(
                    labelText: tr('屏蔽词'),
                    hintText: tr('标签、通配符或 regex:表达式'),
                  ),
                  validator: (value) {
                    final error = BlockRule.error(value ?? '');
                    if (error != null) return tr(error);
                    if (widget.existing.any(
                      (entry) =>
                          entry != widget.initial &&
                          entry.toLowerCase() == value!.trim().toLowerCase(),
                    )) {
                      return tr('该屏蔽词已存在');
                    }
                    return null;
                  },
                  onChanged: (_) => setState(() {
                    _revision++;
                    _status = null;
                    _aliases.text = BlockRule(_entry.text).knownAliases
                        .join('\n');
                  }),
                  onFieldSubmitted: (_) => _save(),
                ),
                Text(
                  tr(
                    '* 匹配任意长度，? 匹配一个字符；regex: 使用正则。title: 只匹配标题，分类: 只匹配该分类标签。',
                  ),
                ),
                const SizedBox(height: Gap.m),
                if (translatable) ...[
                  TextFormField(
                    controller: _aliases,
                    minLines: 2,
                    maxLines: 5,
                    decoration: InputDecoration(labelText: tr('多语言别名（每行一个）')),
                    validator: (_) =>
                        _words.any(
                          (word) =>
                              !BlockRule(word).translatable ||
                              BlockRule(word).scope.isNotEmpty ||
                              word.length > 256,
                        )
                        ? tr('多语言别名只能填写普通词语')
                        : null,
                  ),
                  Text(tr('别名沿用原词的标题或分类范围；保存后离线生效，删除原词时一起移除。')),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _suggest,
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.translate),
                    label: Text(tr('补充多语言')),
                  ),
                  if (_status != null)
                    Text(_status!, style: context.text.bodySmall),
                ] else
                  Text(tr('通配符与正则不进行机器翻译。')),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('取消')),
        ),
        FilledButton(onPressed: _save, child: Text(tr('保存'))),
      ],
    );
  }
}

Future<List<String>?> _chooseCandidates(
  BuildContext context,
  List<BlockCandidate> candidates,
) {
  final selected = <int>{};
  return showDialog<List<String>>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, refresh) => AlertDialog(
        title: Text(tr('选择要屏蔽的别名')),
        content: SizedBox(
          width: 440,
          height: MediaQuery.sizeOf(ctx).height * .5,
          child: ListView.builder(
            itemCount: candidates.length + 1,
            itemBuilder: (_, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: Gap.s),
                  child: Text(tr('译词可能存在歧义，请检查后勾选；词包来源仅供参考。')),
                );
              }
              final candidateIndex = index - 1;
              final candidate = candidates[candidateIndex];
              return CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(candidate.text),
                subtitle: candidate.source.isEmpty
                    ? null
                    : Text(
                        [
                          candidate.source,
                          if (candidate.namespace.isNotEmpty)
                            candidate.namespace,
                        ].join(' · '),
                      ),
                value: selected.contains(candidateIndex),
                onChanged: (on) => refresh(() {
                  on == true
                      ? selected.add(candidateIndex)
                      : selected.remove(candidateIndex);
                }),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, [
              for (final index in selected) candidates[index].text,
            ]),
            child: Text(tr('添加选中项')),
          ),
        ],
      ),
    ),
  );
}
