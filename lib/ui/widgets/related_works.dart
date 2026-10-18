import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../../core/models.dart';
import '../../core/tag_blocklist.dart';
import '../../engine/source_manager.dart';
import '../kit/tokens.dart';
import 'error_view.dart';
import 'paged_grid.dart';
import 'source_interaction.dart';

/// Static related lists remain usable; sources with a related method can continue loading.
class RelatedWorks extends StatefulWidget {
  const RelatedWorks({super.key, required this.detail, this.sourceManager});
  final WorkDetail detail;
  final SourceManager? sourceManager;
  @override
  State<RelatedWorks> createState() => _RelatedWorksState();
}

class _RelatedWorksState extends State<RelatedWorks> {
  SourceManager get _manager => widget.sourceManager ?? SourceManager.instance;
  late final _paged = PagedController(
    (page, cursor) => _manager.related(
      widget.detail.source,
      widget.detail.id,
      page: page,
      cursor: cursor,
      cancelToken: _request,
    ),
    source: widget.detail.source,
  );
  final _request = CancelToken();
  final _extra = <WorkItem>[];
  final _seeds = <String>{};
  WorkItem? _failedSeed;
  Object? _extraError;
  final _pendingExtras = <String>{};
  bool get _extraLoading => _pendingExtras.isNotEmpty;
  bool get _dynamic =>
      _manager.manifest(widget.detail.source)?.can('related') == true;

  @override
  void initState() {
    super.initState();
    if (_dynamic) unawaited(_paged.loadMore());
    sourceInteractionChanges.addListener(_interactionChanged);
  }

  void _interactionChanged() {
    final change = sourceInteractionChanges.value;
    if (!_dynamic ||
        change == null ||
        change.item.source != widget.detail.source ||
        change.value != true) {
      return;
    }
    final known = {
      widget.detail.id,
      ...widget.detail.related.map((i) => i.id),
      ...widget.detail.relatedSections.expand((s) => s.items.map((i) => i.id)),
      ..._paged.items.map((i) => i.id),
      ..._extra.map((i) => i.id),
    };
    if (!known.contains(change.item.id) || !_seeds.add(change.item.id)) return;
    unawaited(_append(change.item));
  }

  Future<void> _append(WorkItem seed) async {
    if (!_pendingExtras.add(seed.uid)) return;
    setState(() {
      _extraError = null;
      _failedSeed = null;
    });
    try {
      final page = await _manager.related(
        seed.source,
        seed.id,
        cancelToken: _request,
      );
      if (!mounted || _request.isCancelled) return;
      setState(() => _extra.addAll(page.items));
    } catch (e) {
      if (mounted && !_request.isCancelled) {
        setState(() {
          _extraError = e;
          _failedSeed = seed;
        });
      }
    } finally {
      _pendingExtras.remove(seed.uid);
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    sourceInteractionChanges.removeListener(_interactionChanged);
    _request.cancel('related closed');
    _paged.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _paged,
    builder: (context, _) {
      final seen = <String>{widget.detail.id};
      final blocklist = TagBlocklist.current();
      final items = [...widget.detail.related, ..._paged.items, ..._extra]
          .where(
            (item) => seen.add(item.id) && blocklist.matchItem(item) == null,
          )
          .toList();
      final error = _paged.error ?? _extraError;
      return Column(
        children: [
          for (final section in widget.detail.relatedSections)
            WorkCarousel(
              title:
                  _manager
                      .manifest(widget.detail.source)
                      ?.copy
                      .text(section.title) ??
                  section.title,
              items: section.items
                  .where(
                    (item) =>
                        item.id != widget.detail.id &&
                        blocklist.matchItem(item) == null,
                  )
                  .toList(),
            ),
          if (items.isNotEmpty)
            WorkCarousel(
              title: tr('相关推荐'),
              items: items,
              onEndReached: _dynamic && _paged.hasNext && error == null
                  ? _paged.loadMore
                  : null,
              trailing: _dynamic && _paged.hasNext && !_paged.loading
                  ? TextButton(
                      onPressed: _paged.loadMore,
                      child: Text(tr('加载更多')),
                    )
                  : null,
            ),
          if (items.isEmpty &&
              _dynamic &&
              _paged.hasNext &&
              !_paged.loading &&
              error == null)
            TextButton(onPressed: _paged.loadMore, child: Text(tr('加载更多'))),
          if (_paged.loading || _extraLoading)
            const Padding(
              padding: EdgeInsets.all(Gap.m),
              child: LinearProgressIndicator(),
            ),
          if (error != null)
            SourceErrorView(
              error: error,
              source: widget.detail.source,
              compact: true,
              onRetry: _paged.error != null
                  ? _paged.loadMore
                  : () => _append(_failedSeed!),
            ),
        ],
      );
    },
  );
}
