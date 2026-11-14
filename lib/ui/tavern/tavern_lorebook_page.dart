import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../../tavern/models.dart';
import '../kit/kit.dart';
import '../widgets/content_translation.dart';

class TavernLorebookPage extends StatelessWidget {
  const TavernLorebookPage({
    super.key,
    required this.title,
    required this.source,
    required this.resource,
  });

  final String title;
  final String source;
  final TavernResource resource;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PageHeader(
        titleWidget: ContentTranslation(
          text: title,
          source: source,
          builder: (value) => Text(value),
        ),
        actions: [TranslationControls(source: source)],
      ),
      body: TavernLorebookList(source: source, resource: resource),
    );
  }
}

class TavernLorebookList extends StatelessWidget {
  const TavernLorebookList({
    super.key,
    required this.source,
    required this.resource,
  });

  final String source;
  final TavernResource resource;

  @override
  Widget build(BuildContext context) {
    final entries = resource.entries;
    return entries.isEmpty
        ? Center(child: Text(tr('没有世界书词条')))
        : ListView.builder(
            padding: const EdgeInsets.fromLTRB(
              Gap.page,
              Gap.s,
              Gap.page,
              Gap.xxl,
            ),
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final entry = entries[index];
              return ExpansionTile(
                key: PageStorageKey('lorebook-$index'),
                title: entry.label.isEmpty
                    ? Text(tr('世界书词条'))
                    : ContentTranslation(
                        text: entry.label,
                        source: source,
                        builder: (value) => Text(value),
                      ),
                subtitle: ContentTranslation(
                  text: entry.keys.join(', '),
                  source: source,
                  builder: (value) => Text(value),
                ),
                childrenPadding: const EdgeInsets.fromLTRB(
                  Gap.page,
                  0,
                  Gap.page,
                  Gap.l,
                ),
                children: [
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: ContentTranslation(
                      text: entry.content,
                      source: source,
                      builder: (value) => Text(value),
                    ),
                  ),
                ],
              );
            },
          );
  }
}
