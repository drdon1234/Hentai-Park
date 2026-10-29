import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/content_scope.dart';
import '../../core/localization.dart';
import '../../core/models.dart';
import '../../core/settings.dart';
import '../../core/work_metadata.dart';
import '../../engine/source_manager.dart';
import '../comments/comments_page.dart';
import '../nav.dart';
import '../settings/source_manage_page.dart';
import '../theme.dart';
import '../web/source_web_page.dart';
import '../widgets/common.dart';
import '../widgets/content_translation.dart';
import '../widgets/error_view.dart';
import 'metadata_controller.dart';
import 'metadata_sections.dart';

class MetadataPage extends StatefulWidget {
  const MetadataPage({
    super.key,
    this.keyword = '',
    this.sourceKey,
    this.sourceManager,
    this.comments,
  });
  final String keyword;
  final String? sourceKey;
  final SourceManager? sourceManager;
  final CommentsEntry? comments;

  @override
  State<MetadataPage> createState() => _MetadataPageState();
}

class _MetadataPageState extends State<MetadataPage> {
  SourceManager get _manager => widget.sourceManager ?? SourceManager.instance;
  late final _controller = MetadataController(_manager);
  late final _text = TextEditingController(text: widget.keyword);
  final _networkSettings = AppSettings.instance.watch(const {'proxy'});
  StreamSubscription<String>? _authentication;
  String? _source;
  String _signature = '';

  bool get _showComments {
    String normalized(String value) =>
        value.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final original = normalized(widget.keyword);
    return widget.comments != null &&
        original.isNotEmpty &&
        normalized(_text.text) == original &&
        (_controller.detail == null ||
            normalized(_controller.detail!.code) == original);
  }

  List<InstalledSource> get _sources => _manager.enabled
      .where(
        (source) =>
            source.manifest!.metadataOnly &&
            source.manifest!.can('metadataSearch') &&
            source.manifest!.can('metadataDetail'),
      )
      .toList();

  @override
  void initState() {
    super.initState();
    _source = widget.sourceKey;
    _manager.addListener(_sourcesChanged);
    _networkSettings.addListener(_reload);
    _authentication = _manager.authenticationChanges.listen((key) {
      if (key == _source) _reload();
    });
    _sync();
    unawaited(_search());
  }

  bool _sync() {
    final sources = _sources;
    if (!sources.any((item) => item.key == _source)) {
      _source = sources.firstOrNull?.key;
    }
    final manifest = _source == null ? null : _manager.manifest(_source!);
    final signature =
        '$_source:${manifest?.version}:${_source == null ? '' : _manager.settingsOf(_source!)}';
    final changed = signature != _signature;
    _signature = signature;
    return changed;
  }

  void _sourcesChanged() {
    if (!mounted) return;
    final changed = _sync();
    setState(() {});
    if (changed) unawaited(_search());
  }

  void _reload() {
    if (mounted) unawaited(_search());
  }

  Future<void> _search() async {
    final key = _source;
    if (key == null || _text.text.trim().isEmpty) {
      _controller.reset();
      return;
    }
    await _controller.search(key, _text.text);
  }

  void _searchJav() {
    final keyword = _controller.detail?.code ?? _text.text.trim();
    if (keyword.isEmpty) return;
    Nav.openAggregateSearch(
      context,
      keyword: keyword,
      scope: const ContentScope.domain(SourceCategory.jav),
    );
  }

  Future<void> _chooseSource() async {
    final selected = await showChoiceSheet<String>(
      context,
      title: tr('资料来源'),
      selected: _source,
      options: _sources.map((source) => source.key).toList(),
      label: (key) => _manager.manifest(key)?.name ?? key,
    );
    if (selected == null || !mounted || selected == _source) return;
    setState(() => _source = selected);
    _sync();
    await _search();
  }

  Future<void> _copy(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) context.toast(tr('已复制'));
  }

  Future<void> _openMagnet(MetadataMagnet magnet) async {
    var opened = false;
    try {
      opened = await launchUrl(
        Uri.parse(magnet.url),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {}
    if (!opened && mounted) context.toast(tr('无法打开磁链，请安装支持磁链的应用或复制链接'));
  }

  @override
  void dispose() {
    _manager.removeListener(_sourcesChanged);
    _networkSettings.removeListener(_reload);
    _authentication?.cancel();
    _controller.dispose();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TranslationPage(
    child: Scaffold(
      appBar: AppBar(
        title: Text(tr('作品资料')),
        actions: [
          const TranslationControls(),
          IconButton(
            tooltip: tr('管理站点'),
            onPressed: () => Nav.push(context, const SourceManagePage()),
            icon: const Icon(Icons.extension_outlined),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: Listenable.merge([_controller, _text]),
        builder: (context, _) => Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: ListView(
              padding: const EdgeInsets.all(Gap.page),
              children: [
                ParkSearchField(
                  controller: _text,
                  hint: tr('搜索番号、作品名或演员'),
                  onSubmitted: (_) => _search(),
                  trailing: [
                    if (_text.text.isNotEmpty)
                      IconButton(
                        tooltip: tr('清空'),
                        onPressed: () {
                          _text.clear();
                          _controller.reset();
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
                    IconButton(
                      tooltip: tr('搜索资料'),
                      onPressed: _source == null ? null : _search,
                      icon: const Icon(Icons.arrow_forward_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: Gap.m),
                Wrap(
                  spacing: Gap.s,
                  runSpacing: Gap.s,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (_source != null)
                      OutlinedButton.icon(
                        onPressed: _chooseSource,
                        icon: const Icon(Icons.expand_more_rounded),
                        label: Text(
                          tr('资料来源：{name}', {
                            'name': _manager.manifest(_source!)?.name ?? '',
                          }),
                        ),
                      ),
                    FilledButton.icon(
                      onPressed:
                          (_controller.detail?.code ?? _text.text.trim())
                              .isEmpty
                          ? null
                          : _searchJav,
                      icon: const Icon(Icons.search_rounded),
                      label: Text(tr('搜索 JAV 站点')),
                    ),
                  ],
                ),
                const SizedBox(height: Gap.l),
                if (_showComments) widget.comments!,
                if (_source == null)
                  EmptyState(
                    icon: Icons.extension_off_outlined,
                    title: tr('没有启用的资料插件'),
                    message: tr('在站点管理中启用或安装资料插件'),
                    actions: [
                      OutlinedButton(
                        onPressed: () =>
                            Nav.push(context, const SourceManagePage()),
                        child: Text(tr('管理站点')),
                      ),
                    ],
                  )
                else if (_controller.error case final error?)
                  SourceErrorView(
                    error: error,
                    source: _source!,
                    onRetry: _search,
                  )
                else if (_controller.loading)
                  const Padding(
                    padding: EdgeInsets.all(Gap.xl),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_controller.detail case final detail?) ...[
                  MetadataOverview(
                    detail: detail,
                    source: _source!,
                    onCopy: () => _copy(detail.code),
                    onOriginal: () => Nav.push(
                      context,
                      SourceWebPage(
                        source: _source!,
                        url: Uri.parse(detail.url),
                      ),
                    ),
                  ),
                  MetadataImages(source: _source!, detail: detail),
                  if (_manager.manifest(_source!)?.can('metadataMagnets') ==
                      true)
                    MetadataMagnets(
                      controller: _controller,
                      onCopy: (magnet) => _copy(magnet.url),
                      onOpen: _openMagnet,
                    ),
                ] else if (_controller.query.isNotEmpty)
                  if (_controller.candidates.isEmpty)
                    EmptyState(
                      icon: Icons.search_off_rounded,
                      title: tr('未找到作品资料'),
                      message: tr('可更换关键词或资料来源，也可搜索 JAV 站点'),
                    )
                  else ...[
                    Text(tr('选择作品'), style: context.text.titleMedium),
                    const SizedBox(height: Gap.m),
                    for (final candidate in _controller.candidates)
                      MetadataCandidateRow(
                        source: _source!,
                        item: candidate,
                        onTap: () => _controller.select(candidate),
                      ),
                  ]
                else
                  EmptyState(
                    icon: Icons.info_outline_rounded,
                    title: tr('搜索作品资料'),
                    message: tr('搜索番号、作品名或演员'),
                  ),
                const SizedBox(height: Gap.xl),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
