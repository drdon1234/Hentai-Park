import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../../core/models.dart';
import '../../core/settings.dart';
import '../../engine/source_manager.dart';
import '../nav.dart';
import '../settings/source_manage_page.dart';
import '../widgets/common.dart';
import '../widgets/content_translation.dart';
import '../widgets/error_view.dart';
import '../widgets/option_bar.dart';
import '../widgets/source_network_hint.dart';
import 'ranking_controller.dart';
import 'ranking_row.dart';

typedef RankingSelection = ({SourceManifest source, RankingDef board});

class RankingsPage extends StatefulWidget {
  const RankingsPage({super.key, this.category, this.sourceManager});
  final SourceCategory? category;
  final SourceManager? sourceManager;

  @override
  State<RankingsPage> createState() => _RankingsPageState();
}

class _RankingsPageState extends State<RankingsPage> {
  StreamSubscription<String>? _authentication;
  @override
  void initState() {
    super.initState();
    _authentication = _manager.authenticationChanges.listen((source) {
      if (!mounted) return;
      setState(() {
        final keys = _sessions.keys
            .where((key) => key.startsWith('$source:'))
            .toList();
        for (final key in keys) {
          _sessions.remove(key)?.dispose();
        }
        _optionLoads.removeWhere((key, _) => key.startsWith('$source:'));
        _activeSession = null;
      });
    });
  }

  late SourceCategory _category =
      widget.category ?? SourceCategory.fromJson(_saved['category'] ?? 'jav');
  late String? _selected = _saved['selected'] as String?;
  late String _section = _saved['section'] as String? ?? 'market';
  late String _kind = _saved['kind'] as String? ?? 'work';
  late final _saved = AppSettings.instance.rankingSelection;
  final _optionLoads = <String, Future<List<OptionDef>>>{};
  final _sessions = <String, RankingController>{};
  late final _options = <String, Map<String, Object?>>{
    for (final e in (_saved['options'] as Map? ?? {}).entries)
      if (e.value is Map) '${e.key}': Map<String, Object?>.from(e.value as Map),
  };
  String? _activeSession;
  void _save() => AppSettings.instance.rankingSelection = {
    'category': _category.name,
    'section': _section,
    'kind': _kind,
    if (_selected != null) 'selected': _selected,
    'options': _options,
  };
  SourceManager get _manager => widget.sourceManager ?? SourceManager.instance;
  String _key(RankingSelection entry) =>
      '${entry.source.key}:${entry.board.key}';

  @override
  void dispose() {
    _authentication?.cancel();
    for (final session in _sessions.values) {
      session.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TranslationPage(
    child: Scaffold(
      appBar: AppBar(
        title: Text(tr('排行榜')),
        actions: [
          const TranslationControls(),
          IconButton(
            tooltip: tr('管理站点'),
            icon: const Icon(Icons.extension_outlined),
            onPressed: () => Nav.push(context, const SourceManagePage()),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _manager,
        builder: (context, _) {
          if (_manager.initializationError case final error?) {
            return SourceErrorView(
              error: error,
              source: '',
              onRetry: () async {
                try {
                  await _manager.init();
                } catch (_) {
                  // 初始化错误由管理器状态展示。
                }
              },
            );
          }
          if (!_manager.loaded) {
            return const Center(child: CircularProgressIndicator());
          }
          final entries = <RankingSelection>[
            for (final source in _manager.enabled)
              for (final board in source.manifest!.rankings)
                (source: source.manifest!, board: board),
          ];
          // 商业榜优先；同一组维持官方插件清单的顺序。
          final commercial = entries
              .where((entry) => entry.source.rankingOnly)
              .toList();
          final community = entries
              .where((entry) => !entry.source.rankingOnly)
              .toList();
          final available = [...commercial, ...community];
          final categories = [
            for (final category in AppSettings.instance.domainOrder)
              if (available.any((entry) => entry.board.category == category))
                category,
          ];
          if (categories.isEmpty) {
            return EmptyState(
              icon: Icons.leaderboard_outlined,
              title: tr('暂无可用排行榜'),
              message: tr('在站点管理中启用或安装站点'),
              actions: [
                TextButton(
                  onPressed: () => Nav.push(context, const SourceManagePage()),
                  child: SelectionContainer.disabled(child: Text(tr('管理站点'))),
                ),
              ],
            );
          }
          final category = categories.contains(_category)
              ? _category
              : categories.first;
          final categoryBoards = available
              .where((e) => e.board.category == category)
              .toList();
          String sectionOf(RankingSelection e) => e.board.section.isEmpty
              ? (e.source.rankingOnly ? 'market' : 'site')
              : e.board.section;
          final sections = [
            'market',
            'site',
          ].where((s) => categoryBoards.any((e) => sectionOf(e) == s)).toList();
          final section = sections.contains(_section)
              ? _section
              : sections.first;
          final sectionBoards = categoryBoards
              .where((e) => sectionOf(e) == section)
              .toList();
          final kinds = [
            'work',
            'actress',
            'genre',
            'seller',
          ].where((k) => sectionBoards.any((e) => e.board.kind == k)).toList();
          final kind = kinds.contains(_kind) ? _kind : kinds.first;
          final boards = sectionBoards
              .where((e) => e.board.kind == kind)
              .toList();
          final entry =
              boards.where((entry) => _key(entry) == _selected).firstOrNull ??
              boards.first;
          final key = _key(entry);
          _category = category;
          _section = section;
          _kind = kind;
          _selected = key;
          return FutureBuilder<List<OptionDef>>(
            key: ValueKey(key),
            future: _optionLoads.putIfAbsent(
              key,
              () => _manager.rankingOptions(entry.source.key, entry.board),
            ),
            builder: (context, snapshot) {
              final definitions = snapshot.data ?? entry.board.options;
              final stored = _options[key] ?? const <String, Object?>{};
              final options = {
                for (final o in definitions)
                  o.key:
                      stored.containsKey(o.key) &&
                          (o.values.isEmpty ||
                              (o.type == 'multi' && stored[o.key] is List
                                  ? (stored[o.key] as List).every(
                                      (v) => o.values.any((c) => c.value == v),
                                    )
                                  : o.values.any(
                                      (c) => c.value == stored[o.key],
                                    )))
                      ? stored[o.key]
                      : o.defaultValue,
              };
              final sessionKey =
                  '$key:${entry.source.version}:${jsonEncode(options)}';
              _options[key] = options;
              final header = Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Gap.page,
                      Gap.s,
                      Gap.page,
                      0,
                    ),
                    child: SelectionContainer.disabled(
                      child: DropdownButtonFormField<SourceCategory>(
                        key: ValueKey(category),
                        initialValue: category,
                        isExpanded: true,
                        decoration: InputDecoration(labelText: tr('分类')),
                        items: [
                          for (final value in categories)
                            DropdownMenuItem(
                              value: value,
                              child: SelectionContainer.disabled(
                                child: Text(value.label),
                              ),
                            ),
                        ],
                        onChanged: (value) => setState(() {
                          if (value == null) return;
                          _category = value;
                          _selected = null;
                          _save();
                        }),
                      ),
                    ),
                  ),
                  _chips(
                    sections,
                    section,
                    (v) => v == 'market' ? tr('市场排行榜') : tr('站点排行榜'),
                    (v) => setState(() {
                      _section = v;
                      _selected = null;
                      _save();
                    }),
                  ),
                  _chips(
                    kinds,
                    kind,
                    (v) => tr(switch (v) {
                      'actress' => '女优榜',
                      'genre' => '分类榜',
                      'seller' => '卖家榜',
                      _ => '作品榜',
                    }),
                    (v) => setState(() {
                      _kind = v;
                      _selected = null;
                      _save();
                    }),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Gap.page,
                      Gap.s,
                      Gap.page,
                      0,
                    ),
                    child: SelectionContainer.disabled(
                      child: DropdownButtonFormField<String>(
                        key: ValueKey(key),
                        initialValue: key,
                        isExpanded: true,
                        decoration: InputDecoration(labelText: tr('榜单')),
                        items: [
                          for (final option in boards)
                            DropdownMenuItem(
                              value: _key(option),
                              child: SelectionContainer.disabled(
                                child: Text(
                                  '${option.source.name} · ${option.board.label}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                        ],
                        onChanged: (value) => setState(() {
                          _selected = value;
                          _save();
                        }),
                      ),
                    ),
                  ),
                  if (snapshot.hasData)
                    OptionBar(
                      key: ValueKey('options-$key'),
                      dropdowns: true,
                      source: entry.source.key,
                      options: definitions,
                      values: options,
                      onChanged: (values) => setState(() {
                        _options[key] = values;
                        _selected = key;
                        _save();
                      }),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Gap.page),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TagTranslationPackStatus(source: entry.source.key),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Gap.page,
                      vertical: Gap.s,
                    ),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(entry.board.metric),
                    ),
                  ),
                ],
              );
              if (!snapshot.hasData) {
                return CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(child: header),
                    SliverToBoxAdapter(
                      child: snapshot.hasError
                          ? SourceErrorView(
                              error: snapshot.error!,
                              source: entry.source.key,
                              onRetry: () =>
                                  setState(() => _optionLoads.remove(key)),
                            )
                          : const Padding(
                              padding: EdgeInsets.all(Gap.xl),
                              child: Center(child: CircularProgressIndicator()),
                            ),
                    ),
                  ],
                );
              }
              final existing = _sessions.containsKey(sessionKey);
              final controller = _sessions.putIfAbsent(sessionKey, () {
                final result = RankingController(
                  (page, cursor, offset) => _manager.ranking(
                    entry.source.key,
                    entry.board.key,
                    page: page,
                    cursor: cursor,
                    offset: offset,
                    options: options,
                  ),
                );
                // 开始加载放在布局后，避免在构建过程中通知监听器。
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) result.loadMore();
                });
                return result;
              });
              if (_activeSession != sessionKey) {
                _activeSession = sessionKey;
                if (existing) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && _activeSession == sessionKey) {
                      controller.refresh();
                    }
                  });
                }
              }
              return _RankingList(
                key: ValueKey(sessionKey),
                controller: controller,
                entry: entry,
                header: header,
              );
            },
          );
        },
      ),
    ),
  );
  Widget _chips(
    List<String> values,
    String selected,
    String Function(String) label,
    ValueChanged<String> onChanged,
  ) => Padding(
    padding: const EdgeInsets.fromLTRB(Gap.page, Gap.s, Gap.page, 0),
    child: SelectionContainer.disabled(
      child: DropdownButtonFormField<String>(
        key: ValueKey('$selected:${values.join(',')}'),
        initialValue: selected,
        isExpanded: true,
        decoration: InputDecoration(labelText: label(selected)),
        items: [
          for (final value in values)
            DropdownMenuItem(
              value: value,
              child: SelectionContainer.disabled(child: Text(label(value))),
            ),
        ],
        onChanged: (value) {
          if (value != null) onChanged(value);
        },
      ),
    ),
  );
}

class _RankingList extends StatefulWidget {
  const _RankingList({
    super.key,
    required this.controller,
    required this.entry,
    required this.header,
  });
  final RankingController controller;
  final RankingSelection entry;
  final Widget header;

  @override
  State<_RankingList> createState() => _RankingListState();
}

class _RankingListState extends State<_RankingList> {
  late final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) => ParkRefresh(
      onRefresh: widget.controller.refresh,
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: widget.header),
          if (widget.controller.hidden > 0)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(Gap.s),
                child: Text(
                  tr('（已屏蔽 {value0} 部）', {'value0': widget.controller.hidden}),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          if (widget.controller.loading && widget.controller.items.isEmpty)
            SliverToBoxAdapter(
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.all(Gap.xl),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  SourceNetworkHint(source: widget.entry.source.key),
                ],
              ),
            ),
          SliverList.builder(
            itemCount: widget.controller.items.length,
            itemBuilder: (context, index) {
              if (index >= widget.controller.items.length - 3 &&
                  widget.controller.hasNext &&
                  !widget.controller.loading &&
                  widget.controller.error == null) {
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => widget.controller.loadMore(),
                );
              }
              final item = widget.controller.items[index];
              return RankingRow(
                key: ValueKey(item.uid),
                item: item,
                board: widget.entry.board,
              );
            },
          ),
          if (widget.controller.error case final error?)
            SliverToBoxAdapter(
              child: SourceErrorView(
                error: error,
                source: widget.entry.source.key,
                onRetry: widget.controller.loadMore,
                compact: widget.controller.items.isNotEmpty,
              ),
            )
          else if (widget.controller.items.isEmpty &&
              !widget.controller.loading &&
              !widget.controller.hasNext)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.leaderboard_outlined,
                title: tr('暂无可用排行榜'),
              ),
            )
          else if (widget.controller.loading &&
              widget.controller.items.isNotEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(Gap.l),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
          if (widget.controller.hasNext &&
              !widget.controller.loading &&
              widget.controller.error == null)
            SliverToBoxAdapter(
              child: Center(
                child: OutlinedButton(
                  onPressed: widget.controller.loadMore,
                  child: SelectionContainer.disabled(child: Text(tr('加载更多'))),
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: Gap.xl)),
        ],
      ),
    ),
  );
}
