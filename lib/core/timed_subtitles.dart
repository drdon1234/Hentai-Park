/// 一条带时间范围的字幕；结束时间为开区间，null 表示没有已知结束时间。
class TimedSubtitleCue {
  const TimedSubtitleCue({
    required this.start,
    required this.end,
    required this.text,
  });

  final Duration start;
  final Duration? end;
  final String text;
}

/// 纯文本字幕时间轴，支持同时出现的多个字幕片段。
class TimedSubtitles {
  TimedSubtitles._(this.cues) {
    var latestEnd = -1;
    for (final cue in cues) {
      final end = cue.end?.inMilliseconds ?? _unbounded;
      if (end > latestEnd) latestEnd = end;
      _prefixEnds.add(latestEnd);
    }
  }

  factory TimedSubtitles.parse(String content, {required String format}) {
    final text = content
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceFirst(RegExp('^\uFEFF'), '');
    final cues = switch (format.toLowerCase().replaceFirst('.', '')) {
      'lrc' => _parseLrc(text),
      'vtt' || 'srt' => _parseBlocks(text),
      _ => throw const FormatException('不支持的字幕格式'),
    };
    cues.sort((a, b) => a.start.compareTo(b.start));
    return TimedSubtitles._(List.unmodifiable(cues));
  }

  static const _unbounded = 0x7fffffffffffffff;
  final List<TimedSubtitleCue> cues;
  final List<int> _prefixEnds = [];

  /// 返回当前仍有效的字幕索引，顺序与 [cues] 一致。
  List<int> activeAt(Duration position) {
    final time = position.inMilliseconds;
    var low = 0;
    var high = cues.length;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (cues[mid].start.inMilliseconds <= time) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    final active = <int>[];
    for (var i = low - 1; i >= 0 && _prefixEnds[i] > time; i--) {
      final end = cues[i].end;
      if (end == null || end.inMilliseconds > time) active.add(i);
    }
    return active.reversed.toList(growable: false);
  }
}

List<TimedSubtitleCue> _parseBlocks(String text) {
  final lines = text.split('\n');
  final cues = <TimedSubtitleCue>[];
  final timeLine = RegExp(r'^\s*(\S+)\s+-->\s+(\S+)(?:\s+.*)?$');
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i].trim();
    if (line == 'NOTE' ||
        line.startsWith('NOTE ') ||
        line == 'STYLE' ||
        line == 'REGION') {
      while (i + 1 < lines.length && lines[i + 1].trim().isNotEmpty) {
        i++;
      }
      continue;
    }
    final match = timeLine.firstMatch(lines[i]);
    if (match == null) continue;
    final start = _subtitleTime(match[1]!);
    final end = _subtitleTime(match[2]!);
    final body = <String>[];
    while (i + 1 < lines.length && lines[i + 1].trim().isNotEmpty) {
      body.add(lines[++i]);
    }
    final value = _subtitleText(body.join('\n'));
    if (start == null || end == null || end <= start || value.isEmpty) continue;
    cues.add(TimedSubtitleCue(start: start, end: end, text: value));
  }
  return cues;
}

List<TimedSubtitleCue> _parseLrc(String text) {
  final timestamp = RegExp(r'\[(\d{1,3}):([0-5]\d)(?:[.:](\d{1,3}))?\]');
  final offsetTag = RegExp(r'^\[offset:([+-]?\d+)\]\s*$', caseSensitive: false);
  var offset = 0;
  final values = <(int, String)>[];
  for (final line in text.split('\n')) {
    final trimmed = line.trim();
    if (offsetTag.firstMatch(trimmed) case final match?) {
      offset = int.tryParse(match[1]!) ?? 0;
      continue;
    }
    final matches = timestamp.allMatches(trimmed).toList();
    if (matches.isEmpty || matches.first.start != 0) continue;
    var end = 0;
    final times = <int>[];
    for (final match in matches) {
      if (match.start != end) break;
      final fraction = (match[3] ?? '').padRight(3, '0');
      times.add(
        (int.parse(match[1]!) * 60 + int.parse(match[2]!)) * 1000 +
            (fraction.isEmpty ? 0 : int.parse(fraction)),
      );
      end = match.end;
    }
    final value = _subtitleText(trimmed.substring(end));
    if (value.isEmpty) continue;
    for (final time in times) {
      values.add((time, value));
    }
  }
  values.sort((a, b) => a.$1.compareTo(b.$1));
  final ends = List<Duration?>.filled(values.length, null);
  Duration? nextEnd;
  for (var i = values.length - 1; i >= 0; i--) {
    if (i + 1 < values.length && values[i + 1].$1 > values[i].$1) {
      nextEnd = Duration(
        milliseconds: (values[i + 1].$1 + offset).clamp(0, 0x7fffffff),
      );
    }
    ends[i] = nextEnd;
  }
  return [
    for (var i = 0; i < values.length; i++)
      TimedSubtitleCue(
        start: Duration(
          milliseconds: (values[i].$1 + offset).clamp(0, 0x7fffffff),
        ),
        end: ends[i],
        text: values[i].$2,
      ),
  ];
}

Duration? _subtitleTime(String value) {
  final match = RegExp(r'^(?:(\d{1,3}):)?(\d{1,2}):([0-5]\d)[.,](\d{1,3})$')
      .firstMatch(value);
  if (match == null) return null;
  final hours = int.tryParse(match[1] ?? '0');
  final minutes = int.tryParse(match[2]!);
  if (hours == null || minutes == null || minutes > 59) return null;
  final milliseconds = int.parse(match[4]!.padRight(3, '0'));
  return Duration(
    hours: hours,
    minutes: minutes,
    seconds: int.parse(match[3]!),
    milliseconds: milliseconds,
  );
}

String _subtitleText(String value) => value
    .replaceAll(RegExp(r'<[^>]*>'), '')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&')
    .trim();
