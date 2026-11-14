import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../../core/models.dart';
import '../../core/timed_subtitles.dart';
import '../../core/voice.dart';
import '../../engine/media_transport_factory.dart';
import '../../engine/source_manager.dart';
import '../kit/kit.dart';
import '../widgets/common.dart' show LoadingIndicator;
import '../widgets/content_translation.dart';
import '../widgets/error_view.dart';
import '../widgets/text_translation.dart';

/// 附件只在本次页面会话中读取，地址和正文不写入作品缓存。
class VoiceAttachmentPage extends StatefulWidget {
  const VoiceAttachmentPage({
    super.key,
    required this.work,
    required this.node,
    this.sourceManager,
    this.localFile,
    this.localFormat,
  });
  final WorkDetail work;
  final VoiceNode node;
  final SourceManager? sourceManager;
  final File? localFile;
  final String? localFormat;

  @override
  State<VoiceAttachmentPage> createState() => _VoiceAttachmentPageState();
}

class _VoiceAttachmentPageState extends State<VoiceAttachmentPage> {
  CancelToken? _cancel;
  Uint8List? _bytes;
  String? _text;
  List<TimedSubtitleCue>? _cues;
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
      _cues = null;
      _error = null;
    });
    try {
      if (widget.localFile case final file?) {
        if (await file.length() > 20 * 1024 * 1024) {
          throw SourceError('PARSE', '媒体资源过大');
        }
        final bytes = await file.readAsBytes();
        final text = widget.node.kind == VoiceNodeKind.image
            ? null
            : utf8.decode(bytes);
        final cues = widget.node.kind == VoiceNodeKind.subtitle
            ? TimedSubtitles.parse(text!, format: widget.localFormat ?? '').cues
            : null;
        if (mounted && !cancel.isCancelled) {
          setState(() {
            _bytes = bytes;
            _text = text;
            _cues = cues;
          });
        }
        return;
      }
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
        final cues = widget.node.kind == VoiceNodeKind.subtitle
            ? TimedSubtitles.parse(
                text!,
                format: resource.format.isNotEmpty
                    ? resource.format
                    : widget.node.name.split('.').last,
              ).cues
            : null;
        if (cues != null && cues.isEmpty) {
          throw SourceError('PARSE', '媒体数据无效');
        }
        if (mounted && !cancel.isCancelled) {
          setState(() {
            _bytes = result.bytes;
            _text = text;
            _cues = cues;
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
      final cues = _cues;
      final chunks = cues == null ? translationChunks(_text ?? '') : null;
      body = TranslationSelectionArea(
        child: ListView.builder(
          padding: const EdgeInsets.all(Gap.page),
          itemCount: cues?.length ?? chunks!.length,
          itemBuilder: (context, index) => cues == null
              ? TranslatedText(chunks![index])
              : Padding(
                  padding: const EdgeInsets.only(bottom: Gap.m),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(cues[index].start.toString()),
                      TranslatedText(cues[index].text),
                    ],
                  ),
                ),
        ),
      );
    }
    return Scaffold(
      appBar: PageHeader(
        title: widget.node.name,
        actions: [
          if (widget.node.kind != VoiceNodeKind.image)
            const TranslationControls(),
        ],
      ),
      body: body,
    );
  }
}
