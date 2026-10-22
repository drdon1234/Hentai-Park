import 'package:flutter/foundation.dart';

import 'diagnostic_entry.dart';
import 'diagnostics.dart';
import 'models.dart';

/// The diagnostics log of this run. Entries are sanitized by [Diagnostics]
/// when recorded, so the in-app view and the export show the same facts.
class AppLog {
  static const _limit = 500;
  static final _entries = <DiagnosticEntry>[];

  static DiagnosticEntry record(
    Map fields, {
    PluginCopy? copy,
    List<String> frames = const [],
  }) {
    final clean = Diagnostics.fields(fields, copy: copy);
    final text = Diagnostics.format(clean);
    final cleanFrames = Diagnostics.stack(
      StackTrace.fromString(frames.join('\n')),
    );
    final now = DateTime.now();
    final last = _entries.reversed
        .where(
          (entry) =>
              now.difference(entry.time) <= const Duration(seconds: 30) &&
              Diagnostics.format(entry.fields) == text &&
              listEquals(entry.frames, cleanFrames),
        )
        .firstOrNull;
    // HLS segments and retries repeat the same failure; count them instead.
    if (last != null &&
        clean['event'] != 'crash' &&
        Diagnostics.format(last.fields) == text &&
        listEquals(last.frames, cleanFrames)) {
      last.count++;
      last.time = now;
      _entries.remove(last);
      _entries.add(last);
    } else {
      _entries.add(
        DiagnosticEntry(
          time: DateTime.now(),
          fields: clean,
          copy: copy,
          frames: cleanFrames,
        ),
      );
      if (_entries.length > _limit) {
        _entries.removeRange(0, _entries.length - _limit);
      }
    }
    if (kDebugMode) debugPrint(text);
    return _entries.last;
  }

  /// Records a failure; cancellations are expected and skipped.
  static void error(
    Object error, {
    String event = 'error',
    String? site,
    String? action,
    StackTrace? stack,
  }) {
    if (error is SourceError && error.code == 'CANCELLED') return;
    record(
      {
        'event': event,
        'site': ?site,
        'action': ?action,
        ...Diagnostics.error(error),
      },
      copy: error is SourceError ? error.copy : null,
      frames: Diagnostics.stack(stack),
    );
  }

  /// Sources that appear in this run's log.
  static Set<String> get sites => {
    for (final entry in _entries) ?entry.fields['site'],
  };

  static List<DiagnosticEntry> get entries => List.unmodifiable(_entries);

  static List<String> get lines => linesFor(LogMode.full);

  static List<String> linesFor(LogMode mode) => [
    for (final entry in _entries.reversed) ...entry.lines(mode),
  ];
}
