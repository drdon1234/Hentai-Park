import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/localization.dart';
import '../../core/models.dart';
import '../../core/settings.dart';
import '../../core/tag_blocklist.dart';
import '../../engine/domains.dart';
import '../../engine/source_manager.dart';
import '../../images/image_store.dart';
import '../../images/park_image.dart';
import '../../images/subscription_cache.dart';
import '../../subscriptions/models.dart';
import '../../subscriptions/subscription_store.dart';
import '../album/open_album.dart';
import '../comments/comments_page.dart';
import '../kit/kit.dart';
import '../nav.dart';
import '../settings/source_settings_page.dart';
import '../short_video/post_video_feed.dart';
import '../short_video/short_video_page.dart';
import '../theme.dart';
import '../video/video_page.dart';
import '../widgets/content_translation.dart';
import '../widgets/cover_tile.dart';
import '../widgets/error_view.dart';
import '../widgets/on_visible.dart';
import '../widgets/result_visibility.dart';
import '../widgets/text_translation.dart';

class SubscriptionWorkPage extends StatelessWidget {
  const SubscriptionWorkPage({super.key, required this.item, this.postScope});
  final WorkItem item;
  final PostVideoScope? postScope;
  @override
  Widget build(BuildContext context) {
    final post = SubscriptionPost(item.json);
    final page = Scaffold(
      appBar: AppBar(
        title: ContentTranslation(
          text: post.title,
          source: item.source,
          builder: Text.new,
        ),
        actions: [TranslationControls(source: item.source)],
      ),
      body: ListView(
        children: [
          Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: SubscriptionPostCard(
                source: item.source,
                post: post,
                selectable: true,
              ),
            ),
          ),
          CommentsEntry(
            source: item.source,
            workId: item.id,
            available: post.commentsAvailable,
            context: {'url': post.url},
          ),
        ],
      ),
    );
    return postScope == null
        ? page
        : PostVideoContext(scope: postScope!, child: page);
  }
}

class SubscriptionPostsPage extends StatefulWidget {
  const SubscriptionPostsPage({
    super.key,
    required this.entry,
    this.targetKind,
    this.sourceManager,
  });
  final SubscriptionEntry entry;
  final String? targetKind;
  final SourceManager? sourceManager;
  @override
  State<SubscriptionPostsPage> createState() => _SubscriptionPostsPageState();
}

class _SubscriptionPostsPageState extends State<SubscriptionPostsPage> {
  SourceManager get _sources => widget.sourceManager ?? SourceManager.instance;
  final posts = <SubscriptionPost>[];
  bool _hidePreviews = false;
  final _cursors = <String>{};
  String? cursor;
  bool loading = false, hasNext = true;
  Object? error;
  int generation = 0;
  CancelToken? request;
  String mediaType = 'all';
  int _emptyPages = 0;
  late final _filters = AppSettings.instance.watch(AppSettings.filterKeys);
  void _filtersChanged() {
    if (mounted) setState(() {});
  }

  SubscriptionPost _visiblePost(SubscriptionPost post) => SubscriptionPost({
    ...post.json,
    'id': post.id,
    'title': post.title,
    'text': post.text,
    'date': post.date,
    'url': post.url,
    'locked': post.locked,
    'media': post.media
        .where((m) => (mediaType == 'all' || m.type == mediaType))
        .map((m) => m.json)
        .toList(),
  });
  bool _isVisible(SubscriptionPost post) =>
      TagBlocklist.current().matchItem(
            WorkItem(post.json, widget.entry.source),
          ) ==
          null &&
      (mediaType == 'all' || post.media.isNotEmpty) &&
      (!_hidePreviews || !WorkItem(post.json, widget.entry.source).previewOnly);

  void _filter({String? type}) => setState(() {
    if (type != null) mediaType = type;
    _emptyPages = 0;
  });
  @override
  void initState() {
    super.initState();
    _filters.addListener(_filtersChanged);
    unawaited(_load());
  }

  @override
  void dispose() {
    generation++;
    _filters.removeListener(_filtersChanged);
    request?.cancel();
    super.dispose();
  }

  Future<void> _load({bool refresh = false}) async {
    if (!refresh && (loading || !hasNext)) return;
    if (refresh) {
      generation++;
      request?.cancel();
      cursor = null;
      hasNext = true;
      posts.clear();
      _cursors.clear();
      _emptyPages = 0;
    }
    final current = ++generation;
    final token = CancelToken();
    request = token;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final p = await _sources.subscriptionPosts(
        widget.entry.source,
        widget.entry.target,
        cursor: cursor,
        cancelToken: token,
      );
      if (!mounted || current != generation) return;
      setState(() {
        final ids = posts.map((p) => p.id).toSet();
        final added = p.items.where((p) => ids.add(p.id)).toList();
        posts.addAll(added);
        _emptyPages = added.any((p) => _isVisible(_visiblePost(p)))
            ? 0
            : _emptyPages + 1;
        final next = p.cursor;
        final invalid =
            p.hasNext && (next == null || next.isEmpty || !_cursors.add(next));
        hasNext = p.hasNext && !invalid;
        if (invalid) error = SourceError('PARSE', '分页链接无效');
        cursor = p.cursor;
      });
    } catch (e) {
      if (mounted && current == generation && !token.isCancelled) {
        setState(() => error = e);
      }
    } finally {
      if (mounted && current == generation) setState(() => loading = false);
    }
  }

  Future<void> _login() async {
    await Nav.push(context, SourceSettingsPage(sourceKey: widget.entry.source));
    if (mounted) await _load(refresh: true);
  }

  @override
  Widget build(BuildContext context) {
    final manifest = _sources.manifest(widget.entry.source);
    final visible = posts.map(_visiblePost).where(_isVisible).toList();
    final scope = PostVideoScope(
      source: widget.entry.source,
      title: widget.entry.label,
      target: widget.entry.target,
    );
    return PostVideoContext(
      scope: scope,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.entry.label),
          actions: [
            TranslationControls(source: widget.entry.source),
            if (manifest?.can('album') == true)
              IconButton(
                tooltip: tr('相册'),
                icon: const Icon(Icons.photo_library_outlined),
                onPressed: () => openMediaAlbum(
                  context,
                  source: widget.entry.source,
                  title: widget.entry.label,
                  scope: {'target': widget.entry.target},
                ),
              ),
            if (manifest?.json['postShortVideos'] == true)
              IconButton(
                tooltip: tr('短视频模式'),
                onPressed: () => Nav.push(
                  context,
                  ShortVideoPage(source: widget.entry.source, postScope: scope),
                ),
                icon: const Icon(Icons.smart_display_outlined),
              ),
            IconButton(
              tooltip: tr('账号与站点设置'),
              onPressed: _login,
              icon: const Icon(Icons.manage_accounts),
            ),
            IconButton(
              tooltip: tr('刷新'),
              onPressed: () => _load(refresh: true),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: ParkRefresh(
          showRefreshButton: false,
          onRefresh: () => _load(refresh: true),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              Gap.page,
              Gap.s,
              Gap.page,
              Gap.xl,
            ),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              Text(
                manifest?.copy.text(
                      (manifest.json['subscription']
                                  as Map?)?[widget.targetKind == 'community'
                                  ? 'communityHint'
                                  : 'hint']
                              ?.toString() ??
                          '无需登录即可保存订阅；媒体访问取决于原站权限。',
                    ) ??
                    tr('无需登录即可保存订阅；媒体访问取决于原站权限。'),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ResultVisibility(
                    hidePreviews: _hidePreviews,
                    onPreviews: (v) => setState(() {
                      _hidePreviews = v;
                      _emptyPages = 0;
                    }),
                  ),
                  for (final type in const ['all', 'image', 'video'])
                    SelectionChip(
                      label: tr(switch (type) {
                        'image' => '图片',
                        'video' => '视频',
                        _ => '全部',
                      }),
                      selected: mediaType == type,
                      onSelected: (_) => _filter(type: type),
                    ),
                ],
              ),
              for (final post in visible)
                SubscriptionPostCard(source: widget.entry.source, post: post),
              if (error != null)
                SourceErrorView(
                  error: error!,
                  source: widget.entry.source,
                  onRetry: () => _load(refresh: !hasNext),
                ),
              if (visible.isEmpty && !loading && error == null)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(tr(hasNext ? '本页没有匹配的内容，可继续加载' : '当前筛选下没有帖子或媒体')),
                ),
              if (loading)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (!loading && hasNext && error == null)
                OnVisible(
                  onVisible: (visible) {
                    if (visible && mounted && _emptyPages < 3) _load();
                  },
                  child: OutlinedButton(
                    onPressed: () {
                      _emptyPages = 0;
                      _load();
                    },
                    child: SelectionContainer.disabled(child: Text(tr('加载更多'))),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class SubscriptionPostCard extends StatelessWidget {
  const SubscriptionPostCard({
    super.key,
    required this.source,
    required this.post,
    this.selectable = false,
  });
  final String source;
  final SubscriptionPost post;
  final bool selectable;
  @override
  Widget build(BuildContext context) => Card(
    child: ActionInkWell(
      onLongPress: selectable
          ? null
          : () => showWorkActions(context, WorkItem(post.json, source)),
      child: Padding(
        padding: const EdgeInsets.all(Gap.page),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (post.title.isNotEmpty)
              ContentTranslation(
                text: post.title,
                source: source,
                builder: (value) =>
                    Text(value, style: Theme.of(context).textTheme.titleMedium),
              ),
            if (post.date.isNotEmpty)
              Text(post.date, style: Theme.of(context).textTheme.bodySmall),
            if (post.text.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: selectable
                    ? TranslationSelectionArea(
                        child: ContentTranslation(
                          text: post.text,
                          source: source,
                          builder: Text.new,
                        ),
                      )
                    : ContentTranslation(
                        text: post.text,
                        source: source,
                        builder: Text.new,
                      ),
              ),
            if (post.locked ||
                post.media.any((m) => m.json['previewOnly'] == true))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  tr(
                    post.locked
                        ? '受限内容，仅展示原站公开预览'
                        : post.media.any(
                            (m) =>
                                m.type == 'video' &&
                                m.json['previewOnly'] == true,
                          )
                        ? '公开视频预览，可在应用内播放；完整内容取决于原站权限'
                        : '公开预览，完整内容请到原站查看',
                  ),
                ),
              ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < post.media.length; i++)
                  SubscriptionMediaTile(source: source, post: post, index: i),
              ],
            ),
            if (post.url.isNotEmpty)
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: OutlinedButton(
                  onPressed: () async {
                    final u = Uri.tryParse(post.url);
                    if (u?.scheme == 'https') {
                      try {
                        await launchUrl(
                          u!,
                          mode: LaunchMode.externalApplication,
                        );
                      } catch (_) {
                        if (context.mounted) {
                          context.toast(tr('无法打开链接'));
                        }
                      }
                    }
                  },
                  child: SelectionContainer.disabled(child: Text(tr('在原站打开'))),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class SubscriptionMediaTile extends StatelessWidget {
  const SubscriptionMediaTile({
    super.key,
    required this.source,
    required this.post,
    required this.index,
  });
  final String source;
  final SubscriptionPost post;
  final int index;
  @override
  Widget build(BuildContext context) {
    final media = post.media[index];
    return Semantics(
      button: true,
      label: tr(media.type == 'video' ? '播放视频' : '查看图片'),
      child: ActionInkWell(
        onLongPress: () =>
            showWorkActions(context, WorkItem(post.json, source)),
        onTap: () async {
          if (media.type == 'video' &&
              !media.needsDownload &&
              SourceManager.instance.manifest(source)?.feeds.isNotEmpty ==
                  true) {
            await Nav.openWork(
              context,
              WorkItem({
                ...post.json,
                'id': post.id,
                'title': post.title,
                'text': post.text,
                'url': post.url,
                'date': post.date,
                'mediaKind': 'video',
                if (SourceManager.instance
                        .manifest(source)
                        ?.json['postShortVideos'] ==
                    true)
                  'postVideoIndex': post.media
                      .take(index)
                      .where((m) => m.type == 'video')
                      .length,
                'cover': media.preview,
                'media': [
                  media.json,
                  for (var i = 0; i < post.media.length; i++)
                    if (i != index &&
                        SourceManager.instance
                                .manifest(source)
                                ?.json['postShortVideos'] !=
                            true)
                      post.media[i].json,
                ],
              }, source),
            );
            return;
          }
          await Nav.push(
            context,
            media.type == 'image'
                ? SubscriptionGalleryPage(
                    source: source,
                    post: post,
                    index: index,
                  )
                : SubscriptionMediaPage(
                    source: source,
                    post: post,
                    index: index,
                  ),
          );
        },
        child: SelectionContainer.disabled(
          child: SizedBox(
            width: 136,
            height: 136,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (media.preview.isNotEmpty)
                  ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                    enabled: media.json['blurred'] == true,
                    child: Image(
                      image: ParkImage.url(source, media.preview),
                      fit: BoxFit.cover,
                      errorBuilder: (_, error, stack) => const Center(
                        child: Icon(Icons.broken_image_outlined),
                      ),
                    ),
                  )
                else
                  ColoredBox(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                  ),
                if (media.type == 'video' || media.preview.isEmpty)
                  Center(
                    child: Icon(
                      media.type == 'video'
                          ? Icons.play_circle
                          : Icons.image_outlined,
                      size: 40,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SubscriptionGalleryPage extends StatefulWidget {
  const SubscriptionGalleryPage({
    super.key,
    required this.source,
    required this.post,
    required this.index,
  });
  final String source;
  final SubscriptionPost post;
  final int index;
  @override
  State<SubscriptionGalleryPage> createState() =>
      _SubscriptionGalleryPageState();
}

class _SubscriptionGalleryPageState extends State<SubscriptionGalleryPage> {
  late final List<int> _images = [
    for (var i = 0; i < widget.post.media.length; i++)
      if (widget.post.media[i].type == 'image') i,
  ];
  late int _index = _images.indexOf(widget.index);
  late final PageController _pages = PageController(initialPage: _index);
  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('${widget.post.title}  ${_index + 1}/${_images.length}'),
    ),
    body: PageView.builder(
      controller: _pages,
      itemCount: _images.length,
      onPageChanged: (index) => setState(() => _index = index),
      itemBuilder: (_, index) => SubscriptionMediaPage(
        key: ValueKey(_images[index]),
        source: widget.source,
        post: widget.post,
        index: _images[index],
        embedded: true,
      ),
    ),
  );
}

class SubscriptionMediaPage extends StatefulWidget {
  const SubscriptionMediaPage({
    super.key,
    required this.source,
    required this.post,
    required this.index,
    this.embedded = false,
  });
  final String source;
  final SubscriptionPost post;
  final int index;
  final bool embedded;
  @override
  State<SubscriptionMediaPage> createState() => _SubscriptionMediaPageState();
}

class _SubscriptionMediaPageState extends State<SubscriptionMediaPage> {
  final request = CancelToken();
  File? file;
  Object? error;
  double? progress;
  bool loading = true;
  bool _loadStarted = false;
  SubscriptionMedia get media => widget.post.media[widget.index];
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    request.cancel();
    if (file != null) SubscriptionCache.instance.release(file!);
    unawaited(ImageStore.instance.trim());
    super.dispose();
  }

  Future<void> _load() async {
    if (_loadStarted) return;
    _loadStarted = true;
    if (file != null) {
      SubscriptionCache.instance.release(file!);
      file = null;
    }
    setState(() {
      loading = true;
      error = null;
      progress = null;
    });
    try {
      if (!media.needsDownload) {
        final uri = Uri.tryParse(media.url);
        final manifest = SourceManager.instance.manifest(widget.source);
        if (uri == null ||
            manifest == null ||
            uri.scheme != 'https' ||
            uri.userInfo.isNotEmpty ||
            uri.port != 443 ||
            !hostInDomains(uri.host, declaredDomains(manifest.json))) {
          throw SourceError('CONFIG', '媒体地址不在站点声明的 HTTPS 域名内');
        }
      }
      if (media.needsDownload) {
        file = await SourceManager.instance.subscriptionMediaFile(
          widget.source,
          media,
          cancelToken: request,
          onProgress: (done, total) {
            if (mounted) setState(() => progress = done / total);
          },
        );
      }
      if (!mounted) {
        if (file != null) SubscriptionCache.instance.release(file!);
        unawaited(ImageStore.instance.trim());
        return;
      }
      if (media.type == 'video') {
        final work = WorkDetail({
          'id': 'subscription:${widget.post.id}:${widget.index}',
          'title': widget.post.title,
          'cover': media.preview,
          'url': widget.post.url,
        }, widget.source);
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => VideoPage(
              work: work,
              localFile: file,
              recordHistory: false,
              initialSources: media.needsDownload
                  ? null
                  : [
                      VideoSource({
                        'url': media.url,
                        'format': media.json['format'] ?? 'mp4',
                        'headers': media.json['headers'] ?? {},
                      }),
                    ],
            ),
          ),
        );
      } else {
        setState(() => loading = false);
      }
    } catch (e) {
      if (mounted && !request.isCancelled) {
        setState(() {
          error = e;
          loading = false;
        });
      }
    } finally {
      _loadStarted = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (error != null) {
      body = SourceErrorView(
        error: error!,
        source: widget.source,
        onRetry: _load,
      );
    } else if (loading) {
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(value: progress),
            const SizedBox(height: 12),
            Text(tr('正在读取媒体')),
          ],
        ),
      );
    } else {
      body = InteractiveViewer(
        minScale: 0.5,
        maxScale: 8,
        child: Center(
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
            enabled: media.json['blurred'] == true,
            child: file != null
                ? Image.file(
                    file!,
                    errorBuilder: (_, e, s) => Text(tr('媒体数据无效')),
                  )
                : Image(
                    image: ParkImage.url(widget.source, media.url),
                    errorBuilder: (_, e, s) => Text(tr('媒体数据无效')),
                  ),
          ),
        ),
      );
    }
    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.post.title.isEmpty ? tr('订阅媒体') : widget.post.title),
      ),
      body: body,
    );
  }
}
