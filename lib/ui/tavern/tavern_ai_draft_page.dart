import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../../tavern/client.dart';
import '../../tavern/models.dart';
import '../../tavern/proposal.dart';
import '../../tavern/store.dart';
import '../kit/kit.dart';
import '../nav.dart';
import '../theme.dart';
import 'tavern_ai_text.dart';
import 'tavern_editor_page.dart';

class TavernAiDraftPage extends StatefulWidget {
  const TavernAiDraftPage({super.key});

  @override
  State<TavernAiDraftPage> createState() => _TavernAiDraftPageState();
}

class _TavernAiDraftPageState extends State<TavernAiDraftPage> {
  final _prompt = TextEditingController();
  final _structured = {
    for (final key in [
      'name',
      'creator',
      'tags',
      'description',
      'personality',
      'scenario',
      'system_prompt',
      'post_history_instructions',
      'first_mes',
      'mes_example',
      'alternate_greetings',
      'purpose',
      'entries',
    ])
      key: TextEditingController(),
  };

  String _kind = 'character';
  String _inputMode = 'natural';
  String _draft = '';
  String _error = '';
  bool _busy = false;
  TavernResource? _resource;
  TavernGeneration? _generation;
  TavernResource? _baseline;
  final _omitted = <String>{};
  String get _instruction => _kind == 'character'
      ? '''请根据用户提供的内容生成一份 Character Card V2 JSON。只输出 JSON，不要 Markdown 代码围栏、解释、建议、警告、免责声明、安全提示或其他元话语。必须使用 spec=chara_card_v2、spec_version=2.0、data 三个顶级字段。data 包含 creator_notes、system_prompt、post_history_instructions、alternate_greetings、tags、creator、character_version、extensions，以及 name、description、personality、scenario、first_mes、mes_example 字段。可以包含 alternate_greetings、system_prompt 和 character_book。所有文本使用当前用户语言。'''
      : '''请根据用户提供的内容生成一份标准世界书 JSON。只输出 JSON，不要 Markdown 代码围栏、解释、建议、警告、免责声明、安全提示或其他元话语。必须包含 name 和 entries。entries 是数组，每项至少包含 comment、keys、content、enabled。所有文本使用当前用户语言。''';

  bool get _structuredMode => _inputMode == 'structured';

  String get _userPrompt =>
      _structuredMode ? _structuredPrompt() : _prompt.text.trim();

  String _structuredPrompt() {
    final fields = <String>[];
    void add(String label, String key) {
      final value = _structured[key]!.text.trim();
      if (value.isNotEmpty) fields.add('$label：$value');
    }

    if (_kind == 'character') {
      add(tr('名称'), 'name');
      add(tr('作者'), 'creator');
      add(tr('标签'), 'tags');
      add(tr('描述'), 'description');
      add(tr('性格'), 'personality');
      add(tr('场景'), 'scenario');
      add(tr('系统提示词'), 'system_prompt');
      add(tr('后置指令'), 'post_history_instructions');
      add(tr('开场白'), 'first_mes');
      add(tr('示例对话'), 'mes_example');
      add(tr('其他开场白'), 'alternate_greetings');
    } else {
      add(tr('名称'), 'name');
      add(tr('描述'), 'purpose');
      add(tr('世界书词条'), 'entries');
    }
    return fields.join('\n\n');
  }

  Widget _structuredField(
    String key,
    String label, {
    int lines = 1,
    String? helperText,
  }) => TextField(
    controller: _structured[key],
    enabled: !_busy,
    minLines: lines,
    maxLines: lines == 1 ? 1 : 8,
    decoration: InputDecoration(labelText: label, helperText: helperText),
  );

  Widget _structuredForm() => Column(
    children: _kind == 'character'
        ? [
            _structuredField('name', tr('名称')),
            const SizedBox(height: Gap.s),
            _structuredField('creator', tr('作者')),
            const SizedBox(height: Gap.s),
            _structuredField('tags', tr('标签')),
            const SizedBox(height: Gap.s),
            _structuredField('description', tr('描述'), lines: 4),
            const SizedBox(height: Gap.s),
            _structuredField('personality', tr('性格'), lines: 3),
            const SizedBox(height: Gap.s),
            _structuredField('scenario', tr('场景'), lines: 3),
            const SizedBox(height: Gap.s),
            _structuredField('system_prompt', tr('系统提示词'), lines: 3),
            const SizedBox(height: Gap.s),
            _structuredField('post_history_instructions', tr('后置指令'), lines: 3),
            const SizedBox(height: Gap.s),
            _structuredField('first_mes', tr('开场白'), lines: 4),
            const SizedBox(height: Gap.s),
            _structuredField('mes_example', tr('示例对话'), lines: 4),
            const SizedBox(height: Gap.s),
            _structuredField('alternate_greetings', tr('其他开场白'), lines: 3),
          ]
        : [
            _structuredField('name', tr('名称')),
            const SizedBox(height: Gap.s),
            _structuredField('purpose', tr('描述'), lines: 4),
            const SizedBox(height: Gap.s),
            _structuredField(
              'entries',
              tr('世界书词条'),
              lines: 8,
              helperText: tr('每行一个词条，按标题、关键词和正文填写'),
            ),
          ],
  );

  void _clearInput() {
    _prompt.clear();
    for (final field in _structured.values) {
      field.clear();
    }
  }

  Future<void> _generate() async {
    if (_busy || _userPrompt.isEmpty) return;
    setState(() {
      _busy = true;
      _error = '';
      _draft = '';
    });
    final previous = _resource == null
        ? null
        : reviewTavernProposal(_resource!, _baseline, _omitted).$1;
    final generation = _generation = TavernGeneration();
    try {
      await TavernApiSettings.instance.load();
      final config = TavernApiSettings.instance.config;
      if (!config.configured) throw const TavernApiException('configuration');
      final key = await TavernApiSettings.instance.apiKey();
      final buffer = StringBuffer();
      await for (final value in generation.send(
        config: config,
        apiKey: key,
        messages: [
          {'role': 'system', 'content': _instruction},
          if (previous != null)
            {'role': 'assistant', 'content': jsonEncode(previous.raw)},
          {'role': 'user', 'content': _userPrompt},
        ],
      )) {
        buffer.write(value);
        if (mounted) setState(() => _draft = buffer.toString());
      }
      if (generation.finishReason == 'length') {
        throw const TavernApiException('length');
      }
      final decoded = _decodeJson(buffer.toString());
      final bytes = Uint8List.fromList(utf8.encode(jsonEncode(decoded)));
      final resource = TavernResource.parse(_kind, 'json', bytes);
      if (mounted) {
        setState(() {
          _baseline = previous;
          _omitted.clear();
          _resource = resource;
          _clearInput();
        });
      }
    } on TavernApiException catch (error) {
      if (mounted) setState(() => _error = _generationError(error.code));
    } on FormatException {
      if (mounted) setState(() => _error = tr('模型返回的资源格式无效，请重新生成'));
    } catch (_) {
      if (mounted) setState(() => _error = tr('生成失败，请检查模型连接后重试'));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          if (_resource != null) {
            _draft = const JsonEncoder.withIndent('  ').convert(_resource!.raw);
          }
        });
      }
      _generation = null;
    }
  }

  Object _decodeJson(String text) {
    var value = text.trim();
    if (value.startsWith('```')) {
      value = value
          .replaceFirst(RegExp(r'^```(?:json)?\s*'), '')
          .replaceFirst(RegExp(r'\s*```$'), '');
    }
    final start = value.indexOf('{');
    final end = value.lastIndexOf('}');
    if (start >= 0 && end > start) value = value.substring(start, end + 1);
    final decoded = jsonDecode(value);
    if (decoded is! Map) throw const FormatException();
    final data = Map<String, dynamic>.from(
      decoded['data'] is Map ? decoded['data'] as Map : decoded,
    );
    if (_kind == 'character') {
      for (final key in [
        'name',
        'description',
        'personality',
        'scenario',
        'first_mes',
        'mes_example',
        'creator_notes',
        'system_prompt',
        'post_history_instructions',
        'creator',
        'character_version',
      ]) {
        data[key] ??= '';
        if (data[key] is! String) throw const FormatException();
      }
      for (final key in ['tags', 'alternate_greetings']) {
        data[key] ??= <String>[];
        if (data[key] is! List ||
            (data[key] as List).any((v) => v is! String)) {
          throw const FormatException();
        }
      }
      data['extensions'] ??= {};
      if (data['extensions'] is! Map) throw const FormatException();
    }
    final book = _kind == 'character' ? data['character_book'] : data;
    if (book != null) {
      if (book is! Map || book['entries'] is! List) {
        throw const FormatException();
      }
      book['extensions'] ??= {};
      if (book['extensions'] is! Map) throw const FormatException();
      for (final entry in book['entries'] as List) {
        if (entry is! Map ||
            entry['keys'] is! List ||
            (entry['keys'] as List).any((v) => v is! String) ||
            entry['content'] is! String ||
            (entry['content'] as String).trim().isEmpty) {
          throw const FormatException();
        }
        entry['enabled'] ??= true;
        entry['insertion_order'] ??= 100;
        entry['extensions'] ??= {};
        if (entry['enabled'] is! bool ||
            entry['insertion_order'] is! int ||
            entry['extensions'] is! Map) {
          throw const FormatException();
        }
      }
    }
    return _kind == 'character'
        ? {'spec': 'chara_card_v2', 'spec_version': '2.0', 'data': data}
        : data;
  }

  String _generationError(String code) => switch (code) {
    'configuration' => tr('请先在酒馆设置中配置 AI 服务'),
    'insecure_key' => tr('HTTP 服务不能发送 API 密钥'),
    'length' => tr('模型输出未完成，请降低描述复杂度后重试'),
    'cancelled' => tr('生成已取消'),
    _ => tr('生成失败，请检查模型连接后重试'),
  };

  Future<void> _outline() async {
    final outline = await Nav.push<String>(
      context,
      TavernAiText(
        text: _userPrompt,
        requireGeneration: true,
        task: 'Create an editable world book outline from the brief. Group entries into batches, with a title, scope and distinct trigger keywords for each entry.',
      ),
    );
    if (outline != null && mounted) {
      setState(() {
        _inputMode = 'natural';
        _prompt.text = outline;
      });
    }
  }

  Future<void> _save() async {
    final resource = _resource;
    if (resource == null) return;
    final changed = await Nav.push<bool>(
      context,
      TavernEditorPage.create(
        _kind,
        draft: reviewTavernProposal(resource, _baseline, _omitted).$1,
      ),
    );
    if (changed == true && mounted) Navigator.pop(context);
  }

  List<Widget> _proposalChoices() {
    final (reviewed, changes) = reviewTavernProposal(
      _resource!,
      _baseline,
      _omitted,
    );
    Set<String> keys(Map row) =>
        TavernLoreEntry(Map<String, dynamic>.from(row)).keys
            .map((k) => k.trim().toLowerCase())
            .toSet();
    final counts = <String, int>{};
    for (final entry in reviewed.entries) {
      for (final k in keys(entry.raw)) {
        counts[k] = (counts[k] ?? 0) + 1;
      }
    }
    return [
      for (final change in changes.entries)
        Builder(
          builder: (context) {
            final value = change.value.$2;
            final duplicates =
                change.key.startsWith('entry:') &&
                    !_omitted.contains(change.key) &&
                    value is Map
                ? keys(value).where((k) => (counts[k] ?? 0) > 1).join(', ')
                : '';
            return CheckboxListTile(
              value: !_omitted.contains(change.key),
              title: Text(
                change.key.startsWith('field:')
                    ? ({
                            'name': tr('名称'),
                            'description': tr('描述'),
                            'personality': tr('性格'),
                            'scenario': tr('场景'),
                            'first_mes': tr('开场白'),
                            'mes_example': tr('示例对话'),
                            'creator': tr('作者'),
                            'tags': tr('标签'),
                            'alternate_greetings': tr('其他开场白'),
                            'system_prompt': tr('系统提示词'),
                          }[change.value.$1] ??
                          change.value.$1)
                    : change.value.$1,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                [
                  if (duplicates.isNotEmpty) "${tr('共享关键词')} · $duplicates",
                  jsonEncode(value),
                ].join('\n'),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              onChanged: (checked) => setState(() {
                if (checked == true) {
                  _omitted.remove(change.key);
                } else {
                  _omitted.add(change.key);
                }
              }),
            );
          },
        ),
    ];
  }

  @override
  void dispose() {
    _generation?.cancel();
    _prompt.dispose();
    for (final field in _structured.values) {
      field.dispose();
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: PageHeader(
      title: tr('AI 创作酒馆资源'),
      actions: [
        if (_busy)
          IconButton(
            tooltip: tr('停止生成'),
            onPressed: _generation?.cancel,
            icon: const Icon(Icons.stop_rounded),
          ),
      ],
    ),
    body: ReadableWidth(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(Gap.page, Gap.l, Gap.page, Gap.xxl),
        children: [
          SegmentedButton<String>(
            segments: [
              ButtonSegment(
                value: 'character',
                label: Text(tr('角色卡')),
                icon: const Icon(Icons.person_outline_rounded),
              ),
              ButtonSegment(
                value: 'lorebook',
                label: Text(tr('世界书')),
                icon: const Icon(Icons.menu_book_outlined),
              ),
            ],
            selected: {_kind},
            onSelectionChanged: _busy
                ? null
                : (value) => setState(() {
                    _kind = value.first;
                    _resource = null;
                    _baseline = null;
                    _omitted.clear();
                    _draft = '';
                    _error = '';
                  }),
          ),
          const SizedBox(height: Gap.l),
          Text(tr('输入方式'), style: context.text.titleSmall),
          const SizedBox(height: Gap.s),
          SegmentedButton<String>(
            segments: [
              ButtonSegment(
                value: 'natural',
                label: Text(tr('自然语言')),
                icon: const Icon(Icons.notes_outlined),
              ),
              ButtonSegment(
                value: 'structured',
                label: Text(tr('结构化输入')),
                icon: const Icon(Icons.view_list_outlined),
              ),
            ],
            selected: {_inputMode},
            onSelectionChanged: _busy
                ? null
                : (value) => setState(() => _inputMode = value.first),
          ),
          const SizedBox(height: Gap.m),
          if (_structuredMode)
            _structuredForm()
          else
            TextField(
              enabled: !_busy,
              controller: _prompt,
              minLines: 6,
              maxLines: 12,
              decoration: InputDecoration(
                labelText: tr('描述你想创作的内容'),
                hintText: tr('例如：一个嘴硬心软、会逐渐信任用户的精灵佣兵'),
              ),
            ),
          const SizedBox(height: Gap.m),
          if (_kind == 'lorebook')
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: _busy ? null : _outline,
                child: Text(tr('生成世界书大纲')),
              ),
            ),
          FilledButton.icon(
            onPressed: _busy ? null : _generate,
            icon: const Icon(Icons.auto_awesome),
            label: Text(_busy ? tr('正在生成') : tr('生成草稿')),
          ),
          if (_error.isNotEmpty) ...[
            const SizedBox(height: Gap.s),
            Text(
              _error,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          if (_draft.isNotEmpty) ...[
            const SizedBox(height: Gap.l),
            Text(tr('生成预览'), style: context.text.titleMedium),
            const SizedBox(height: Gap.s),
            Text(_draft),
          ],
          if (_resource != null && !_busy) ...[
            ..._proposalChoices(),
            const SizedBox(height: Gap.m),
            Text(
              tr('格式校验通过'),
              style: TextStyle(color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(height: Gap.s),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(tr('编辑')),
            ),
          ],
        ],
      ),
    ),
  );
}
