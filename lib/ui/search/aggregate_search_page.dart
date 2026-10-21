import 'package:flutter/material.dart';

import '../../core/content_scope.dart';
import '../../core/localization.dart';
import '../../core/models.dart';
import '../../core/settings.dart';
import '../../engine/source_manager.dart';
import '../kit/adaptive_sheet.dart';
import '../nav.dart';
import '../settings/source_manage_page.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/content_translation.dart';
import 'aggregate_search_controller.dart';
import 'aggregate_search_widgets.dart';
import 'multi_language.dart';

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

  List<InstalledSource> get _eligible => _sources.displayEnabled
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
    final refs = _sources.extractRefs(k).where((ref) {
      final manifest = _sources.manifest(ref.source);
      return manifest != null && manifest.can('detail');
    }).toList();
    if (refs.isNotEmpty && _multi == null) {
      setState(() {
        _submitted = '';
        _submittedSources = [];
      });
      if (refs.length == 1) {
        Nav.openRef(
          context,
          refs.single.source,
          refs.single.id,
          sourceManager: widget.sourceManager,
        );
      }
      return;
    }
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

  Future<void> _paste() async {
    final text = await readSearchClipboard(context, focusNode: _focus);
    if (mounted && text != null) {
      _text.value = TextEditingValue(
        text: text.trim(),
        selection: TextSelection.collapsed(offset: text.trim().length),
      );
      _submit(_text.text);
    }
  }

  void _toggleSite(String key, bool on) {
    AppSettings.instance.setAggregateIncluded(key, on);
    _generation++;
    if (_submitted.isNotEmpty && _text.text.trim() == _submitted) _dispatch();
  }

  /// Which sites take part, grouped by category; most visits never need it, so it lives in a sheet.
  Future<void> _editSites() => showAdaptiveSheet<void>(
    context: context,
    sheetAnimationStyle: Motion.menu(context),
    isScrollControlled: true,
    builder: (ctx) => ListenableBuilder(
      listenable: AppSettings.instance.watch(const {'aggregateExcluded'}),
      builder: (ctx, _) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * .8,
          ),
          child: SearchScopeBar(
            sources: _eligible,
            scope: _targets.map((s) => s.key).toSet(),
            onToggle: _toggleSite,
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final typed = _text.text.trim();
    return TranslationPage(
      child: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(
            titleSpacing: 0,
            title: ParkSearchField(
              controller: _text,
              focusNode: _focus,
              hint: tr('作品、标签、链接或编号'),
              onSubmitted: _submit,
              trailing: [
                IconButton(
                  icon: Icon(
                    typed.isEmpty
                        ? Icons.content_paste_rounded
                        : Icons.close_rounded,
                  ),
                  tooltip: tr(typed.isEmpty ? '粘贴' : '清空'),
                  onPressed: () => typed.isEmpty ? _paste() : _text.clear(),
                ),
              ],
            ),
            actions: const [
              TranslationControls(),
              SizedBox(width: Gap.xs),
            ],
          ),
          body: ListenableBuilder(
            listenable: Listenable.merge([
              _sources,
              AppSettings.instance.watch(AppSettings.filterKeys),
              AppSettings.instance.watch(const {
                'aggregateExcluded',
                'domainOrder',
                'searchHistories',
              }),
              _results,
            ]),
            builder: (context, _) {
              final submittedKeys = _submittedSources.map((s) => s.key).toSet();
              final resultSources = _sources.displayAll
                  .where((s) => submittedKeys.contains(s.key))
                  .toList();
              final refs = typed.isEmpty
                  ? const <({String source, String id})>[]
                  : _directRefs(typed);
              final eligible = _eligible.length;
              final included = _targets.length;
              return CustomScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        Gap.page,
                        Gap.s,
                        Gap.page,
                        0,
                      ),
                      child: Wrap(
                        spacing: Gap.s,
                        runSpacing: Gap.s,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          MenuChip<SourceCategory?>(
                            label: _range.isAll ? tr('全部分类') : _domain.label,
                            active: !_range.isAll,
                            options: {
                              null: tr('全部分类'),
                              for (final d in AppSettings.instance.domainOrder)
                                d: d.label,
                            },
                            onSelected: (d) => _changeRange(
                              d == null
                                  ? const ContentScope.all()
                                  : ContentScope.domain(d),
                            ),
                          ),
                          ActionChip(
                            label: SelectionContainer.disabled(
                              child: Text(
                                included == eligible
                                    ? tr('全部站点 · {count}', {'count': eligible})
                                    : tr('站点 {included}/{count}', {
                                        'included': included,
                                        'count': eligible,
                                      }),
                              ),
                            ),
                            onPressed: _editSites,
                          ),
                          if (_translation.busy)
                            const Padding(
                              padding: EdgeInsets.all(Gap.s),
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          else
                            ActionChip(
                              avatar: const Icon(
                                Icons.translate_rounded,
                                size: 18,
                              ),
                              label: SelectionContainer.disabled(
                                child: Text(tr('多语言搜索')),
                              ),
                              onPressed: typed.isEmpty ? null : _submitMulti,
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (refs.isNotEmpty)
                    SliverToBoxAdapter(
                      child: DirectJump(refs: refs, sourceManager: _sources),
                    ),
                  if (_submitted.isEmpty || typed != _submitted)
                    SliverToBoxAdapter(
                      child: SearchHistoryList(
                        scope: _range,
                        onPick: (k) => _submit(k),
                      ),
                    ),
                  if (_awaitingSources)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.all(Gap.xl),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    ),
                  if (!_awaitingSources &&
                      (_submitted.isEmpty ? _targets : _submittedSources)
                          .isEmpty)
                    SliverToBoxAdapter(
                      child: EmptyState(
                        icon: Icons.search_off,
                        title: tr('这个范围没有可搜索的站点'),
                        actions: [
                          OutlinedButton(
                            onPressed: () =>
                                Nav.push(context, const SourceManagePage()),
                            child: SelectionContainer.disabled(
                              child: Text(tr('管理站点')),
                            ),
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
                        if (_range.isAll)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                Gap.page,
                                Gap.xl,
                                Gap.page,
                                0,
                              ),
                              child: Text(
                                category.label,
                                style: context.text.labelLarge?.copyWith(
                                  color: context.colors.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                        SliverList.list(
                          children: [
                            for (final s in resultSources.where(
                              (s) => s.manifest!.category == category,
                            ))
                              if (_sources.manifest(s.key) != null)
                                SourceResultsRow(
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
                  const SliverToBoxAdapter(child: SizedBox(height: Gap.xxl)),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  List<({String source, String id})> _directRefs(String text) {
    final sm = _sources;
    final refs = sm.extractRefs(text);
    final hasLinks = refs.isNotEmpty;
    // A bare word without digits is a keyword; several sites accept any slug as an ID.
    if (refs.isEmpty && !text.contains(' ') && RegExp(r'\d').hasMatch(text)) {
      for (final s in sm.displayEnabled) {
        final id = s.manifest!.matchExplicitId(text);
        if (id != null) refs.add((source: s.key, id: id));
      }
    }
    final seen = <String>{};
    return refs
        .where((r) {
          final m = sm.manifest(r.source);
          return m != null &&
              m.can('detail') &&
              (hasLinks || _range.contains(r.source, m.category)) &&
              seen.add('${r.source}:${r.id}');
        })
        .take(6)
        .toList();
  }
}
