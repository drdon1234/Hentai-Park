import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../../core/models.dart';
import '../../engine/source_manager.dart';
import '../../images/park_image.dart';
import '../../library/library.dart';
import '../../subscriptions/models.dart';
import '../library/favorite_actions.dart';
import '../nav.dart';
import '../search/source_link_search_page.dart';
import '../subscriptions/subscription_posts_page.dart';
import '../theme.dart';
import '../video/video_page.dart';
import '../widgets/common.dart';
import '../widgets/content_translation.dart';
import '../widgets/cover_tile.dart';
import '../widgets/error_view.dart';
import '../widgets/text_translation.dart';

class FeedArticleTile extends StatelessWidget {
  const FeedArticleTile({
    super.key,
    required this.item,
    this.showSource = false,
  });
  final WorkItem item;
  final bool showSource;

  @override
  Widget build(BuildContext context) {
    final metadata = [
      if (showSource)
        SourceManager.instance.manifest(item.source)?.name ?? item.source,
      if (item.uploaded.isNotEmpty) item.uploaded,
    ];
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: MergeSemantics(
          child: SelectionContainer.disabled(
            child: ActionInkWell(
              onTap: () => Nav.openWork(context, item),
              onLongPress: () => showWorkActions(context, item),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Gap.page,
                  vertical: Gap.m,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ContentTranslation(
                      text: item.title,
                      source: item.source,
                      builder: (text) => Text(
                        text,
                        style: ParkText.serif(context.text.titleMedium),
                      ),
                    ),
                    if (metadata.isNotEmpty) ...[
                      const SizedBox(height: Gap.xs),
                      Text(
                        metadata.join(' · '),
                        style: context.text.bodySmall?.copyWith(
                          color: context.colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (item.cover.isNotEmpty) ...[
                      const SizedBox(height: Gap.s),
                      AspectRatio(
                        aspectRatio: (item.coverAspect ?? 16 / 9).clamp(1, 2),
                        child: CoverImage(
                          source: item.source,
                          url: item.cover,
                          title: item.title,
                        ),
                      ),
                    ],
                    const SizedBox(height: Gap.m),
                    const Divider(height: 1),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class FeedArticlePage extends StatefulWidget {
  const FeedArticlePage({super.key, required this.item, this.sourceManager});
  final WorkItem item;
  final SourceManager? sourceManager;

  @override
  State<FeedArticlePage> createState() => _FeedArticlePageState();
}

class _FeedArticlePageState extends State<FeedArticlePage> {
  final _cancel = CancelToken();
  SourceManager get _sources => widget.sourceManager ?? SourceManager.instance;
  WorkDetail? _detail;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _cancel.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await _sources.detail(
        widget.item.source,
        widget.item.id,
        preview: widget.item,
        cancelToken: _cancel,
      );
      if (mounted) {
        Library.instance.recordVisit(_snapshot(detail));
        setState(() => _detail = detail);
      }
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  WorkItem _snapshot(WorkDetail detail) => WorkItem({
    'id': detail.id,
    'title': detail.title,
    'cover': detail.cover.isEmpty ? widget.item.cover : detail.cover,
    'uploaded': detail.uploaded.isEmpty
        ? widget.item.uploaded
        : detail.uploaded,
    'tags': detail.tags,
    'mediaKind': 'article',
    'contentDomain': 'feed',
  }, detail.source);

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    final blocks = (detail?.json['blocks'] as List? ?? const [])
        .whereType<Map>()
        .map((block) => block.cast<String, dynamic>())
        .toList();
    final imageBlocks = blocks
        .where((block) => block['type'] == 'image')
        .toList();
    var nextImage = 0;
    final imageIndices = <int, int>{
      for (var i = 0; i < blocks.length; i++)
        if (blocks[i]['type'] == 'image') i: nextImage++,
    };
    final tagLinks = (detail?.json['tagLinks'] as List? ?? const [])
        .whereType<Map>()
        .where((tag) => tag['name'] is String && tag['url'] is String)
        .toList();
    final post = SubscriptionPost({
      'id': widget.item.id,
      'title': detail?.title ?? widget.item.title,
      'media': [
        for (final block in imageBlocks)
          {'type': 'image', 'url': block['url'], 'preview': block['url']},
      ],
    });
    return Scaffold(
      appBar: AppBar(
        title: Text(_sources.manifest(widget.item.source)?.name ?? tr('吃瓜')),
        actions: [
          TranslationControls(source: widget.item.source),
          ListenableBuilder(
            listenable: Library.instance.work(widget.item.uid),
            builder: (context, _) {
              final favorite = Library.instance.isFavorite(widget.item.uid);
              return IconButton(
                tooltip: tr(favorite ? '取消应用内收藏' : '应用内收藏'),
                icon: Icon(favorite ? Icons.bookmark : Icons.bookmark_border),
                onPressed: () => toggleFavorite(
                  context,
                  detail == null ? widget.item : _snapshot(detail),
                ),
              );
            },
          ),
        ],
      ),
      body: _loading
          ? const LoadingIndicator()
          : _error != null
          ? SourceErrorView(
              error: _error!,
              source: widget.item.source,
              onRetry: _load,
            )
          : SafeArea(
              top: false,
              child: TranslationSelectionArea(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: ListView.builder(
                      padding: const EdgeInsets.all(Gap.page),
                      itemCount: 1 + blocks.length + (tagLinks.isEmpty ? 0 : 1),
                      itemBuilder: (context, position) {
                        if (position == 0) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ContentTranslation(
                                text: detail!.title,
                                source: widget.item.source,
                                builder: (text) => Text(
                                  text,
                                  style: ParkText.serif(
                                    context.text.headlineSmall,
                                  ),
                                ),
                              ),
                              if (detail.uploaded.isNotEmpty) ...[
                                const SizedBox(height: Gap.s),
                                Text(
                                  detail.uploaded,
                                  style: context.text.bodySmall?.copyWith(
                                    color: context.colors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                              const SizedBox(height: Gap.l),
                            ],
                          );
                        }
                        if (position <= blocks.length) {
                          final index = position - 1;
                          final block = blocks[index];
                          if (block['type'] == 'text') {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: Gap.m),
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
                            );
                          }
                          if (block['type'] == 'image') {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: Gap.m),
                              child: ActionInkWell(
                                onTap: () => Nav.push(
                                  context,
                                  SubscriptionGalleryPage(
                                    source: widget.item.source,
                                    post: post,
                                    index: imageIndices[index]!,
                                  ),
                                ),
                                child: _ArticleImage(
                                  source: widget.item.source,
                                  url: block['url'].toString(),
                                ),
                              ),
                            );
                          }
                          if (block['type'] != 'video') {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(bottom: Gap.m),
                            child: SelectionContainer.disabled(
                              child: OutlinedButton.icon(
                                onPressed: () => Nav.push(
                                  context,
                                  VideoPage(
                                    work: WorkDetail({
                                      ...detail!.json,
                                      'chapters': null,
                                      'singleChapterId': block['id'],
                                    }, detail.source),
                                    episodeId: block['id']?.toString(),
                                    recordHistory: false,
                                  ),
                                ),
                                icon: const Icon(Icons.play_arrow_rounded),
                                label: Text(tr('播放视频')),
                              ),
                            ),
                          );
                        }
                        return SelectionContainer.disabled(
                          child: LayoutBuilder(
                            builder: (context, constraints) => Wrap(
                              spacing: Gap.s,
                              runSpacing: Gap.s,
                              children: [
                                for (final tag in tagLinks)
                                  ActionChip(
                                    tooltip: tag['name'] as String,
                                    label: ConstrainedBox(
                                      constraints: BoxConstraints(
                                        maxWidth: (constraints.maxWidth - 32)
                                            .clamp(0, 728),
                                      ),
                                      child: ContentTranslation(
                                        text: tag['name'] as String,
                                        source: widget.item.source,
                                        tag: true,
                                        builder: (value) => Text(
                                          value,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                    onPressed: () => Nav.push(
                                      context,
                                      SourceLinkSearchPage(
                                        source: widget.item.source,
                                        url: tag['url'] as String,
                                        manager:
                                            widget.sourceManager ??
                                            SourceManager.instance,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

/// 图片失败在原位重试，不重载正文或丢失阅读位置。
class _ArticleImage extends StatefulWidget {
  const _ArticleImage({required this.source, required this.url});
  final String source;
  final String url;

  @override
  State<_ArticleImage> createState() => _ArticleImageState();
}

class _ArticleImageState extends State<_ArticleImage> {
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: Radii.small,
    child: Image(
      image: ParkImage.url(widget.source, widget.url),
      fit: BoxFit.contain,
      loadingBuilder: (context, child, progress) => progress == null
          ? child
          : const SizedBox(height: 180, child: LoadingIndicator()),
      errorBuilder: (context, error, stack) => SelectionContainer.disabled(
        child: SizedBox(
          height: 180,
          child: Center(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.refresh_rounded),
              label: Text(tr('重试')),
              onPressed: () async {
                await ParkImage.url(widget.source, widget.url).evict();
                if (mounted) setState(() {});
              },
            ),
          ),
        ),
      ),
    ),
  );
}
