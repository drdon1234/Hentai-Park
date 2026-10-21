import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../../core/models.dart';
import '../../core/reverse_search.dart';
import '../../engine/http_service.dart';
import '../kit/tokens.dart';
import '../theme.dart';
import '../widgets/content_translation.dart';
import '../widgets/text_translation.dart';

class ReverseSearchResult extends StatelessWidget {
  const ReverseSearchResult({
    super.key,
    required this.source,
    required this.match,
    required this.onOpen,
    required this.onSearch,
  });
  final String source;
  final ReverseSearchMatch match;
  final void Function(String) onOpen, onSearch;

  String _time(double value) {
    final seconds = value.floor();
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  String _score(double value) =>
      value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final metadata = context.text.bodySmall?.copyWith(
      color: colors.onSurfaceVariant,
    );
    return TranslationSelectionArea(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: Gap.xl),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: colors.outlineVariant)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ResultText(
              text: match.title,
              source: source,
              style: ParkText.serif(context.text.titleLarge),
            ),
            if (match.similarity != null ||
                match.episode.isNotEmpty ||
                match.from != null ||
                match.to != null) ...[
              const SizedBox(height: Gap.s),
              Wrap(
                spacing: Gap.l,
                runSpacing: Gap.xs,
                children: [
                  if (match.similarity != null)
                    Text(
                      tr('相似度 {score}%', {'score': _score(match.similarity!)}),
                      style: metadata?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  if (match.episode.isNotEmpty)
                    Text(
                      tr('第 {episode} 集', {'episode': match.episode}),
                      style: metadata,
                    ),
                  if (match.from != null || match.to != null)
                    Text(
                      [
                        if (match.from != null) _time(match.from!),
                        if (match.to != null) _time(match.to!),
                      ].join(' – '),
                      style: metadata,
                    ),
                ],
              ),
            ],
            if (match.uncertain) ...[
              const SizedBox(height: Gap.m),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 18,
                    color: colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: Gap.s),
                  Expanded(child: Text(tr('服务标记为低可信候选，请核对'), style: metadata)),
                ],
              ),
            ],
            if (match.description.isNotEmpty) ...[
              const SizedBox(height: Gap.m),
              _ResultText(
                text: match.description,
                source: source,
                style: context.text.bodyMedium,
              ),
            ],
            if (match.images.isNotEmpty) ...[
              const SizedBox(height: Gap.l),
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = (constraints.maxWidth / 260).floor().clamp(
                    1,
                    match.images.length.clamp(1, 3),
                  );
                  final width =
                      (constraints.maxWidth - Gap.m * (columns - 1)) / columns;
                  return Wrap(
                    spacing: Gap.m,
                    runSpacing: Gap.m,
                    children: [
                      for (var i = 0; i < match.images.length; i++)
                        SizedBox(
                          width: width,
                          child: _ResultImage(
                            key: ValueKey((source, i, match.images[i].url)),
                            source: source,
                            image: match.images[i],
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
            const SizedBox(height: Gap.m),
            SelectionContainer.disabled(
              child: Wrap(
                spacing: Gap.s,
                runSpacing: Gap.s,
                children: [
                  if (match.keyword.isNotEmpty)
                    OutlinedButton.icon(
                      onPressed: () => onSearch(match.keyword),
                      icon: const Icon(Icons.search, size: 18),
                      label: Text(tr('搜索资源')),
                    ),
                  if (match.url.isNotEmpty)
                    TextButton.icon(
                      onPressed: () => onOpen(match.url),
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: Text(tr('原站')),
                    ),
                ],
              ),
            ),
            if (match.details.isNotEmpty)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: SelectionContainer.disabled(
                  child: Text(tr('原站信息'), style: context.text.bodySmall),
                ),
                children: [
                  for (final entry in match.details.entries)
                    _DetailValue(
                      source: source,
                      label: entry.key,
                      value: entry.value,
                      onOpen: onOpen,
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _ResultText extends StatelessWidget {
  const _ResultText({required this.text, required this.source, this.style});
  final String text, source;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final chunk in translationChunks(text))
        ContentTranslation(
          text: chunk,
          source: source,
          builder: (value) => Text(value, style: style),
        ),
    ],
  );
}

class _DetailValue extends StatelessWidget {
  const _DetailValue({
    required this.source,
    required this.label,
    required this.value,
    required this.onOpen,
  });
  final String source, label;
  final Object? value;
  final void Function(String) onOpen;

  @override
  Widget build(BuildContext context) {
    final entries = switch (value) {
      final Map<String, Object?> map => map.entries.toList(),
      final List list => [
        for (var i = 0; i < list.length; i++) MapEntry('${i + 1}', list[i]),
      ],
      _ => null,
    };
    if (entries != null && entries.isNotEmpty) {
      return ExpansionTile(
        title: _ResultText(text: label, source: source),
        childrenPadding: const EdgeInsetsDirectional.only(start: Gap.l),
        children: [
          for (final entry in entries)
            _DetailValue(
              source: source,
              label: entry.key,
              value: entry.value,
              onOpen: onOpen,
            ),
        ],
      );
    }
    final text = '$value';
    final uri = Uri.tryParse(text);
    final isLink =
        uri != null &&
        {'http', 'https'}.contains(uri.scheme) &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Gap.xs),
        child: isLink
            ? TextButton(
                onPressed: () => onOpen(text),
                child: SelectionContainer.disabled(
                  child: Text('$label: $text'),
                ),
              )
            : _ResultText(text: '$label: $text', source: source),
      ),
    );
  }
}

class _ResultImage extends StatefulWidget {
  const _ResultImage({super.key, required this.source, required this.image});
  final String source;
  final ReverseSearchImage image;
  @override
  State<_ResultImage> createState() => _ResultImageState();
}

class _ResultImageState extends State<_ResultImage> {
  final _token = CancelToken();
  MemoryImage? _provider;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _failed = false);
    try {
      final Uint8List bytes;
      if (Uri.parse(widget.image.url).scheme == 'data') {
        bytes = base64Decode(
          widget.image.url.substring(widget.image.url.indexOf(',') + 1),
        );
      } else {
        final result = await HttpService.instance.send(
          method: 'GET',
          url: widget.image.url,
          partition: widget.source,
          headers: const {'Accept': 'image/*', 'Cache-Control': 'no-store'},
          timeout: const Duration(seconds: 30),
          maxBytes: 4 * 1024 * 1024,
          detectCloudflare: false,
          cancelToken: _token,
        );
        if (!result.ok) throw SourceError('HTTP', '图片加载失败');
        bytes = result.bytes;
      }
      if (!mounted || _token.isCancelled) return;
      setState(() => _provider = MemoryImage(bytes));
    } catch (_) {
      if (mounted && !_token.isCancelled) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _token.cancel();
    _provider?.evict();
    super.dispose();
  }

  Widget _failure() => TextButton.icon(
    onPressed: () {
      _provider?.evict();
      _provider = null;
      _load();
    },
    icon: const Icon(Icons.refresh),
    label: Text(tr('图片加载失败，点击重试')),
  );

  void _preview() => showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 900,
          maxHeight: MediaQuery.sizeOf(context).height * .8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: IconButton(
                tooltip: tr('关闭'),
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ),
            Flexible(
              child: InteractiveViewer(
                child: Image(
                  image: _provider!,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => Text(tr('图片加载失败')),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final caption = context.text.bodySmall?.copyWith(
      color: colors.onSurfaceVariant,
    );
    return Material(
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: Radii.medium,
        side: BorderSide(color: colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 16 / 10,
            child: _failed
                ? Center(child: _failure())
                : _provider == null
                ? const Center(child: CircularProgressIndicator())
                : InkWell(
                    onTap: _preview,
                    child: Semantics(
                      button: true,
                      label: tr('查看图片'),
                      child: Image(
                        image: _provider!,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => Center(child: _failure()),
                      ),
                    ),
                  ),
          ),
          if (widget.image.label.isNotEmpty || widget.image.similarity != null)
            Padding(
              padding: const EdgeInsets.all(Gap.m),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.image.label.isNotEmpty)
                    _ResultText(
                      text: widget.image.label,
                      source: widget.source,
                      style: context.text.bodySmall,
                    ),
                  if (widget.image.similarity != null)
                    Text(
                      tr('相似度 {score}%', {
                        'score': widget.image.similarity!
                            .toStringAsFixed(2)
                            .replaceFirst(RegExp(r'\.?0+$'), ''),
                      }),
                      style: caption,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
