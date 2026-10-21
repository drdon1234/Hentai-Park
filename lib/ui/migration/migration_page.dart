import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../../core/models.dart';
import '../../core/titles.dart';
import '../../engine/source_manager.dart';
import '../../library/library.dart';
import '../../library/migration.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/cover_tile.dart';
import '../widgets/error_view.dart';

/// Moves favorites to another source (Mihon's migration): search every other source for the title,
/// pick the matching work, then copy categories / read marks and optionally drop the old favorite.
/// Several works are migrated one after another.
class MigrationPage extends StatefulWidget {
  const MigrationPage({super.key, required this.items});
  final List<WorkItem> items;

  @override
  State<MigrationPage> createState() => _MigrationPageState();
}

class _MigrationPageState extends State<MigrationPage> {
  int _index = 0;
  late final _query = TextEditingController(
    text: searchableTitle(_current.title),
  );
  String _keyword = '';
  int _generation = 0;
  bool _busy = false;

  WorkItem get _current => widget.items[_index];

  @override
  void initState() {
    super.initState();
    _keyword = _query.text;
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  List<InstalledSource> get _targets {
    final kind = SourceManager.instance.kindOf(_current);
    return SourceManager.instance.enabled
        .where(
          (s) =>
              s.key != _current.source &&
              s.manifest!.can('search') &&
              s.manifest!.kind == kind,
        )
        .toList();
  }

  void _search() => setState(() {
    _keyword = _query.text.trim();
    _generation++;
  });

  void _next() {
    if (_index >= widget.items.length - 1) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _index++;
      _query.text = searchableTitle(_current.title);
      _keyword = _query.text;
      _generation++;
    });
  }

  Future<void> _pick(WorkItem target) async {
    final options = await showDialog<MigrationOptions>(
      context: context,
      builder: (_) => _OptionsDialog(to: target),
    );
    if (options == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final detail = await SourceManager.instance.detail(
        target.source,
        target.id,
      );
      final removedOriginal = await Migrator.migrate(
        Library.instance,
        from: _current,
        to: detail,
        options: options,
      );
      if (!mounted) return;
      context.toast(
        options.removeOld && !removedOriginal
            ? tr('已复制到新的站点；未匹配的进度保留在原收藏中')
            : options.removeOld
            ? tr('已迁移到 {value0}', {
                'value0':
                    SourceManager.instance.manifest(target.source)?.name ??
                    target.source,
              })
            : tr('已复制到新的站点'),
      );
      _next();
    } catch (e) {
      if (mounted) {
        context.toast(
          tr('迁移失败：{value0}', {'value0': e.asSourceError.friendly}),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final from =
        SourceManager.instance.manifest(_current.source)?.name ??
        _current.source;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.items.length > 1
              ? tr('迁移（{value0}/{value1}）', {
                  'value0': _index + 1,
                  'value1': widget.items.length,
                })
              : tr('迁移到其他站点'),
        ),
        actions: [
          if (widget.items.length > 1)
            TextButton(
              onPressed: _busy ? null : _next,
              child: SelectionContainer.disabled(child: Text(tr('跳过'))),
            ),
        ],
        bottom: _busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
      ),
      body: AbsorbPointer(
        absorbing: _busy,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: ListTile(
                leading: SizedBox(
                  width: 42,
                  height: 58,
                  child: CoverImage(
                    source: _current.source,
                    url: _current.cover,
                    sourceBlurred: _current.json['coverBlurred'] == true,
                    radius: 6,
                  ),
                ),
                title: SelectionContainer.disabled(
                  child: Text(
                    _current.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                subtitle: SelectionContainer.disabled(
                  child: Text(tr('当前来源：{value0}', {'value0': from})),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: TextField(
                  controller: _query,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _search(),
                  decoration: InputDecoration(
                    labelText: tr('搜索标题'),
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      tooltip: tr('搜索'),
                      icon: const Icon(Icons.search_rounded),
                      onPressed: _search,
                    ),
                  ),
                ),
              ),
            ),
            if (_targets.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: Icons.swap_horiz_rounded,
                  title: tr('没有可迁移的目标站点'),
                  message: tr('需要至少一个其他已启用、支持搜索的同类站点'),
                ),
              )
            else
              SliverList.builder(
                itemCount: _targets.length,
                itemBuilder: (context, i) => _TargetResults(
                  key: ValueKey('${_targets[i].key}-$_generation-$_index'),
                  source: _targets[i].key,
                  keyword: _keyword,
                  onPick: _pick,
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ],
        ),
      ),
    );
  }
}

class _TargetResults extends StatefulWidget {
  const _TargetResults({
    super.key,
    required this.source,
    required this.keyword,
    required this.onPick,
  });
  final String source;
  final String keyword;
  final ValueChanged<WorkItem> onPick;

  @override
  State<_TargetResults> createState() => _TargetResultsState();
}

class _TargetResultsState extends State<_TargetResults> {
  late Future<WorkPage> _future = _load();

  Future<WorkPage> _load() {
    final m = SourceManager.instance.manifest(widget.source)!;
    return SourceManager.instance.search(
      widget.source,
      keyword: widget.keyword,
      filters: m.defaultFilters(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = SourceManager.instance.manifest(widget.source)!;
    return FutureBuilder<WorkPage>(
      future: _future,
      builder: (context, snap) {
        Widget body;
        if (snap.connectionState != ConnectionState.done) {
          body = const Padding(
            padding: EdgeInsets.all(16),
            child: LinearProgressIndicator(),
          );
        } else if (snap.hasError) {
          body = Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SourceErrorView(
              error: snap.error!,
              source: widget.source,
              compact: true,
              onRetry: () => setState(() => _future = _load()),
            ),
          );
        } else if (snap.data!.items.isEmpty) {
          body = Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              tr('没有找到'),
              style: context.text.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          );
        } else {
          final items = snap.data!.items;
          final a = gridAspectFor(items, m.kind);
          final w = a > 1 ? 200.0 : 118.0;
          body = SizedBox(
            height: w / a + cardTextExtent(context),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, i) => SizedBox(
                width: w,
                child: CoverTile(
                  item: items[i],
                  aspect: a,
                  onTap: () => widget.onPick(items[i]),
                ),
              ),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              m.name,
              leading: SourceAvatar(widget.source, size: 26),
            ),
            body,
          ],
        );
      },
    );
  }
}

class _OptionsDialog extends StatefulWidget {
  const _OptionsDialog({required this.to});
  final WorkItem to;

  @override
  State<_OptionsDialog> createState() => _OptionsDialogState();
}

class _OptionsDialogState extends State<_OptionsDialog> {
  bool categories = true, readState = true;

  @override
  Widget build(BuildContext context) {
    final target =
        SourceManager.instance.manifest(widget.to.source)?.name ??
        widget.to.source;
    return AlertDialog(
      title: Text(tr('迁移选项')),
      contentPadding: const EdgeInsets.fromLTRB(8, 16, 8, 0),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              tr('目标：{value0} ·「{value1}」', {
                'value0': target,
                'value1': widget.to.title,
              }),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          CheckboxListTile(
            value: categories,
            title: SelectionContainer.disabled(child: Text(tr('复制分类'))),
            onChanged: (v) => setState(() => categories = v!),
          ),
          if (!widget.to.isGame)
            CheckboxListTile(
              value: readState,
              title: SelectionContainer.disabled(child: Text(tr('复制已读章节'))),
              subtitle: SelectionContainer.disabled(child: Text(tr('按章节号匹配'))),
              onChanged: (v) => setState(() => readState = v!),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: SelectionContainer.disabled(child: Text(tr('取消'))),
        ),
        TextButton(
          onPressed: () => Navigator.pop(
            context,
            MigrationOptions(
              categories: categories,
              readState: readState,
              removeOld: false,
            ),
          ),
          child: SelectionContainer.disabled(child: Text(tr('复制'))),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            MigrationOptions(categories: categories, readState: readState),
          ),
          child: SelectionContainer.disabled(child: Text(tr('迁移'))),
        ),
      ],
    );
  }
}
