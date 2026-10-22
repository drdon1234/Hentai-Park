import 'dart:convert';

import 'diagnostics.dart';
import 'models.dart';

enum LogMode { full, redacted }

/// A timestamp belongs to the whole event, including its ordered stack frames.
class DiagnosticEntry {
  DiagnosticEntry({
    required this.time,
    required Map fields,
    PluginCopy? copy,
    List<String> frames = const [],
    this.count = 1,
  }) : fields = Diagnostics.fields(fields, copy: copy),
       frames = Diagnostics.stack(StackTrace.fromString(frames.join('\n')));

  DateTime time;
  final Map<String, String> fields;
  final List<String> frames;
  int count;

  /// 正常退出与升级不属于故障；未知原因只有非零退出码才保留。
  bool get actionable =>
      fields['event'] != 'process_exit' ||
      (!const {
            'USER_REQUESTED',
            'USER_STOPPED',
            'PACKAGE_UPDATED',
            'PACKAGE_STATE_CHANGE',
            'PERMISSION_CHANGE',
            'EXIT_SELF',
          }.contains(fields['reason']) &&
          (!const {'OTHER', 'UNKNOWN'}.contains(fields['reason']) ||
              int.tryParse(fields['exitStatus'] ?? '0') != 0));

  String get identity => jsonEncode({
    'time': time.toIso8601String(),
    // Plugin-only copy keys may be dropped when history is sanitized without
    // a plugin runtime. They must not make the same crash appear twice.
    'fields': {...fields}..remove('message'),
    'frames': frames,
  });

  Map<String, Object> toJson() => {
    'time': time.toIso8601String(),
    'fields': fields,
    'frames': frames,
    if (count > 1) 'count': count,
  };

  static DiagnosticEntry? fromJson(Object? value) {
    if (value is! Map || value['fields'] is! Map) return null;
    final time = DateTime.tryParse('${value['time']}');
    if (time == null) return null;
    return DiagnosticEntry(
      time: time,
      fields: Diagnostics.fields(value['fields'] as Map),
      frames: value['frames'] is List
          ? (value['frames'] as List).whereType<String>().toList()
          : const [],
      count: value['count'] is int && value['count'] > 0 ? value['count'] : 1,
    );
  }

  List<String> lines(LogMode mode) {
    final selectedFields = {...fields};
    if (mode == LogMode.redacted) selectedFields.remove('host');
    return [
      '${time.toLocal().toIso8601String()} ${Diagnostics.format(selectedFields)}'
          '${count > 1 ? ' ×$count' : ''}',
      for (final frame in frames) '  $frame',
    ];
  }
}
