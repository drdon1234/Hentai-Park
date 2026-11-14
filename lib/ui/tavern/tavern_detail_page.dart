import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../../core/models.dart';
import '../../core/settings.dart';
import '../../engine/source_manager.dart';
import '../../library/export_files.dart';
import '../../library/library.dart';
import '../../tavern/models.dart';
import '../../tavern/store.dart';
import '../detail/detail_actions.dart';
import '../kit/adaptive_sheet.dart';
import '../library/favorite_actions.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/content_translation.dart';
import '../widgets/error_view.dart';
import '../widgets/text_translation.dart';
import 'tavern_chat_page.dart';
import 'tavern_lorebook_page.dart';

class TavernDetailPage extends StatefulWidget {
  const TavernDetailPage({super.key, required this.item});
  final WorkItem item;
  @override
  State<TavernDetailPage> createState() => _TavernDetailPageState();
}

class _TavernDetailPageState extends State<TavernDetailPage> {
  TavernResource? _resource;
  Uint8List? _bytes;
  String _format = '';
  bool _loading = true;
  bool _busy = false;
  bool _opening = false;
  bool _exporting = false;
  bool _saved = false;
  Object? _error;
  int _greeting = 0;
  WorkItem get _item => WorkItem({
    ...widget.item.json,
    if (widget.item.title.isEmpty && _resource?.name.isNotEmpty == true)
      'title': _resource!.name,
    if (_resource != null) 'tavernKind': _resource!.kind,
  }, widget.item.source);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final saved = await TavernStore.instance.get(widget.item.uid);
      if (saved != null) {
        _resource = saved.resource;
        _bytes = saved.bytes;
        _format = saved.format;
        _saved = true;
      } else {
        final asset = await SourceManager.instance.tavernAsset(
          widget.item.source,
          widget.item.id,
        );
        _resource = TavernResource.parse(asset.kind, asset.format, asset.bytes);
        _bytes = asset.bytes;
        _format = asset.format;
      }
    } catch (error) {
      _error = error;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<SavedTavernResource?> _save() async {
    if (_resource == null || _bytes == null || _busy) return null;
    setState(() => _busy = true);
    try {
      await TavernStore.instance.save(_item, _resource!, _format, _bytes!);
      final saved = await TavernStore.instance.get(widget.item.uid);
      _saved = true;
      return saved;
    } catch (_) {
      if (mounted) context.toast(tr('保存失败，请重试'));
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _download() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      if (_bytes == null || _resource == null || !mounted) return;
      final saved = SavedTavernResource(
        item: _item,
        resource: _resource!,
        format: _format,
        bytes: _bytes!,
      );
      final uri = await FilePicker.saveFile(
        fileName: '${exportFileName(_item.title)}.${saved.format}',
        bytes: saved.bytes,
        mimeType: saved.format == 'png' ? 'image/png' : 'application/json',
      );
      if (uri != null && mounted) context.toast(tr('已导出'));
    } catch (_) {
      if (mounted) context.toast(tr('导出失败，请重试'));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _chat() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final persist = !AppSettings.instance.incognito;
      final saved = persist
          ? (_saved
                ? await TavernStore.instance.get(widget.item.uid)
                : await _save())
          : _resource == null || _bytes == null
          ? null
          : SavedTavernResource(
              item: _item,
              resource: _resource!,
              format: _format,
              bytes: _bytes!,
            );
      if (saved == null || !mounted) return;
      final session = await TavernStore.instance.createSession(
        saved,
        _greeting,
        persist: persist,
      );
      if (mounted) {
        await Nav.push(
          context,
          TavernChatPage(session: session, persist: persist, portrait: saved),
        );
      }
    } catch (_) {
      if (mounted) context.toast(tr('创建会话失败'));
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _openLorebook() async {
    final resource = _resource;
    if (resource == null || resource.entries.isEmpty) return;
    await Nav.push(
      context,
      TavernLorebookPage(
        title: _item.title,
        source: widget.item.source,
        resource: resource,
      ),
    );
  }

  Future<void> _more() async {
    final action = await showAdaptiveSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            if (!_saved)
              ListTile(
                leading: const Icon(Icons.bookmark_add_outlined),
                title: Text(tr('保存到本地')),
                onTap: () => Navigator.pop(context, 'save'),
              ),
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: Text(tr('导出原文件')),
              onTap: () => Navigator.pop(context, 'export'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'save') {
      if (await _save() != null && mounted) context.toast(tr('已保存'));
    } else if (action == 'export') {
      await _download();
    }
  }

  Widget _section(String title, String content) => content.trim().isEmpty
      ? const SizedBox.shrink()
      : ExpansionTile(
          title: Text(title),
          childrenPadding: const EdgeInsets.fromLTRB(
            Gap.page,
            0,
            Gap.page,
            Gap.l,
          ),
          children: [
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TranslationSelectionArea(
                child: ContentTranslation(
                  text: content,
                  source: widget.item.source,
                  builder: (value) => SelectableText(value),
                ),
              ),
            ),
          ],
        );

  @override
  Widget build(BuildContext context) {
    final resource = _resource;
    return Scaffold(
      appBar: PageHeader(
        titleWidget: ContentTranslation(
          text: _item.title,
          source: widget.item.source,
          builder: (value) => Text(value),
        ),
        actions: [TranslationControls(source: widget.item.source)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null || resource == null
          ? _error is SourceError
                ? SourceErrorView(
                    error: _error!,
                    source: widget.item.source,
                    onRetry: _load,
                  )
                : Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(tr('酒馆资源加载失败')),
                        const SizedBox(height: Gap.s),
                        OutlinedButton(onPressed: _load, child: Text(tr('重试'))),
                      ],
                    ),
                  )
          : ReadableWidth(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  Gap.page,
                  Gap.l,
                  Gap.page,
                  Gap.xxl,
                ),
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 100,
                        height: 140,
                        child: _format == 'png' && _bytes != null
                            ? Image.memory(_bytes!, fit: BoxFit.contain)
                            : CoverImage(
                                source: widget.item.source,
                                url: widget.item.cover,
                                mediaKind: MediaKind.tavern,
                              ),
                      ),
                      const SizedBox(width: Gap.l),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ContentTranslation(
                              text: resource.name.isEmpty
                                  ? widget.item.title
                                  : resource.name,
                              source: widget.item.source,
                              builder: (value) => Text(
                                value,
                                style: context.text.headlineSmall,
                              ),
                            ),
                            const SizedBox(height: Gap.s),
                            Text(
                              resource.kind == 'character'
                                  ? tr('角色卡')
                                  : tr('世界书'),
                              style: context.text.bodyMedium,
                            ),
                            Text(
                              tr('{count} 条世界书词条', {
                                'count': resource.entries.length,
                              }),
                              style: context.text.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Gap.l),
                  Row(
                    children: [
                      if (resource.kind == 'character')
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _busy || _opening ? null : _chat,
                            icon: const Icon(Icons.chat_bubble_outline_rounded),
                            label: Text(tr('开始对话')),
                          ),
                        )
                      else
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _openLorebook,
                            icon: const Icon(Icons.menu_book_outlined),
                            label: Text(tr('查看世界书')),
                          ),
                        ),
                      const SizedBox(width: Gap.s),
                      ListenableBuilder(
                        listenable: Library.instance.work(widget.item.uid),
                        builder: (context, _) => DetailSecondaryButton(
                          icon: Library.instance.isFavorite(widget.item.uid)
                              ? Icons.bookmark_rounded
                              : Icons.bookmark_border_rounded,
                          tooltip: Library.instance.isFavorite(widget.item.uid)
                              ? tr('取消应用内收藏')
                              : tr('应用内收藏'),
                          active: Library.instance.isFavorite(widget.item.uid),
                          onPressed: () => toggleFavorite(context, _item),
                          onLongPress:
                              Library.instance.isFavorite(widget.item.uid)
                              ? () => editFavoriteCategories(
                                  context,
                                  widget.item.uid,
                                )
                              : null,
                        ),
                      ),
                      const SizedBox(width: Gap.s),
                      DetailSecondaryButton(
                        icon: Icons.more_horiz_rounded,
                        tooltip: tr('更多'),
                        onPressed: _busy || _exporting ? null : _more,
                      ),
                    ],
                  ),
                  if (resource.kind == 'character') ...[
                    const SizedBox(height: Gap.l),
                    if (resource.greetings.isNotEmpty)
                      DropdownButtonFormField<int>(
                        initialValue: _greeting,
                        decoration: InputDecoration(labelText: tr('选择开场白')),
                        items: [
                          for (var i = 0; i < resource.greetings.length; i++)
                            DropdownMenuItem(
                              value: i,
                              child: Text(
                                tr('开场白 {number}', {'number': i + 1}),
                              ),
                            ),
                        ],
                        onChanged: (value) =>
                            setState(() => _greeting = value ?? 0),
                      ),
                    const SizedBox(height: Gap.m),
                    Text(
                      tr('开始对话需要自行配置 AI 服务。'),
                      style: context.text.bodySmall,
                    ),
                    _section(tr('作者说明'), resource.text('creator_notes')),
                    if (resource.hasUnsupportedLore)
                      Text(tr('部分世界书扩展尚不支持，已保留原始数据。')),
                    _section(tr('角色设定'), resource.text('description')),
                    _section(tr('性格'), resource.text('personality')),
                    _section(tr('场景'), resource.text('scenario')),
                    if (resource.greetings.isNotEmpty)
                      _section(tr('开场白'), resource.greetings[_greeting]),
                    _section(tr('示例对话'), resource.text('mes_example')),
                  ],
                  if (resource.kind == 'character' &&
                      resource.entries.isNotEmpty)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.menu_book_outlined),
                      title: Text(tr('世界书')),
                      subtitle: Text(
                        tr('{count} 条世界书词条', {
                          'count': resource.entries.length,
                        }),
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: _openLorebook,
                    ),
                ],
              ),
            ),
    );
  }
}
