import 'package:flutter/material.dart';

import '../../images/park_image.dart';

/// 独立封面使用解码后的原图比例；网格与缩略图仍可由父布局限制尺寸。
class AdaptiveCover extends StatefulWidget {
  const AdaptiveCover({
    super.key,
    required this.source,
    required this.url,
    required this.child,
    this.placeholderAspect = 1,
  });

  final String source, url;
  final Widget child;
  final double placeholderAspect;

  @override
  State<AdaptiveCover> createState() => _AdaptiveCoverState();
}

class _AdaptiveCoverState extends State<AdaptiveCover> {
  ImageStream? _stream;
  ImageStreamListener? _listener;
  double? _aspect;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(AdaptiveCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source || oldWidget.url != widget.url) {
      _aspect = null;
      _resolve();
    }
  }

  void _resolve() {
    _detach();
    if (widget.url.isEmpty) return;
    final stream = ResizeImage.resizeIfNeeded(
      1024,
      null,
      ParkImage.url(widget.source, widget.url),
    ).resolve(createLocalImageConfiguration(context));
    _stream = stream;
    _listener = ImageStreamListener((info, synchronous) {
      final aspect = info.image.width / info.image.height;
      info.dispose();
      if (!mounted || _aspect == aspect) return;
      if (synchronous) {
        _aspect = aspect;
      } else {
        setState(() => _aspect = aspect);
      }
    }, onError: (Object _, StackTrace? _) {});
    stream.addListener(_listener!);
  }

  void _detach() {
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: _aspect ?? widget.placeholderAspect,
    child: widget.child,
  );
}
