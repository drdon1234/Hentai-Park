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

typedef _RankingAction = ({String label, VoidCallback onPressed});

class RankingRow extends StatefulWidget {
  const RankingRow({
    super.key,
    required this.item,
    required this.board,
    this.sourceManager,
  });
  final RankingEntry item;
  final RankingDef board;
  final SourceManager? sourceManager;

  @override
  State<RankingRow> createState() => _RankingRowState();
}

class _RankingRowState extends State<RankingRow> {
  bool _expanded = false;
  SourceManager get manager => widget.sourceManager ?? SourceManager.instance;

  void _openMetadata() {
    final keyword = widget.item.json['keyword'];
    Nav.push(
      context,
      MetadataPage(
        keyword: keyword is String && keyword.trim().isNotEmpty
            ? keyword
            : widget.item.title,
        sourceManager: manager,
        comments: CommentsEntry(
          source: widget.item.source,
          workId: widget.item.id,
          manager: manager,
          available: widget.item.work?.commentsAvailable,
          context: {
            'url': '${widget.item.json['url'] ?? ''}',
            'board': widget.board.key,
          },
        ),
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
    final manifest = manager.manifest(widget.item.source);
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

  double _actionWidth(_RankingAction action) {
    final style = Theme.of(context).outlinedButtonTheme.style;
    final painter = TextPainter(
      text: TextSpan(
        text: action.label,
        style: style?.textStyle?.resolve({}) ?? context.text.labelLarge,
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final width = (painter.width + Gap.m * 2)
        .clamp(48.0, double.infinity)
        .toDouble();
    painter.dispose();
    return width;
  }

  Widget _actionBar(List<_RankingAction> actions) => LayoutBuilder(
    builder: (context, constraints) {
      final rows = <List<_RankingAction>>[];
      var row = <_RankingAction>[];
      var width = 0.0;
      for (final action in actions) {
        final requiredWidth = _actionWidth(action);
        final nextWidth = requiredWidth.clamp(width, double.infinity);
        if (row.isNotEmpty &&
            nextWidth * (row.length + 1) + Gap.s * row.length >
                constraints.maxWidth) {
          rows.add(row);
          row = [];
          width = 0;
        }
        row.add(action);
        width = requiredWidth.clamp(width, double.infinity);
      }
      if (row.isNotEmpty) rows.add(row);
      return SelectionContainer.disabled(
        child: Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const SizedBox(height: Gap.s),
              Row(
                children: [
                  for (var j = 0; j < rows[i].length; j++) ...[
                    if (j > 0) const SizedBox(width: Gap.s),
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: Gap.m,
                          ),
                        ),
                        onPressed: rows[i][j].onPressed,
                        child: Text(
                          rows[i][j].label,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      );
    },
  );

  Widget _information(
    List<_RankingAction> actions,
    VoidCallback? openOriginal,
  ) {
    final item = widget.item;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                ],
              ),
            ),
            if (openOriginal != null) ...[
              const SizedBox(width: Gap.s),
              IconButton(
                tooltip: tr('打开原站'),
                icon: const Icon(Icons.open_in_new_rounded),
                onPressed: openOriginal,
              ),
            ],
          ],
        ),
        if (actions.isNotEmpty) ...[
          const SizedBox(height: Gap.m),
          _actionBar(actions),
        ],
      ],
    );
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
    final VoidCallback? openDetail = metadataDetail
        ? _openMetadata
        : webDetail
        ? () => _openOriginal(url)
        : widget.board.opensWork && item.work != null
        ? _open
        : null;
    final VoidCallback? openOriginal = original && !webDetail
        ? () => _openOriginal(url)
        : null;
    final actions = <_RankingAction>[
      if (openDetail != null) (label: tr('详情'), onPressed: openDetail),
      if (widget.board.kind != 'seller' && !widget.board.opensWork)
        (label: tr('搜索'), onPressed: _open),
    ];
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
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      const compactCoverWidth = 76.0;
                      var coverWidth =
                          widget.board.category == SourceCategory.jav
                          ? 120.0
                          : compactCoverWidth;
                      var actionsBelow = false;
                      if (item.cover.isNotEmpty && actions.isNotEmpty) {
                        var actionWidth = Gap.s * (actions.length - 1);
                        var textWidth = 48.0;
                        for (final action in actions) {
                          textWidth = _actionWidth(action)
                              .clamp(textWidth, double.infinity);
                        }
                        actionWidth += textWidth * actions.length;
                        // 先收紧封面旁的空白；仍放不下时给操作区整行宽度。
                        final availableCover =
                            constraints.maxWidth - Gap.m - actionWidth;
                        if (availableCover >= compactCoverWidth) {
                          coverWidth = availableCover.clamp(
                            compactCoverWidth,
                            coverWidth,
                          );
                        } else {
                          actionsBelow = true;
                        }
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (item.cover.isNotEmpty) ...[
                                Semantics(
                                  label: item.title,
                                  button: openDetail != null,
                                  image: openDetail == null,
                                  child: InkWell(
                                    onTap: openDetail,
                                    borderRadius: Radii.small,
                                    child: ExcludeSemantics(
                                      child: SizedBox(
                                        width: coverWidth,
                                        height: 104,
                                        child: CoverImage(
                                          source: item.source,
                                          url: item.cover,
                                          sourceBlurred:
                                              item.json['coverBlurred'] == true,
                                          title: item.title,
                                          fit: BoxFit.contain,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: Gap.m),
                              ],
                              Expanded(
                                child: _information(
                                  actionsBelow ? const [] : actions,
                                  openOriginal,
                                ),
                              ),
                            ],
                          ),
                          if (actionsBelow) ...[
                            const SizedBox(height: Gap.m),
                            _actionBar(actions),
                          ],
                        ],
                      );
                    },
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
