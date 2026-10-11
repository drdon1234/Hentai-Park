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
import '../widgets/error_view.dart';
import '../widgets/work_card.dart';
import 'multi_language.dart';
import 'source_search_page.dart';

/// One query, every source: results stream in per source as they arrive. Links and ids
/// (e.g. "JM350234", an nhentai URL) are recognised and offered as direct jumps.
class AggregateSearchPage extends StatefulWidget {
  const AggregateSearchPage({super.key, this.initialKeyword = ''});
  final String initialKeyword;

  @override
  State<AggregateSearchPage> createState() => _AggregateSearchPageState();
}

class _AggregateSearchPageState extends State<AggregateSearchPage> {
  late final _text = TextEditingController(text: widget.initialKeyword);
  final _focus = FocusNode();
  String _submitted = '';
  int _generation = 0;
  MultiKeyword? _multi;
  bool _translating = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialKeyword.isNotEmpty) {
      _submit(widget.initialKeyword);
    } else {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _focus.requestFocus(),
      );
    }
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit(String keyword) {
    final k = keyword.trim();
    if (k.isEmpty) return;
    AppSettings.instance.addSearchHistory(k);
    _focus.unfocus();
    setState(() {
      _submitted = k;
      _multi = null;
      _generation++;
    });
  }

  /// Translates the keyword into the configured languages and searches all of them at once.
  Future<void> _submitMulti() async {
    final k = _text.text.trim();
    if (k.isEmpty || _translating) return;
    _focus.unfocus();
    setState(() => _translating = true);
    final multi = await translateKeyword(context, k);
    if (!mounted) return;
    setState(() => _translating = false);
    if (multi == null) return;
    AppSettings.instance.addSearchHistory(k);
    setState(() {
      _submitted = k;
      _multi = multi;
      _generation++;
    });
  }

  List<InstalledSource> get _scope {
    final excluded = AppSettings.instance.aggregateExcluded;
    return SourceManager.instance.enabled
        .where((s) => s.manifest!.can('search') && !excluded.contains(s.key))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    AppLocalizations.of(context);
    final typed = _text.text.trim();
    final refs = typed.isEmpty
        ? const <({String source, String id})>[]
        : _directRefs(typed);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _text,
          focusNode: _focus,
          textInputAction: TextInputAction.search,
          onSubmitted: _submit,
          decoration: InputDecoration(
            hintText: tr('搜索全部源站，或粘贴链接 / 车号'),
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: typed.isEmpty
                ? IconButton(
                    tooltip: tr('粘贴'),
                    icon: const Icon(Icons.content_paste_rounded),
                    onPressed: () async {
                      final data = await Clipboard.getData('text/plain');
                      if (data?.text != null) _text.text = data!.text!.trim();
                    },
                  )
                : IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => _text.clear(),
                  ),
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
          ),
        ),
        actions: [
          _translating
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  ),
                )
              : TextButton(
                  onPressed: typed.isEmpty ? null : _submitMulti,
                  child: Text(tr('多语言')),
                ),
          TextButton(
            onPressed: () => _submit(_text.text),
            child: Text(tr('搜索')),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([
          SourceManager.instance,
          AppSettings.instance,
        ]),
        builder: (context, _) => CustomScrollView(
          slivers: [
            if (refs.isNotEmpty)
              SliverToBoxAdapter(child: _DirectJump(refs: refs)),
            if (_submitted.isEmpty || typed != _submitted) ...[
              SliverToBoxAdapter(
                child: _ScopeBar(scope: _scope.map((s) => s.key).toSet()),
              ),
              SliverToBoxAdapter(
                child: _History(
                  onPick: (k) {
                    _text.text = k;
                    _submit(k);
                  },
                ),
              ),
            ],
            if (_submitted.isNotEmpty && typed == _submitted && _multi != null)
              SliverToBoxAdapter(
                child: TranslationsBar(
                  keyword: _multi!,
                  onPick: (k) {
                    _text.text = k;
                    _submit(k);
                  },
                ),
              ),
            if (_submitted.isNotEmpty && typed == _submitted)
              SliverList.builder(
                itemCount: _scope.length,
                itemBuilder: (context, i) => _SourceResults(
                  key: ValueKey('${_scope[i].key}-$_generation'),
                  source: _scope[i].key,
                  keyword: _submitted,
                  multi: _multi,
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ],
        ),
      ),
    );
  }

  /// Links/codes in the text plus bare ids that match a source's id format.
  List<({String source, String id})> _directRefs(String text) {
    final sm = SourceManager.instance;
    final refs = sm.extractRefs(text);
    if (refs.isEmpty && !text.contains(' ')) {
      for (final s in sm.enabled) {
        final id = s.manifest!.matchExplicitId(text);
        if (id != null) refs.add((source: s.key, id: id));
      }
    }
    final seen = <String>{};
    return refs.where((r) => seen.add('${r.source}:${r.id}')).take(6).toList();
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
  const _ScopeBar({required this.scope});
  final Set<String> scope;

  @override
  Widget build(BuildContext context) {
    AppLocalizations.of(context);
    final sources = SourceManager.instance.enabled
        .where((s) => s.manifest!.can('search'))
        .toList();
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
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in sources)
                FilterChip(
                  avatar: SourceAvatar(s.key, size: 22),
                  label: Text(s.name),
                  selected: scope.contains(s.key),
                  showCheckmark: false,
                  onSelected: (on) =>
                      AppSettings.instance.setAggregateIncluded(s.key, on),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _History extends StatelessWidget {
  const _History({required this.onPick});
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    AppLocalizations.of(context);
    final history = AppSettings.instance.searchHistory;
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
            onPressed: AppSettings.instance.clearSearchHistory,
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
                  onDeleted: () => AppSettings.instance.removeSearchHistory(k),
                  deleteIconColor: context.colors.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SourceResults extends StatefulWidget {
  const _SourceResults({
    super.key,
    required this.source,
    required this.keyword,
    this.multi,
  });
  final String source;
  final String keyword;
  final MultiKeyword? multi;

  @override
  State<_SourceResults> createState() => _SourceResultsState();
}

class _SourceResultsState extends State<_SourceResults>
    with AutomaticKeepAliveClientMixin {
  late Future<WorkPage> _future = _load();

  Future<WorkPage> _load() {
    final m = SourceManager.instance.manifest(widget.source)!;
    final multi = widget.multi;
    if (multi != null && multi.all.length > 1)
      return MultiKeywordSearch(
        widget.source,
        multi.all,
        m.defaultFilters(),
      ).next();
    return SourceManager.instance.search(
      widget.source,
      keyword: widget.keyword,
      filters: m.defaultFilters(),
    );
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    AppLocalizations.of(context);
    super.build(context);
    final m = SourceManager.instance.manifest(widget.source)!;
    return FutureBuilder<WorkPage>(
      future: _future,
      builder: (context, snap) {
        final header = SectionHeader(
          m.name,
          leading: SourceAvatar(widget.source, size: 26),
          trailing: TextButton(
            onPressed: () => widget.multi != null
                ? Nav.push(
                    context,
                    SourceSearchPage(
                      sourceKey: widget.source,
                      initialKeyword: widget.keyword,
                      initialMulti: widget.multi,
                    ),
                  )
                : Nav.openSourceSearch(
                    context,
                    widget.source,
                    keyword: widget.keyword,
                  ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (snap.connectionState != ConnectionState.done) ...[
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                ],
                if (snap.hasData && (snap.data!.total ?? 0) > 0)
                  Text(
                    tr('{count} 部 ', {'count': formatCount(snap.data!.total)}),
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
        if (snap.connectionState != ConnectionState.done) {
          body = SizedBox(
            height: cardWidth / aspect + cardTextExtent(context),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: 5,
              physics: const NeverScrollableScrollPhysics(),
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, __) => SizedBox(
                width: cardWidth,
                child: WorkCardSkeleton(aspect: aspect),
              ),
            ),
          );
        } else if (snap.hasError) {
          body = Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              child: SourceErrorView(
                error: snap.error!,
                source: widget.source,
                compact: true,
                onRetry: () => setState(() => _future = _load()),
              ),
            ),
          );
        } else if (snap.data!.items.isEmpty) {
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
          final items = snap.data!.items
              .where((e) => blocklist.matchItem(e) == null)
              .toList();
          final a = gridAspectFor(items, kind);
          final w = a > 1 ? 200.0 : 118.0;
          body = SizedBox(
            height: w / a + cardTextExtent(context),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
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
      },
    );
  }
}
