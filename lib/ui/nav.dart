import 'package:flutter/material.dart';

import '../core/models.dart';
import '../engine/source_manager.dart';
import '../library/library.dart';
import '../library/downloads.dart';
import 'detail/detail_page.dart';
import 'reader/reader_page.dart';
import 'search/aggregate_search_page.dart';
import 'search/source_search_page.dart';
import 'settings/settings_page.dart';
import 'settings/source_settings_page.dart';
import 'source/source_page.dart';
import 'video/video_page.dart';
import 'web/web_verify_page.dart';
import 'widgets/common.dart';
import 'widgets/error_view.dart';

/// Central navigation so every entry point (cards, tags, links, history…) behaves the same.
class Nav {
  static Future<T?> push<T>(BuildContext context, Widget page) => Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => page));

  static Future<void> openWork(BuildContext context, WorkItem item) => push(context, DetailPage(source: item.source, id: item.id, preview: item));

  static Future<void> openRef(BuildContext context, String source, String id) => push(context, DetailPage(source: source, id: id));

  static Future<void> openSource(BuildContext context, String source) => push(context, SourcePage(sourceKey: source));

  static Future<void> openSourceSearch(BuildContext context, String source, {String keyword = '', Map<String, Object?>? filters}) =>
      push(context, SourceSearchPage(sourceKey: source, initialKeyword: keyword, initialFilters: filters));

  static Future<void> openAggregateSearch(BuildContext context, {String keyword = ''}) => push(context, AggregateSearchPage(initialKeyword: keyword));

  static Future<void> openReader(BuildContext context, WorkDetail work, {Chapter? chapter, int startPage = 0}) =>
      push(context, ReaderPage(work: work, chapter: chapter, startPage: startPage));

  static Future<void> openVideo(
    BuildContext context,
    WorkDetail work, {
    String? episodeId,
  }) => push(context, VideoPage(work: work, episodeId: episodeId));

  /// Opens the reader or player at [chapterId] from a stored chapter list.
  static Future<void> openChapter(
    BuildContext context,
    WorkItem item,
    String? chapterId, {
    int? page,
  }) async {
    final lib = Library.instance;
    final chapters =
        lib.chaptersCached(item.uid) ?? await lib.loadChapters(item.uid);
    final task = await DownloadManager.instance.normalizeTask(item.uid);
    if (!context.mounted) return;
    if (kindOf(item.source) == MediaKind.video ||
        task?.isVideo == true ||
        lib.historyOf(item.uid)?.position != null) {
      final episodes = [
        for (final chapter in chapters)
          Chapter(chapter.chapterId, chapter.title),
      ];
      final known = episodes.map((episode) => episode.id).toSet();
      for (final episode in task?.chapters ?? const <Chapter>[]) {
        if (known.add(episode.id)) episodes.add(episode);
      }
      if (episodes.isNotEmpty) {
        return openVideo(
          context,
          WorkDetail({
            ...item.json,
            'chaptersComplete': false,
            'chapters': [
              for (final episode in episodes)
                {'id': episode.id, 'title': episode.title},
            ],
          }, item.source),
          episodeId: chapterId,
        );
      }
      final offline = DownloadManager.instance.offlineDetail(
        item.source,
        item.id,
      );
      if (offline != null) {
        return openVideo(context, offline, episodeId: chapterId);
      }
      final detail = await guarded(
        context,
        item.source,
        () => SourceManager.instance.detail(item.source, item.id),
      );
      if (detail != null && context.mounted) {
        await openVideo(context, detail, episodeId: chapterId);
      }
      return;
    }
    if (chapters.isEmpty) return openWork(context, item);
    final key = chapterKeyOf(chapterId);
    final state =
        chapters.where((c) => c.chapterId == key).firstOrNull ?? chapters.first;
    final start = page ?? (state.read ? 0 : state.lastPage);
    if (chapters.length == 1) {
      final only = chapters.first.chapterId;
      final detail = WorkDetail({
        ...item.json,
        'id': item.id,
        'singleChapterId': only == '_' ? null : only,
      }, item.source);
      return openReader(context, detail, startPage: start);
    }
    final detail = WorkDetail({
      ...item.json,
      'id': item.id,
      'chapters': [
        for (final c in chapters) {'id': c.chapterId, 'title': c.title},
      ],
    }, item.source);
    return openReader(
      context,
      detail,
      chapter: Chapter(state.chapterId, state.title),
      startPage: start,
    );
  }

  static Future<void> openSourceSettings(BuildContext context, String source) => push(context, SourceSettingsPage(sourceKey: source));

  static Future<void> openNetworkSettings(BuildContext context) => push(context, const SettingsPage(initialSection: 'network'));

  /// Opens the site in the built-in browser so the user can pass a Cloudflare check.
  /// Returns true once the page loads normally and the cookies have been imported.
  static Future<bool> verifyCloudflare(BuildContext context, String source, {String? url}) async {
    final m = SourceManager.instance.manifest(source);
    final target = (url != null && url.startsWith('http')) ? url : (m?.origin ?? m?.homepage ?? '');
    if (target.isEmpty) return false;
    final ok = await push<bool>(context, WebVerifyPage.cloudflare(source: source, url: target));
    return ok == true;
  }

  static Future<void> random(BuildContext context, String source) async {
    final id = await guarded(context, source, () => SourceManager.instance.random(source));
    if (id != null && context.mounted) await openRef(context, source, id);
  }
}
