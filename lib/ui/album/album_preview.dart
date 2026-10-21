import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/async_tasks.dart';
import '../../core/localization.dart';
import '../../engine/source_manager.dart';
import '../../images/subscription_cache.dart';
import '../../subscriptions/models.dart';
import '../widgets/common.dart';
import 'album_media.dart';

/// 缩略图和原附件分开读取，滚动相册不会下载完整视频。
class AlbumPreview extends StatefulWidget {
  const AlbumPreview({super.key, required this.entry});
  final AlbumMediaEntry entry;
  @override
  State<AlbumPreview> createState() => _AlbumPreviewState();
}

class _AlbumPreviewState extends State<AlbumPreview> {
  static final _queue = SerialExecutor();
  CancelToken _request = CancelToken();
  File? _file;
  bool _failed = false, _loading = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant AlbumPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry.work.source == widget.entry.work.source &&
        oldWidget.entry.preview == widget.entry.preview &&
        mapEquals(
          oldWidget.entry.media['previewResource'],
          widget.entry.media['previewResource'],
        )) {
      return;
    }
    _request.cancel();
    _request = CancelToken();
    if (_file case final file?) SubscriptionCache.instance.release(file);
    _file = null;
    _failed = false;
    _loading = false;
    unawaited(_load());
  }

  Future<void> _load() async {
    if (_loading) return;
    final entry = widget.entry;
    final resource = entry.media['previewResource'];
    if (entry.preview.isNotEmpty || resource is! Map) return;
    final size = resource['size'];
    if (size is! int || size < 1 || size > 2097152) {
      if (mounted) setState(() => _failed = true);
      return;
    }
    _loading = true;
    final request = _request;
    try {
      final file = await _queue.run(() async {
        if (request.cancelError case final error?) throw error;
        return SourceManager.instance.subscriptionMediaFile(
          entry.work.source,
          SubscriptionMedia({'type': 'image', 'resource': resource}),
          cancelToken: request,
        );
      });
      if (!mounted || request != _request || request.isCancelled) {
        SubscriptionCache.instance.release(file);
        return;
      }
      setState(() => _file = file);
    } catch (_) {
      if (mounted && request == _request && !request.isCancelled) {
        setState(() => _failed = true);
      }
    } finally {
      if (request == _request) _loading = false;
    }
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      CoverImage(
        source: widget.entry.work.source,
        url: _file?.uri.toString() ?? widget.entry.preview,
        radius: 0,
        sourceBlurred: widget.entry.media['blurred'] == true,
      ),
      if (_failed)
        Align(
          alignment: AlignmentDirectional.bottomEnd,
          child: IconButton(
            tooltip: tr('重试'),
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() => _failed = false);
              unawaited(_load());
            },
          ),
        ),
    ],
  );

  @override
  void dispose() {
    _request.cancel();
    if (_file case final file?) SubscriptionCache.instance.release(file);
    super.dispose();
  }
}
