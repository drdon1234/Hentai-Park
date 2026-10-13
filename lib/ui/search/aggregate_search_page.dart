import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models.dart';
import '../../core/localization.dart';
import '../../core/settings.dart';
import '../../core/tag_blocklist.dart';
import '../../engine/source_manager.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/content_translation.dart';
import '../widgets/error_view.dart';
import '../widgets/work_card.dart';
import '../widgets/work_text_row.dart';
import '../../subscriptions/models.dart';
import '../subscriptions/subscription_posts_page.dart';
import '../widgets/source_network_hint.dart';
import 'multi_language.dart';
import 'source_search_page.dart';
import 'search_toolbar.dart';
import '../discovery_navigation.dart';

import '../../core/content_scope.dart';
import 'aggregate_search_controller.dart';
import '../history/history_page.dart';
import '../settings/source_manage_page.dart';

class AggregateSearchPage extends StatefulWidget {
  const AggregateSearchPage({
    super.key,
    this.initialKeyword = '',
    this.scope = const ContentScope.all(),
    this.sourceManager,
  });
  final SourceManager? sourceManager;
  final String initialKeyword;
  final ContentScope scope;
  @override
  State<AggregateSearchPage> createState() => _AggregateSearchPageState();
}

class _AggregateSearchPageState extends State<AggregateSearchPage> {
  SourceManager get _sources => widget.sourceManager ?? SourceManager.instance;
  late final _text = TextEditingController(text: widget.initialKeyword);
  final _focus = FocusNode();
  late ContentScope _range = widget.scope;
  SourceCategory _domain = SourceCategory.doujin;
  String _submitted = '';
  int _generation = 0;
  MultiKeyword? _multi;
  final _translation = KeywordTranslationRequest();
  final _results = AggregateSearchController();
  List<InstalledSource> _submittedSources = [];
  bool _awaitingSources = false;

  @override
  void initState() {
    super.initState();
    _domain = _range.category ?? SourceCategory.doujin;
    _translation.addListener(_changed);
    _sources.addListener(_sourcesChanged);
    _text.addListener(_changed);
    if (widget.initialKeyword.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _submit(widget.initialKeyword);
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _sourcesChanged() {
    if (!mounted || !_awaitingSources || !_sources.loaded) return;
    _awaitingSources = false;
    final generation = _generation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && generation == _generation) _dispatch();
    });
  }

  @override
  void dispose() {
    _translation.dispose();
    _sources.removeListener(_sourcesChanged);
    _results.dispose();
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  List<InstalledSource> get _eligible => _sources.enabled
      .where(
        (s) =>
            s.manifest!.can('search') &&
            _range.contains(s.key, s.manifest!.category),
      )
      .toList();
  List<InstalledSource> get _targets => _eligible
      .where((s) => !AppSettings.instance.aggregateExcluded.contains(s.key))
      .toList();

  void _changeRange(ContentScope range) {
    if (_range == range) return;
    _results.reset();
    _awaitingSources = false;
    setState(() {
      _range = range;
      _submitted = '';
      _multi = null;
      _submittedSources = [];
      _generation++;
      if (range.category != null) _domain = range.category!;
    });
  }

  void _submit(String keyword, {MultiKeyword? multi}) {
    final k = keyword.trim();
    if (k.isEmpty) return;
    _text.text = k;
    AppSettings.instance.addSearchHistory(k, scope: _range);
    _focus.unfocus();
    setState(() {
      _submitted = k;
      _multi = multi;
      _generation++;
    });
    _dispatch();
  }

  void _dispatch() {
    _results.reset();
    _awaitingSources = !_sources.loaded;
    if (_awaitingSources) return;
    final k = _submitted;
    final multi = _multi;
    final sources = _targets;
    final manifests = {for (final s in sources) s.key: s.manifest!};
    setState(() => _submittedSources = sources);
    _results.start(manifests.keys, (source, token) {
      final filters = manifests[source]!.defaultFilters();
      if (multi != null && multi.all.length > 1) {
        return MultiKeywordSearch(
          source,
          multi.all,
          filters,
          sourceManager: _sources,
          cancelToken: token,
        ).next();
      }
      return _sources.search(
        source,
        keyword: k,
        filters: filters,
        cancelToken: token,
      );
    });
  }

  Future<void> _submitMulti() async {
    if (_translation.busy) return;
    final keyword = _text.text.trim();
    if (!await confirmMultiLanguageSearch(context, keyword) ||
        !mounted ||
        _text.text.trim() != keyword) {
      return;
    }
    _focus.unfocus();
    final multi = await _translation.run(
      keyword: () => _text.text,
      generation: () => _generation,
      translate: (text) => translateKeyword(context, text),
    );
    if (mounted && multi != null) _submit(multi.original, multi: multi);
  }

  @override
  Widget build(BuildContext context) {
    AppLocalizations.of(context);
    final typed = _text.text.trim();
    return TranslationPage(
      child: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: Text(tr('聚合搜索')),
            actions: [const DomainMenu(), const TranslationControls()],
          ),
          body: SearchLayout(
            toolbar: SearchToolbar(
              field: TextField(
                controller: _text,
                focusNode: _focus,
                textInputAction: TextInputAction.search,
                onSubmitted: _submit,
                decoration: InputDecoration(
                  hintText: tr('关键词、链接或编号'),
                  suffixIcon: IconButton(
                    icon: Icon(
                      typed.isEmpty
                          ? Icons.content_paste_rounded
                          : Icons.close_rounded,
                    ),
                    tooltip: tr(typed.isEmpty ? '粘贴' : '清空'),
                    onPressed: () async {
                      if (typed.isNotEmpty) {
                        _text.clear();
                        return;
                      }
                      final data = await Clipboard.getData('text/plain');
                      if (mounted && data?.text != null) {
                        _text.text = data!.text!.trim();
                      }
                    },
                  ),
                  contentPadding: SearchToolbar.inputPadding,
                ),
              ),
              actions: [
                FilledButton.icon(
                  onPressed: typed.isEmpty ? null : () => _submit(_text.text),
                  icon: const Icon(Icons.search),
                  label: Text(tr('搜索')),
                ),
                if (_translation.busy)
                  const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  TextButton.icon(
                    label: Text(tr('多语言搜索')),
                    onPressed: _submitMulti,
                    icon: const Icon(Icons.language_rounded),
                  ),
              ],
            ),
            results: ListenableBuilder(
              listenable: Listenable.merge([
                _sources,
                AppSettings.instance,
                _results,
              ]),
              builder: (context, _) {
                final submittedKeys = _submittedSources
                    .map((s) => s.key)
                    .toSet();
                final resultSources = _sources.all
                    .where((s) => submittedKeys.contains(s.key))
                    .toList();
                final refs = typed.isEmpty
                    ? const <({String source, String id})>[]
                    : _directRefs(typed);
                return CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            ChoiceChip(
                              label: Text(tr('域内聚合搜索')),
                              selected: !_range.isAll,
                              onSelected: (_) =>
                                  _changeRange(ContentScope.domain(_domain)),
                            ),
                            ChoiceChip(
                              label: Text(tr('跨域聚合搜索')),
                              selected: _range.isAll,
                              onSelected: (_) =>
                                  _changeRange(const ContentScope.all()),
                            ),
                            if (!_range.isAll)
                              DropdownButton<SourceCategory>(
                                value: _domain,
                                items: [
                                  for (final d
                                      in AppSettings.instance.domainOrder)
                                    DropdownMenuItem(
                                      value: d,
                                      child: Text(d.label),
                                    ),
                                ],
                                onChanged: (d) {
                                  if (d != null) {
                                    _changeRange(ContentScope.domain(d));
                                  }
                                },
                              ),
                            OutlinedButton.icon(
                              icon: const Icon(Icons.history),
                              label: Text(tr('浏览历史')),
                              onPressed: () =>
                                  Nav.push(context, HistoryPage(scope: _range)),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (refs.isNotEmpty)
                      SliverToBoxAdapter(child: _DirectJump(refs: refs)),
                    ...[
                      SliverToBoxAdapter(
                        child: _ScopeBar(
                          sources: _eligible,
                          scope: _targets.map((s) => s.key).toSet(),
                          onToggle: (key, on) {
                            AppSettings.instance.setAggregateIncluded(key, on);
                            _generation++;
                            if (_submitted.isNotEmpty && typed == _submitted) {
                              _dispatch();
                            }
                          },
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: _History(
                          scope: _range,
                          onPick: (k) => _submit(k),
                        ),
                      ),
                    ],
                    if (_awaitingSources)
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      ),
                    if (!_awaitingSources &&
                        (_submitted.isEmpty ? _targets : _submittedSources)
                            .isEmpty)
                      SliverToBoxAdapter(
                        child: MessageView(
                          icon: Icons.search_off,
                          title: tr('当前范围没有可搜索的源站'),
                          actions: [
                            OutlinedButton.icon(
                              onPressed: () =>
                                  Nav.push(context, const SourceManagePage()),
                              icon: const Icon(Icons.extension_outlined),
                              label: Text(tr('源站管理')),
                            ),
                          ],
                          compact: true,
                        ),
                      ),
                    if (_submitted.isNotEmpty &&
                        typed == _submitted &&
                        _multi != null)
                      SliverToBoxAdapter(
                        child: TranslationsBar(
                          keyword: _multi!,
                          onPick: (k) => _submit(k),
                        ),
                      ),
                    if (_submitted.isNotEmpty && typed == _submitted)
                      for (final category in AppSettings.instance.domainOrder)
                        if (resultSources.any(
                          (s) => s.manifest!.category == category,
                        )) ...[
                          SliverToBoxAdapter(
                            child: SectionHeader(category.label),
                          ),
                          SliverList.list(
                            children: [
                              for (final s in resultSources.where(
                                (s) => s.manifest!.category == category,
                              ))
                                if (_sources.manifest(s.key) != null)
                                  _SourceResults(
                                    source: s.key,
                                    keyword: _submitted,
                                    multi: _multi,
                                    manifest: s.manifest!,
                                    result: _results.results[s.key]!,
                                    onRetry: () => _results.retry(s.key),
                                  ),
                            ],
                          ),
                        ],
                    const SliverToBoxAdapter(child: SizedBox(height: 40)),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  List<({String source, String id})> _directRefs(String text) {
    final sm = _sources;
    final refs = sm.extractRefs(text);
    if (refs.isEmpty && !text.contains(' ')) {
      for (final s in sm.enabled) {
        final id = s.manifest!.matchExplicitId(text);
        if (id != null) refs.add((source: s.key, id: id));
      }
    }
    final seen = <String>{};
    return refs
        .where((r) {
          final m = sm.manifest(r.source);
          return m != null &&
              _range.contains(r.source, m.category) &&
              seen.add('${r.source}:${r.id}');
        })
        .take(6)
        .toList();
  }
}

class _DirectJump extends StatelessWidget {
  const _DirectJump({required this.refs});
  final List<({String source, String id})> refs;

  @override
  Widget build(BuildContext context) {
    AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          tr('直达作品'),
          leading: Icon(
            Icons.bolt_rounded,
            color: context.colors.primary,
            size: 20,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final r in refs)
                ActionChip(
                  avatar: SourceAvatar(r.source, size: 22),
                  label: Text(
                    '${SourceManager.instance.manifest(r.source)?.name ?? r.source}  ${r.id}',
                  ),
                  onPressed: () => Nav.openRef(context, r.source, r.id),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ScopeBar extends StatelessWidget {
  const _ScopeBar({
    required this.sources,
    required this.scope,
    required this.onToggle,
  });
  final List<InstalledSource> sources;
  final void Function(String key, bool included) onToggle;
  final Set<String> scope;

  @override
  Widget build(BuildContext context) {
    AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          tr('搜索范围'),
          leading: Icon(
            Icons.hub_outlined,
            color: context.colors.primary,
            size: 20,
          ),
        ),
        for (final category in AppSettings.instance.domainOrder)
          if (sources.any((s) => s.manifest!.category == category))
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(category.label, style: context.text.labelLarge),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final s in sources.where(
                        (s) => s.manifest!.category == category,
                      ))
                        FilterChip(
                          avatar: SourceAvatar(s.key, size: 22),
                          label: Text(s.name),
                          selected: scope.contains(s.key),
                          showCheckmark: false,
                          onSelected: (on) => onToggle(s.key, on),
                        ),
                    ],
                  ),
                ],
              ),
            ),
      ],
    );
  }
}

class _History extends StatelessWidget {
  const _History({required this.onPick, required this.scope});
  final ContentScope scope;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    AppLocalizations.of(context);
    final history = AppSettings.instance.searchHistoryFor(scope);
    if (history.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          tr('最近搜索'),
          leading: Icon(
            Icons.history_rounded,
            color: context.colors.primary,
            size: 20,
          ),
          trailing: IconButton(
            tooltip: tr('清空'),
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: () =>
                AppSettings.instance.clearSearchHistory(scope: scope),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final k in history)
                InputChip(
                  label: Text(k),
                  onPressed: () => onPick(k),
                  onDeleted: () =>
                      AppSettings.instance.removeSearchHistory(k, scope: scope),
                  deleteIconColor: context.colors.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SourceResults extends StatelessWidget {
  const _SourceResults({
    required this.source,
    required this.keyword,
    this.multi,
    required this.result,
    required this.onRetry,
    required this.manifest,
  });
  final SourceManifest manifest;
  final String source, keyword;
  final MultiKeyword? multi;
  final AggregateResult result;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    AppLocalizations.of(context);
    final m = manifest;
    final header = SectionHeader(
      m.name,
      leading: SourceAvatar(source, size: 26),
      trailing: TextButton(
        onPressed: () => multi != null
            ? Nav.push(
                context,
                SourceSearchPage(
                  sourceKey: source,
                  initialKeyword: keyword,
                  initialMulti: multi,
                ),
              )
            : Nav.openSourceSearch(context, source, keyword: keyword),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (result.loading) ...[
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 8),
            ],
            if (result.page != null && (result.page!.total ?? 0) > 0)
              Text(
                tr('{count} 部 ', {'count': formatCount(result.page!.total)}),
                style: context.text.labelMedium,
              ),
            Text(tr('全部')),
            const Icon(Icons.chevron_right_rounded, size: 18),
          ],
        ),
      ),
    );
    final kind = m.kind;
    final aspect = kind == MediaKind.video ? 16 / 9 : 0.7;
    final cardWidth = aspect > 1 ? 200.0 : 118.0;
    Widget body;
    if (result.loading) {
      body = kind == MediaKind.novel
          ? Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Skeleton(height: 18),
                ),
                SourceNetworkHint(source: source),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: cardWidth / aspect + cardTextExtent(context),
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: 5,
                    physics: const NeverScrollableScrollPhysics(),
                    separatorBuilder: (_, _) => const SizedBox(width: 10),
                    itemBuilder: (_, _) => SizedBox(
                      width: cardWidth,
                      child: WorkCardSkeleton(aspect: aspect),
                    ),
                  ),
                ),
                SourceNetworkHint(source: source),
              ],
            );
    } else if (result.error != null) {
      body = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Card(
          child: SourceErrorView(
            error: result.error!,
            source: source,
            compact: true,
            onRetry: onRetry,
          ),
        ),
      );
    } else if (result.page!.items.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Text(
          tr('没有找到相关作品'),
          style: context.text.bodySmall?.copyWith(
            color: context.colors.onSurfaceVariant,
          ),
        ),
      );
    } else {
      final blocklist = TagBlocklist.current();
      final items = result.page!.items
          .where((e) => blocklist.matchItem(e) == null)
          .toList();
      if (items.isEmpty) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header,
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                tr('（已屏蔽 {value0} 部）', {'value0': result.page!.items.length}),
                style: context.text.bodySmall,
              ),
            ),
          ],
        );
      }
      final a = gridAspectFor(items, kind);
      final w = a > 1 ? 200.0 : 118.0;
      body = kind == MediaKind.novel
          ? Column(
              children: [for (final item in items) WorkTextRow(item: item)],
            )
          : items.any((item) => item.json['presentation'] == 'post')
          ? Column(
              children: [
                for (final item in items)
                  SubscriptionPostCard(
                    source: item.source,
                    post: SubscriptionPost(item.json),
                  ),
              ],
            )
          : SizedBox(
              height: w / a + cardTextExtent(context),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, i) => SizedBox(
                  width: w,
                  child: WorkCard(item: items[i], aspect: a),
                ),
              ),
            );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [header, body],
    );
  }
}
