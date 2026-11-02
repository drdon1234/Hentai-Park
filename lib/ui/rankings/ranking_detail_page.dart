import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../../core/models.dart';
import '../../core/work_metadata.dart';
import '../../engine/ranking_details.dart';
import '../../engine/source_manager.dart';
import '../comments/comments_page.dart';
import '../detail/detail_page.dart';
import '../metadata/metadata_page.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/error_view.dart';

class RankingDetailPage extends StatefulWidget {
  const RankingDetailPage({
    super.key,
    required this.item,
    required this.board,
    required this.manager,
    this.source,
  });
  final RankingEntry item;
  final RankingDef board;
  final SourceManager manager;
  final String? source;

  @override
  State<RankingDetailPage> createState() => _RankingDetailPageState();
}

class _RankingDetailPageState extends State<RankingDetailPage> {
  final _cancel = CancelToken();
  late final _sources = rankingDetailSources(
    widget.manager,
    widget.board.category,
    origin: widget.item.source,
  );
  String? _source;
  Object? _error;
  bool _loading = true;
  List<WorkItem> _candidates = [];
  List<MetadataCandidate> _metadataCandidates = [];
  Widget? _detail;

  @override
  void initState() {
    super.initState();
    final selected = _sources.any((s) => s.key == widget.source)
        ? widget.source
        : null;
    final own = _sources.where((s) => s.key == widget.item.source).firstOrNull;
    // 本站榜单始终先用本站真实 ID；优先级用于需要跨站查找的作品。
    _load(selected ?? own?.key ?? _sources.firstOrNull?.key);
  }

  String get _keyword {
    final value = widget.item.json['keyword'];
    return value is String && value.trim().isNotEmpty
        ? value.trim()
        : widget.item.title;
  }

  Widget _metadata(String source, String? id) => MetadataPage(
    keyword: _keyword,
    sourceKey: source,
    id: id,
    category: widget.board.category,
    sourceManager: widget.manager,
    detailContext: {'url': widget.item.json['url'], 'board': widget.board.key},
    commentsRequireCodeMatch: source != widget.item.source,
    comments:
        (source == widget.item.source ||
            widget.board.category == SourceCategory.jav)
        ? CommentsEntry(
            source: widget.item.source,
            workId: widget.item.id,
            manager: widget.manager,
            available: widget.item.work?.commentsAvailable,
            context: {
              'url': '${widget.item.json['url'] ?? ''}',
              'board': widget.board.key,
            },
          )
        : null,
  );

  Future<void> _load(String? source) async {
    if (source == null) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _source = source;
      _loading = true;
      _error = null;
      _candidates = [];
      _metadataCandidates = [];
    });
    try {
      final m = widget.manager.manifest(source)!;
      if (source == widget.item.source && widget.board.opensWork) {
        _detail = DetailPage(
          source: source,
          id: widget.item.id,
          preview: widget.item.work,
          sourceManager: widget.manager,
        );
      } else if (source == widget.item.source && m.can('metadataDetail')) {
        _detail = _metadata(source, widget.item.id);
      } else if (m.can('metadataSearch')) {
        final results = await widget.manager.metadataSearch(
          source,
          _keyword,
          cancelToken: _cancel,
          category: widget.board.category,
        );
        if (!mounted) return;
        String normalized(String value) => value.toLowerCase().replaceAll(
          RegExp(r'[\s_\-:：/\\.,，。!?！？()（）\[\]【】]'),
          '',
        );
        final exact = results
            .where(
              (item) =>
                  normalized(item.code) == normalized(_keyword) ||
                  normalized(item.title) == normalized(widget.item.title),
            )
            .toList();
        if (exact.length == 1) {
          _detail = _metadata(source, exact.single.id);
        } else {
          _metadataCandidates = results;
        }
      } else {
        final results = await widget.manager.search(
          source,
          keyword: _keyword,
          cancelToken: _cancel,
        );
        if (!mounted) return;
        String normalized(String value) => value.toLowerCase().replaceAll(
          RegExp(r'[\s_\-:：/\\.,，。!?！？()（）\[\]【】]'),
          '',
        );
        final exact = results.items
            .where(
              (item) =>
                  normalized(item.title) == normalized(widget.item.title) ||
                  normalized('${item.json['code'] ?? ''}') ==
                      normalized(_keyword) ||
                  normalized(item.id) == normalized(_keyword),
            )
            .toList();
        if (exact.length == 1) {
          _detail = DetailPage(
            source: source,
            id: exact.single.id,
            preview: exact.single,
            sourceManager: widget.manager,
          );
        } else {
          _candidates = results.items;
        }
      }
      if (mounted &&
          widget.source == null &&
          _detail == null &&
          _candidates.isEmpty &&
          _metadataCandidates.isEmpty) {
        final next = _sources.indexWhere((s) => s.key == source) + 1;
        if (next < _sources.length) await _load(_sources[next].key);
      }
    } catch (e) {
      if (mounted) _error = e;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _cancel.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_detail != null) return _detail!;
    return Scaffold(
      appBar: AppBar(title: Text(tr('作品资料'))),
      body: ListView(
        padding: const EdgeInsets.all(Gap.page),
        children: [
          Text(widget.item.title, style: context.text.titleLarge),
          const SizedBox(height: Gap.m),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else ...[
            if (_error != null)
              SourceErrorView(
                error: _error!,
                source: _source ?? '',
                onRetry: () => _load(_source),
              )
            else if (_candidates.isEmpty && _metadataCandidates.isEmpty)
              EmptyState(icon: Icons.search_off_rounded, title: tr('未找到作品资料'))
            else ...[
              Text(tr('选择作品'), style: context.text.titleMedium),
              for (final item in _candidates)
                ListTile(
                  title: Text(item.title),
                  subtitle: Text(item.id),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => setState(
                    () => _detail = DetailPage(
                      source: item.source,
                      id: item.id,
                      preview: item,
                      sourceManager: widget.manager,
                    ),
                  ),
                ),
              for (final item in _metadataCandidates)
                ListTile(
                  title: Text(item.title),
                  subtitle: Text(item.code),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () =>
                      setState(() => _detail = _metadata(_source!, item.id)),
                ),
            ],
            if (widget.source == null)
              for (final source in _sources.where((s) => s.key != _source))
                OutlinedButton(
                  onPressed: () => _load(source.key),
                  child: Text(source.manifest!.name),
                ),
          ],
        ],
      ),
    );
  }
}
