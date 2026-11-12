import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../../core/models.dart';
import '../../core/voice.dart';
import '../../engine/media_transport_factory.dart';
import '../../engine/source_manager.dart';
import '../kit/kit.dart';
import '../widgets/common.dart' show LoadingIndicator;
import '../widgets/error_view.dart';

/// 附件只在本次页面会话中读取，地址和正文不写入作品缓存。
class VoiceAttachmentPage extends StatefulWidget {
  const VoiceAttachmentPage({
    super.key,
    required this.work,
    required this.node,
    this.sourceManager,
  });
  final WorkDetail work;
  final VoiceNode node;
  final SourceManager? sourceManager;

  @override
  State<VoiceAttachmentPage> createState() => _VoiceAttachmentPageState();
}

class _VoiceAttachmentPageState extends State<VoiceAttachmentPage> {
  CancelToken? _cancel;
  Uint8List? _bytes;
  String? _text;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    _cancel?.cancel();
    final cancel = _cancel = CancelToken();
    setState(() {
      _bytes = null;
      _text = null;
      _error = null;
    });
    try {
      final manager = widget.sourceManager ?? SourceManager.instance;
      final source = manager.manifest(widget.work.source);
      if (source == null) throw SourceError('CONFIG', '媒体数据无效');
      final resource = await manager.voiceResource(
        widget.work.source,
        widget.work.id,
        widget.node.id,
        cancelToken: cancel,
      );
      final transport = createMediaTransport(source, initialUrl: resource.url);
      try {
        final result = await transport.fetch(
          resource.url,
          maxBytes: widget.node.kind == VoiceNodeKind.image
              ? 20 * 1024 * 1024
              : 2 * 1024 * 1024,
          cancelToken: cancel,
        );
        final text =
            widget.node.kind == VoiceNodeKind.script ||
                widget.node.kind == VoiceNodeKind.subtitle
            ? utf8.decode(result.bytes)
            : null;
        if (mounted && !cancel.isCancelled) {
          setState(() {
            _bytes = result.bytes;
            _text = text;
          });
        }
      } finally {
        await transport.close();
      }
    } catch (error) {
      if (mounted && !cancel.isCancelled) setState(() => _error = error);
    }
  }

  @override
  void dispose() {
    _cancel?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (_error case final error?) {
      body = SourceErrorView(
        error: error,
        source: widget.work.source,
        onRetry: _load,
      );
    } else if (_bytes == null) {
      body = const Center(child: LoadingIndicator());
    } else if (widget.node.kind == VoiceNodeKind.image) {
      body = Center(
        child: InteractiveViewer(
          child: Image.memory(
            _bytes!,
            errorBuilder: (_, _, _) => EmptyState(
              icon: Icons.broken_image_outlined,
              title: tr('图片加载失败'),
              actions: [TextButton(onPressed: _load, child: Text(tr('重试')))],
            ),
          ),
        ),
      );
    } else {
      body = SingleChildScrollView(
        padding: const EdgeInsets.all(Gap.page),
        child: SelectableText(_text ?? ''),
      );
    }
    return Scaffold(
      appBar: PageHeader(title: widget.node.name),
      body: body,
    );
  }
}
