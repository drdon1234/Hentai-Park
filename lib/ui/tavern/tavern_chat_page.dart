import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../core/localization.dart';
import '../../core/models.dart';
import '../../tavern/conversation.dart';
import '../../tavern/store.dart';
import '../../tavern/transfer.dart';
import '../kit/kit.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets/content_translation.dart';
import 'tavern_avatar.dart';
import 'tavern_settings_page.dart';

class TavernChatPage extends StatefulWidget {
  const TavernChatPage({
    super.key,
    required this.session,
    this.persist = true,
    this.portrait,
  });
  final TavernSession session;
  final bool persist;
  final SavedTavernResource? portrait;
  @override
  State<TavernChatPage> createState() => _TavernChatPageState();
}

class _TavernChatPageState extends State<TavernChatPage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  late final TavernConversation _chat;
  bool _following = true;
  bool _leaving = false;
  bool _editing = false;
  SavedTavernResource? _portrait;
  TavernSession get _session => _chat.session;
  bool get _sending => _chat.busy || _editing;
  @override
  void initState() {
    super.initState();
    _chat = TavernConversation(widget.session, persist: widget.persist)
      ..addListener(_changed);
    _scroll.addListener(() {
      final next = _scroll.position.extentAfter < 80;
      if (next != _following && mounted) setState(() => _following = next);
    });
    _portrait = widget.portrait;
    if (_portrait == null) unawaited(_loadPortrait());
  }

  Future<void> _loadPortrait() async {
    try {
      final saved = await TavernStore.instance.get(_session.resourceUid);
      if (mounted) setState(() => _portrait = saved);
    } catch (_) {
      /* 头像读取失败不影响对话，保留身份占位。 */
    }
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    if (_following) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _following && _scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    }
  }

  Future<void> _generate({
    bool regenerate = false,
    bool continuation = false,
    bool send = false,
  }) async {
    if (_sending) return;
    if (send && _input.text.trim().isEmpty) return;
    final text = send ? _input.text : null;
    if (send) _input.clear();
    await _chat.generate(
      text: text,
      regenerate: regenerate,
      continuation: continuation,
    );
    if (!mounted) return;
    final error = _chat.failure;
    if (error?.code == 'configuration') {
      if (text != null) _input.text = text;
      context.toast(tr('请先配置 AI 服务'));
      await Nav.push(context, const TavernSettingsPage());
    }
  }

  Future<void> _save() async {
    try {
      await _chat.save();
    } catch (_) {
      if (mounted) context.toast(tr('保存失败，请重试'));
    }
  }

  Future<void> _leave() async {
    if (_leaving || _editing) return;
    if (!await confirmAction(
      context,
      title: tr('离开会话？'),
      message: tr('未保存的内容和正在生成的回复可能丢失。'),
      confirmLabel: tr('离开'),
      destructive: true,
    )) {
      return;
    }
    _chat.cancel();
    if (mounted) {
      setState(() => _leaving = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
    }
  }

  Future<String?> _editText(String title, String initial) async {
    final controller = TextEditingController(text: initial);
    final route = DialogRoute<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(controller: controller, minLines: 3, maxLines: 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(tr('保存')),
          ),
        ],
      ),
    );
    final result = await Navigator.of(context).push(route);
    await route.completed;
    controller.dispose();
    return result;
  }

  Future<void> _edit(int index) async {
    if (_sending) return;
    setState(() => _editing = true);
    try {
      final text = await _editText(
        tr('编辑消息'),
        _session.messages[index]['content'] ?? '',
      );
      if (text != null && text.trim().isNotEmpty) await _chat.edit(index, text);
    } catch (_) {
      if (mounted) context.toast(tr('保存失败，请重试'));
    } finally {
      if (mounted) setState(() => _editing = false);
    }
  }

  Future<void> _truncate(int index) async {
    if (_sending) return;
    if (!await confirmAction(
      context,
      title: tr('删除消息？'),
      message: tr('将删除此条及后续消息。'),
      confirmLabel: tr('删除'),
      destructive: true,
    )) {
      return;
    }
    try {
      await _chat.truncate(index);
    } catch (_) {
      if (mounted) context.toast(tr('保存失败，请重试'));
    }
  }

  Future<void> _persona() async {
    if (_sending) return;
    setState(() => _editing = true);
    final name = TextEditingController(text: _session.userName);
    final description = TextEditingController(text: _session.persona);
    try {
      final route = DialogRoute<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(tr('用户人格')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: InputDecoration(labelText: tr('名称')),
                ),
                const SizedBox(height: Gap.l),
                TextField(
                  controller: description,
                  minLines: 3,
                  maxLines: 8,
                  decoration: InputDecoration(labelText: tr('角色设定')),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr('取消')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr('保存')),
            ),
          ],
        ),
      );
      final saved = await Navigator.of(context).push(route);
      await route.completed;
      if (saved == true) {
        _session.userName = name.text.trim().isEmpty
            ? 'User'
            : name.text.trim();
        _session.persona = description.text;
        await _save();
      }
    } finally {
      name.dispose();
      description.dispose();
      if (mounted) setState(() => _editing = false);
    }
  }

  Future<void> _export() async {
    try {
      final bytes = await TavernTransfer.exportSession(_session);
      if (!mounted) return;
      final result = await FilePicker.saveFile(
        fileName: 'conversation.json',
        bytes: bytes,
        mimeType: 'application/json',
      );
      if (result != null && mounted) context.toast(tr('已导出'));
    } catch (_) {
      if (mounted) context.toast(tr('导出失败，请重试'));
    }
  }

  Future<void> _branch(int index) async {
    try {
      final branch = await _chat.branch(index);
      if (mounted) {
        await Nav.push(
          context,
          TavernChatPage(
            session: branch,
            persist: !_chat.ephemeral,
            portrait: _portrait,
          ),
        );
      }
    } catch (_) {
      if (mounted) context.toast(tr('保存失败，请重试'));
    }
  }

  Future<void> _alternative(int index) async {
    try {
      await _chat.nextAlternative(index);
    } catch (_) {
      if (mounted) context.toast(tr('保存失败，请重试'));
    }
  }

  Future<void> _chooseBooks() async {
    if (_sending) return;
    setState(() => _editing = true);
    try {
      await _selectBooks();
    } finally {
      if (mounted) setState(() => _editing = false);
    }
  }

  Future<void> _selectBooks() async {
    late final List<WorkItem> books;
    try {
      books = await TavernStore.instance.resources(kind: 'lorebook');
    } catch (_) {
      if (mounted) context.toast(tr('读取失败，请重试'));
      return;
    }
    if (!mounted) return;
    if (books.isEmpty) {
      context.toast(tr('请先保存世界书'));
      return;
    }
    final selected = _session.books.toSet();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(tr('关联世界书')),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final book in books)
                    CheckboxListTile(
                      value: selected.contains(book.uid),
                      title: Text(book.title),
                      onChanged: (value) => update(() {
                        if (value == true) {
                          selected.add(book.uid);
                        } else {
                          selected.remove(book.uid);
                        }
                      }),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr('取消')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr('保存')),
            ),
          ],
        ),
      ),
    );
    if (result != true) return;
    _session.books
      ..clear()
      ..addAll(selected);
    try {
      await _chat.save();
    } catch (_) {
      if (mounted) context.toast(tr('保存失败，请重试'));
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _chat.removeListener(_changed);
    _chat.dispose();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  String _failure() => switch (_chat.failure?.code) {
    'length' => tr('回复达到输出上限，可继续生成。'),
    'cancelled' => tr('已停止生成'),
    'http' => tr('AI 服务返回 HTTP {status}', {
      'status': _chat.failure?.status ?? 0,
    }),
    'context_too_large' => tr('角色设定或消息过长，无法发送'),
    'book_missing' => tr('关联的世界书已不存在'),
    'insecure_key' => tr('HTTP 本机服务不能携带 API Key'),
    _ => tr('AI 服务连接失败，请检查设置后重试'),
  };
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _leaving || (!_sending && !_chat.unsaved && _input.text.isEmpty),
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) unawaited(_leave());
    },
    child: Scaffold(
      appBar: PageHeader(
        titleWidget: Row(
          children: [
            TavernAvatar(name: _session.title, saved: _portrait),
            const SizedBox(width: Gap.m),
            Expanded(
              child: ContentTranslation(
                text: _session.title,
                source: _session.resourceUid.split(':').first,
                builder: (value) => Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ParkText.serif(context.text.titleLarge),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TranslationControls(source: _session.resourceUid.split(':').first),
          PopupMenuButton<String>(
            tooltip: tr('更多'),
            enabled: !_sending,
            onSelected: (value) {
              switch (value) {
                case 'persona':
                  _persona();
                case 'books':
                  _chooseBooks();
                case 'export':
                  _export();
                case 'settings':
                  Nav.push(context, const TavernSettingsPage());
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(value: 'persona', child: Text(tr('用户人格'))),
              PopupMenuItem(value: 'books', child: Text(tr('关联世界书'))),
              PopupMenuItem(value: 'export', child: Text(tr('导出会话'))),
              PopupMenuItem(value: 'settings', child: Text(tr('AI 服务设置'))),
            ],
          ),
        ],
      ),
      body: ReadableWidth(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(Gap.page),
              child: Text(
                _chat.ephemeral
                    ? tr('无痕模式下此会话不会保存。')
                    : tr('消息和角色设定会发送到你配置的 AI 服务。'),
                style: context.text.bodySmall,
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.symmetric(horizontal: Gap.page),
                itemCount:
                    _session.messages.length + (_chat.draft.isEmpty ? 0 : 1),
                itemBuilder: (context, index) {
                  final draft = index == _session.messages.length;
                  final message = draft
                      ? {'role': 'assistant', 'content': _chat.draft}
                      : _session.messages[index];
                  final last = index == _session.messages.length - 1;
                  final user = message['role'] == 'user';
                  final name =
                      message['name'] ??
                      (user ? _session.userName : _session.title);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: Gap.xl),
                    child: Align(
                      alignment: user
                          ? AlignmentDirectional.centerEnd
                          : AlignmentDirectional.centerStart,
                      child: FractionallySizedBox(
                        widthFactor: user ? 0.88 : 1,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: user
                                ? context.colors.surfaceContainerHigh
                                : null,
                            borderRadius: Radii.medium,
                          ),
                          child: Padding(
                            padding: user
                                ? const EdgeInsets.symmetric(
                                    horizontal: Gap.m,
                                    vertical: Gap.xs,
                                  )
                                : EdgeInsets.zero,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    TavernAvatar(
                                      name: name,
                                      user: user,
                                      saved: _portrait,
                                    ),
                                    const SizedBox(width: Gap.m),
                                    Expanded(
                                      child: Text(
                                        name,
                                        style: context.text.titleSmall,
                                      ),
                                    ),
                                    if (!draft)
                                      PopupMenuButton<String>(
                                        tooltip: tr('消息操作'),
                                        enabled: !_sending,
                                        onSelected: (value) {
                                          switch (value) {
                                            case 'edit':
                                              _edit(index);
                                            case 'delete':
                                              _truncate(index);
                                            case 'branch':
                                              _branch(index);
                                            case 'alternative':
                                              _alternative(index);
                                          }
                                        },
                                        itemBuilder: (context) => [
                                          PopupMenuItem(
                                            value: 'edit',
                                            child: Text(tr('编辑消息')),
                                          ),
                                          PopupMenuItem(
                                            value: 'branch',
                                            child: Text(tr('从此处分支')),
                                          ),
                                          if (_session
                                                  .alternatives['$index']
                                                  ?.isNotEmpty ==
                                              true)
                                            PopupMenuItem(
                                              value: 'alternative',
                                              child: Text(tr('切换候选回复')),
                                            ),
                                          PopupMenuItem(
                                            value: 'delete',
                                            child: Text(tr('删除')),
                                          ),
                                        ],
                                      ),
                                  ],
                                ),
                                const SizedBox(height: Gap.s),
                                MarkdownBody(
                                  data: message['content'] ?? '',
                                  selectable: true,
                                  styleSheet:
                                      MarkdownStyleSheet.fromTheme(
                                        Theme.of(context),
                                      ).copyWith(
                                        p: context.text.bodyLarge?.copyWith(
                                          height: 1.55,
                                        ),
                                        em: context.text.bodyLarge?.copyWith(
                                          height: 1.55,
                                          fontStyle: FontStyle.italic,
                                          color:
                                              context.colors.onSurfaceVariant,
                                        ),
                                      ),
                                  // 模型输出不自动请求外部图片，不执行 HTML 或脚本。
                                  imageBuilder: (uri, title, alt) =>
                                      Text(alt ?? ''),
                                ),
                                if (message['status'] == 'length')
                                  Text(
                                    tr('回复达到输出上限，可继续生成。'),
                                    style: context.text.bodySmall,
                                  ),
                                if (message['status'] != null &&
                                    !{
                                      'complete',
                                      'length',
                                    }.contains(message['status']))
                                  Text(
                                    tr('回复尚未完成，可继续生成。'),
                                    style: context.text.bodySmall,
                                  ),
                                if (!draft && !_sending)
                                  Wrap(
                                    spacing: Gap.s,
                                    children: [
                                      if (last && !user)
                                        TextButton(
                                          onPressed: () =>
                                              _generate(continuation: true),
                                          child: Text(tr('续写')),
                                        ),
                                      if (last &&
                                          (user ||
                                              (index > 0 &&
                                                  _session.messages[index -
                                                          1]['role'] ==
                                                      'user')))
                                        TextButton(
                                          onPressed: () =>
                                              _generate(regenerate: !user),
                                          child: Text(tr('重新生成')),
                                        ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (_chat.trimmed)
              Text(tr('较早的消息超出上下文，已从本次请求中省略。'), style: context.text.bodySmall),
            if (_chat.unsupportedLore)
              Text(tr('部分世界书扩展尚不支持，已保留原始数据。'), style: context.text.bodySmall),
            if (_chat.matched > 0)
              Text(
                tr('本轮匹配 {count} 条世界书', {'count': _chat.matched}),
                style: context.text.bodySmall,
              ),
            if (_chat.totalTokens != null)
              Text(
                tr('本轮用量 {count} Token', {'count': _chat.totalTokens!}),
                style: context.text.bodySmall,
              ),
            if (_chat.failure != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Gap.page),
                child: Text(_failure()),
              ),
            if (_chat.unsaved)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Gap.page),
                child: Row(
                  children: [
                    Expanded(child: Text(tr('保存失败，请重试'))),
                    TextButton(onPressed: _save, child: Text(tr('重试保存'))),
                  ],
                ),
              ),
            if (_chat.busy) const LinearProgressIndicator(),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(Gap.page),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _input,
                        minLines: 1,
                        maxLines: 5,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(hintText: tr('输入消息')),
                      ),
                    ),
                    const SizedBox(width: Gap.s),
                    IconButton.filled(
                      tooltip: _chat.busy ? tr('停止生成') : tr('发送'),
                      onPressed:
                          _editing ||
                              _chat.unsaved ||
                              (!_chat.busy && _input.text.trim().isEmpty)
                          ? null
                          : _chat.busy
                          ? _chat.cancel
                          : () => _generate(send: true),
                      icon: Icon(
                        _chat.busy
                            ? Icons.stop_rounded
                            : Icons.arrow_upward_rounded,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
