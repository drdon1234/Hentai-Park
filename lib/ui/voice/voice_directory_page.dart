import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../../core/models.dart';
import '../../core/voice.dart';
import '../../engine/source_manager.dart';
import '../kit/kit.dart';
import '../nav.dart';
import '../widgets/common.dart' show LoadingIndicator;
import '../widgets/error_view.dart';
import '../widgets/option_bar.dart';
import 'voice_attachment_page.dart';
import 'voice_labels.dart';

enum _TrackFilter { all, audio, video, mixed }

enum _LanguageFilter { all, chineseSpoken, chineseSubtitled, foreignOriginal }

class _FolderState {
  _FolderState({this.expanded = false});
  bool expanded;
  bool loading = false;
  bool complete = false;
  int page = 1;
  Object? error;
  CancelToken? cancel;
  Future<void>? operation;
  final List<VoiceNode> items = [];
  final Set<String> seen = {};
  Map<String, List<VoiceNode>> subtitles = const {};
  bool hasAudio = false;
  bool hasVideo = false;
}

class _TreeRow {
  const _TreeRow(this.folder, this.depth, {this.node, this.status = false});
  final _FolderState folder;
  final VoiceNode? node;
  final int depth;
  final bool status;
}

/// 多层目录以单个可虚拟化列表展示；各目录独立加载、取消及重试。
class VoiceDirectoryPage extends StatefulWidget {
  const VoiceDirectoryPage({
    super.key,
    required this.work,
    required this.root,
    this.sourceManager,
  });
  final WorkDetail work;
  final VoiceNode root;
  final SourceManager? sourceManager;

  @override
  State<VoiceDirectoryPage> createState() => _VoiceDirectoryPageState();
}

class _VoiceDirectoryPageState extends State<VoiceDirectoryPage> {
  final _folders = <String, _FolderState>{};
  _TrackFilter _filter = _TrackFilter.all;
  _LanguageFilter _language = _LanguageFilter.all;
  late final String _rootId;
  final _option = OptionDef.fromJson({
    'key': 'media',
    'label': '类型',
    'default': 'all',
    'values': [
      {'value': 'all', 'label': '全部'},
      {'value': 'audio', 'label': '音频'},
      {'value': 'video', 'label': '视频'},
      {'value': 'mixed', 'label': '音画混合'},
    ],
  });
  final _languageOption = OptionDef.fromJson({
    'key': 'language',
    'label': '语言',
    'default': 'all',
    'values': [
      {'value': 'all', 'label': '全部'},
      {'value': 'chineseSpoken', 'label': '中文配音'},
      {'value': 'chineseSubtitled', 'label': '中文字幕'},
      {'value': 'foreignOriginal', 'label': '外语原版'},
    ],
  });

  @override
  void initState() {
    super.initState();
    final node = widget.root;
    final slash = node.id.lastIndexOf('/');
    _rootId = node.kind == VoiceNodeKind.directory
        ? node.id
        : slash <= 0
        ? '/'
        : node.id.substring(0, slash);
    _folders[_rootId] = _FolderState(expanded: true);
    unawaited(_load(_rootId));
  }

  Future<void> _load(String id) {
    final folder = _folders.putIfAbsent(id, _FolderState.new);
    if (folder.loading || folder.complete) {
      return folder.operation ?? Future.value();
    }
    final cancel = folder.cancel = CancelToken();
    folder.loading = true;
    folder.error = null;
    final operation = () async {
      try {
        while (true) {
          final result = await (widget.sourceManager ?? SourceManager.instance)
              .voiceDirectory(
                widget.work.source,
                widget.work.id,
                id,
                page: folder.page,
                cancelToken: cancel,
              );
          if (!mounted ||
              cancel.isCancelled ||
              !identical(folder.cancel, cancel)) {
            return;
          }
          if (result.items.any((node) => folder.seen.contains(node.id))) {
            throw SourceError('PARSE', '媒体数据无效');
          }
          folder.items.addAll(result.items);
          folder.seen.addAll(result.items.map((node) => node.id));
          folder.hasAudio =
              folder.hasAudio ||
              result.items.any((node) => node.kind == VoiceNodeKind.audio);
          folder.hasVideo =
              folder.hasVideo ||
              result.items.any((node) => node.kind == VoiceNodeKind.video);
          folder.subtitles = matchVoiceSubtitles(folder.items);
          folder.page++;
          folder.complete = !result.hasNext;
          setState(() {});
          if (folder.complete) break;
          if (result.items.isEmpty ||
              folder.items.length >= 5000 ||
              folder.page > 100) {
            throw SourceError('PARSE', '媒体数据无效');
          }
        }
      } catch (error) {
        if (mounted &&
            !cancel.isCancelled &&
            identical(folder.cancel, cancel)) {
          folder.error = error;
        }
      } finally {
        if (mounted && identical(folder.cancel, cancel)) {
          folder.loading = false;
          setState(() {});
        }
      }
    }();
    folder.operation = operation;
    if (mounted) setState(() {});
    return operation;
  }

  VoiceLanguageStatus _trackLanguage(VoiceNode node, _FolderState folder) =>
      voiceTrackLanguage(
        node,
        folder.subtitles,
        inherited: widget.work.voiceLanguageStatus,
      );

  bool _included(VoiceNode node, _FolderState folder) {
    final media = switch (_filter) {
      _TrackFilter.all => true,
      _TrackFilter.audio => node.kind == VoiceNodeKind.audio,
      _TrackFilter.video => node.kind == VoiceNodeKind.video,
      _TrackFilter.mixed => node.playable && folder.hasAudio && folder.hasVideo,
    };
    if (!media || _language == _LanguageFilter.all || !node.playable) {
      return media && (_language == _LanguageFilter.all || node.playable);
    }
    return _trackLanguage(node, folder).name == _language.name;
  }

  List<_TreeRow> _rows() {
    final rows = <_TreeRow>[];
    void addFolder(_FolderState folder, int depth) {
      for (final node in folder.items) {
        if (node.kind != VoiceNodeKind.directory && !_included(node, folder)) {
          continue;
        }
        rows.add(_TreeRow(folder, depth, node: node));
        if (node.kind == VoiceNodeKind.directory) {
          final child = _folders[node.id];
          if (child?.expanded == true) addFolder(child!, depth + 1);
        }
      }
      if (folder.loading || folder.error != null) {
        rows.add(_TreeRow(folder, depth, status: true));
      }
    }

    addFolder(_folders[_rootId]!, 0);
    return rows;
  }

  void _toggleFolder(VoiceNode node) {
    final folder = _folders.putIfAbsent(node.id, _FolderState.new);
    setState(() => folder.expanded = !folder.expanded);
    if (folder.expanded) {
      unawaited(_load(node.id));
    } else {
      folder.cancel?.cancel('directory collapsed');
      folder.cancel = null;
      folder.loading = false;
    }
  }

  Future<void> _play(VoiceNode node, _FolderState folder) async {
    if (!mounted) return;
    final tracks = folder.items
        .where((entry) => entry.playable && _included(entry, folder))
        .toList();
    if (!tracks.any((track) => track.id == node.id)) return;
    final subtitles = folder.subtitles;
    final form = voiceMediaForm(
      VoiceNode(
        id: _rootId,
        name: widget.work.title,
        kind: VoiceNodeKind.directory,
        children: folder.items,
        childrenComplete: folder.complete,
      ),
    );
    final work = WorkDetail({
      ...widget.work.json,
      if (form != VoiceMediaForm.unknown) 'voiceMediaForm': form.name,
      'chaptersComplete': false,
      'chapters': [
        for (final track in tracks) {'id': track.id, 'title': track.name},
      ],
      'voiceTrackKinds': {
        for (final track in tracks) track.id: track.kind.name,
      },
      'voiceSubtitles': {
        for (final entry in subtitles.entries)
          entry.key: [for (final subtitle in entry.value) subtitle.id],
      },
    }, widget.work.source);
    await Nav.openVideo(context, work, episodeId: node.id);
  }

  Widget _row(_TreeRow row) {
    final indent = (row.depth * Gap.l).clamp(0.0, 7 * Gap.l);
    if (row.status) {
      if (row.folder.error case final error?) {
        final id = _folders.entries
            .firstWhere((entry) => identical(entry.value, row.folder))
            .key;
        return Padding(
          padding: EdgeInsetsDirectional.only(start: indent),
          child: SourceErrorView(
            error: error,
            source: widget.work.source,
            compact: true,
            onRetry: () => unawaited(_load(id)),
          ),
        );
      }
      return const Padding(
        padding: EdgeInsets.all(Gap.l),
        child: Center(child: LoadingIndicator()),
      );
    }
    final node = row.node!;
    final isDirectory = node.kind == VoiceNodeKind.directory;
    final expanded = _folders[node.id]?.expanded == true;
    final languageLabel = node.playable
        ? voiceLanguageLabel(_trackLanguage(node, row.folder))
        : null;
    final openAttachment =
        node.kind == VoiceNodeKind.image ||
        (node.kind == VoiceNodeKind.script &&
            node.name.toLowerCase().endsWith('.txt'));
    final icon = switch (node.kind) {
      VoiceNodeKind.directory => Icons.folder_outlined,
      VoiceNodeKind.audio => Icons.audio_file_outlined,
      VoiceNodeKind.video => Icons.movie_outlined,
      VoiceNodeKind.subtitle => Icons.subtitles_outlined,
      VoiceNodeKind.image => Icons.image_outlined,
      VoiceNodeKind.script => Icons.description_outlined,
      _ => Icons.insert_drive_file_outlined,
    };
    return Semantics(
      expanded: isDirectory ? expanded : null,
      child: Padding(
        padding: EdgeInsetsDirectional.only(start: indent),
        child: ListTile(
          leading: Icon(icon),
          title: Text(node.name),
          subtitle: languageLabel == null ? null : Text(languageLabel),
          trailing: isDirectory
              ? Icon(
                  expanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                )
              : node.playable
              ? const Icon(Icons.play_arrow_rounded)
              : null,
          onTap: isDirectory
              ? () => _toggleFolder(node)
              : node.playable
              ? () => _play(node, row.folder)
              : openAttachment
              ? () => Nav.push(
                  context,
                  VoiceAttachmentPage(
                    work: widget.work,
                    node: node,
                    sourceManager: widget.sourceManager,
                  ),
                )
              : null,
        ),
      ),
    );
  }

  @override
  void dispose() {
    for (final folder in _folders.values) {
      folder.cancel?.cancel('directory page closed');
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows();
    final root = _folders[_rootId]!;
    return Scaffold(
      appBar: PageHeader(title: widget.work.title),
      body: Column(
        children: [
          OptionBar(
            options: [_option, _languageOption],
            values: {'media': _filter.name, 'language': _language.name},
            onChanged: (values) => setState(() {
              _filter = _TrackFilter.values.firstWhere(
                (value) => value.name == values['media'],
              );
              _language = _LanguageFilter.values.firstWhere(
                (value) => value.name == values['language'],
              );
            }),
          ),
          Expanded(
            child: rows.isEmpty && root.complete
                ? Center(
                    child: Text(
                      tr(
                        _filter == _TrackFilter.all &&
                                _language == _LanguageFilter.all
                            ? '目录为空'
                            : '没有符合条件的曲目',
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: rows.length,
                    itemBuilder: (context, index) => _row(rows[index]),
                  ),
          ),
        ],
      ),
    );
  }
}
