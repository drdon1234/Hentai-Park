import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/content_scope.dart';
import '../../core/localization.dart';
import '../../core/models.dart';
import '../../engine/domains.dart';
import '../../engine/source_manager.dart';
import '../comments/comments_page.dart';
import '../metadata/metadata_page.dart';
import '../nav.dart';
import '../theme.dart';
import '../web/source_web_page.dart';
import '../widgets/common.dart';
import '../widgets/content_translation.dart';

class RankingRow extends StatefulWidget {
  const RankingRow({super.key, required this.item, required this.board});
  final RankingEntry item;
  final RankingDef board;

  @override
  State<RankingRow> createState() => _RankingRowState();
}

class _RankingRowState extends State<RankingRow> {
  bool _expanded = false;

  void _openMetadata() {
    final keyword = widget.item.json['keyword'];
    Nav.push(
      context,
      MetadataPage(
        keyword: keyword is String && keyword.trim().isNotEmpty
            ? keyword
            : widget.item.title,
      ),
    );
  }

  void _open() {
    final item = widget.item;
    if (widget.board.kind == 'seller') return;
    if (widget.board.opensWork) {
      if (item.work case final work?) Nav.openWork(context, work);
    } else {
      final keyword = item.json['keyword'] as String?;
      Nav.openAggregateSearch(
        context,
        keyword: keyword?.isNotEmpty == true ? keyword! : item.title,
        scope: ContentScope.domain(widget.board.category),
      );
    }
  }

  /// 原站页面在应用内打开；不属于插件声明域的链接才交给系统浏览器。
  Future<void> _openOriginal(Uri url) async {
    final manifest = SourceManager.instance.manifest(widget.item.source);
    if (manifest != null &&
        httpsDomainAddressAllowed(url, declaredDomains(manifest.json))) {
      await Nav.push(
        context,
        SourceWebPage(source: widget.item.source, url: url),
      );
      return;
    }
    var opened = false;
    try {
      opened = await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {
      // 平台没有可处理链接的浏览器时也提供可重试提示。
    }
    if (!opened && mounted) context.toast(tr('无法打开原站'));
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final url = Uri.tryParse('${item.json['url'] ?? ''}');
    final original =
        url != null &&
        url.scheme == 'https' &&
        url.host.isNotEmpty &&
        url.userInfo.isEmpty;
    final metadataDetail =
        widget.board.kind == 'work' &&
        widget.board.category == SourceCategory.jav;
    final webDetail =
        widget.board.kind == 'work' &&
        !widget.board.opensWork &&
        !metadataDetail &&
        original;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Gap.page),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Gap.m),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 40,
                  child: Semantics(
                    label: tr('第 {rank} 名', {'rank': item.json['rank'] ?? ''}),
                    child: Text(
                      '${item.json['rank'] ?? ''}',
                      style: context.text.titleMedium,
                    ),
                  ),
                ),
                if (item.cover.isNotEmpty) ...[
                  GestureDetector(
                    onTap: metadataDetail
                        ? _openMetadata
                        : webDetail
                        ? () => _openOriginal(url)
                        : _open,
                    child: SizedBox(
                      width: widget.board.category == SourceCategory.jav
                          ? 120
                          : 76,
                      height: 104,
                      child: CoverImage(
                        source: item.source,
                        url: item.cover,
                        sourceBlurred: item.json['coverBlurred'] == true,
                        title: item.title,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  const SizedBox(width: Gap.m),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        onTap: () => setState(() => _expanded = !_expanded),
                        child: ContentTranslation(
                          source: item.source,
                          text: item.title,
                          tag: widget.board.kind == 'genre',
                          namespace: 'genre',
                          builder: (value) => Text(
                            value,
                            maxLines: _expanded ? null : 3,
                            overflow: _expanded ? null : TextOverflow.ellipsis,
                            style: context.text.titleSmall,
                          ),
                        ),
                      ),
                      if (item.subtitle.isNotEmpty)
                        ContentTranslation(
                          source: item.source,
                          text: item.subtitle,
                          builder: (value) => Text(
                            value,
                            maxLines: _expanded ? null : 2,
                            overflow: _expanded ? null : TextOverflow.ellipsis,
                            style: context.text.bodySmall,
                          ),
                        ),
                      if (item.json['workCount'] case final num count)
                        Text(
                          tr('作品数：{count}', {'count': count}),
                          style: context.text.bodySmall,
                        ),
                      Wrap(
                        spacing: Gap.s,
                        runSpacing: Gap.s,
                        children: [
                          if (webDetail || metadataDetail)
                            OutlinedButton(
                              onPressed: metadataDetail
                                  ? _openMetadata
                                  : () => _openOriginal(url!),
                              child: SelectionContainer.disabled(
                                child: Text(tr('打开详情')),
                              ),
                            ),
                          if (widget.board.kind == 'work')
                            CommentsEntry(
                              source: item.source,
                              workId: item.id,
                              available: item.work?.commentsAvailable,
                              compact: true,
                              context: {
                                'url': '${item.json['url'] ?? ''}',
                                'board': widget.board.key,
                              },
                            ),
                          if (widget.board.kind != 'seller' &&
                              (!metadataDetail || !widget.board.opensWork))
                            OutlinedButton(
                              onPressed: _open,
                              child: SelectionContainer.disabled(
                                child: Text(
                                  widget.board.opensWork
                                      ? tr('打开详情')
                                      : tr('搜索作品'),
                                ),
                              ),
                            ),
                          if (original && !webDetail)
                            OutlinedButton(
                              onPressed: () => _openOriginal(url),
                              child: SelectionContainer.disabled(
                                child: Text(tr('原站')),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
        ],
      ),
    );
  }
}
