import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../../core/models.dart';
import '../../engine/source_manager.dart';
import '../../subscriptions/models.dart';
import '../../subscriptions/subscription_store.dart';
import '../nav.dart';
import '../widgets/common.dart';
import '../widgets/error_view.dart';
import '../widgets/source_account_strip.dart';
import 'subscription_posts_page.dart';

/// 无公共首页的站点仍可直接访问公开频道或作者，无需先保存订阅。
class SubscriptionSourcePage extends StatefulWidget {
  const SubscriptionSourcePage({
    super.key,
    required this.source,
    this.communitiesOnly = false,
    this.embedded = false,
    this.sourceManager,
  });
  final String source;
  final bool communitiesOnly;
  final bool embedded;
  final SourceManager? sourceManager;
  @override
  State<SubscriptionSourcePage> createState() => _SubscriptionSourcePageState();
}

class _SubscriptionSourcePageState extends State<SubscriptionSourcePage> {
  SourceManager get _sources => widget.sourceManager ?? SourceManager.instance;
  Object? _error;
  bool _loadingTargets = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _openJoinedTargets() async {
    if (_loadingTargets) return;
    setState(() => _loadingTargets = true);
    try {
      final targets = <SubscriptionTarget>[];
      String? cursor;
      var hasNext = true;
      var hasLoaded = false;
      var started = false;
      var searching = false;
      var serverResults = false;
      var queryApplied = false;
      Object? pageError;
      var generation = 0;
      CancelToken? requestToken;
      String? activeQuery;
      final filter = TextEditingController();
      final target =
          await showDialog<SubscriptionTarget>(
            context: context,
            builder: (context) => StatefulBuilder(
              builder: (context, refresh) {
                Future<void> load({bool next = false, String? query}) async {
                  final normalizedQuery = query?.trim();
                  final requestQuery = normalizedQuery?.isNotEmpty == true
                      ? normalizedQuery
                      : next && serverResults
                      ? filter.text.trim()
                      : null;
                  if (searching && activeQuery == requestQuery && !next) return;
                  requestToken?.cancel('target query changed');
                  final request = CancelToken();
                  requestToken = request;
                  activeQuery = requestQuery;
                  final requestGeneration = ++generation;
                  searching = true;
                  pageError = null;
                  refresh(() {});
                  try {
                    final page = await _sources.subscriptionTargetPage(
                      widget.source,
                      kind: widget.communitiesOnly ? 'community' : null,
                      cursor: next ? cursor : null,
                      query: requestQuery,
                      cancelToken: request,
                    );
                    if (request.isCancelled ||
                        !context.mounted ||
                        requestGeneration != generation) {
                      return;
                    }
                    refresh(() {
                      hasLoaded = true;
                      serverResults = requestQuery != null;
                      queryApplied = page.queryApplied;
                      if (next) {
                        final known = targets
                            .map((target) => target.id)
                            .toSet();
                        targets.addAll(
                          page.targets.where((target) => known.add(target.id)),
                        );
                      } else {
                        targets
                          ..clear()
                          ..addAll(page.targets);
                      }
                      cursor = page.cursor;
                      hasNext = page.hasNext;
                      pageError = null;
                    });
                  } catch (error) {
                    if (!request.isCancelled &&
                        requestGeneration == generation &&
                        context.mounted) {
                      refresh(() => pageError = error);
                    }
                  } finally {
                    if (requestGeneration == generation) {
                      searching = false;
                      if (context.mounted) refresh(() {});
                    }
                  }
                }

                final query = filter.text.trim().toLowerCase();
                final visible = targets
                    .where(
                      (item) =>
                          (queryApplied &&
                              activeQuery?.toLowerCase() == query) ||
                          item.label.toLowerCase().contains(query) ||
                          item.id.toLowerCase().contains(query),
                    )
                    .toList();
                if (!started) {
                  started = true;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (context.mounted) load();
                  });
                }
                return AlertDialog(
                  title: Text(tr('已加入或已关注')),
                  content: SizedBox(
                    width: 420,
                    height: 480,
                    child: Column(
                      children: [
                        TextField(
                          controller: filter,
                          autofocus: true,
                          textInputAction: TextInputAction.search,
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.search_rounded),
                            hintText: tr('筛选频道或作者'),
                            suffixIcon: IconButton(
                              tooltip: tr('搜索'),
                              icon: const Icon(Icons.search_rounded),
                              onPressed: () => load(
                                query: filter.text.isEmpty ? null : filter.text,
                              ),
                            ),
                          ),
                          onChanged: (_) => refresh(() {}),
                          onSubmitted: (value) => load(query: value),
                        ),
                        const SizedBox(height: Gap.s),
                        Expanded(
                          child: ListView(
                            children: [
                              for (final item in visible)
                                ListTile(
                                  title: Text(item.label),
                                  onTap: () => Navigator.pop(context, item),
                                ),
                              if (visible.isEmpty &&
                                  !searching &&
                                  hasLoaded &&
                                  pageError == null)
                                Padding(
                                  padding: const EdgeInsets.all(Gap.l),
                                  child: Text(
                                    pageError == null ? tr('没有匹配的频道或作者') : '',
                                  ),
                                ),
                              if (searching)
                                const Padding(
                                  padding: EdgeInsets.all(Gap.m),
                                  child: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                ),
                              if (pageError != null)
                                SourceErrorView(
                                  error: pageError!,
                                  source: widget.source,
                                  compact: true,
                                  onRetry: () => load(query: filter.text),
                                ),
                              if (hasNext && hasLoaded)
                                TextButton.icon(
                                  onPressed: searching
                                      ? null
                                      : () => load(next: true),
                                  icon: const Icon(Icons.expand_more_rounded),
                                  label: Text(tr('加载更多')),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(tr('关闭')),
                    ),
                  ],
                );
              },
            ),
          ).whenComplete(() {
            generation++;
            requestToken?.cancel('target picker closed');
            filter.dispose();
          });
      if (!mounted || target == null) return;
      await Nav.push(
        context,
        SubscriptionPostsPage(
          targetKind: target.kind,
          entry: SubscriptionEntry(
            source: widget.source,
            target: target.id,
            label: target.label,
          ),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loadingTargets = false);
    }
  }

  Future<void> _load() async {
    try {
      await SubscriptionStore.instance.load();
      if (mounted) setState(() => _error = null);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _sources,
    builder: (context, _) => _build(context),
  );

  Widget _build(BuildContext context) {
    final manifest = _sources.manifest(widget.source);
    if (manifest == null) {
      return Scaffold(
        appBar: AppBar(title: Text(tr('订阅'))),
        body: EmptyState(
          icon: Icons.extension_off_outlined,
          title: tr('站点未加载'),
        ),
      );
    }
    return Scaffold(
      appBar: widget.embedded
          ? null
          : AppBar(
              bottom: manifest.account != null
                  ? PreferredSize(
                      preferredSize: Size.fromHeight(
                        SourceAccountStrip.height(context),
                      ),
                      child: SourceAccountStrip(
                        source: widget.source,
                        sourceManager: _sources,
                      ),
                    )
                  : null,
              title: Text(widget.communitiesOnly ? tr('社群') : manifest.name),
              actions: [
                IconButton(
                  tooltip: tr('站点设置'),
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: () =>
                      Nav.openSourceSettings(context, widget.source),
                ),
              ],
            ),
      body: ListenableBuilder(
        listenable: SubscriptionStore.instance,
        builder: (context, _) => CustomScrollView(
          key: PageStorageKey((widget.source, widget.communitiesOnly)),
          slivers: [
            if (widget.embedded)
              SliverOverlapInjector(
                handle: NestedScrollView.sliverOverlapAbsorberHandleFor(
                  context,
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.all(Gap.page),
              sliver: SliverList.list(
                children: [
                  if (widget.embedded) ...[
                    Text(
                      tr(widget.communitiesOnly ? '已加入频道' : '已关注博主'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: Gap.m),
                  ],
                  if (_error != null)
                    SourceErrorView(
                      error: _error!,
                      source: widget.source,
                      onRetry: _load,
                    ),
                  SubscriptionSourceEntry(
                    source: widget.source,
                    sourceManager: _sources,
                    communitiesOnly: widget.communitiesOnly,
                    showAccount: manifest.account == null,
                  ),
                  if ((manifest.json['subscription']
                          as Map?)?['joinedTargets'] ==
                      true) ...[
                    const SizedBox(height: Gap.m),
                    OutlinedButton.icon(
                      onPressed: _loadingTargets ? null : _openJoinedTargets,
                      icon: const Icon(Icons.people_alt_outlined),
                      label: Text(
                        tr(
                          _loadingTargets
                              ? '加载中'
                              : widget.embedded
                              ? widget.communitiesOnly
                                    ? '已加入频道'
                                    : '已关注博主'
                              : '已加入或已关注',
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: Gap.l),
                  for (final entry in SubscriptionStore.instance.items.where(
                    (e) =>
                        e.source == widget.source &&
                        e.dimension == 'posts' &&
                        !widget.communitiesOnly,
                  ))
                    ListTile(
                      title: Text(entry.label),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Nav.push(
                        context,
                        SubscriptionPostsPage(entry: entry),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 域页和站点页共用公开作者入口；空输入也给出可执行的反馈。
class SubscriptionSourceEntry extends StatefulWidget {
  const SubscriptionSourceEntry({
    super.key,
    required this.source,
    this.sourceManager,
    this.showAccount = true,
    this.onOpened,
    this.communitiesOnly = false,
  });
  final String source;
  final SourceManager? sourceManager;
  final bool showAccount;
  final VoidCallback? onOpened;
  final bool communitiesOnly;

  @override
  State<SubscriptionSourceEntry> createState() =>
      _SubscriptionSourceEntryState();
}

class _SubscriptionSourceEntryState extends State<SubscriptionSourceEntry> {
  final _target = TextEditingController();
  final _focus = FocusNode();
  bool _busy = false;
  bool _empty = false;
  SourceManager get _sources => widget.sourceManager ?? SourceManager.instance;

  Future<void> _open() async {
    if (_busy) return;
    final input = _target.text.trim();
    if (input.isEmpty) {
      setState(() => _empty = true);
      _focus.requestFocus();
      return;
    }
    setState(() => _busy = true);
    final target = await guarded(context, widget.source, () async {
      if (widget.communitiesOnly) {
        final target = await _sources.normalizeSubscription(
          widget.source,
          input,
        );
        if (target.kind != 'community') throw SourceError('CONFIG', '订阅目标无效');
      }
      return _sources.resolveSubscription(widget.source, input);
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (target == null) return;
    await Nav.push(
      context,
      SubscriptionPostsPage(
        targetKind: target.kind,
        entry: SubscriptionEntry(
          source: widget.source,
          target: target.id,
          label: target.label,
        ),
      ),
    );
    if (mounted) widget.onOpened?.call();
  }

  @override
  void dispose() {
    _target.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final manifest = _sources.manifest(widget.source);
    if (manifest == null) return const SizedBox.shrink();
    final subscription = manifest.json['subscription'] as Map?;
    final hint =
        subscription?[widget.communitiesOnly ? 'communityHint' : 'hint']
            ?.toString();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.showAccount && manifest.account != null)
          SourceAccountStrip(source: widget.source, sourceManager: _sources),
        Text(tr(widget.communitiesOnly ? '社群' : '访问频道或作者')),
        if (hint != null && hint.isNotEmpty) ...[
          const SizedBox(height: Gap.s),
          Text(manifest.copy.text(hint)),
        ],
        const SizedBox(height: Gap.m),
        TextField(
          controller: _target,
          focusNode: _focus,
          enabled: !_busy,
          autocorrect: false,
          textInputAction: TextInputAction.go,
          decoration: InputDecoration(
            labelText: tr('订阅目标'),
            hintText: widget.communitiesOnly
                ? (subscription?['communityExample'])?.toString()
                : manifest.idExample,
            helperText: tr('先输入用户名、频道名或主页链接，再点击打开'),
            helperMaxLines: 3,
            errorText: _empty ? tr('请先输入用户名、频道名或主页链接') : null,
            errorMaxLines: 3,
          ),
          onChanged: (_) {
            if (_empty) setState(() => _empty = false);
          },
          onSubmitted: (_) => _open(),
        ),
        const SizedBox(height: Gap.m),
        OutlinedButton(
          onPressed: _busy ? null : _open,
          child: SelectionContainer.disabled(
            child: Text(tr(_busy ? '加载中' : '打开')),
          ),
        ),
        if (widget.showAccount && manifest.account == null) ...[
          const SizedBox(height: Gap.s),
          Text(tr('仅显示公开内容；会员内容请在原站登录后查看')),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: OutlinedButton(
              onPressed: () => Nav.login(context, widget.source),
              child: SelectionContainer.disabled(child: Text(tr('在原站登录'))),
            ),
          ),
        ],
      ],
    );
  }
}
