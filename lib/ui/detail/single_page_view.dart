import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../../core/models.dart';
import '../../engine/source_manager.dart';
import '../../images/park_image.dart';
import '../../library/downloads.dart';
import '../widgets/common.dart';
import '../widgets/error_view.dart';

/// 只有一页图片的作品直接在详情中显示，点按进入全屏阅读。
class SinglePageView extends StatefulWidget {
  const SinglePageView({super.key, required this.detail, required this.onOpen});
  final WorkDetail detail;
  final VoidCallback onOpen;

  @override
  State<SinglePageView> createState() => _SinglePageViewState();
}

class _SinglePageViewState extends State<SinglePageView> {
  CancelToken? _request;
  PageImage? _page;
  Object? _error;

  String? get _chapterId =>
      widget.detail.chapters?.singleOrNull?.id ?? widget.detail.singleChapterId;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _request?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    _request?.cancel();
    final request = _request = CancelToken();
    final d = widget.detail;
    setState(() {
      _page = null;
      _error = null;
    });
    try {
      final pages =
          await DownloadManager.instance.localChapter(
            d.source,
            d.id,
            _chapterId ?? '_',
          ) ??
          (await SourceManager.instance.chapter(
            d.source,
            d.id,
            _chapterId,
            cancelToken: request,
          )).pages;
      if (!mounted || request.isCancelled) return;
      if (pages.isEmpty) throw SourceError('NOT_FOUND', '暂无章节');
      setState(() => _page = pages.first);
    } catch (e) {
      if (mounted && !request.isCancelled) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.detail;
    final page = _page;
    final Widget child;
    if (_error != null) {
      child = SourceErrorView(
        error: _error!,
        source: d.source,
        onRetry: _load,
        compact: true,
      );
    } else if (page == null) {
      child = AspectRatio(
        aspectRatio: d.coverAspect ?? .7,
        child: const Skeleton(),
      );
    } else {
      child = Semantics(
        button: true,
        label: tr('全屏查看'),
        child: GestureDetector(
          onTap: widget.onOpen,
          child: ClipRRect(
            borderRadius: Radii.medium,
            child: Image(
              image: ParkImage.page(d.source, d.id, _chapterId, 0, page),
              width: double.infinity,
              fit: BoxFit.fitWidth,
              frameBuilder: (context, child, frame, synchronous) =>
                  frame == null && !synchronous
                  ? AspectRatio(
                      aspectRatio: page.aspect ?? d.coverAspect ?? .7,
                      child: const Skeleton(),
                    )
                  : child,
              errorBuilder: (_, _, _) => SourceErrorView(
                error: SourceError('NETWORK', '图片加载失败'),
                source: d.source,
                onRetry: _load,
                compact: true,
              ),
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.page, Gap.s, Gap.page, Gap.m),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: child,
        ),
      ),
    );
  }
}
