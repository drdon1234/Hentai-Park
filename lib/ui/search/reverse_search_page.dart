import 'dart:async';
import 'dart:convert';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/localization.dart';
import '../../core/platform_capabilities.dart';
import '../../core/reverse_search.dart';
import '../../core/reverse_search_history.dart';
import '../../engine/source_manager.dart';
import '../../images/image_input.dart';
import '../../images/search_image.dart';
import '../nav.dart';
import '../settings/source_manage_page.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/content_translation.dart';
import '../widgets/image_input_region.dart';
import 'browser_image_search_panel.dart';
import 'reverse_search_controller.dart';
import 'reverse_search_form.dart';
import 'reverse_search_history_sheet.dart';
import 'reverse_search_more.dart';
import 'reverse_search_result.dart';
import 'reverse_search_results_header.dart';
import 'search_crop_page.dart';

class ReverseSearchPage extends StatefulWidget {
  const ReverseSearchPage({super.key, this.sourceKey});
  final String? sourceKey;
  @override
  State<ReverseSearchPage> createState() => _ReverseSearchPageState();
}

class _ReverseSearchPageState extends State<ReverseSearchPage> {
  final _manager = SourceManager.instance;
  final _searchController = ReverseSearchController();
  final _selectedSources = <String>{};
  String _sourceSignature = '';
  String? _resultSource;
  bool _selectionInitialized = false;
  SearchImage? _original, _image;
  int _generation = 0;
  bool _preparing = false;

  bool get _busy => _searchController.busy;
  List<InstalledSource> get _sources =>
      _manager.enabled.where((s) => s.manifest!.can('reverseSearch')).toList();
  @override
  void initState() {
    super.initState();
    _syncSources();
    _manager.addListener(_sourcesChanged);
    _searchController.addListener(_searchChanged);
  }

  void _syncSources() {
    final available = _sources.map((s) => s.key).toSet();
    if (!_selectionInitialized && available.isNotEmpty) {
      final initial = widget.sourceKey ?? 'google_lens';
      if (available.contains(initial)) _selectedSources.add(initial);
      _selectionInitialized = true;
    }
    _selectedSources.removeWhere((key) => !available.contains(key));
    _sourceSignature = jsonEncode({
      for (final key in _selectedSources.toList()..sort())
        key: _manager.manifest(key)?.json,
    });
  }

  void _sourcesChanged() {
    if (!mounted) return;
    final signature = _sourceSignature;
    _syncSources();
    if (signature != _sourceSignature) _invalidate();
    setState(() {});
  }

  void _searchChanged() {
    if (!mounted) return;
    setState(() {
      final successful = _searchController.successfulSources;
      if (!successful.contains(_resultSource)) {
        _resultSource = successful.firstOrNull;
      }
    });
  }

  void _invalidate() {
    _generation++;
    _searchController.reset();
    _resultSource = null;
    _preparing = false;
  }

  @override
  void dispose() {
    _manager.removeListener(_sourcesChanged);
    _searchController.removeListener(_searchChanged);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _readImage(
    Future<Uint8List?> Function() read, {
    bool clipboard = false,
  }) async {
    setState(() {
      _generation++;
      _preparing = true;
    });
    final generation = _generation;
    try {
      final bytes = await read();
      if (!mounted || generation != _generation) return;
      if (bytes == null) {
        if (clipboard) context.toast(tr('剪贴板没有可粘贴的图片'));
        return;
      }
      final image = await SearchImage.prepare(bytes);
      if (!mounted || generation != _generation) return;
      setState(() {
        _invalidate();
        _original = image;
        _image = image;
      });
    } catch (_) {
      if (mounted && generation == _generation) context.toast(tr('图片无法处理'));
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _preparing = false);
      }
    }
  }

  Future<void> _pick() => _readImage(() async {
    final selected = await FilePicker.pickFile(type: FileType.image);
    return selected == null ? null : ImageInput.readFile(selected.xFile);
  });

  Future<void> _paste() =>
      _readImage(ImageInput.readClipboard, clipboard: true);

  Future<void> _drop(List<DropItem> files) => _readImage(() async {
    if (files.length != 1 || files.single is DropItemDirectory) {
      throw const FormatException();
    }
    return ImageInput.readFile(files.single);
  });

  Future<void> _crop() async {
    final original = _original;
    if (original == null) return;
    setState(_invalidate);
    final generation = _generation;
    final crop = await Nav.push<Rect>(
      context,
      SearchCropPage(
        bytes: original.bytes,
        width: original.width,
        height: original.height,
      ),
    );
    if (crop == null || !mounted || generation != _generation) return;
    setState(() => _preparing = true);
    try {
      final image = await SearchImage.prepare(original.bytes, crop: crop);
      if (mounted && generation == _generation) setState(() => _image = image);
    } catch (_) {
      if (mounted && generation == _generation) context.toast(tr('图片无法处理'));
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _preparing = false);
      }
    }
  }

  void _search() {
    final image = _image;
    if (image == null || _selectedSources.isEmpty || _busy || _preparing) {
      return;
    }
    final base64 = image.base64;
    unawaited(ReverseSearchHistory.instance.add(image.bytes, _selectedSources));
    _searchController.start(
      _sources.where((s) => _selectedSources.contains(s.key)).map((s) => s.key),
      (source, token, browserSearch) => _manager.reverseSearch(
        source,
        base64,
        cancelToken: token,
        browserSearch: browserSearch,
      ),
    );
  }

  Future<void> _open(String url) async {
    var opened = false;
    try {
      opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {}
    if (!opened && mounted) context.toast(tr('无法打开原站'));
  }

  Widget _form() => ReverseSearchForm(
    sources: _sources,
    selectedSources: _selectedSources,
    image: _image,
    preparing: _preparing,
    busy: _busy,
    onSelect: (keys) => setState(() {
      _invalidate();
      for (final key in keys) {
        if (!_selectedSources.add(key)) _selectedSources.remove(key);
      }
      HapticFeedback.selectionClick();
      _syncSources();
    }),
    onPick: _pick,
    onPaste: PlatformCapabilities.desktop ? _paste : null,
    onCrop: _crop,
    onRemove: () => setState(() {
      _invalidate();
      _original = null;
      _image = null;
    }),
    onSearch: _search,
    onCancel: _searchController.cancel,
    onManage: () => Nav.push(context, const SourceManagePage()),
  );

  List<Widget> _resultHeader(BuildContext context) => [
    ReverseSearchResultsHeader(
      controller: _searchController,
      source: _resultSource,
      sourceName: (source) => _manager.manifest(source)?.name ?? source,
      onSelected: (source) => setState(() {
        if (_resultSource != source) HapticFeedback.selectionClick();
        _resultSource = source;
      }),
    ),
    const SizedBox(height: Gap.l),
  ];

  Widget _result(ReverseSearchMatch match) => ReverseSearchResult(
    key: ValueKey((_resultSource, match)),
    source: _resultSource!,
    match: match,
    onOpen: _open,
    onSearch: (keyword) => Nav.openAggregateSearch(context, keyword: keyword),
  );

  Widget _workspace(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 840;
      final inset = wide ? Gap.xl : Gap.page;
      final siteResult = _searchController.results[_resultSource];
      final results = siteResult?.matches ?? const <ReverseSearchMatch>[];
      final more = siteResult?.hasMore == true;
      Widget footer() => ReverseSearchMore(
        key: ValueKey(('reverse-more', _resultSource)),
        result: siteResult!,
        onLoad: () => _searchController.loadAll(_resultSource!),
      );
      // 两栏各自滚动；窄屏保持一条连续的阅读与操作路径。
      if (wide && _sources.isNotEmpty) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 360,
              child: ListView(
                padding: EdgeInsets.all(inset),
                children: [_form()],
              ),
            ),
            VerticalDivider(
              width: Gap.xl,
              color: context.colors.outlineVariant,
            ),
            Expanded(
              child: ListView.builder(
                padding: EdgeInsetsDirectional.fromSTEB(0, inset, inset, inset),
                itemCount: results.length + 1 + (more ? 1 : 0),
                itemBuilder: (context, index) => index == 0
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: _resultHeader(context),
                      )
                    : index == results.length + 1
                    ? footer()
                    : _result(results[index - 1]),
              ),
            ),
          ],
        );
      }
      return ListView.builder(
        padding: EdgeInsets.all(inset),
        itemCount: results.length + 1 + (more ? 1 : 0),
        itemBuilder: (context, index) => index == 0
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _form(),
                  if (_sources.isNotEmpty) ...[
                    const SizedBox(height: Gap.xl),
                    const Divider(),
                    const SizedBox(height: Gap.xl),
                    ..._resultHeader(context),
                  ],
                ],
              )
            : index == results.length + 1
            ? footer()
            : _result(results[index - 1]),
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final browser = _searchController.browser;
    return TranslationPage(
      child: Scaffold(
        appBar: AppBar(
          title: Text(tr('图片反搜')),
          actions: [
            IconButton(
              tooltip: tr('反搜历史'),
              icon: const Icon(Icons.history_rounded),
              onPressed: _preparing || _busy
                  ? null
                  : () async {
                      final entry = await showReverseSearchHistory(context);
                      if (entry == null || !mounted) return;
                      await _readImage(
                        () async => base64Decode(entry['image'] as String),
                      );
                      if (!mounted) return;
                      setState(() {
                        _selectedSources
                          ..clear()
                          ..addAll(
                            (entry['sources'] as List).whereType<String>(),
                          );
                        _syncSources();
                      });
                    },
            ),
            const TranslationControls(),
            IconButton(
              tooltip: tr('管理站点'),
              icon: const Icon(Icons.extension_outlined),
              onPressed: () => Nav.push(context, const SourceManagePage()),
            ),
          ],
        ),
        body: ImageInputRegion(
          onDrop: _drop,
          onPaste: _paste,
          child: SafeArea(
            top: false,
            child: LayoutBuilder(
              builder: (context, constraints) => Stack(
                children: [
                  // 后台网页保持正常尺寸并参与绘制，前景原生界面覆盖网页。
                  if (browser != null)
                    Positioned(
                      left: Gap.page,
                      right: Gap.page,
                      bottom: 0,
                      height: constraints.maxHeight * 0.6,
                      child: BrowserImageSearchPanel(
                        key: ValueKey(browser),
                        source: browser.source,
                        request: browser.request,
                        imageBase64: _image!.base64,
                        cancelToken: browser.token,
                        onComplete: (result) =>
                            _searchController.finishBrowser(browser, result),
                        onError: (error) => _searchController.finishBrowser(
                          browser,
                          null,
                          error: error,
                        ),
                      ),
                    ),
                  Column(
                    children: [
                      Expanded(
                        child: ColoredBox(
                          color: context.colors.surface,
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 1200),
                              child: _workspace(context),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
