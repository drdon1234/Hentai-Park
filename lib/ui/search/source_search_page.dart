import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/content_scope.dart';
import '../../core/localization.dart';
import '../../core/models.dart';
import '../../core/settings.dart';
import '../../engine/source_manager.dart';
import '../album/open_album.dart';
import '../kit/adaptive_sheet.dart';
import '../nav.dart';
import '../short_video/post_video_feed.dart';
import '../short_video/short_video_page.dart';
import '../theme.dart';
import '../voice/voice_work_filters.dart';
import '../widgets/common.dart';
import '../widgets/common_filters.dart';
import '../widgets/content_translation.dart';
import '../widgets/filter_controller.dart';
import '../widgets/option_bar.dart';
import '../widgets/paged_grid.dart';
import '../widgets/result_visibility.dart';
import '../widgets/source_account_strip.dart';
import 'multi_language.dart';
import 'search_suggestions.dart';

/// Search inside one source with that source's native filters (sort, category, language, rating…).
class SourceSearchPage extends StatefulWidget {
  const SourceSearchPage({
    super.key,
    required this.sourceKey,
    this.initialKeyword = '',
    this.initialFilters,
    this.initialCommon,
    this.initialMulti,
    this.initialPage,
    this.initialMultiSearch,
    this.initialShowBlocked = false,
    this.initialHidePreviews = false,
    this.sourceManager,
    this.searchOnlyEntry = false,
  });
  final String sourceKey;
  final WorkPage? initialPage;
  final MultiKeywordSearch? initialMultiSearch;
  final bool initialShowBlocked, initialHidePreviews;
  final String initialKeyword;
  final Map<String, Object?>? initialFilters;
  final Map<String, Object?>? initialCommon;
  final SourceManager? sourceManager;
  final bool searchOnlyEntry;

  /// A keyword and its translations, searched together.
  final MultiKeyword? initialMulti;

  @override
  State<SourceSearchPage> createState() => _SourceSearchPageState();
}

class _SourceSearchPageState extends State<SourceSearchPage> {
  SourceManager get _sources => widget.sourceManager ?? SourceManager.instance;
  late final SourceManifest _m = _sources.manifest(widget.sourceKey)!;
  late final _text = TextEditingController(text: widget.initialKeyword);
  final _focus = FocusNode();
  late Map<String, Object?> _filters = {
    ..._m.defaultFilters(),
    ...?widget.initialFilters,
  };
  late Map<String, Object?> _commonFilters = Map<String, Object?>.from(
    widget.initialCommon ?? const {},
  );
  late String _filterKeyword = widget.initialKeyword.trim();
  late final PagedController _controller = PagedController(
    _load,
    source: widget.sourceKey,
  );
  String _configuration = '';
  void _configurationChanged() {
    final next = jsonEncode(_sources.settingsOf(widget.sourceKey));
    if (next == _configuration) return;
    _configuration = next;
    if (_started) unawaited(_controller.refresh());
  }

  bool _started = false;
  WorkPage? _initialPage;
  late final _suggestions = SearchSuggestions(
    (keyword, token, _) => _sources.searchSuggestions(
      widget.sourceKey,
      keyword,
      cancelToken: token,
    ),
  );
  final _translation = KeywordTranslationRequest();
  bool get _translating => _translation.busy;

  void _translationChanged() => setState(() {});
  String _submitted = '';
  Map<String, Object?> _submittedFilters = const {};
  Map<String, Object?> _submittedCommon = const {};
  int _searchGeneration = 0;
  MultiKeyword? _multi;
  MultiKeywordSearch? _multiSearch;

  PostVideoScope get _postScope => PostVideoScope(
    source: widget.sourceKey,
    title: _submitted,
    keyword: _submitted,
    filters: Map.of(_submittedFilters),
    common: Map.of(_submittedCommon),
  );

  @override
  void initState() {
    super.initState();
    _configuration = jsonEncode(_sources.settingsOf(widget.sourceKey));
    _sources.addListener(_configurationChanged);
    _translation.addListener(_translationChanged);
    _text.addListener(_textChanged);
    _focus.addListener(() {
      if (!_focus.hasFocus) _suggestions.clear();
    });
    _controller.showBlocked = widget.initialShowBlocked;
    _controller.hidePreviews = widget.initialHidePreviews;
    _initialPage = widget.initialPage;
    if (widget.initialMulti != null) {
      _multi = widget.initialMulti;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _search(keepMulti: true);
      });
    } else if (widget.initialKeyword.isNotEmpty ||
        (widget.initialFilters?.isNotEmpty ?? false) ||
        (widget.initialCommon?.isNotEmpty ?? false)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _search();
      });
    }
  }

  @override
  void dispose() {
    _sources.removeListener(_configurationChanged);
    _suggestions.dispose();
    _controller.dispose();
    _translation.dispose();
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _textChanged() {
    _syncFilterKeyword(_text.text.trim());
    if (_focus.hasFocus &&
        _m.can('searchSuggestions') &&
        _text.value.composing.isCollapsed) {
      _suggestions.update(_text.text);
    } else {
      _suggestions.clear();
    }
    if (_text.text.isEmpty && _started) {
      _searchGeneration++;
      setState(() => _started = false);
    }
  }

  void _syncFilterKeyword(String keyword) {
    if (_filterKeyword == keyword) return;
    _filterKeyword = keyword;
    final reset = {
      for (final option in _m.searchFilters)
        if (option.dynamicValues && option.keywordDependent) option.key,
    };
    var changed = true;
    while (changed) {
      changed = false;
      for (final option in _m.searchFilters) {
        if (!reset.contains(option.key) &&
            option.dependsOn.any(reset.contains)) {
          reset.add(option.key);
          changed = true;
        }
      }
    }
    if (reset.isEmpty) return;
    setState(() {
      _filters = {
        ..._filters,
        for (final option in _m.searchFilters)
          if (reset.contains(option.key)) option.key: option.defaultValue,
      };
    });
  }

  Future<WorkPage> _load(int page, String? cursor) {
    final initial = _initialPage;
    _initialPage = null;
    if (page == 1 && initial != null) {
      _multiSearch = widget.initialMultiSearch;
      return Future.value(initial);
    }
    if (page == 1 && _multi != null) {
      _multiSearch = MultiKeywordSearch(
        widget.sourceKey,
        _multi!.all,
        _submittedFilters,
        common: _submittedCommon,
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
      common: _submittedCommon,
    );
  }

  void _search({bool keepMulti = false}) {
    _suggestions.clear();
    final k = _text.text.trim();
    _syncFilterKeyword(k);
    final refs = _sources
        .extractRefs(k)
        .where((ref) => _sources.manifest(ref.source)?.can('detail') == true)
        .toList();
    if (refs.length == 1 && !keepMulti) {
      FocusScope.of(context).unfocus();
      Nav.openRef(
        context,
        refs.single.source,
        refs.single.id,
        sourceManager: widget.sourceManager,
      );
      return;
    }
    _searchGeneration++;
    _submitted = k;
    _submittedFilters = Map.unmodifiable({
      for (final entry in _filters.entries)
        entry.key: entry.value is List
            ? List.unmodifiable(entry.value as List)
            : entry.value,
    });
    _submittedCommon = normalizeCommonFilters(
      _m.searchCommonFilters,
      _commonFilters,
    );
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
            common: _submittedCommon,
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
    final native = _filters.entries.where((e) {
      final d = defaults[e.key];
      if (e.value is List && d is List) return !listEquals(e.value as List, d);
      return e.value != d && !(e.value == null && d == null);
    }).length;
    return native + _commonFilters.length;
  }

  Future<void> _openFilters() async {
    final keyword = _text.text.trim();
    _syncFilterKeyword(keyword);
    final result = await showAdaptiveSheet<FilterSheetResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => FilterSheet(
        manifest: _m,
        values: _filters,
        commonValues: _commonFilters,
        sourceManager: _sources,
        keyword: keyword,
      ),
    );
    if (mounted && result != null && _text.text.trim() == keyword) {
      setState(() {
        _filters = result.filters;
        _commonFilters = result.common;
      });
      _search(keepMulti: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TranslationPage(
      child: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(
            bottom: widget.searchOnlyEntry && _m.account != null
                ? PreferredSize(
                    preferredSize: Size.fromHeight(
                      SourceAccountStrip.height(context),
                    ),
                    child: SourceAccountStrip(
                      source: widget.sourceKey,
                      sourceManager: _sources,
                    ),
                  )
                : null,
            titleSpacing: 0,
            title: ParkSearchField(
              controller: _text,
              focusNode: _focus,
              autofocus:
                  !widget.searchOnlyEntry &&
                  widget.initialKeyword.isEmpty &&
                  widget.initialFilters == null,
              hint: tr('在 {source} 中搜索', {'source': _m.name}),
              onSubmitted: (_) => _search(),
              trailing: [
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  tooltip: tr('清空'),
                  onPressed: _text.clear,
                ),
              ],
            ),
            actions: [
              const TranslationControls(),
              IconButton(
                tooltip: tr('多语言搜索'),
                onPressed: _translating ? null : _searchMulti,
                icon: _translating
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.g_translate_rounded),
              ),
            ],
          ),
          body: Column(
            children: [
              if (widget.searchOnlyEntry && !_started)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Gap.page,
                    Gap.s,
                    Gap.page,
                    0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr('超级省流'), style: context.text.labelLarge),
                      Text(
                        tr('站点页不自动加载作品，输入关键词后搜索'),
                        style: context.text.bodySmall,
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Gap.page,
                  Gap.s,
                  Gap.page,
                  Gap.xs,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        SourceAvatar(_m.key, size: 20),
                        const SizedBox(width: Gap.s),
                        Expanded(
                          child: Text(
                            _m.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.labelLarge?.copyWith(
                              color: context.colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                        ResultVisibility(
                          supportsPreviews: _m.can('previewContent'),
                          showBlocked: _controller.showBlocked,
                          hidePreviews: _controller.hidePreviews,
                          onBlocked: (v) => setState(
                            () => _controller.setVisibility(blocked: v),
                          ),
                          onPreviews: (v) => setState(
                            () => _controller.setVisibility(previews: v),
                          ),
                        ),
                        if (_m.searchFilters.isNotEmpty ||
                            _m.searchCommonFilters.isNotEmpty)
                          Badge(
                            isLabelVisible: _activeFilters > 0,
                            label: Text('$_activeFilters'),
                            child: IconButton(
                              tooltip: tr('筛选'),
                              onPressed: _openFilters,
                              icon: const Icon(Icons.filter_alt_outlined),
                            ),
                          ),
                      ],
                    ),
                    if (_started &&
                        _multi == null &&
                        (_m.supportsAlbumMode || _m.supportsShortVideoMode))
                      Wrap(
                        spacing: Gap.s,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (_m.supportsAlbumMode)
                            ToolbarButton.icon(
                              icon: const Icon(Icons.photo_library_outlined),
                              label: Text(tr('相册')),
                              onPressed: () => openMediaAlbum(
                                context,
                                source: widget.sourceKey,
                                title: _submitted,
                                sources: _sources,
                                scope: {
                                  'search': {
                                    'keyword': _submitted,
                                    'filters': Map.of(_submittedFilters),
                                    'common': Map.of(_submittedCommon),
                                  },
                                },
                              ),
                            ),
                          if (_m.supportsShortVideoMode)
                            ToolbarButton.icon(
                              icon: const Icon(Icons.smart_display_outlined),
                              label: Text(tr('短视频模式')),
                              onPressed: () => Nav.push(
                                context,
                                ShortVideoPage(
                                  source: widget.sourceKey,
                                  sequence: _controller.sequence(),
                                ),
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
              Expanded(
                child: ListenableBuilder(
                  listenable: _suggestions,
                  builder: (context, _) => _suggestions.items.isNotEmpty
                      ? ListView(
                          padding: const EdgeInsets.symmetric(
                            horizontal: Gap.page,
                          ),
                          children: [
                            for (final item in _suggestions.items)
                              ListTile(
                                leading: const Icon(Icons.search),
                                title: Text(item['label']!),
                                subtitle: item['subtitle']!.isEmpty
                                    ? null
                                    : Text(item['subtitle']!),
                                onTap: () {
                                  _text.text = item['keyword']!;
                                  _search();
                                },
                              ),
                          ],
                        )
                      : !_started
                      ? ListenableBuilder(
                          listenable: AppSettings.instance.watch(const {
                            'searchHistories',
                          }),
                          builder: (context, _) => _Intro(
                            manifest: _m,
                            onPick: (k) {
                              _text.text = k;
                              _search();
                            },
                          ),
                        )
                      : ParkRefresh(
                          onRefresh: () =>
                              _controller.refresh(retainItems: true),
                          child: CustomScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            slivers: [
                              if (_m.category == SourceCategory.asmr)
                                SliverToBoxAdapter(
                                  child: VoiceWorkFilters(
                                    controller: _controller,
                                  ),
                                ),
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
                                    commonValues: _commonFilters,
                                    onTap: _openFilters,
                                  ),
                                ),
                              PostVideoContext(
                                scope: _postScope,
                                child: PagedSliverGrid(
                                  controller: _controller,
                                  kind: _m.kind,
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
              ),
            ],
          ),
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
    final scope = ContentScope.source(manifest.key);
    final history = AppSettings.instance.searchHistoryFor(scope);
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: Gap.page),
      children: [
        if (manifest.searchHint.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: Gap.m),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.lightbulb_outline_rounded,
                  size: 18,
                  color: context.colors.onSurfaceVariant,
                ),
                const SizedBox(width: Gap.s),
                Expanded(
                  child: Text(
                    manifest.searchHint,
                    style: context.text.bodyMedium?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (history.isNotEmpty) ...[
          SectionHeader(
            tr('最近搜索'),
            padding: const EdgeInsets.fromLTRB(0, Gap.xl, 0, Gap.s),
            trailing: ToolbarButton(
              onPressed: () =>
                  AppSettings.instance.clearSearchHistory(scope: scope),
              child: SelectionContainer.disabled(child: Text(tr('清空'))),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final k in history)
                InputChip(
                  label: SelectionContainer.disabled(child: Text(k)),
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
    this.commonValues = const {},
    required this.onTap,
  });
  final SourceManifest manifest;
  final Map<String, Object?> values;
  final Map<String, Object?> commonValues;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
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
    if (commonValues.isNotEmpty) chips.add(tr('通用筛选'));
    return PageGutter(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(vertical: Gap.s),
        child: Row(
          children: [
            for (final c in chips)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ActionChip(
                  label: SelectionContainer.disabled(child: Text(c)),
                  onPressed: onTap,
                  visualDensity: VisualDensity.compact,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet editing a source's search filters.
class FilterSheet extends StatefulWidget {
  const FilterSheet({
    super.key,
    required this.manifest,
    required this.values,
    required this.commonValues,
    required this.sourceManager,
    required this.keyword,
    this.feed,
  });
  final FeedDef? feed;
  List<OptionDef> get definitions => feed?.options ?? manifest.searchFilters;
  List<CommonFilterDef> get commonDefinitions => feed == null
      ? manifest.searchCommonFilters
      : manifest.sharedFeedCommonFilters;
  List<CommonFilterDef> get feedSpecificCommonDefinitions =>
      feed == null ? const [] : manifest.uniqueFeedCommonFilters(feed!);
  final SourceManifest manifest;
  final Map<String, Object?> values;
  final Map<String, Object?> commonValues;
  final SourceManager sourceManager;
  final String keyword;

  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class FilterSheetResult {
  const FilterSheetResult({required this.filters, required this.common});
  final Map<String, Object?> filters;
  final Map<String, Object?> common;
}

class _FilterSheetState extends State<FilterSheet> {
  final _choiceQueries = <String, String>{};

  Iterable<Choice> _visibleChoices(String key) {
    final query = _choiceQueries[key]?.trim().toLowerCase() ?? '';
    return _filters
        .choicesFor(key)
        .where(
          (choice) =>
              query.isEmpty || choice.label.toLowerCase().contains(query),
        );
  }

  late final FilterController _filters = FilterController(
    source: widget.manifest.key,
    scope: widget.feed == null ? 'search' : 'feed',
    feed: widget.feed?.key,
    keyword: widget.keyword,
    definitions: widget.definitions,
    loader: (filter, values, token) => widget.sourceManager.filterOptions(
      widget.manifest.key,
      scope: widget.feed == null ? 'search' : 'feed',
      feed: widget.feed?.key,
      filter: filter,
      keyword: widget.keyword,
      values: values,
      cancelToken: token,
    ),
  );
  late Map<String, Object?> _commonValues = widget.commonValues;
  bool _commonValid = true;
  bool _feedCommonValid = true;
  bool _baseCommonValid = true;
  int _commonRevision = 0;
  bool _initializing = true;
  int _initializationGeneration = 0;

  void _reset() {
    _initializationGeneration++;
    _filters.reset();
    setState(() {
      _initializing = false;
      _commonValues = const {};
      _commonValid = true;
      _feedCommonValid = true;
      _baseCommonValid = true;
      _commonRevision++;
    });
  }

  @override
  void initState() {
    super.initState();
    _initializeFilters();
  }

  Future<void> _initializeFilters() async {
    final generation = ++_initializationGeneration;
    await _filters.initialize(initialValues: widget.values);
    if (!mounted || generation != _initializationGeneration) return;
    await _filters.loadEnabledDynamic();
    if (mounted && generation == _initializationGeneration) {
      setState(() => _initializing = false);
    }
  }

  @override
  void dispose() {
    _filters.dispose();
    super.dispose();
  }

  Future<void> _change(String key, Object? value) async {
    _filters.setValue(key, value);
    await _filters.loadEnabledDynamic();
  }

  @override
  Widget build(BuildContext context) {
    return TranslationPage(
      child: ListenableBuilder(
        listenable: _filters,
        builder: (context, _) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          maxChildSize: 0.92,
          builder: (context, scroll) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Gap.page,
                  0,
                  Gap.page,
                  Gap.xs,
                ),
                child: Row(
                  children: [
                    Text(
                      tr('筛选'),
                      style: context.text.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    if (widget.definitions.any((f) => f.dynamicValues))
                      const TranslationControls(),
                    ToolbarButton(
                      onPressed: _reset,
                      child: SelectionContainer.disabled(child: Text(tr('重置'))),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scroll,
                  padding: const EdgeInsets.fromLTRB(
                    Gap.page,
                    Gap.m,
                    Gap.page,
                    Gap.m,
                  ),
                  children: [
                    for (final f in widget.definitions) ...[
                      IgnorePointer(
                        ignoring: _initializing || !_filters.isEnabled(f.key),
                        child: Opacity(
                          opacity: _filters.isEnabled(f.key) ? 1 : 0.45,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (f.type != 'switch')
                                Padding(
                                  padding: const EdgeInsets.only(
                                    top: 14,
                                    bottom: 8,
                                  ),
                                  child: Text(
                                    f.label,
                                    style: context.text.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              if (f.type == 'number')
                                TextFormField(
                                  key: ValueKey((_commonRevision, f.key)),
                                  initialValue:
                                      (_filters.values[f.key] == 0
                                          ? ''
                                          : _filters.values[f.key]
                                                ?.toString()) ??
                                      '',
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                  ],
                                  decoration: InputDecoration(
                                    hintText: tr('不限'),
                                  ),
                                  onChanged: (value) =>
                                      _change(f.key, int.tryParse(value) ?? 0),
                                )
                              else if (f.type == 'text')
                                TextFormField(
                                  key: ValueKey((_commonRevision, f.key)),
                                  initialValue:
                                      _filters.values[f.key]?.toString() ?? '',
                                  onChanged: (value) => _change(f.key, value),
                                )
                              else if (f.type == 'switch')
                                SwitchListTile.adaptive(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(f.label),
                                  value: _filters.values[f.key] == true,
                                  onChanged: (value) => _change(f.key, value),
                                )
                              else ...[
                                TextField(
                                  key: ValueKey(('choice-search', f.key)),
                                  decoration: InputDecoration(
                                    prefixIcon: const Icon(
                                      Icons.search_rounded,
                                    ),
                                    hintText: tr('搜索'),
                                  ),
                                  onChanged: (value) => setState(
                                    () => _choiceQueries[f.key] = value,
                                  ),
                                ),
                                const SizedBox(height: Gap.s),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (final c in _visibleChoices(f.key))
                                      if (f.type == 'multi')
                                        FilterChip(
                                          label: SelectionContainer.disabled(
                                            child: OptionBar.choiceLabel(
                                              f,
                                              c,
                                              widget.manifest.key,
                                            ),
                                          ),
                                          selected:
                                              ((_filters.values[f.key]
                                                          as List?) ??
                                                      [])
                                                  .contains(c.value),
                                          avatar: c.color != null
                                              ? CircleAvatar(
                                                  backgroundColor:
                                                      parseHexColor(c.color!),
                                                  radius: 5,
                                                )
                                              : null,
                                          showCheckmark: false,
                                          onSelected: (on) {
                                            final list = [
                                              ...((_filters.values[f.key]
                                                      as List?) ??
                                                  []),
                                            ];
                                            on
                                                ? list.add(c.value)
                                                : list.remove(c.value);
                                            _change(f.key, list);
                                          },
                                        )
                                      else
                                        ChoiceChip(
                                          label: SelectionContainer.disabled(
                                            child: OptionBar.choiceLabel(
                                              f,
                                              c,
                                              widget.manifest.key,
                                            ),
                                          ),
                                          selected:
                                              _filters.values[f.key] == c.value,
                                          showCheckmark: false,
                                          onSelected: (_) =>
                                              _change(f.key, c.value),
                                        ),
                                  ],
                                ),
                              ],
                              if (f.dynamicValues &&
                                  _filters.isLoadingOption(f.key))
                                const Padding(
                                  padding: EdgeInsets.all(8),
                                  child: LinearProgressIndicator(),
                                ),
                              if (_filters.errorFor(f.key) != null)
                                OutlinedButton.icon(
                                  onPressed: () => _filters.loadDynamic(f.key),
                                  icon: const Icon(Icons.refresh_rounded),
                                  label: Text(tr('加载失败，点击重试')),
                                ),
                              if ({'text', 'number'}.contains(f.type))
                                const SizedBox(height: Gap.m),
                            ],
                          ),
                        ),
                      ),
                    ],
                    if (widget.feedSpecificCommonDefinitions.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: Gap.m),
                        child: Text(
                          tr('栏目筛选'),
                          style: context.text.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      CommonFilterFields(
                        key: ValueKey((_commonRevision, 'feed')),
                        definitions: widget.feedSpecificCommonDefinitions,
                        initialValues: _commonValues,
                        onChanged: (values, valid) => setState(() {
                          final dimensions = widget
                              .feedSpecificCommonDefinitions
                              .map((definition) => definition.dimension.name)
                              .toSet();
                          _commonValues = {
                            for (final entry in _commonValues.entries)
                              if (!dimensions.contains(entry.key))
                                entry.key: entry.value,
                            ...values,
                          };
                          _feedCommonValid = valid;
                          _commonValid = _feedCommonValid && _baseCommonValid;
                        }),
                      ),
                      const SizedBox(height: Gap.m),
                    ],
                    if (widget.commonDefinitions.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: Gap.m),
                        child: Text(
                          tr('通用筛选'),
                          style: context.text.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      CommonFilterFields(
                        key: ValueKey((_commonRevision, 'base')),
                        definitions: widget.commonDefinitions,
                        initialValues: _commonValues,
                        onChanged: (values, valid) => setState(() {
                          final dimensions = widget.commonDefinitions
                              .map((definition) => definition.dimension.name)
                              .toSet();
                          _commonValues = {
                            for (final entry in _commonValues.entries)
                              if (!dimensions.contains(entry.key))
                                entry.key: entry.value,
                            ...values,
                          };
                          _baseCommonValid = valid;
                          _commonValid = _feedCommonValid && _baseCommonValid;
                        }),
                      ),
                      const SizedBox(height: Gap.m),
                    ],
                    const SizedBox(height: 24),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Gap.page,
                    Gap.s,
                    Gap.page,
                    Gap.m,
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed:
                          _commonValid && !_initializing && !_filters.isLoading
                          ? () => Navigator.pop(
                              context,
                              FilterSheetResult(
                                filters: _filters.values,
                                common: _commonValues,
                              ),
                            )
                          : null,
                      child: SelectionContainer.disabled(
                        child: Text(tr('应用筛选')),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
