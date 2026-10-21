import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../../core/models.dart';
import '../../core/settings.dart';
import '../../engine/source_manager.dart';
import '../../images/park_image.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/on_visible.dart';

typedef ThumbnailLoader =
    Future<({List<PreviewThumb> thumbs, bool hasNext})> Function(int page);

/// Preview paging keeps local batches and remote pages in one sequence.
class ThumbnailPager extends ChangeNotifier {
  ThumbnailPager(this.detail, {this.loader}) {
    thumbs = detail.thumbnails.take(20).toList();
    hasMore =
        detail.thumbnails.length > thumbs.length ||
        (loader != null &&
            (detail.thumbnailsTotal ?? thumbs.length) > thumbs.length);
  }
  final WorkDetail detail;
  final ThumbnailLoader? loader;
  late List<PreviewThumb> thumbs;
  late bool hasMore;
  bool loading = false;
  bool automatic = false;
  Object? error;
  bool _disposed = false;
  int _page = 0;

  Future<void> more({bool fromUser = false}) async {
    if (_disposed ||
        loading ||
        !hasMore ||
        (!fromUser && (!automatic || error != null))) {
      return;
    }
    if (fromUser) automatic = true;
    error = null;
    if (detail.thumbnails.length > thumbs.length) {
      thumbs = detail.thumbnails.take(thumbs.length + 40).toList();
      hasMore =
          detail.thumbnails.length > thumbs.length ||
          (loader != null &&
              (detail.thumbnailsTotal ?? thumbs.length) > thumbs.length);
      notifyListeners();
      return;
    }
    if (loader == null) {
      hasMore = false;
      notifyListeners();
      return;
    }
    loading = true;
    notifyListeners();
    try {
      final result = await loader!(_page + 1);
      if (_disposed) return;
      final seen = thumbs.map(_identity).toSet();
      final added = result.thumbs
          .where((thumb) => seen.add(_identity(thumb)))
          .toList();
      thumbs = [...thumbs, ...added];
      _page++;
      hasMore = result.hasNext && added.isNotEmpty;
    } catch (failure) {
      if (_disposed) return;
      error = failure;
    } finally {
      if (!_disposed) {
        loading = false;
        notifyListeners();
      }
    }
  }

  String _identity(PreviewThumb thumb) => thumb.index != null
      ? 'index:${thumb.index}'
      : '${thumb.url}:${thumb.offsetX}:${thumb.offsetY}';

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Page preview grid. Supports plain thumbnails (nhentai) and sprite sheets (E-Hentai packs
/// up to 20 thumbnails into one image; each cell shows its own offset window).
class ThumbnailSection extends StatefulWidget {
  const ThumbnailSection({
    super.key,
    required this.detail,
    required this.onOpen,
  });
  final WorkDetail detail;
  final ValueChanged<int> onOpen;

  @override
  State<ThumbnailSection> createState() => _ThumbnailSectionState();
}

class _ThumbnailSectionState extends State<ThumbnailSection> {
  late ThumbnailPager _pager;

  @override
  void initState() {
    super.initState();
    _initPager();
  }

  void _initPager() {
    final d = widget.detail;
    _pager = ThumbnailPager(
      d,
      loader:
          SourceManager.instance.manifest(d.source)?.can('thumbnails') == true
          ? (page) => SourceManager.instance.thumbnails(d.source, d.id, page)
          : null,
    );
    _pager.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(ThumbnailSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.detail != widget.detail) {
      _pager.dispose();
      _initPager();
    }
  }

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  Future<void> _more({bool fromUser = false}) async {
    final pager = _pager;
    if (!fromUser && pager.error != null) return;
    await pager.more(fromUser: fromUser);
    final error = pager.error;
    if (mounted && identical(pager, _pager) && error != null) {
      context.toast(
        tr('预览加载失败：{value0}', {'value0': error.asSourceError.message}),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final thumbs = _pager.thumbs;
    if (thumbs.isEmpty) return const SizedBox.shrink();
    final blur = AppSettings.instance.blurCovers;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          tr('预览'),
          leading: Icon(
            Icons.grid_view_rounded,
            color: context.colors.primary,
            size: 20,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GridView.builder(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 110,
              childAspectRatio: 0.7,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: thumbs.length,
            itemBuilder: (context, i) {
              final t = thumbs[i];
              final index = t.index ?? i;
              return InkWell(
                borderRadius: Radii.small,
                onTap: () => widget.onOpen(index),
                child: SelectionContainer.disabled(
                  child: Column(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: Radii.small,
                          child: ColoredBox(
                            color: context.colors.surfaceContainerHigh,
                            child: t.isSprite
                                ? _Sprite(
                                    source: widget.detail.source,
                                    thumb: t,
                                  )
                                : CoverImage(
                                    source: widget.detail.source,
                                    url: t.url,
                                    radius: 0,
                                    blur: blur,
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${index + 1}',
                        style: context.text.labelSmall?.copyWith(
                          color: context.colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        if (_pager.hasMore)
          OnVisible(
            key: ValueKey(thumbs.length),
            onVisible: (visible) {
              if (visible) _more();
            },
            child: Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _pager.loading
                    ? const Padding(
                        padding: EdgeInsets.all(8),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : _pager.automatic && _pager.error == null
                    ? const SizedBox(height: 36)
                    : OutlinedButton.icon(
                        onPressed: () => _more(fromUser: true),
                        icon: const Icon(Icons.expand_more_rounded),
                        label: SelectionContainer.disabled(
                          child: Text(tr('加载更多预览')),
                        ),
                      ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Sprite extends StatelessWidget {
  const _Sprite({required this.source, required this.thumb});
  final String source;
  final PreviewThumb thumb;

  @override
  Widget build(BuildContext context) {
    final w = thumb.width!;
    final h = thumb.height!;
    return FittedBox(
      child: SizedBox(
        width: w,
        height: h,
        child: ClipRect(
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: 0,
            minHeight: 0,
            maxWidth: double.infinity,
            maxHeight: double.infinity,
            child: Transform.translate(
              offset: Offset(-thumb.offsetX, -thumb.offsetY),
              child: Image(
                image: ParkImage.url(source, thumb.url),
                alignment: Alignment.topLeft,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
