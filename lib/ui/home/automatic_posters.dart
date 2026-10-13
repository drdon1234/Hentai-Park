import 'dart:convert';

import '../../core/async_tasks.dart';
import '../../core/settings.dart';
import '../../core/tag_blocklist.dart';
import '../../engine/source_manager.dart';
import '../../library/library.dart';

/// 同一站点一个会话内复用首页海报，避免滚动和域切换重复请求。
class AutomaticPosters {
  AutomaticPosters({SourceManager? sourceManager})
    : _sources = sourceManager ?? SourceManager.instance;

  static final instance = AutomaticPosters();
  final SourceManager _sources;
  final _cache = <String, Future<List<String>>>{};
  final _requests = SerialExecutor();
  final _refresh = <String>{};

  String identity(InstalledSource source) =>
      '${source.key}:${source.version}:${source.account?.loggedIn}:${source.manifest.hashCode}:${jsonEncode([AppSettings.instance.blockedTags, AppSettings.instance.blockPresetState])}';

  Future<List<String>> load(InstalledSource source) {
    final account = source.account?.loggedIn == true;
    final manifest = source.manifest!;
    final blocklist = TagBlocklist.current();
    return _cache.putIfAbsent(
      identity(source),
      () => _requests.run(() async {
        final recent = Library.instance
            .history(source: source.key)
            .where((h) => blocklist.matchItem(h.item) == null)
            .map((h) => h.item.cover)
            .where((url) => url.isNotEmpty)
            .toSet()
            .take(3)
            .toList();
        if (recent.isNotEmpty) return recent;
        if (manifest.feeds.isEmpty ||
            (manifest.account?.required == true && !account)) {
          return <String>[];
        }
        try {
          final feed = manifest.feeds[manifest.defaultFeedIndex];
          final page = await _sources.feed(
            source.key,
            feed.key,
            options: feed.defaultOptions(),
            refresh: _refresh.remove(source.key),
          );
          return [...page.items, ...?page.sections?.expand((s) => s.items)]
              .where((item) => blocklist.matchItem(item) == null)
              .map((item) => item.cover)
              .where((url) => url.isNotEmpty)
              .toSet()
              .take(3)
              .toList();
        } catch (_) {
          return <String>[];
        }
      }),
    );
  }

  void refresh(String source) {
    _cache.removeWhere((key, _) => key.startsWith('$source:'));
    _refresh.add(source);
  }
}
