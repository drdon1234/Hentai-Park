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
    final date = work.workDate;
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
