import 'package:flutter/material.dart';

import '../../core/comments.dart';
import '../../core/localization.dart';
import '../../core/plugin_copy.dart';
import '../../engine/source_manager.dart';
import '../../images/park_image.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/content_translation.dart';
import '../widgets/error_view.dart';
import '../widgets/text_translation.dart';
import 'comments_controller.dart';

class CommentsEntry extends StatelessWidget {
  const CommentsEntry({
    super.key,
    required this.source,
    required this.workId,
    this.manager,
    this.count,
    this.available,
    this.context = const {},
    this.compact = false,
    this.color,
  });
  final String source, workId;
  final SourceManager? manager;
  final int? count;
  final bool? available;
  final Map<String, dynamic> context;
  final bool compact;
  final Color? color;

  @override
  Widget build(BuildContext buildContext) {
    final sources = manager ?? SourceManager.instance;
    if (available == false ||
        sources.manifest(source)?.can('comments') != true) {
      return const SizedBox.shrink();
    }
    void open() => Nav.push(
      buildContext,
      CommentsPage(
        source: source,
        workId: workId,
        manager: sources,
        requestContext: context,
      ),
    );
    final label = count == null
        ? tr('评论')
        : tr('评论 · {count}', {'count': count!});
    if (compact) {
      return IconButton(
        tooltip: label,
        color: color,
        onPressed: open,
        icon: const Icon(Icons.chat_bubble_outline_rounded),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Gap.page,
        vertical: Gap.s,
      ),
      child: FilledButton.tonalIcon(
        onPressed: open,
        icon: const Icon(Icons.chat_bubble_outline_rounded),
        label: Text(label),
      ),
    );
  }
}

class CommentsPage extends StatefulWidget {
  const CommentsPage({
    super.key,
    required this.source,
    required this.workId,
    this.manager,
    this.requestContext = const {},
    this.parentId,
    this.initial = const [],
  });
  final String source, workId;
  final SourceManager? manager;
  final Map<String, dynamic> requestContext;
  final String? parentId;
  final List<SourceComment> initial;
  @override
  State<CommentsPage> createState() => _CommentsPageState();
}

class _CommentsPageState extends State<CommentsPage> {
  SourceManager get manager => widget.manager ?? SourceManager.instance;
  late final controller = CommentsController(
    (page, cursor, sort, token) => manager.comments(
      widget.source,
      widget.workId,
      page: page,
      cursor: cursor,
      sort: sort,
      parentId: widget.parentId,
      context: widget.requestContext,
      cancelToken: token,
    ),
    initial: widget.initial,
  );
  @override
  void initState() {
    super.initState();
    controller.load();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TranslationPage(
    child: Scaffold(
      appBar: AppBar(
        title: Text(tr(widget.parentId == null ? '评论' : '回复')),
        actions: [
          TranslationControls(source: widget.source),
          IconButton(
            tooltip: tr('刷新'),
            onPressed: () => controller.refresh(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final c = controller;
          if (c.items.isEmpty && c.error != null) {
            return SourceErrorView(
              error: c.error!,
              source: widget.source,
              onRetry: c.load,
            );
          }
          return RefreshIndicator(
            onRefresh: c.refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: Gap.page),
              children: [
                if (c.sorts.isNotEmpty && widget.parentId == null)
                  Padding(
                    padding: const EdgeInsets.all(Gap.page),
                    child: Wrap(
                      spacing: Gap.s,
                      runSpacing: Gap.s,
                      children: [
                        for (final order in c.sorts)
                          ChoiceChip(
                            label: Text(
                              manager
                                      .manifest(widget.source)
                                      ?.copy
                                      .text(order.label) ??
                                  tr(order.label),
                            ),
                            selected:
                                c.sort == order.value ||
                                c.sort == 'default' && order == c.sorts.first,
                            onSelected: (_) => c.refresh(order: order.value),
                          ),
                      ],
                    ),
                  ),
                if (c.total != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Gap.page,
                      vertical: Gap.s,
                    ),
                    child: Text(
                      tr('评论 · {count}', {'count': c.total!}),
                      style: context.text.labelLarge,
                    ),
                  ),
                for (final comment in c.threads)
                  CommentTile(
                    key: ValueKey(comment.id),
                    comment: comment,
                    source: widget.source,
                    copy: manager.manifest(widget.source)?.copy,
                    onLink: (url) => Nav.openContentLink(
                      context,
                      widget.source,
                      url,
                      sourceManager: manager,
                    ),
                    onReplies: (reply) => Nav.push(
                      context,
                      CommentsPage(
                        source: widget.source,
                        workId: widget.workId,
                        manager: manager,
                        requestContext: widget.requestContext,
                        parentId: reply.id,
                        initial: reply.replies,
                      ),
                    ),
                  ),
                if (c.items.isEmpty && !c.loading && c.error == null)
                  Padding(
                    padding: const EdgeInsets.all(Gap.page),
                    child: Text(tr('暂无评论'), textAlign: TextAlign.center),
                  ),
                if (c.loading)
                  const Padding(
                    padding: EdgeInsets.all(Gap.page),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                if (c.error != null)
                  SourceErrorView(
                    error: c.error!,
                    source: widget.source,
                    onRetry: c.load,
                    compact: true,
                  )
                else if (!c.loading && c.hasNext)
                  Center(
                    child: TextButton(
                      onPressed: c.load,
                      child: Text(tr('加载更多')),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    ),
  );
}

class CommentTile extends StatefulWidget {
  const CommentTile({
    super.key,
    required this.comment,
    required this.source,
    required this.onLink,
    this.onReplies,
    this.nested = false,
    this.copy,
  });
  final SourceComment comment;
  final String source;
  final void Function(String) onLink;
  final ValueChanged<SourceComment>? onReplies;
  final bool nested;
  final PluginCopy? copy;
  @override
  State<CommentTile> createState() => _CommentTileState();
}

class _CommentTileState extends State<CommentTile> {
  bool revealed = false, expanded = false, repliesExpanded = false;
  @override
  Widget build(BuildContext context) {
    final c = widget.comment;
    final copy =
        widget.copy ?? SourceManager.instance.manifest(widget.source)?.copy;
    final long = c.body.fold<int>(0, (n, p) => n + p.text.length) > 800;
    final replies = repliesExpanded ? c.replies : c.replies.take(2);
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: widget.nested ? Gap.m : Gap.page,
        vertical: Gap.m,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: Gap.s,
            runSpacing: Gap.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (c.avatar != null)
                ClipOval(
                  child: Image(
                    image: ParkImage.url(widget.source, c.avatar!),
                    width: 28,
                    height: 28,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        const Icon(Icons.person_outline_rounded),
                  ),
                ),
              Text(
                c.author.isEmpty ? tr('匿名') : c.author,
                style: context.text.titleSmall,
              ),
              for (final badge in c.badges)
                Text(
                  copy?.has(badge) == true ? copy!.text(badge) : badge,
                  style: context.text.labelSmall?.copyWith(
                    color: context.colors.primary,
                  ),
                ),
            ],
          ),
          if (c.date.isNotEmpty || c.likes != null || c.rating != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Gap.xs),
              child: Wrap(
                spacing: Gap.m,
                runSpacing: Gap.xs,
                children: [
                  if (c.date.isNotEmpty)
                    Text(c.date, style: context.text.bodySmall),
                  if (c.likes != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.thumb_up_outlined, size: 16),
                        const SizedBox(width: Gap.xs),
                        Text('${c.likes}', style: context.text.bodySmall),
                      ],
                    ),
                  if (c.rating != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.star_outline_rounded, size: 16),
                        const SizedBox(width: Gap.xs),
                        Text('${c.rating}/5', style: context.text.bodySmall),
                      ],
                    ),
                ],
              ),
            ),
          if (!widget.nested && c.parentId?.isNotEmpty == true)
            Text(
              tr('回复 #{id}', {'id': c.parentId!}),
              style: context.text.labelSmall,
            ),
          if (c.spoiler && !revealed)
            TextButton(
              onPressed: () => setState(() => revealed = true),
              child: Text(tr('显示剧透评论')),
            )
          else ...[
            CommentBody(
              parts: c.body,
              source: widget.source,
              onLink: widget.onLink,
              limit: long && !expanded ? 800 : null,
            ),
            if (long)
              TextButton(
                onPressed: () => setState(() => expanded = !expanded),
                child: Text(tr(expanded ? '收起' : '展开全文')),
              ),
          ],
          ...[
            for (final reply in replies)
              DecoratedBox(
                decoration: BoxDecoration(
                  color: context.colors.surfaceContainerLow,
                ),
                child: CommentTile(
                  comment: reply,
                  source: widget.source,
                  copy: copy,
                  onLink: widget.onLink,
                  onReplies: widget.onReplies,
                  nested: true,
                ),
              ),
            if (c.replies.length > 2)
              TextButton(
                onPressed: () =>
                    setState(() => repliesExpanded = !repliesExpanded),
                child: Text(tr(repliesExpanded ? '收起回复' : '展开回复')),
              ),
            if (widget.onReplies != null && c.repliesAvailable)
              TextButton(
                onPressed: () => widget.onReplies!(c),
                child: Text(
                  c.replyCount > 0
                      ? tr('查看回复 · {count}', {'count': c.replyCount})
                      : tr('查看回复'),
                ),
              ),
            if ((widget.onReplies == null || !c.repliesAvailable) &&
                c.replyCount > c.replies.length)
              Text(
                tr('回复 · {count}', {'count': c.replyCount}),
                style: context.text.bodySmall,
              ),
            const Divider(),
          ],
        ],
      ),
    );
  }
}

class CommentBody extends StatefulWidget {
  const CommentBody({
    super.key,
    required this.parts,
    required this.source,
    required this.onLink,
    this.limit,
  });
  final List<CommentPart> parts;
  final String source;
  final void Function(String) onLink;
  final int? limit;
  @override
  State<CommentBody> createState() => _CommentBodyState();
}

class _CommentBodyState extends State<CommentBody> {
  @override
  Widget build(BuildContext context) {
    final children = <Widget>[], spans = <InlineSpan>[];
    var left = widget.limit ?? 65536;
    void flush() {
      if (spans.isEmpty) return;
      children.add(
        Text.rich(
          TextSpan(children: List.of(spans)),
          style: context.text.bodyMedium,
        ),
      );
      spans.clear();
    }

    for (final p in widget.parts) {
      if (left <= 0) break;
      if (p.type == 'image') {
        flush();
        children.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Gap.s),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240, maxWidth: 360),
              child: Image(
                image: ParkImage.url(widget.source, p.url!),
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => TextButton(
                  onPressed: () => widget.onLink(p.url!),
                  child: Text(tr('查看图片')),
                ),
              ),
            ),
          ),
        );
        continue;
      }
      final text = p.text.length > left
          ? '${p.text.substring(0, left)}…'
          : p.text;
      left -= p.text.length;
      final style = p.type == 'link'
          ? TextStyle(
              color: context.colors.primary,
              decoration: TextDecoration.underline,
            )
          : p.type == 'quote'
          ? TextStyle(
              color: context.colors.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            )
          : context.text.bodyMedium;
      for (final chunk in translationChunks(text)) {
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: ContentTranslation(
              text: chunk,
              source: widget.source,
              builder: (value) => GestureDetector(
                onTap: p.type == 'link' && p.url != null
                    ? () => widget.onLink(p.url!)
                    : null,
                child: Text(value, style: style),
              ),
            ),
          ),
        );
      }
    }
    flush();
    return TranslationSelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}
