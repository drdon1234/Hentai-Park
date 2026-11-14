import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../../core/models.dart';
import '../../core/voice.dart';
import '../../library/downloads.dart';
import '../../library/offline_bundle.dart';
import '../nav.dart';
import '../theme.dart';
import '../video/video_page.dart';
import '../voice/voice_attachment_page.dart';
import '../widgets/common.dart';
import '../widgets/content_translation.dart';
import '../widgets/error_view.dart';
import '../widgets/platform_share.dart';
import '../widgets/text_translation.dart';

/// 下载页、书库和历史共用，只读取本地包，缺失资源不会回退到联网。
class OfflineBundlePage extends StatefulWidget {
  const OfflineBundlePage({
    super.key,
    required this.item,
    required this.chapterId,
  });
  final WorkItem item;
  final String chapterId;
  @override
  State<OfflineBundlePage> createState() => _OfflineBundlePageState();
}

class _OfflineBundlePageState extends State<OfflineBundlePage> {
  late Future<OfflineBundle?> _load = _read();
  Future<OfflineBundle?> _read() => DownloadManager.instance.localBundle(
    widget.item.source,
    widget.item.id,
    widget.chapterId,
  );

  @override
  Widget build(BuildContext context) => FutureBuilder<OfflineBundle?>(
    future: _load,
    builder: (context, state) {
      final bundle = state.data;
      return Scaffold(
        appBar: PageHeader(
          title: widget.item.title,
          actions: const [TranslationControls()],
        ),
        body: state.connectionState != ConnectionState.done
            ? const Center(child: LoadingIndicator())
            : bundle == null || state.hasError
            ? SourceErrorView(
                error: state.error ?? SourceError('NOT_FOUND', '本地文件已被删除'),
                source: widget.item.source,
                onRetry: () => setState(() => _load = _read()),
              )
            : _BundleBody(item: widget.item, bundle: bundle),
      );
    },
  );
}

class _BundleBody extends StatefulWidget {
  const _BundleBody({required this.item, required this.bundle});
  final WorkItem item;
  final OfflineBundle bundle;
  @override
  State<_BundleBody> createState() => _BundleBodyState();
}

class _BundleBodyState extends State<_BundleBody> {
  final _parents = <String>[];
  Future<void> _open(Map<String, dynamic> entry) async {
    if (entry['type'] == 'directory') {
      setState(() => _parents.add(entry['id'] as String));
      return;
    }
    if (const {'image', 'video'}.contains(entry['type'])) {
      final entries = widget.bundle.entries
          .where(
            (e) =>
                const {'image', 'video'}.contains(e['type']) &&
                e['parent'] == entry['parent'],
          )
          .toList();
      await Nav.push(
        context,
        _BundleGallery(
          item: widget.item,
          bundle: widget.bundle,
          entries: entries,
          initial: entries.indexWhere((e) => e['id'] == entry['id']),
        ),
      );
      return;
    }
    try {
      final file = await widget.bundle.file(entry);
      if (file == null) throw SourceError('NOT_FOUND', '本地文件已被删除');
      if (!mounted) return;
      if (entry['type'] == 'audio') {
        await Nav.push(
          context,
          VideoPage(
            work: _work(widget.item, widget.bundle, entry),
            episodeId: entry['id'] as String,
            downloadedOnly: true,
          ),
        );
      } else if (const {'subtitle', 'script'}.contains(entry['type'])) {
        await Nav.push(
          context,
          VoiceAttachmentPage(
            work: WorkDetail(widget.item.json, widget.item.source),
            node: VoiceNode(
              id: entry['id'] as String,
              name: entry['name'] as String,
              kind: VoiceNodeKind.fromJson(entry['type']),
            ),
            localFile: file,
            localFormat: entry['format']?.toString(),
          ),
        );
      } else {
        await shareContent(context, files: [XFile(file.path)]);
      }
    } catch (error) {
      if (mounted) context.toast(error.asSourceError.friendly);
    }
  }

  Widget _entry(Map<String, dynamic> entry) => ListTile(
    contentPadding: widget.bundle.blocks.isEmpty ? null : EdgeInsets.zero,
    leading: Icon(switch (entry['type']) {
      'directory' => Icons.folder_outlined,
      'audio' => Icons.audio_file_outlined,
      'video' => Icons.movie_outlined,
      'image' => Icons.image_outlined,
      'subtitle' => Icons.subtitles_outlined,
      _ => Icons.description_outlined,
    }),
    title: Text(entry['name']?.toString() ?? ''),
    subtitle: entry['type'] != 'directory' && entry['file'] == null
        ? Text(tr('未完成'))
        : null,
    onTap: () => _open(entry),
  );

  @override
  Widget build(BuildContext context) {
    final blocks = widget.bundle.blocks;
    final entries = widget.bundle.entries;
    final content = Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: blocks.isEmpty
            ? ListView(
                children: [
                  if (_parents.isNotEmpty)
                    ListTile(
                      leading: const Icon(Icons.arrow_upward),
                      title: Text(tr('返回上级目录')),
                      onTap: () => setState(() => _parents.removeLast()),
                    ),
                  for (final entry in entries.where(
                    (e) => e['parent'] == (_parents.lastOrNull),
                  ))
                    _entry(entry),
                ],
              )
            : ListView.builder(
                padding: const EdgeInsets.all(Gap.page),
                itemCount: blocks.length,
                itemBuilder: (context, index) {
                  final block = blocks[index];
                  if (block['type'] == 'text') {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: Gap.m),
                      child: TranslationSelectionArea(
                        child: ContentTranslation(
                          text: block['text']?.toString() ?? '',
                          source: widget.item.source,
                          builder: (text) => Text(
                            text,
                            style: context.text.bodyLarge?.copyWith(
                              height: 1.65,
                            ),
                          ),
                        ),
                      ),
                    );
                  }
                  final entry = entries
                      .where((e) => e['id'] == block['asset'])
                      .firstOrNull;
                  if (entry == null) return Text(tr('本地文件已被删除'));
                  if (entry['type'] != 'image') return _entry(entry);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: Gap.m),
                    child: FutureBuilder<File?>(
                      future: widget.bundle.file(entry),
                      builder: (context, state) => state.data == null
                          ? _entry(entry)
                          : ActionInkWell(
                              onTap: () => _open(entry),
                              child: Image.file(
                                state.data!,
                                width: double.infinity,
                                fit: BoxFit.fitWidth,
                                errorBuilder: (_, _, _) => _entry(entry),
                              ),
                            ),
                    ),
                  );
                },
              ),
      ),
    );
    return Column(
      children: [
        if (widget.bundle.json['previewOnly'] == true)
          Padding(
            padding: const EdgeInsets.all(Gap.page),
            child: Text(tr('受限内容，仅展示原站公开预览')),
          ),
        Expanded(child: content),
      ],
    );
  }
}

WorkDetail _work(WorkItem item, OfflineBundle bundle, Map entry) {
  final tracks = bundle.entries
      .where(
        (e) =>
            const {'audio', 'video'}.contains(e['type']) &&
            e['parent'] == entry['parent'],
      )
      .toList();
  return WorkDetail({
    ...item.json,
    'title': bundle.json['title'],
    'mediaKind': bundle.json['kind'] == 'voice' ? 'voice' : 'video',
    'chaptersComplete': false,
    'chapters': [
      for (final e in tracks) {'id': e['id'], 'title': e['name']},
    ],
    'voiceTrackKinds': {for (final e in tracks) e['id'] as String: e['type']},
    'voiceSubtitles': {
      for (final e in tracks)
        if (e['subtitleIds'] is List) e['id'] as String: e['subtitleIds'],
    },
  }, item.source);
}

class _BundleGallery extends StatefulWidget {
  const _BundleGallery({
    required this.item,
    required this.bundle,
    required this.entries,
    required this.initial,
  });
  final WorkItem item;
  final OfflineBundle bundle;
  final List<Map<String, dynamic>> entries;
  final int initial;
  @override
  State<_BundleGallery> createState() => _BundleGalleryState();
}

class _BundleGalleryState extends State<_BundleGallery> {
  late final _pages = PageController(initialPage: widget.initial);
  late int _index = widget.initial;
  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: PageHeader(title: widget.entries[_index]['name'] as String),
    body: PageView.builder(
      controller: _pages,
      itemCount: widget.entries.length,
      onPageChanged: (index) => setState(() => _index = index),
      itemBuilder: (context, index) {
        if (index != _index) return const SizedBox.shrink();
        final entry = widget.entries[index];
        return FutureBuilder<File?>(
          future: widget.bundle.file(entry),
          builder: (context, state) {
            final file = state.data;
            if (state.connectionState != ConnectionState.done) {
              return const Center(child: LoadingIndicator());
            }
            if (file == null) return Center(child: Text(tr('本地文件已被删除')));
            return entry['type'] == 'video'
                ? VideoPage(
                    key: ValueKey(entry['id']),
                    work: _work(widget.item, widget.bundle, entry),
                    episodeId: entry['id'] as String,
                    downloadedOnly: true,
                    pageHorizontally: true,
                  )
                : InteractiveViewer(child: Center(child: Image.file(file)));
          },
        );
      },
    ),
  );
}
