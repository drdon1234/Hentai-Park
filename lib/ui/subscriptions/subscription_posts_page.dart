import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/localization.dart';
import '../../core/models.dart';
import '../../engine/source_manager.dart';
import '../../engine/domains.dart';
import '../../images/park_image.dart';
import '../../images/subscription_cache.dart';
import '../../images/image_store.dart';
import '../../subscriptions/models.dart';
import '../../subscriptions/subscription_store.dart';
import '../nav.dart';
import '../settings/source_settings_page.dart';
import '../video/video_page.dart';
import '../widgets/error_view.dart';
import '../theme.dart';
import '../widgets/on_visible.dart';
import '../widgets/text_translation.dart';

class SubscriptionWorkPage extends StatelessWidget {
  const SubscriptionWorkPage({super.key, required this.item});
  final WorkItem item;
  @override
  Widget build(BuildContext context) {
    final post = SubscriptionPost(item.json);
    return Scaffold(
      appBar: AppBar(title: Text(post.title)),
      body: ListView(
        children: [SubscriptionPostCard(source: item.source, post: post)],
      ),
    );
  }
}

class SubscriptionPostsPage extends StatefulWidget {
  const SubscriptionPostsPage({super.key, required this.entry});
  final SubscriptionEntry entry;
  @override
  State<SubscriptionPostsPage> createState() => _SubscriptionPostsPageState();
}

class _SubscriptionPostsPageState extends State<SubscriptionPostsPage> {
  final posts = <SubscriptionPost>[];
  String? cursor;
  bool loading = false, hasNext = true;
  Object? error;
  int generation = 0;
  CancelToken? request;
  String mediaType = 'all';
  String display = 'posts';
  int _emptyPages = 0;

  SubscriptionPost _visiblePost(SubscriptionPost post) => SubscriptionPost({
    'id': post.id,
    'title': post.title,
    'text': post.text,
    'date': post.date,
    'url': post.url,
    'locked': post.locked,
    'media': post.media
        .where(
          (m) =>
              (mediaType == 'all' || m.type == mediaType) &&
              (display == 'posts' || m.type == display),
        )
        .map((m) => m.json)
        .toList(),
  });
  bool _isVisible(SubscriptionPost post) =>
      (display == 'posts' && mediaType == 'all') || post.media.isNotEmpty;

  void _filter({String? type, String? mode}) => setState(() {
    if (type != null) mediaType = type;
    if (mode != null) display = mode;
    _emptyPages = 0;
  });
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    generation++;
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
      final p = await SourceManager.instance.subscriptionPosts(
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
        hasNext = p.hasNext && p.cursor != null && p.cursor != cursor;
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
    AppLocalizations.of(context);
    final manifest = SourceManager.instance.manifest(widget.entry.source);
    final visible = posts.map(_visiblePost).where(_isVisible).toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.entry.label),
        actions: [
          IconButton(
            tooltip: tr('账号与源设置'),
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
      body: RefreshIndicator(
        onRefresh: () => _load(refresh: true),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            Text(
              tr(
                (manifest?.json['subscription'] as Map?)?['hint']?.toString() ??
                    '无需登录即可保存订阅；媒体访问取决于原站权限。',
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final mode in const ['posts', 'image', 'video'])
                  ChoiceChip(
                    label: Text(
                      tr(switch (mode) {
                        'image' => '图集',
                        'video' => '视频集',
                        _ => '帖子',
                      }),
                    ),
                    selected: display == mode,
                    onSelected: (_) => _filter(mode: mode),
                  ),
              ],
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final type in const ['all', 'image', 'video'])
                  FilterChip(
                    label: Text(
                      tr(switch (type) {
                        'image' => '图片',
                        'video' => '视频',
                        _ => '全部',
                      }),
                    ),
                    selected: mediaType == type,
                    onSelected: (_) => _filter(type: type),
                  ),
              ],
            ),
            for (final post in visible)
              display == 'posts'
                  ? SubscriptionPostCard(
                      source: widget.entry.source,
                      post: post,
                    )
                  : Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (var i = 0; i < post.media.length; i++)
                            SubscriptionMediaTile(
                              source: widget.entry.source,
                              post: post,
                              index: i,
                            ),
                        ],
                      ),
                    ),
            if (error != null)
              SourceErrorView(
                error: error!,
                source: widget.entry.source,
                onRetry: () => _load(),
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
                  child: Text(tr('加载更多')),
                ),
              ),
          ],
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
  });
  final String source;
  final SubscriptionPost post;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (post.title.isNotEmpty)
            Text(post.title, style: Theme.of(context).textTheme.titleMedium),
          if (post.date.isNotEmpty)
            Text(post.date, style: Theme.of(context).textTheme.bodySmall),
          if (post.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: TranslationSelectionArea(child: Text(post.text)),
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
              child: TextButton(
                onPressed: () async {
                  final u = Uri.tryParse(post.url);
                  if (u?.scheme == 'https') {
                    try {
                      await launchUrl(u!, mode: LaunchMode.externalApplication);
                    } catch (_) {
                      if (context.mounted) {
                        context.toast(tr('无法打开链接'));
                      }
                    }
                  }
                },
                child: Text(tr('在原站打开')),
              ),
            ),
        ],
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
      child: InkWell(
        onTap: () => Nav.push(
          context,
          media.type == 'image'
              ? SubscriptionGalleryPage(
                  source: source,
                  post: post,
                  index: index,
                )
              : SubscriptionMediaPage(source: source, post: post, index: index),
        ),
        child: SizedBox(
          width: 136,
          height: 136,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (media.preview.isNotEmpty)
                Image(
                  image: ParkImage.url(source, media.preview),
                  fit: BoxFit.cover,
                  errorBuilder: (_, error, stack) =>
                      const Center(child: Icon(Icons.broken_image_outlined)),
                )
              else
                ColoredBox(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
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
          throw SourceError('CONFIG', '媒体地址不在源声明的 HTTPS 域名内');
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
    AppLocalizations.of(context);
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
          child: file != null
              ? Image.file(file!, errorBuilder: (_, e, s) => Text(tr('媒体数据无效')))
              : Image(
                  image: ParkImage.url(widget.source, media.url),
                  errorBuilder: (_, e, s) => Text(tr('媒体数据无效')),
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
