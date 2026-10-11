import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/settings.dart';
import '../../engine/source_manager.dart';
import '../../images/park_image.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Page preview grid. Supports plain thumbnails (nhentai) and sprite sheets (E-Hentai packs
/// up to 20 thumbnails into one image; each cell shows its own offset window).
class ThumbnailSection extends StatefulWidget {
  const ThumbnailSection({super.key, required this.detail, required this.onOpen});
  final WorkDetail detail;
  final ValueChanged<int> onOpen;

  @override
  State<ThumbnailSection> createState() => _ThumbnailSectionState();
}

class _ThumbnailSectionState extends State<ThumbnailSection> {
  late List<PreviewThumb> _thumbs = widget.detail.thumbnails.take(_initial).toList();
  bool _hasMore = false;
  bool _loading = false;
  int _page = 0;

  static const _initial = 20;

  @override
  void initState() {
    super.initState();
    final total = widget.detail.thumbnailsTotal ?? widget.detail.thumbnails.length;
    _hasMore = widget.detail.thumbnails.length > _initial || total > _thumbs.length;
  }

  Future<void> _more() async {
    final d = widget.detail;
    if (d.thumbnails.length > _thumbs.length) {
      setState(() => _thumbs = d.thumbnails.take(_thumbs.length + 40).toList());
      _hasMore = d.thumbnails.length > _thumbs.length;
      return;
    }
    if (SourceManager.instance.manifest(d.source)?.can('thumbnails') != true) return;
    setState(() => _loading = true);
    try {
      final res = await SourceManager.instance.thumbnails(d.source, d.id, ++_page);
      setState(() {
        _thumbs = [..._thumbs, ...res.thumbs];
        _hasMore = res.hasNext;
      });
    } catch (e) {
      _page--;
      if (mounted) context.toast('预览加载失败：${e.asSourceError.message}');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_thumbs.isEmpty) return const SizedBox.shrink();
    final blur = AppSettings.instance.blurCovers;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader('预览', leading: Icon(Icons.grid_view_rounded, color: context.colors.primary, size: 20)),
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
            itemCount: _thumbs.length,
            itemBuilder: (context, i) {
              final t = _thumbs[i];
              final index = t.index ?? i;
              return InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => widget.onOpen(index),
                child: Column(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: ColoredBox(
                          color: context.colors.surfaceContainerHigh,
                          child: t.isSprite
                              ? _Sprite(source: widget.detail.source, thumb: t)
                              : CoverImage(source: widget.detail.source, url: t.url, radius: 0, blur: blur),
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text('${index + 1}', style: context.text.labelSmall?.copyWith(color: context.colors.onSurfaceVariant)),
                  ],
                ),
              );
            },
          ),
        ),
        if (_hasMore)
          Center(
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(8),
                      child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : TextButton.icon(onPressed: _more, icon: const Icon(Icons.expand_more_rounded), label: const Text('加载更多预览')),
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
      fit: BoxFit.contain,
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
              child: Image(image: ParkImage.url(source, thumb.url), filterQuality: FilterQuality.medium, alignment: Alignment.topLeft),
            ),
          ),
        ),
      ),
    );
  }
}
