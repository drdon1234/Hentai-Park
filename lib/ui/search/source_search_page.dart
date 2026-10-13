import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/localization.dart';
import '../../core/settings.dart';
import '../../core/content_scope.dart';
import '../../engine/source_manager.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/content_translation.dart';
import '../widgets/paged_grid.dart';
import 'multi_language.dart';
import 'search_toolbar.dart';
import '../discovery_navigation.dart';

/// Search inside one source with that source's native filters (sort, category, language, rating…).
class SourceSearchPage extends StatefulWidget {
  const SourceSearchPage({
    super.key,
    required this.sourceKey,
    this.initialKeyword = '',
    this.initialFilters,
    this.initialMulti,
    this.sourceManager,
  });
  final String sourceKey;
  final String initialKeyword;
  final Map<String, Object?>? initialFilters;
  final SourceManager? sourceManager;

  /// A keyword and its translations, searched together.
  final MultiKeyword? initialMulti;

  @override
  State<SourceSearchPage> createState() => _SourceSearchPageState();
}

class _SourceSearchPageState extends State<SourceSearchPage> {
  SourceManager get _sources => widget.sourceManager ?? SourceManager.instance;
  late final SourceManifest _m = _sources.manifest(widget.sourceKey)!;
  late final _text = TextEditingController(text: widget.initialKeyword);
  late Map<String, Object?> _filters = {
    ..._m.defaultFilters(),
    ...?widget.initialFilters,
  };
  late final PagedController _controller = PagedController(
    _load,
    source: widget.sourceKey,
  );
  bool _started = false;
  final _translation = KeywordTranslationRequest();
  bool get _translating => _translation.busy;

  void _translationChanged() => setState(() {});
  String _submitted = '';
  Map<String, Object?> _submittedFilters = const {};
  int _searchGeneration = 0;
  MultiKeyword? _multi;
  MultiKeywordSearch? _multiSearch;

  @override
  void initState() {
    super.initState();
    _translation.addListener(_translationChanged);
    _text.addListener(_textChanged);
    if (widget.initialMulti != null) {
      _multi = widget.initialMulti;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _search(keepMulti: true);
      });
    } else if (widget.initialKeyword.isNotEmpty ||
        (widget.initialFilters?.isNotEmpty ?? false)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _search();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _translation.dispose();
    _text.dispose();
    super.dispose();
  }

  void _textChanged() {
    if (_text.text.isEmpty && _started) {
      _searchGeneration++;
      setState(() => _started = false);
    }
  }

  Future<WorkPage> _load(int page, String? cursor) {
    if (page == 1 && _multi != null) {
      _multiSearch = MultiKeywordSearch(
        widget.sourceKey,
        _multi!.all,
        _submittedFilters,
        sourceManager: _sources,
      );
    }
    final multi = _multiSearch;
    if (multi != null) return multi.next();
    return _sources.search(
      widget.sourceKey,
      keyword: _submitted,
      page: page,
      cursor: cursor,
      filters: _submittedFilters,
    );
  }

  void _search({bool keepMulti = false}) {
    final k = _text.text.trim();
    _searchGeneration++;
    _submitted = k;
    _submittedFilters = Map.unmodifiable({
      for (final entry in _filters.entries)
        entry.key: entry.value is List
            ? List.unmodifiable(entry.value as List)
            : entry.value,
    });
    if (k.isNotEmpty) {
      AppSettings.instance.addSearchHistory(
        k,
        scope: ContentScope.source(widget.sourceKey),
      );
    }
    FocusScope.of(context).unfocus();
    if (!keepMulti || _multi?.original != k) _multi = null;
    _multiSearch = _multi == null
        ? null
        : MultiKeywordSearch(
            widget.sourceKey,
            _multi!.all,
            _submittedFilters,
            sourceManager: _sources,
          );
    setState(() => _started = true);
    _controller.refresh();
  }

  /// Translates the keyword into the configured languages and searches all of them at once.
  Future<void> _searchMulti() async {
    final k = _text.text.trim();
    if (_translating) return;
    if (!await confirmMultiLanguageSearch(context, k) ||
        !mounted ||
        _text.text.trim() != k) {
      return;
    }
    FocusScope.of(context).unfocus();
    final multi = await _translation.run(
      keyword: () => _text.text,
      generation: () => _searchGeneration,
      translate: (text) => translateKeyword(context, text),
    );
    if (!mounted || multi == null) return;
    _multi = multi;
    _search(keepMulti: true);
  }

  int get _activeFilters {
    final defaults = _m.defaultFilters();
    return _filters.entries.where((e) {
      final d = defaults[e.key];
      if (e.value is List) return (e.value as List).isNotEmpty;
      return e.value != d && !(e.value == null && d == null);
    }).length;
  }

  Future<void> _openFilters() async {
    final result = await showModalBottomSheet<Map<String, Object?>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => FilterSheet(manifest: _m, values: _filters),
    );
    if (mounted && result != null) {
      setState(() => _filters = result);
      _search(keepMulti: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    AppLocalizations.of(context);
    return TranslationPage(
      child: Theme(
        data: ParkTheme.build(Theme.of(context).brightness, _m.color),
        child: Builder(
          builder: (context) {
            return Scaffold(
              appBar: AppBar(
                title: Text(
                  _m.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                actions: [
                  const DomainMenu(),
                  TranslationControls(source: widget.sourceKey),
                ],
              ),
              body: SearchLayout(
                toolbar: SearchToolbar(
                  field: TextField(
                    controller: _text,
                    autofocus:
                        widget.initialKeyword.isEmpty &&
                        widget.initialFilters == null,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _search(),
                    decoration: InputDecoration(
                      hintText: tr('在 {source} 中搜索', {'source': _m.name}),
                      prefixIcon: Padding(
                        padding: const EdgeInsetsDirectional.fromSTEB(
                          14,
                          10,
                          12,
                          10,
                        ),
                        child: SourceAvatar(_m.key, size: 24),
                      ),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.close_rounded),
                        tooltip: tr('清空'),
                        onPressed: _text.clear,
                      ),
                      contentPadding: SearchToolbar.inputPadding,
                    ),
                  ),
                  actions: [
                    if (_m.searchFilters.isNotEmpty)
                      TextButton.icon(
                        label: Text(tr('筛选')),
                        icon: Badge(
                          isLabelVisible: _activeFilters > 0,
                          label: Text('$_activeFilters'),
                          child: const Icon(Icons.filter_list_rounded),
                        ),
                        onPressed: _openFilters,
                      ),
                    _translating
                        ? const Padding(
                            padding: EdgeInsets.all(14),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                              ),
                            ),
                          )
                        : TextButton.icon(
                            label: Text(tr('多语言搜索')),
                            onPressed: _searchMulti,
                            icon: const Icon(Icons.language_rounded),
                          ),
                    FilledButton.icon(
                      label: Text(tr('搜索')),
                      icon: const Icon(Icons.search_rounded),
                      onPressed: _search,
                    ),
                  ],
                ),
                results: !_started
                    ? ListenableBuilder(
                        listenable: AppSettings.instance,
                        builder: (context, _) => _Intro(
                          manifest: _m,
                          onPick: (k) {
                            _text.text = k;
                            _search();
                          },
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _controller.refresh,
                        child: CustomScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          slivers: [
                            if (_multi != null)
                              SliverToBoxAdapter(
                                child: TranslationsBar(
                                  keyword: _multi!,
                                  onPick: (k) {
                                    _text.text = k;
                                    _search();
                                  },
                                ),
                              ),
                            if (_activeFilters > 0)
                              SliverToBoxAdapter(
                                child: _ActiveFilters(
                                  manifest: _m,
                                  values: _filters,
                                  onTap: _openFilters,
                                ),
                              ),
                            PagedSliverGrid(
                              controller: _controller,
                              kind: _m.kind,
                            ),
                          ],
                        ),
                      ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro({required this.manifest, required this.onPick});
  final SourceManifest manifest;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    AppLocalizations.of(context);
    final scope = ContentScope.source(manifest.key);
    final history = AppSettings.instance.searchHistoryFor(scope);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (manifest.searchHint.isNotEmpty)
          Card(
            child: ListTile(
              leading: Icon(
                Icons.lightbulb_outline_rounded,
                color: context.colors.primary,
              ),
              title: Text(tr('搜索技巧')),
              subtitle: Text(manifest.searchHint),
            ),
          ),
        if (history.isNotEmpty) ...[
          SectionHeader(
            tr('最近搜索'),
            padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
            trailing: IconButton(
              tooltip: tr('清空'),
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: () =>
                  AppSettings.instance.clearSearchHistory(scope: scope),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final k in history)
                InputChip(
                  label: Text(k),
                  onPressed: () => onPick(k),
                  onDeleted: () =>
                      AppSettings.instance.removeSearchHistory(k, scope: scope),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _ActiveFilters extends StatelessWidget {
  const _ActiveFilters({
    required this.manifest,
    required this.values,
    required this.onTap,
  });
  final SourceManifest manifest;
  final Map<String, Object?> values;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    AppLocalizations.of(context);
    final defaults = manifest.defaultFilters();
    final chips = <String>[];
    for (final f in manifest.searchFilters) {
      final v = values[f.key];
      if (v is List) {
        if (v.isNotEmpty) chips.add('${f.label}：${v.map(f.labelOf).join('、')}');
      } else if (v != defaults[f.key] &&
          v != null &&
          '$v' != '' &&
          '$v' != '0') {
        chips.add('${f.label}：${f.values.isEmpty ? v : f.labelOf(v)}');
      }
    }
    for (final e in values.entries) {
      if (!manifest.searchFilters.any((f) => f.key == e.key) &&
          e.value is List &&
          (e.value as List).isNotEmpty) {
        chips.add(tr('标签：{tags}', {'tags': (e.value as List).join(tr('、'))}));
      }
    }
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: [
          for (final c in chips)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ActionChip(
                label: Text(c),
                onPressed: onTap,
                visualDensity: VisualDensity.compact,
              ),
            ),
        ],
      ),
    );
  }
}

/// Bottom sheet editing a source's search filters.
class FilterSheet extends StatefulWidget {
  const FilterSheet({super.key, required this.manifest, required this.values});
  final SourceManifest manifest;
  final Map<String, Object?> values;

  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {
  late final Map<String, Object?> _v = {...widget.values};

  @override
  Widget build(BuildContext context) {
    AppLocalizations.of(context);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      builder: (context, scroll) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 12, 4),
            child: Row(
              children: [
                Text(
                  tr('筛选'),
                  style: context.text.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(
                    () => _v
                      ..clear()
                      ..addAll(widget.manifest.defaultFilters()),
                  ),
                  child: Text(tr('重置')),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              controller: scroll,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                for (final f in widget.manifest.searchFilters) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 14, bottom: 8),
                    child: Text(
                      f.label,
                      style: context.text.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (f.type == 'number')
                    _NumberField(
                      value: (_v[f.key] as num?)?.toInt() ?? 0,
                      onChanged: (n) => setState(() => _v[f.key] = n),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final c in f.values)
                          if (f.type == 'multi')
                            FilterChip(
                              label: Text(c.label),
                              selected: ((_v[f.key] as List?) ?? []).contains(
                                c.value,
                              ),
                              avatar: c.color != null
                                  ? CircleAvatar(
                                      backgroundColor: parseHexColor(c.color!),
                                      radius: 5,
                                    )
                                  : null,
                              showCheckmark: false,
                              onSelected: (on) => setState(() {
                                final list = [...((_v[f.key] as List?) ?? [])];
                                on ? list.add(c.value) : list.remove(c.value);
                                _v[f.key] = list;
                              }),
                            )
                          else
                            ChoiceChip(
                              label: Text(c.label),
                              selected: _v[f.key] == c.value,
                              showCheckmark: false,
                              onSelected: (_) =>
                                  setState(() => _v[f.key] = c.value),
                            ),
                      ],
                    ),
                ],
                const SizedBox(height: 24),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, _v),
                  child: Text(tr('应用筛选')),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    AppLocalizations.of(context);
    return Row(
      children: [
        IconButton.filledTonal(
          onPressed: value > 0
              ? () => onChanged((value - 10).clamp(0, 9999))
              : null,
          icon: const Icon(Icons.remove_rounded),
        ),
        SizedBox(
          width: 72,
          child: Text(
            value == 0 ? tr('不限') : '≥ $value',
            textAlign: TextAlign.center,
            style: context.text.titleMedium,
          ),
        ),
        IconButton.filledTonal(
          onPressed: () => onChanged(value + 10),
          icon: const Icon(Icons.add_rounded),
        ),
      ],
    );
  }
}
