import 'timed_subtitles.dart';

/// 曲目保持原身份与独立进度，拼接坐标只用于显示和跨集定位。
class VoiceTimeline {
  VoiceTimeline(List<Duration> lengths) : lengths = List.unmodifiable(lengths) {
    if (lengths.isEmpty || lengths.any((value) => value <= Duration.zero)) {
      throw ArgumentError('Track duration must be positive');
    }
    var offset = Duration.zero;
    for (final length in lengths) {
      offsets.add(offset);
      offset += length;
    }
    duration = offset;
  }
  final List<Duration> lengths;
  final List<Duration> offsets = [];
  late final Duration duration;

  ({int index, Duration position}) locate(Duration position) {
    final bounded = Duration(
      microseconds: position.inMicroseconds.clamp(0, duration.inMicroseconds),
    );
    for (var i = lengths.length - 1; i >= 0; i--) {
      if (bounded >= offsets[i]) {
        return (index: i, position: bounded - offsets[i]);
      }
    }
    return (index: 0, position: Duration.zero);
  }

  List<TimedSubtitleCue> subtitles(List<List<TimedSubtitleCue>> tracks) => [
    for (var i = 0; i < tracks.length; i++)
      for (final cue in tracks[i])
        if (cue.start < lengths[i])
          TimedSubtitleCue(
            start: offsets[i] + cue.start,
            end:
                offsets[i] +
                (cue.end == null || cue.end! > lengths[i]
                    ? lengths[i]
                    : cue.end!),
            text: cue.text,
          ),
  ];
}
