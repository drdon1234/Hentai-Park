import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../images/park_image.dart';
import '../../core/localization.dart';

/// Resolves a page image manually so the reader knows its real size (stable layout), can show a
/// numbered placeholder while loading, and can retry failed pages in place.
class ReaderImage extends StatefulWidget {
  const ReaderImage({
    super.key,
    required this.provider,
    required this.index,
    this.knownAspect,
    this.onAspect,
    this.fit = BoxFit.fitWidth,
    this.fillHeight = false,
    this.alignment = Alignment.center,
  });
  final ParkImage provider;
  final int index;
  final double? knownAspect;
  final ValueChanged<double>? onAspect;
  final BoxFit fit;
  final bool
  fillHeight; // paged mode: fill the viewport instead of sizing by width
  final Alignment alignment; // dual pages lean towards the spine

  @override
  State<ReaderImage> createState() => _ReaderImageState();
}

class _ReaderImageState extends State<ReaderImage> {
  ImageStream? _stream;
  ImageInfo? _info;
  Object? _error;
  late ImageStreamListener _listener;
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    _listener = ImageStreamListener(_onImage, onError: _onError);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(ReaderImage old) {
    super.didUpdateWidget(old);
    if (old.provider != widget.provider) _resolve();
  }

  void _resolve() {
    final stream = widget.provider.resolve(
      createLocalImageConfiguration(context),
    );
    if (stream.key == _stream?.key) return;
    _stream?.removeListener(_listener);
    _stream = stream..addListener(_listener);
  }

  void _onImage(ImageInfo info, bool sync) {
    final w = info.image.width, h = info.image.height;
    if (h > 0) widget.onAspect?.call(w / h);
    setState(() {
      _info?.dispose();
      _info = info;
      _error = null;
    });
  }

  void _onError(Object error, StackTrace? st) {
    if (mounted) setState(() => _error = error);
  }

  Future<void> _retry() async {
    _stream?.removeListener(_listener);
    _stream = null;
    await widget.provider.evict();
    setState(() {
      _error = null;
      _attempt++;
    });
    _resolve();
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    _info?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    AppLocalizations.of(context);
    final info = _info;
    if (info != null) {
      final img = RawImage(
        image: info.image,
        fit: widget.fit,
        alignment: widget.alignment,
        filterQuality: FilterQuality.medium,
        width: double.infinity,
        height: widget.fillHeight ? double.infinity : null,
      );
      if (widget.fillHeight) return img;
      return AspectRatio(
        aspectRatio: info.image.width / info.image.height,
        child: img,
      );
    }
    final aspect = widget.knownAspect ?? 0.7;
    final placeholder = Center(
      child: _error != null
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.broken_image_outlined,
                  color: Colors.white38,
                  size: 40,
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    tr('第 {value0} 页加载失败\n{value1}', {
                      'value0': widget.index + 1,
                      'value1': _error is SourceError
                          ? (_error as SourceError).message
                          : _error,
                    }),
                    textAlign: TextAlign.center,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ),
                const SizedBox(height: 10),
                FilledButton.tonalIcon(
                  onPressed: _retry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(_attempt > 0 ? tr('再试一次') : tr('重试')),
                ),
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: Colors.white38,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '${widget.index + 1}',
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
    );
    if (widget.fillHeight) return placeholder;
    return AspectRatio(aspectRatio: aspect, child: placeholder);
  }
}
