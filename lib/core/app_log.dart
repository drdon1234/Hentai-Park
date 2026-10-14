import 'package:flutter/foundation.dart';

import 'diagnostics.dart';
import 'models.dart';

class _Entry {
  _Entry(this.time, this.site, this.text, this.frames);
  final DateTime time;
  final String? site;
  final String text;
  final List<String> frames;
  int count = 1;
}

/// The diagnostics log of this run. Entries are sanitized by [Diagnostics]
/// when recorded, so the in-app view and the export show the same facts.
class AppLog {
  static const _limit = 500;
  static final _entries = <_Entry>[];

  static void record(
    Map fields, {
    PluginCopy? copy,
    List<String> frames = const [],
  }) {
    final clean = Diagnostics.fields(fields, copy: copy);
    final text = Diagnostics.format(clean);
    final last = _entries.lastOrNull;
    // HLS segments and retries repeat the same failure; count them instead.
    if (last != null &&
        last.text == text &&
        frames.isEmpty &&
        last.frames.isEmpty) {
      last.count++;
    } else {
      _entries.add(_Entry(DateTime.now(), clean['site'], text, frames));
      if (_entries.length > _limit) {
        _entries.removeRange(0, _entries.length - _limit);
      }
    }
    if (kDebugMode) debugPrint(text);
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
  static Set<String> get sites => {for (final entry in _entries) ?entry.site};

  static List<String> get lines => [
    for (final entry in _entries) ...[
      '${entry.time.toIso8601String().substring(11, 19)} ${entry.text}'
          '${entry.count > 1 ? ' ×${entry.count}' : ''}',
      for (final frame in entry.frames) '  $frame',
    ],
  ];
}
