import '../../core/models.dart';

class AlbumMediaEntry {
  const AlbumMediaEntry({
    required this.work,
    required this.index,
    required this.type,
    required this.preview,
    required this.count,
  });

  final WorkItem work;
  final int index;
  final String type;
  final String preview;
  final int count;

  String get identity {
    final item = _media(work)[index];
    return '${work.uid}:${item['id']}';
  }

  Map<String, dynamic> get media => _media(work)[index].cast<String, dynamic>();
}

List<Map> _media(WorkItem item) =>
    (item.json['media'] as List? ?? const []).cast<Map>();

DateTime? albumDate(WorkItem item) {
  final value = item.json['date'];
  if (value == null || value.toString().trim().isEmpty) {
    if (item.uploaded.isEmpty) return null;
    return DateTime.tryParse(item.uploaded)?.toLocal();
  }
  if (value is num) {
    if (!value.isFinite) return null;
    final number = value.toInt();
    final milliseconds = number.abs() < 100000000000 ? number * 1000 : number;
    if (milliseconds.abs() > 8640000000000000) return null;
    return DateTime.fromMillisecondsSinceEpoch(milliseconds);
  }
  final raw = value?.toString().trim() ?? '';
  if (raw.isEmpty) return null;
  return DateTime.tryParse(raw)?.toLocal();
}

List<AlbumMediaEntry> albumMedia(
  Iterable<WorkItem> works, {
  String type = 'all',
  DateTime? start,
  DateTime? end,
  bool collapsed = false,
}) {
  final entries = <AlbumMediaEntry>[];
  final startDay = start == null
      ? null
      : DateTime(start.year, start.month, start.day);
  final afterEndDay = end == null
      ? null
      : DateTime(end.year, end.month, end.day + 1);
  for (final work in works) {
    final date = albumDate(work);
    if ((startDay != null || afterEndDay != null) && date == null) continue;
    if (startDay != null && date!.isBefore(startDay)) continue;
    if (afterEndDay != null && !date!.isBefore(afterEndDay)) continue;
    final media = _media(work);
    final matches = <int>[];
    for (var i = 0; i < media.length; i++) {
      final kind = media[i]['type'];
      if ((kind != 'image' && kind != 'video') ||
          (type != 'all' && kind != type)) {
        continue;
      }
      matches.add(i);
    }
    if (matches.isEmpty) continue;
    final shown = collapsed ? [matches.first] : matches;
    for (final index in shown) {
      final item = media[index];
      final supplied = item['preview']?.toString() ?? '';
      final preview = supplied.isNotEmpty
          ? supplied
          : (item['type'] == 'image' ? item['url']?.toString() ?? '' : '');
      entries.add(
        AlbumMediaEntry(
          work: work,
          index: index,
          type: item['type'] as String,
          preview: preview,
          count: matches.length,
        ),
      );
    }
  }
  return entries;
}
