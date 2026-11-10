/// 音声源提供的公开元数据。未知值不能推断为外语原版或纯音频。
enum VoiceLanguageStatus {
  chineseSpoken,
  chineseSubtitled,
  foreignOriginal,
  unknown;

  static VoiceLanguageStatus fromJson(Object? value) => values.firstWhere(
    (status) => status.name == value,
    orElse: () => unknown,
  );
}

enum VoiceMediaForm {
  audioOnly,
  videoOnly,
  mixed,
  unknown;

  static VoiceMediaForm fromJson(Object? value) =>
      values.firstWhere((form) => form.name == value, orElse: () => unknown);
}

enum VoiceNodeKind {
  directory,
  audio,
  video,
  subtitle,
  image,
  script,
  other;

  static VoiceNodeKind fromJson(Object? value) =>
      values.firstWhere((kind) => kind.name == value, orElse: () => other);
}

/// 节点 ID 用于向源重新解析资源；临时媒体地址不存进目录或历史。
class VoiceNode {
  VoiceNode({
    required this.id,
    required this.name,
    required this.kind,
    this.languageStatus = VoiceLanguageStatus.unknown,
    this.subtitleLanguage,
    this.subtitleIds = const [],
    this.children = const [],
    this.childrenComplete = true,
  });

  factory VoiceNode.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    if (id is! String || id.isEmpty || name is! String || name.isEmpty) {
      throw const FormatException('音声目录节点缺少身份或名称');
    }
    final kind = VoiceNodeKind.fromJson(json['type']);
    final rawSubtitleIds = json['subtitleIds'];
    if (rawSubtitleIds != null &&
        ((kind != VoiceNodeKind.audio && kind != VoiceNodeKind.video) ||
            rawSubtitleIds is! List ||
            rawSubtitleIds.length > 50 ||
            rawSubtitleIds.any(
              (id) =>
                  id is! String ||
                  id.isEmpty ||
                  id.length > 4096 ||
                  _voiceUrlPattern.hasMatch(id),
            ) ||
            rawSubtitleIds.toSet().length != rawSubtitleIds.length)) {
      throw const FormatException('音声字幕关联格式无效');
    }
    final rawChildren = json['children'];
    if (rawChildren != null &&
        (kind != VoiceNodeKind.directory || rawChildren is! List)) {
      throw const FormatException('音声目录节点格式无效');
    }
    final children = <VoiceNode>[];
    if (rawChildren is List) {
      final seen = <String>{};
      for (final entry in rawChildren) {
        if (entry is! Map) throw const FormatException('音声目录节点格式无效');
        final child = VoiceNode.fromJson(entry.cast<String, dynamic>());
        if (!seen.add(child.id)) throw const FormatException('音声目录节点身份重复');
        children.add(child);
      }
    }
    return VoiceNode(
      id: id,
      name: name,
      kind: kind,
      languageStatus: VoiceLanguageStatus.fromJson(json['voiceLanguageStatus']),
      subtitleLanguage: json['subtitleLanguage'] is String
          ? json['subtitleLanguage'] as String
          : null,
      subtitleIds: rawSubtitleIds is List
          ? List<String>.unmodifiable(rawSubtitleIds.cast<String>())
          : const [],
      children: List.unmodifiable(children),
      childrenComplete:
          kind != VoiceNodeKind.directory ||
          (rawChildren is List && json['childrenComplete'] != false),
    );
  }

  final String id;
  final String name;
  final VoiceNodeKind kind;
  final VoiceLanguageStatus languageStatus;

  /// 字幕语言只能由站点提供，不从文件扩展名推断。
  final String? subtitleLanguage;

  /// 源明确给出的字幕节点身份；只会关联当前目录中的字幕。
  final List<String> subtitleIds;
  final List<VoiceNode> children;

  /// 未加载或分页未完成的目录不能用于断定作品只有某一种媒体。
  final bool childrenComplete;

  bool get playable =>
      kind == VoiceNodeKind.audio || kind == VoiceNodeKind.video;
}

/// 只在来源声明字幕语言且同级文件完成配对时标记中文字幕。
VoiceLanguageStatus voiceTrackLanguage(
  VoiceNode track,
  Map<String, List<VoiceNode>> subtitles, {
  VoiceLanguageStatus inherited = VoiceLanguageStatus.unknown,
}) {
  if (subtitles[track.id]?.any(
        (subtitle) => subtitle.subtitleLanguage == 'zh',
      ) ==
      true) {
    return VoiceLanguageStatus.chineseSubtitled;
  }
  return track.languageStatus == VoiceLanguageStatus.unknown
      ? inherited
      : track.languageStatus;
}

class VoiceDirectoryPageData {
  const VoiceDirectoryPageData({required this.items, required this.hasNext});

  final List<VoiceNode> items;
  final bool hasNext;
}

final _voiceUrlPattern = RegExp(r'^[a-z][a-z0-9+.-]*://', caseSensitive: false);

/// 详情中的曲目字幕引用只包含稳定节点 ID，不包含媒体 URL。
Map<String, List<String>> parseVoiceSubtitleReferences(Object? value) {
  if (value == null) return const {};
  if (value is! Map || value.length > 5000) {
    throw const FormatException('音声字幕关联格式无效');
  }
  final result = <String, List<String>>{};
  for (final entry in value.entries) {
    final key = entry.key, raw = entry.value;
    if (key is! String ||
        key.isEmpty ||
        key.length > 4096 ||
        _voiceUrlPattern.hasMatch(key) ||
        raw is! List ||
        raw.length > 50 ||
        raw.any(
          (id) =>
              id is! String ||
              id.isEmpty ||
              id.length > 4096 ||
              _voiceUrlPattern.hasMatch(id),
        ) ||
        raw.toSet().length != raw.length) {
      throw const FormatException('音声字幕关联格式无效');
    }
    result[key] = List<String>.unmodifiable(raw.cast<String>());
  }
  return Map.unmodifiable(result);
}

/// 优先关联源明确给出的字幕，并补充同级同名的 LRC/VTT/SRT。
/// 不跨目录匹配，也不把文件名后缀之外的语言标记当作同名。
Map<String, List<VoiceNode>> matchVoiceSubtitles(List<VoiceNode> siblings) {
  final subtitles = <String, List<VoiceNode>>{};
  final byId = <String, VoiceNode>{};
  for (final node in siblings) {
    if (node.kind != VoiceNodeKind.subtitle) continue;
    byId[node.id] = node;
    final stem = _voiceStem(node.name, const {'lrc', 'vtt', 'srt'});
    if (stem != null) (subtitles[stem] ??= []).add(node);
  }
  final result = <String, List<VoiceNode>>{};
  for (final node in siblings.where((node) => node.playable)) {
    final stem = _voiceStem(node.name, const {
      'mp3',
      'flac',
      'wav',
      'm4a',
      'aac',
      'ogg',
      'opus',
      'mp4',
      'm4v',
      'mkv',
      'webm',
      'm3u8',
    });
    final matches = <String, VoiceNode>{};
    for (final id in node.subtitleIds) {
      if (byId[id] case final subtitle?) matches[id] = subtitle;
    }
    if (stem != null) {
      for (final subtitle in subtitles[stem] ?? const <VoiceNode>[]) {
        matches[subtitle.id] = subtitle;
      }
    }
    if (matches.isNotEmpty) result[node.id] = List.unmodifiable(matches.values);
  }
  return result;
}

String? _voiceStem(String name, Set<String> extensions) {
  if (name.contains('/') || name.contains(r'\')) return null;
  final dot = name.lastIndexOf('.');
  if (dot <= 0 || dot == name.length - 1) return null;
  if (!extensions.contains(name.substring(dot + 1).toLowerCase())) return null;
  return name.substring(0, dot).toLowerCase();
}

/// 仅在目录已完整加载时将单一形态作为确定结论；已见两种媒体即为混合。
VoiceMediaForm voiceMediaForm(VoiceNode root) {
  var audio = false;
  var video = false;
  var complete = true;
  void visit(VoiceNode node) {
    if (node.kind == VoiceNodeKind.audio) audio = true;
    if (node.kind == VoiceNodeKind.video) video = true;
    if (node.kind == VoiceNodeKind.directory) {
      complete = complete && node.childrenComplete;
      for (final child in node.children) {
        visit(child);
      }
    }
  }

  visit(root);
  if (audio && video) return VoiceMediaForm.mixed;
  if (!complete) return VoiceMediaForm.unknown;
  if (audio) return VoiceMediaForm.audioOnly;
  if (video) return VoiceMediaForm.videoOnly;
  return VoiceMediaForm.unknown;
}
