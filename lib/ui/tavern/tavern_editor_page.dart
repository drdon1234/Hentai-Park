import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as image;
import 'package:uuid/uuid.dart';

import '../../core/localization.dart';
import '../../core/models.dart';
import '../../core/settings.dart';
import '../../tavern/models.dart';
import '../../tavern/store.dart';
import '../kit/kit.dart';
import '../nav.dart';
import '../theme.dart';
import 'tavern_ai_text.dart';

/// 角色卡与世界书的本地编辑器。
///
/// 编辑器只改写标准字段，未知字段沿用原始 JSON，因此导入的扩展数据不会
/// 因为一次编辑而被静默丢弃。
class TavernEditorPage extends StatefulWidget {
  const TavernEditorPage({
    super.key,
    required this.saved,
    this.fromProposal = false,
  });
  final bool fromProposal;
  final SavedTavernResource saved;

  factory TavernEditorPage.create(String kind, {TavernResource? draft}) {
    final resource =
        draft ?? TavernResource(kind: kind, raw: TavernResource.blank(kind));
    final item = WorkItem({
      'id': const Uuid().v4(),
      'mediaKind': 'tavern',
      'tavernKind': kind,
      'title': resource.name,
    }, 'tavern-local');
    return TavernEditorPage(
      fromProposal: draft != null,
      saved: SavedTavernResource(
        item: item,
        resource: resource,
        format: 'json',
        bytes: Uint8List(0),
      ),
    );
  }

  @override
  State<TavernEditorPage> createState() => _TavernEditorPageState();
}

class _TavernEditorPageState extends State<TavernEditorPage> {
  late Map<String, dynamic> _raw;
  late Map<String, dynamic> _data;
  late TextEditingController _title;
  late TextEditingController _name;
  late TextEditingController _description;
  late TextEditingController _personality;
  late TextEditingController _scenario;
  late TextEditingController _systemPrompt;
  late TextEditingController _example;
  late TextEditingController _firstMessage;
  late List<TextEditingController> _greetings;
  late List<Map<String, dynamic>> _entries;
  final _entryIds = Map<Map<String, dynamic>, String>.identity();
  Uint8List? _portrait;
  final _creator = TextEditingController();
  final _tags = TextEditingController();
  String _sample = '';
  List<String>? _matches;
  int _hitCount = 0;
  bool _busy = false;

  bool get _character => widget.saved.resource.kind == 'character';

  @override
  void initState() {
    super.initState();
    _privacy.addListener(_privacyChanged);
    _privacyChanged();
    _loadFields(widget.saved.resource.raw);
    _restoreDraft();
  }

  late final String _draftId = widget.saved.bytes.isEmpty
      ? 'new:${widget.saved.resource.kind}'
      : 'asset:${widget.saved.item.uid}:${sha256.convert(widget.saved.bytes)}:${sha256.convert(utf8.encode(jsonEncode(widget.saved.resource.raw)))}';
  late final _privacy = AppSettings.instance.watch({'incognito'});
  bool _private = false;
  void _privacyChanged() {
    if (AppSettings.instance.incognito) {
      _private = true;
      _dirty = false;
      _timer?.cancel();
    }
  }

  Timer? _timer;
  bool _dirty = false, _touched = false, _saved = false;
  String _draftNotice = '';
  Iterable<TextEditingController> get _controllers => [
    _title,
    _name,
    _description,
    _personality,
    _scenario,
    _systemPrompt,
    _example,
    _firstMessage,
    ..._greetings,
  ];

  Future<void> _restoreDraft() async {
    if (_private || widget.fromProposal) return;
    try {
      final draft = await TavernStore.instance.readDraft(_draftId);
      if (draft == null || !mounted || _touched || _busy || _private) {
        return;
      }
      _replaceDraft(draft.$1, draft.$2, true);
    } catch (_) {
      if (mounted) setState(() => _draftNotice = tr('草稿保存不可用'));
    }
  }

  bool _recovered = false;
  void _replaceDraft(
    Map<String, dynamic> data,
    Uint8List? portrait,
    bool recovered,
  ) {
    for (final c in _controllers) {
      c.dispose();
    }
    _creator.removeListener(_changed);
    _tags.removeListener(_changed);
    _entryIds.clear();
    setState(() {
      _loadFields(data);
      _portrait = portrait;
      _recovered = recovered;
      _matches = null;
      _draftNotice = recovered ? tr('已恢复编辑草稿') : '';
    });
  }

  Future<void> _discardDraft() async {
    if (!await confirmAction(
          context,
          title: tr('丢弃编辑草稿？'),
          destructive: true,
          confirmLabel: tr('删除'),
        ) ||
        !mounted) {
      return;
    }
    _timer?.cancel();
    _dirty = false;
    setState(() => _busy = true);
    try {
      await TavernStore.instance.clearDraft(_draftId);
      if (mounted) _replaceDraft(widget.saved.resource.raw, null, false);
    } catch (_) {
      if (mounted) setState(() => _draftNotice = tr('删除失败，请重试'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _changed() {
    if (_saved || _private) return;
    _dirty = true;
    _touched = true;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 250), _flushDraft);
  }

  String _reasonLabel(String code) => switch (code) {
    'keyword' => tr('关键词'),
    'constant' => tr('常驻'),
    'probability' => tr('概率未通过'),
    'budget' => tr('超出词条预算'),
    'unsupported' => tr('规则未支持'),
    'secondary' => tr('次关键词条件未满足'),
    'disabled' => tr('已停用'),
    'empty' => tr('正文为空'),
    _ => tr('关键词未命中'),
  };
  void _change(VoidCallback edit) {
    setState(() {
      edit();
      _matches = null;
    });
    _changed();
  }

  void _flushDraft() {
    if (!_dirty || _saved || _private) return;
    final content = jsonEncode(_buildRaw());
    _dirty = false;
    TavernStore.instance.writeDraft(_draftId, content, _portrait).catchError((
      Object e,
    ) {
      if (mounted && !_saved) {
        setState(() {
          _dirty = true;
          _draftNotice = tr('草稿保存不可用');
        });
      }
    });
  }

  void _loadFields(Map<String, dynamic> raw) {
    _raw = jsonDecode(jsonEncode(raw)) as Map<String, dynamic>;
    _data = !_raw.containsKey('entries') && _raw['data'] is Map
        ? Map<String, dynamic>.from(_raw['data'] as Map)
        : _raw;
    _creator.text = _data['creator']?.toString() ?? '';
    _tags.text = _data['tags'] is List
        ? (_data['tags'] as List).join(', ')
        : '';
    _title = TextEditingController(
      text: !_character && _data['name'] is String
          ? _data['name'] as String
          : widget.saved.item.title,
    );
    _name = TextEditingController(text: _data['name']?.toString() ?? '');
    _description = TextEditingController(
      text: _data['description']?.toString() ?? '',
    );
    _personality = TextEditingController(
      text: _data['personality']?.toString() ?? '',
    );
    _scenario = TextEditingController(
      text: _data['scenario']?.toString() ?? '',
    );
    _systemPrompt = TextEditingController(
      text: _data['system_prompt']?.toString() ?? '',
    );
    _example = TextEditingController(
      text: _data['mes_example']?.toString() ?? '',
    );
    _firstMessage = TextEditingController(
      text: _data['first_mes']?.toString() ?? '',
    );
    final greetings = _data['alternate_greetings'];
    _greetings = [
      if (greetings is List)
        for (final value in greetings)
          if (value is String) TextEditingController(text: value),
    ];
    _entries = _entryMaps(_character ? _data['character_book'] : _data);
    for (final c in [..._controllers, _creator, _tags]) {
      c.addListener(_changed);
    }
  }

  List<Map<String, dynamic>> _entryMaps(Object? book) {
    if (book is! Map) return [];
    final value = book['entries'];
    if (value is List) {
      return [
        for (final item in value)
          if (item is Map) Map<String, dynamic>.from(item),
      ];
    }
    if (value is Map) {
      return value.entries.map((entry) {
        final item = Map<String, dynamic>.from(entry.value as Map);
        _entryIds[item] = entry.key.toString();
        return item;
      }).toList();
    }
    return [];
  }

  TextField _field(
    String label,
    TextEditingController controller, {
    int lines = 1,
  }) => TextField(
    controller: controller,
    minLines: lines,
    maxLines: lines == 1 ? 1 : 8,
    decoration: InputDecoration(
      labelText: label,
      suffixIcon: lines < 3
          ? null
          : IconButton(
              tooltip: tr('AI 创作'),
              icon: const Icon(Icons.auto_awesome_outlined),
              onPressed: () async {
                final value = await Nav.push<String>(
                  context,
                  TavernAiText(
                    text: controller.text,
                    task: 'Revise this field of a roleplaying resource: $label',
                  ),
                );
                if (value != null && mounted) controller.text = value;
              },
            ),
    ),
  );

  void _setEntries(Map<String, dynamic> book) {
    if (book['entries'] is Map) {
      final used = _entryIds.values.toSet();
      var next = 0;
      for (final entry in _entries) {
        if (_entryIds.containsKey(entry)) continue;
        while (used.contains(next.toString())) {
          next++;
        }
        _entryIds[entry] = next.toString();
        used.add(next.toString());
      }
      book['entries'] = {
        for (final entry in _entries) _entryIds[entry]!: entry,
      };
    } else {
      book['entries'] = _entries;
    }
  }

  Map<String, dynamic> _buildRaw() {
    if (_character) {
      _data['name'] = _name.text.trim();
      _data['creator'] = _creator.text.trim();
      _data['tags'] = _tags.text
          .split(RegExp('[,，]'))
          .map((v) => v.trim())
          .where((v) => v.isNotEmpty)
          .toList();
      _data['description'] = _description.text;
      _data['personality'] = _personality.text;
      _data['scenario'] = _scenario.text;
      _data['system_prompt'] = _systemPrompt.text;
      _data['mes_example'] = _example.text;
      _data['first_mes'] = _firstMessage.text;
      _data['alternate_greetings'] = [
        for (final controller in _greetings)
          if (controller.text.trim().isNotEmpty) controller.text,
      ];
      if (_entries.isNotEmpty || _data['character_book'] is Map) {
        final book = Map<String, dynamic>.from(
          (_data['character_book'] as Map?) ??
              {'extensions': <String, dynamic>{}},
        );
        _setEntries(book);
        _data['character_book'] = book;
      }
      if (_raw['data'] is Map) {
        _raw['data'] = _data;
      }
    } else {
      final book = _data;
      book['name'] = _title.text.trim();
      _setEntries(book);
      if (!identical(_raw, book)) _raw['data'] = book;
    }
    return _raw;
  }

  Future<void> _history() async {
    try {
      final revisions = await TavernStore.instance.revisions(
        widget.saved.item.uid,
      );
      if (!mounted) return;
      final current = _buildRaw();
      final chosen = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: Text(tr('文本版本历史')),
          content: SizedBox(
            width: 480,
            child: ListView(
              shrinkWrap: true,
              children: [
                if (revisions.isEmpty) Text(tr('没有找到')),
                for (final (time, raw) in revisions)
                  ExpansionTile(
                    title: Text(
                      DateTime.fromMillisecondsSinceEpoch(time)
                          .toLocal()
                          .toString()
                          .split('.')
                          .first,
                    ),
                    children: [
                      SelectableText(
                        const JsonEncoder.withIndent('  ')
                            .convert(_changes(current, raw)),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(dialog, raw),
                        child: Text(tr('应用')),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: Text(tr('关闭')),
            ),
          ],
        ),
      );
      if (chosen == null || !mounted) return;
      final previous = SavedTavernResource(
        item: widget.saved.item,
        format: _portrait == null ? widget.saved.format : 'png',
        bytes: _portrait ?? widget.saved.bytes,
        resource: TavernResource(kind: widget.saved.resource.kind, raw: chosen),
      );
      final saved = await Nav.push<bool>(
        context,
        TavernEditorPage(saved: previous),
      );
      if (saved == true && mounted) {
        _saved = true;
        _timer?.cancel();
        if (!_private) await TavernStore.instance.clearDraft(_draftId);
        if (mounted) Navigator.pop(context, true);
      }
    } catch (_) {
      if (mounted) context.toast(tr('加载失败'));
    }
  }

  Map<String, dynamic> _changes(
    Map<String, dynamic> current,
    Map<String, dynamic> prior,
  ) {
    final a = current['data'] is Map ? current['data'] as Map : current;
    final b = prior['data'] is Map ? prior['data'] as Map : prior;
    return {
      for (final key in {...a.keys, ...b.keys})
        if (jsonEncode(a[key]) != jsonEncode(b[key])) key.toString(): b[key],
    };
  }

  Future<void> _pickPortrait() async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['png'],
      );
      if (file == null) return;
      if (await file.xFile.length() > 12 * 1024 * 1024) {
        throw const FormatException();
      }
      final bytes = await file.xFile.readAsBytes();
      final info = image.PngDecoder().startDecode(bytes);
      if (info == null ||
          info.width * info.height > 40000000 ||
          image.decodePng(bytes) == null) {
        throw const FormatException();
      }
      if (mounted) _change(() => _portrait = bytes);
    } catch (_) {
      if (mounted) context.toast(tr('导入失败，请检查文件格式'));
    }
  }

  Future<void> _save({bool copy = false}) async {
    if (_busy) return;
    if (_character && _name.text.trim().isEmpty) {
      context.toast(tr('角色名称不能为空'));
      return;
    }
    if (!_character && _entries.isEmpty) {
      context.toast(tr('世界书至少需要一条词条'));
      return;
    }
    _timer?.cancel();
    _flushDraft();
    setState(() => _busy = true);
    try {
      final resource = TavernResource(
        kind: widget.saved.resource.kind,
        raw: _buildRaw(),
      );
      await TavernStore.instance.updateResource(
        SavedTavernResource(
          item: copy
              ? WorkItem({
                  ...widget.saved.item.json,
                  'id': const Uuid().v4(),
                }, 'tavern-local')
              : widget.saved.item,
          resource: widget.saved.resource,
          format: _portrait == null ? widget.saved.format : 'png',
          bytes: _portrait ?? widget.saved.bytes,
        ),
        resource,
        title: _character ? resource.name : _title.text,
        draftId: _private || (widget.fromProposal && !_touched)
            ? null
            : _draftId,
      );
      _saved = true;
      _timer?.cancel();

      if (mounted) {
        context.toast(tr('已保存'));
        Navigator.pop(context, true);
      }
    } catch (_) {
      if (mounted) context.toast(tr('保存失败，请重试'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editEntry(int index) async {
    final entry = _entries[index];
    final label = TextEditingController(
      text: (entry['comment'] ?? entry['name'] ?? '').toString(),
    );
    final keys = TextEditingController(
      text:
          ((entry['keys'] ?? entry['key']) is List
                  ? ((entry['keys'] ?? entry['key']) as List).join(', ')
                  : '')
              .toString(),
    );
    final content = TextEditingController(
      text: entry['content']?.toString() ?? '',
    );
    final options = Map<String, dynamic>.from(entry);
    final secondary = TextEditingController(
      text: TavernLoreEntry(entry).secondaryKeys.join(', '),
    );
    final numbers = {
      for (final key in [
        'priority',
        'insertion_order',
        'probability',
        'scanDepth',
      ])
        key: TextEditingController(
          text: TavernLoreEntry(entry).option(key)?.toString() ?? '',
        ),
    };
    final route = DialogRoute<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(tr('编辑世界书词条')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _field(tr('名称'), label),
                const SizedBox(height: Gap.s),
                _field(tr('关键词'), keys),
                const SizedBox(height: Gap.s),
                _field(tr('内容'), content, lines: 5),
                ExpansionTile(
                  title: Text(tr('触发规则')),
                  children: [
                    _field(tr('次关键词'), secondary),
                    for (final field in {
                      'enabled': tr('启用'),
                      'constant': tr('常驻'),
                      'selective': tr('次关键词'),
                      'useProbability': tr('概率'),
                    }.entries)
                      SwitchListTile(
                        title: Text(field.value),
                        value: field.key == 'enabled'
                            ? TavernLoreEntry(options).enabled
                            : TavernLoreEntry(options).option(field.key) ==
                                  true,
                        onChanged: (v) => update(() {
                          options[field.key] = v;
                          if (field.key == 'enabled' &&
                              options.containsKey('disable')) {
                            options['disable'] = !v;
                          }
                        }),
                      ),
                    for (final field in {
                      'priority': tr('优先级'),
                      'insertion_order': tr('插入顺序'),
                      'probability': tr('概率'),
                      'scanDepth': tr('扫描深度'),
                    }.entries)
                      TextField(
                        controller: numbers[field.key],
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(labelText: field.value),
                      ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(tr('取消')),
            ),
            FilledButton(
              onPressed: () {
                for (final item in numbers.entries) {
                  if (item.value.text.trim().isEmpty) continue;
                  final n = int.tryParse(item.value.text.trim());
                  if (n == null ||
                      (item.key == 'probability' && (n < 0 || n > 100)) ||
                      (item.key == 'scanDepth' && (n < 0 || n > 1000))) {
                    context.toast(tr('数值无效'));
                    return;
                  }
                  options[item.key] = n;
                }
                entry.addAll(options);
                entry['secondary_keys'] = secondary.text
                    .split(RegExp('[,，]'))
                    .map((s) => s.trim())
                    .where((s) => s.isNotEmpty)
                    .toList();
                entry['comment'] = label.text;
                entry['keys'] = keys.text
                    .split(RegExp('[,，]'))
                    .map((value) => value.trim())
                    .where((value) => value.isNotEmpty)
                    .toList();
                for (final pair in {
                  'key': 'keys',
                  'keysecondary': 'secondary_keys',
                  'secondaryKeys': 'secondary_keys',
                  'order': 'insertion_order',
                }.entries) {
                  if (entry.containsKey(pair.key) &&
                      entry.containsKey(pair.value)) {
                    entry[pair.key] = entry[pair.value];
                  }
                }
                entry['content'] = content.text;
                Navigator.pop(context, true);
              },
              child: Text(tr('保存')),
            ),
          ],
        ),
      ),
    );
    final result = await Navigator.of(context).push(route);
    await route.completed;
    secondary.dispose();
    for (final c in numbers.values) {
      c.dispose();
    }
    label.dispose();
    keys.dispose();
    content.dispose();
    if (result == true && mounted) _change(() => _matches = null);
  }

  Future<void> _importEntries() async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (file == null) return;
      if (await file.xFile.length() > 12 * 1024 * 1024) {
        throw const FormatException();
      }
      final book = TavernResource.parse(
        'lorebook',
        'json',
        await file.xFile.readAsBytes(),
      );
      final used = {
        for (final entry in _entries)
          for (final key in ['uid', 'id'])
            if (entry[key] != null) entry[key].toString(),
      };
      var nextId = 0;
      final additions = <Map<String, dynamic>>[];
      for (final entry in book.entries) {
        final data = Map<String, dynamic>.from(entry.raw);
        for (final key in ['uid', 'id']) {
          final id = data[key];
          if (id == null) continue;
          if (!used.add(id.toString())) {
            while (used.contains(nextId.toString())) {
              nextId++;
            }
            data[key] = nextId;
            used.add(nextId.toString());
          }
        }
        additions.add(data);
      }
      if (mounted) {
        _change(() {
          _entries.addAll(additions);
          _matches = null;
        });
      }
    } catch (_) {
      if (mounted) context.toast(tr('导入失败，请检查文件格式'));
    }
  }

  void _addEntry() {
    _change(() {
      _entries.add({
        'comment': tr('新世界书词条'),
        'keys': <String>[],
        'content': '',
        'enabled': true,
        'extensions': <String, dynamic>{},
        'insertion_order': 100,
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _flushDraft();
    _privacy.removeListener(_privacyChanged);
    for (final controller in [
      _title,
      _tags,
      _creator,
      _name,
      _description,
      _personality,
      _scenario,
      _systemPrompt,
      _example,
      _firstMessage,
      ..._greetings,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Widget _characterBody() => ListView(
    padding: const EdgeInsets.fromLTRB(Gap.page, Gap.l, Gap.page, Gap.xxl),
    children: [
      if (_portrait != null || widget.saved.format == 'png')
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Image.memory(
            _portrait ?? widget.saved.bytes,
            width: 80,
            height: 100,
            fit: BoxFit.contain,
          ),
        ),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          onPressed: _pickPortrait,
          icon: const Icon(Icons.image_outlined),
          label: Text(tr('头像')),
        ),
      ),
      _field(tr('名称'), _name),
      _field(tr('作者'), _creator),
      _field(tr('标签'), _tags),
      const SizedBox(height: Gap.s),
      _field(tr('描述'), _description, lines: 6),
      const SizedBox(height: Gap.s),
      _field(tr('性格'), _personality, lines: 4),
      const SizedBox(height: Gap.s),
      _field(tr('场景'), _scenario, lines: 4),
      const SizedBox(height: Gap.s),
      _field(tr('系统提示词'), _systemPrompt, lines: 4),
      const SizedBox(height: Gap.s),
      _field(tr('示例对话'), _example, lines: 6),
      const SizedBox(height: Gap.s),
      _field(tr('开场白'), _firstMessage, lines: 5),
      const SizedBox(height: Gap.l),
      Text(tr('其他开场白'), style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: Gap.s),
      for (var i = 0; i < _greetings.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: Gap.s),
          child: Row(
            children: [
              Expanded(
                child: _field('${tr('开场白')} ${i + 2}', _greetings[i], lines: 3),
              ),
              IconButton(
                onPressed: () =>
                    _change(() => _greetings.removeAt(i).dispose()),
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ),
        ),
      OutlinedButton.icon(
        onPressed: () => _change(
          () => _greetings.add(TextEditingController()..addListener(_changed)),
        ),
        icon: const Icon(Icons.add),
        label: Text(tr('新增')),
      ),
      const SizedBox(height: Gap.l),
      _entriesBody(),
    ],
  );

  Widget _entriesBody() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              tr('世界书'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          IconButton(
            tooltip: tr('导入世界书词条'),
            onPressed: _importEntries,
            icon: const Icon(Icons.file_open_outlined),
          ),
          TextButton.icon(
            onPressed: _addEntry,
            icon: const Icon(Icons.add),
            label: Text(tr('新增')),
          ),
        ],
      ),
      if (_entries.isNotEmpty)
        ExpansionTile(
          title: Text(tr('测试触发')),
          children: [
            TextField(
              onChanged: (text) => setState(() {
                _sample = text;
                _matches = null;
              }),
              decoration: InputDecoration(labelText: tr('消息')),
            ),
            TextButton(
              onPressed: () {
                final book = TavernResource(
                  kind: widget.saved.resource.kind,
                  raw: _buildRaw(),
                );
                final settings = book.bookSettings;
                final entries = book.entries;
                final reasons = <TavernLoreEntry, String>{};
                final hits = matchTavernLore(
                  entries,
                  [_sample],
                  explain: (entry, reason, key) {
                    reasons[entry] = [
                      entry.label,
                      _reasonLabel(reason),
                      if (key.isNotEmpty) key,
                    ].join(' · ');
                  },
                  scanDepth: (settings['scan_depth'] as num?)?.toInt() ?? 4,
                  tokenBudget:
                      (settings['token_budget'] as num?)?.toInt() ?? 2048,
                  recursive: settings['recursive_scanning'] == true,
                );
                setState(() {
                  _hitCount = hits.length;
                  _matches = [
                    for (final entry in entries)
                      if (reasons.containsKey(entry)) reasons[entry]!,
                  ];
                });
              },
              child: Text(tr('测试触发')),
            ),
            if (_matches != null)
              Text(
                [
                  tr('本轮匹配 {count} 条世界书', {'count': _hitCount}),
                  ..._matches!,
                ].join('\n'),
              ),
          ],
        ),
      for (var i = 0; i < _entries.length; i++)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            (_entries[i]['comment'] ?? _entries[i]['name'] ?? tr('世界书词条'))
                .toString(),
          ),
          subtitle: Text(
            ((_entries[i]['keys'] ?? _entries[i]['key']) is List
                    ? ((_entries[i]['keys'] ?? _entries[i]['key']) as List)
                          .join(', ')
                    : '')
                .toString(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Wrap(
            children: [
              IconButton(
                onPressed: () => _editEntry(i),
                icon: const Icon(Icons.edit_outlined),
              ),
              IconButton(
                onPressed: () => _change(() => _entries.removeAt(i)),
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ),
        ),
    ],
  );

  Widget _bookBody() => ListView(
    padding: const EdgeInsets.fromLTRB(Gap.page, Gap.l, Gap.page, Gap.xxl),
    children: [_entriesBody()],
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: PageHeader(
      title: _character ? tr('编辑角色卡') : tr('编辑世界书'),
      actions: [
        if (widget.saved.bytes.isNotEmpty)
          IconButton(
            tooltip: tr('文本版本历史'),
            icon: const Icon(Icons.history_rounded),
            onPressed: _busy ? null : _history,
          ),
        if (widget.saved.bytes.isNotEmpty)
          IconButton(
            tooltip: tr('另存为副本'),
            icon: const Icon(Icons.copy_outlined),
            onPressed: _busy ? null : () => _save(copy: true),
          ),
        TextButton(onPressed: _busy ? null : _save, child: Text(tr('保存'))),
      ],
    ),
    body: AbsorbPointer(
      absorbing: _busy,
      child: ReadableWidth(
        child: Column(
          children: [
            if (!_character)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Gap.page,
                  Gap.s,
                  Gap.page,
                  0,
                ),
                child: _field(tr('名称'), _title),
              ),
            if (_draftNotice.isNotEmpty)
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(_draftNotice),
                  if (_recovered)
                    TextButton(onPressed: _discardDraft, child: Text(tr('删除'))),
                ],
              ),
            if (_busy) const LinearProgressIndicator(),
            Expanded(child: _character ? _characterBody() : _bookBody()),
          ],
        ),
      ),
    ),
  );
}
