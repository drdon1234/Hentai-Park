import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/localization.dart';
import '../../core/reverse_search.dart';
import '../../engine/browser_image_search.dart';
import '../../engine/source_manager.dart';
import '../../images/search_image.dart';
import '../nav.dart';
import '../settings/source_manage_page.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/error_view.dart';
import '../widgets/source_network_hint.dart';
import 'browser_image_search_panel.dart';
import 'search_crop_page.dart';

class ReverseSearchPage extends StatefulWidget {
  const ReverseSearchPage({super.key, this.sourceKey});
  final String? sourceKey;
  @override
  State<ReverseSearchPage> createState() => _ReverseSearchPageState();
}

class _ReverseSearchPageState extends State<ReverseSearchPage> {
  final _manager = SourceManager.instance;
  String? _source;
  String _sourceSignature = '';
  SearchImage? _original, _image;
  CancelToken? _token;
  int _generation = 0;
  bool _busy = false, _preparing = false;
  List<ReverseSearchMatch>? _results;
  Object? _error;
  BrowserImageSearchRequest? _browserRequest;
  Completer<BrowserImageSearchResult?>? _browserResult;

  List<InstalledSource> get _sources =>
      _manager.enabled.where((s) => s.manifest!.can('reverseSearch')).toList();
  @override
  void initState() {
    super.initState();
    _source = widget.sourceKey;
    _syncSource();
    _manager.addListener(_sourcesChanged);
  }

  void _syncSource() {
    final sources = _sources;
    if (!sources.any((s) => s.key == _source)) {
      _source = sources.firstOrNull?.key;
    }
    _sourceSignature = jsonEncode(
      _source == null ? null : _manager.manifest(_source!)?.json,
    );
  }

  void _sourcesChanged() {
    if (!mounted) return;
    final previous = _source, signature = _sourceSignature;
    _syncSource();
    if (previous != _source || signature != _sourceSignature) _invalidate();
    setState(() {});
  }

  void _invalidate() {
    _generation++;
    _token?.cancel();
    _token = null;
    _finishBrowser(null);
    _busy = false;
    _preparing = false;
    _results = null;
    _error = null;
  }

  void _finishBrowser(BrowserImageSearchResult? result) {
    final pending = _browserResult;
    _browserResult = null;
    _browserRequest = null;
    if (pending != null && !pending.isCompleted) pending.complete(result);
  }

  @override
  void dispose() {
    _manager.removeListener(_sourcesChanged);
    _invalidate();
    super.dispose();
  }

  Future<void> _pick() async {
    setState(_invalidate);
    final generation = _generation;
    try {
      final selected = await FilePicker.pickFile(type: FileType.image);
      if (!mounted || generation != _generation || selected == null) return;
      setState(() => _preparing = true);
      final file = selected.xFile;
      if (await file.length() > SearchImage.maxInputBytes) {
        throw const FormatException();
      }
      final image = await SearchImage.prepare(await file.readAsBytes());
      if (!mounted || generation != _generation) return;
      setState(() {
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

  Future<void> _search() async {
    final source = _source, image = _image;
    if (source == null || image == null || _busy || _preparing) return;
    setState(() {
      _invalidate();
      _busy = true;
      _token = CancelToken();
    });
    final generation = _generation, token = _token!;
    try {
      final rows = await _manager.reverseSearch(
        source,
        image.base64,
        cancelToken: token,
        browserSearch: (request) async {
          if (!mounted || token.isCancelled || generation != _generation) {
            return null;
          }
          final result = Completer<BrowserImageSearchResult?>();
          setState(() {
            _browserRequest = request;
            _browserResult = result;
          });
          final page = await result.future;
          if (page == null) token.cancel();
          return page;
        },
      );
      if (mounted && generation == _generation && !token.isCancelled) {
        setState(() => _results = rows);
      }
    } catch (error) {
      if (mounted && generation == _generation && !token.isCancelled) {
        setState(() => _error = error);
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
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

  String _time(double value) {
    final seconds = value.floor();
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final sources = _sources;
    final manifest = _source == null ? null : _manager.manifest(_source!);
    final generation = _generation;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('图片反搜')),
        actions: [
          IconButton(
            tooltip: tr('管理站点'),
            icon: const Icon(Icons.extension_outlined),
            onPressed: () => Nav.push(context, const SourceManagePage()),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) => Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(Gap.page),
                children: [
                  Text(tr('从截图或插画查找出处，再用作品名或番号搜索资源')),
                  const SizedBox(height: Gap.l),
                  if (sources.isEmpty)
                    EmptyState(
                      icon: Icons.image_search_outlined,
                      title: tr('没有启用的反搜服务'),
                      message: tr('在站点管理中启用或安装站点'),
                    ),
                  if (sources.isNotEmpty)
                    Wrap(
                      spacing: Gap.s,
                      runSpacing: Gap.s,
                      children: [
                        for (final source in sources)
                          ChoiceChip(
                            label: SelectionContainer.disabled(
                              child: Text(source.manifest!.name),
                            ),
                            selected: source.key == _source,
                            onSelected: (_) => setState(() {
                              _invalidate();
                              _source = source.key;
                              _syncSource();
                            }),
                          ),
                      ],
                    ),
                  if (manifest != null) ...[
                    const SizedBox(height: Gap.m),
                    Text(manifest.description),
                    if (manifest.network['vpnHint'] == true)
                      const NetworkAccessHint(),
                  ],
                  const SizedBox(height: Gap.l),
                  if (_image != null)
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 280),
                      child: Image.memory(
                        _image!.bytes,
                        fit: BoxFit.contain,
                        semanticLabel: tr('待反搜图片'),
                      ),
                    ),
                  const SizedBox(height: Gap.s),
                  Wrap(
                    spacing: Gap.s,
                    runSpacing: Gap.s,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _preparing ? null : _pick,
                        icon: const Icon(Icons.add_photo_alternate_outlined),
                        label: SelectionContainer.disabled(
                          child: Text(tr('选择图片')),
                        ),
                      ),
                      if (_image != null)
                        TextButton(
                          onPressed: _preparing ? null : _crop,
                          child: SelectionContainer.disabled(
                            child: Text(tr('裁剪图片')),
                          ),
                        ),
                      if (_image != null)
                        TextButton(
                          onPressed: () => setState(() {
                            _invalidate();
                            _original = null;
                            _image = null;
                          }),
                          child: SelectionContainer.disabled(
                            child: Text(tr('移除图片')),
                          ),
                        ),
                    ],
                  ),
                  if (_preparing) const LinearProgressIndicator(),
                  const SizedBox(height: Gap.l),
                  Text(tr('点击搜索后，图片会上传至所选服务；请勿上传私人或敏感图片')),
                  const SizedBox(height: Gap.s),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: _busy
                        ? OutlinedButton(
                            onPressed: () => setState(_invalidate),
                            child: SelectionContainer.disabled(
                              child: Text(tr('取消')),
                            ),
                          )
                        : FilledButton.icon(
                            onPressed:
                                _image == null || _source == null || _preparing
                                ? null
                                : _search,
                            icon: const Icon(Icons.image_search_outlined),
                            label: SelectionContainer.disabled(
                              child: Text(tr('开始反搜')),
                            ),
                          ),
                  ),
                  if (_busy) ...[
                    const SizedBox(height: Gap.l),
                    const LinearProgressIndicator(),
                    const SizedBox(height: Gap.s),
                    Text(tr('正在识别，服务繁忙时可能需要排队')),
                  ],
                  if (_error != null && _source != null)
                    SourceErrorView(
                      error: _error!,
                      source: _source!,
                      onRetry: _search,
                      compact: true,
                    ),
                  if (_results != null) ...[
                    const SizedBox(height: Gap.l),
                    Text(tr('识别结果仅供核对；分数由各服务提供，不代表已确认出处')),
                    if (_results!.isEmpty)
                      EmptyState(
                        icon: Icons.search_off_outlined,
                        title: tr('未找到可靠匹配'),
                        message: tr('尝试裁剪主体、使用更清晰的原图或切换服务'),
                      ),
                    for (final row in _results!) ...[
                      const Divider(),
                      SelectableText(
                        row.title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (row.description.isNotEmpty)
                        SelectableText(row.description),
                      if (row.uncertain) Text(tr('低可信候选，请核对')),
                      if (row.similarity != null)
                        Text(
                          tr('相似度 {score}%', {
                            'score': row.similarity!.toStringAsFixed(1),
                          }),
                        ),
                      if (row.episode.isNotEmpty)
                        Text(tr('第 {episode} 集', {'episode': row.episode})),
                      if (row.from != null && row.to != null)
                        Text('${_time(row.from!)} – ${_time(row.to!)}'),
                      Wrap(
                        spacing: Gap.s,
                        runSpacing: Gap.s,
                        children: [
                          if (row.keyword.isNotEmpty)
                            TextButton(
                              onPressed: () => Nav.openAggregateSearch(
                                context,
                                keyword: row.keyword,
                              ),
                              child: SelectionContainer.disabled(
                                child: Text(tr('搜索资源')),
                              ),
                            ),
                          if (row.url.isNotEmpty)
                            TextButton(
                              onPressed: () => _open(row.url),
                              child: SelectionContainer.disabled(
                                child: Text(tr('原站')),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ],
              ),
            ),
            // 会话不放在惰性列表中，滚动和窄屏不能销毁仍在处理的浏览器。
            if (_browserRequest != null)
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: constraints.maxHeight * 0.7,
                ),
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Gap.page),
                    child: BrowserImageSearchPanel(
                      key: ValueKey(_generation),
                      source: _source!,
                      request: _browserRequest!,
                      imageBase64: _image!.base64,
                      cancelToken: _token!,
                      onComplete: (result) {
                        if (mounted && generation == _generation) {
                          setState(() => _finishBrowser(result));
                        }
                      },
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
