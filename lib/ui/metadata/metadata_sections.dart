import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../../core/work_metadata.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/content_translation.dart';
import '../widgets/error_view.dart';
import '../widgets/text_translation.dart';
import 'metadata_controller.dart';

class MetadataOverview extends StatelessWidget {
  const MetadataOverview({
    super.key,
    required this.detail,
    required this.source,
    required this.onCopy,
    required this.onOriginal,
  });
  final WorkMetadata detail;
  final String source;
  final VoidCallback onCopy, onOriginal;

  @override
  Widget build(BuildContext context) {
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          detail.code,
          style: context.text.labelLarge?.copyWith(
            color: context.colors.primary,
          ),
        ),
        const SizedBox(height: Gap.s),
        ContentTranslation(
          source: source,
          text: detail.title,
          builder: (value) =>
              Text(value, style: ParkText.serif(context.text.headlineSmall)),
        ),
        const SizedBox(height: Gap.m),
        Wrap(
          spacing: Gap.s,
          runSpacing: Gap.s,
          children: [
            OutlinedButton.icon(
              onPressed: onCopy,
              icon: const Icon(Icons.copy_outlined),
              label: Text(tr('复制番号')),
            ),
            OutlinedButton.icon(
              onPressed: onOriginal,
              icon: const Icon(Icons.open_in_new_rounded),
              label: Text(tr('原站')),
            ),
          ],
        ),
      ],
    );
    Widget cover() => ClipRRect(
      borderRadius: Radii.small,
      child: AspectRatio(
        aspectRatio: 1.5,
        child: CoverImage(
          source: source,
          url: detail.cover,
          fit: BoxFit.contain,
          title: detail.title,
        ),
      ),
    );
    final fields = [
      (tr('发行日期'), detail.releaseDate),
      (tr('时长'), detail.duration),
      (tr('导演'), detail.director),
      (tr('制作商'), detail.studio),
      (tr('发行商'), detail.publisher),
      (tr('系列'), detail.series),
      (tr('评分'), detail.rating),
    ].where((entry) => entry.$2.isNotEmpty).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (detail.cover.isEmpty)
          info
        else
          LayoutBuilder(
            builder: (context, constraints) => constraints.maxWidth >= 720
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 320, child: cover()),
                      const SizedBox(width: Gap.xl),
                      Expanded(child: info),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      cover(),
                      const SizedBox(height: Gap.l),
                      info,
                    ],
                  ),
          ),
        if (fields.isNotEmpty) ...[
          const SizedBox(height: Gap.l),
          SelectionArea(
            child: TextSelectionGuard(
              child: Wrap(
                spacing: Gap.xl,
                runSpacing: Gap.m,
                children: [
                  for (final (label, value) in fields)
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: context.text.labelMedium?.copyWith(
                            color: context.colors.onSurfaceVariant,
                          ),
                        ),
                        Text(value, style: context.text.bodyMedium),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
        if (detail.description.isNotEmpty) ...[
          const SizedBox(height: Gap.l),
          SelectionArea(
            child: TextSelectionGuard(
              child: ContentTranslation(
                source: source,
                text: detail.description,
                builder: (value) => Text(value),
              ),
            ),
          ),
        ],
        for (final (label, values) in [
          (tr('演员'), detail.actors),
          (tr('标签'), detail.tags),
        ])
          if (values.isNotEmpty) ...[
            const SizedBox(height: Gap.l),
            Text(label, style: context.text.titleSmall),
            const SizedBox(height: Gap.s),
            Wrap(
              spacing: Gap.s,
              runSpacing: Gap.s,
              children: [
                for (final value in values)
                  ContentTranslation(
                    source: source,
                    text: value,
                    tag: true,
                    builder: (text) => Tag(text),
                  ),
              ],
            ),
          ],
      ],
    );
  }
}

class MetadataCandidateRow extends StatelessWidget {
  const MetadataCandidateRow({
    super.key,
    required this.source,
    required this.item,
    required this.onTap,
  });
  final String source;
  final MetadataCandidate item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(vertical: Gap.s),
    leading: item.cover.isEmpty
        ? null
        : SizedBox(
            width: 72,
            height: 56,
            child: CoverImage(
              source: source,
              url: item.cover,
              title: item.title,
            ),
          ),
    title: Text(item.title, maxLines: 3, overflow: TextOverflow.ellipsis),
    subtitle: Text(item.code),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: onTap,
  );
}

class MetadataImages extends StatelessWidget {
  const MetadataImages({super.key, required this.source, required this.detail});
  final String source;
  final WorkMetadata detail;

  @override
  Widget build(BuildContext context) {
    if (detail.images.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: Gap.xl, bottom: Gap.m),
          child: Text(tr('预览图'), style: context.text.titleMedium),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = (constraints.maxWidth / 160).floor().clamp(2, 5);
            final width =
                (constraints.maxWidth - Gap.s * (columns - 1)) / columns;
            return Wrap(
              spacing: Gap.s,
              runSpacing: Gap.s,
              children: [
                for (var i = 0; i < detail.images.length; i++)
                  SizedBox(
                    width: width,
                    child: Semantics(
                      button: true,
                      label: tr('预览图 {index}', {'index': i + 1}),
                      child: InkWell(
                        onTap: () => Nav.push(
                          context,
                          _MetadataImagePage(
                            source: source,
                            images: detail.images,
                            initial: i,
                          ),
                        ),
                        borderRadius: Radii.small,
                        child: ClipRRect(
                          borderRadius: Radii.small,
                          child: AspectRatio(
                            aspectRatio: 1.5,
                            child: CoverImage(
                              source: source,
                              url: detail.images[i],
                              title: detail.title,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _MetadataImagePage extends StatefulWidget {
  const _MetadataImagePage({
    required this.source,
    required this.images,
    required this.initial,
  });
  final String source;
  final List<String> images;
  final int initial;
  @override
  State<_MetadataImagePage> createState() => _MetadataImagePageState();
}

class _MetadataImagePageState extends State<_MetadataImagePage> {
  late final _pages = PageController(initialPage: widget.initial);
  late int _index = widget.initial;
  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('${_index + 1} / ${widget.images.length}')),
    body: PageView.builder(
      controller: _pages,
      itemCount: widget.images.length,
      onPageChanged: (value) => setState(() => _index = value),
      itemBuilder: (context, index) => InteractiveViewer(
        minScale: 1,
        maxScale: 5,
        child: Center(
          child: CoverImage(
            source: widget.source,
            url: widget.images[index],
            fit: BoxFit.contain,
            title: tr('预览图'),
          ),
        ),
      ),
    ),
  );
}

class MetadataMagnets extends StatelessWidget {
  const MetadataMagnets({
    super.key,
    required this.controller,
    required this.onCopy,
    required this.onOpen,
  });
  final MetadataController controller;
  final ValueChanged<MetadataMagnet> onCopy, onOpen;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: Gap.xl, bottom: Gap.m),
        child: Text(tr('磁链资源'), style: context.text.titleMedium),
      ),
      if (controller.magnetsLoading)
        const LinearProgressIndicator()
      else if (controller.magnetError case final error?)
        SourceErrorView(
          error: error,
          source: controller.source,
          onRetry: controller.loadMagnets,
          compact: true,
        )
      else if (controller.magnets.isEmpty)
        Text(
          tr('暂无磁链资源'),
          style: context.text.bodyMedium?.copyWith(
            color: context.colors.onSurfaceVariant,
          ),
        )
      else
        for (final magnet in controller.magnets)
          Padding(
            padding: const EdgeInsets.only(bottom: Gap.m),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SelectionArea(
                  child: TextSelectionGuard(
                    child: Text(magnet.name, style: context.text.titleSmall),
                  ),
                ),
                const SizedBox(height: Gap.xs),
                Text(
                  [
                    magnet.size,
                    magnet.date,
                    ...magnet.tags,
                  ].where((value) => value.isNotEmpty).join(' · '),
                  style: context.text.bodySmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: Gap.s),
                Wrap(
                  spacing: Gap.s,
                  runSpacing: Gap.s,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => onCopy(magnet),
                      icon: const Icon(Icons.copy_outlined),
                      label: Text(tr('复制磁链')),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => onOpen(magnet),
                      icon: const Icon(Icons.open_in_new_rounded),
                      label: Text(tr('打开磁链')),
                    ),
                  ],
                ),
                const SizedBox(height: Gap.m),
                const Divider(),
              ],
            ),
          ),
    ],
  );
}
