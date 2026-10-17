import 'package:flutter/material.dart';

import '../core/content_scope.dart';
import '../core/models.dart';
import '../engine/cookie_store.dart';
import '../engine/source_manager.dart';
import '../library/downloads.dart';
import '../library/playback_resolver.dart';
import 'detail/detail_page.dart';
import 'discovery_navigation.dart';
import 'novel/novel_reader_page.dart';
import 'reader/reader_page.dart';
import 'search/aggregate_search_page.dart';
import 'search/reverse_search_page.dart';
import 'search/source_search_page.dart';
import 'settings/settings_sections.dart';
import 'settings/source_settings_page.dart';
import 'short_video/short_video_page.dart';
import 'source/source_page.dart';
import 'subscriptions/subscription_posts_page.dart';
import 'video/video_page.dart';
import 'web/web_verify_page.dart';
import 'web/web_video_page.dart';
import 'widgets/content_translation.dart';
import 'widgets/error_view.dart';

/// Central navigation so every entry point (cards, tags, links, history…) behaves the same.
class Nav {
  static final routeObserver = RouteObserver<ModalRoute<dynamic>>();
  static bool _short(String source, [WorkItem? item]) {
    final manifest = SourceManager.instance.manifest(source);
    return manifest?.category == SourceCategory.shortvideo ||
        (item?.isSubscriptionPost == true &&
            item?.mediaKind == MediaKind.video &&
            (item?.json['media'] as List? ?? const []).any(
              (media) =>
                  media is Map &&
                  media['type'] == 'video' &&
                  (media['url'] as String? ?? '').isNotEmpty,
            ));
  }

  static int? _videoFeed(String source) {
    final manifest = SourceManager.instance.manifest(source);
    if (manifest?.isVideo != true) return null;
    final index = manifest!.feeds.indexWhere((feed) => feed.key == 'videos');
    return index < 0 ? null : index;
  }

  static Future<T?> push<T>(BuildContext context, Widget page) {
    final discovery = DiscoveryNavigation.of(context);
    return Navigator.of(context).push<T>(
      MaterialPageRoute(
        builder: (_) => TranslationPage(
          child: discovery == null
              ? page
              : DiscoveryNavigation(onSelect: discovery.onSelect, child: page),
        ),
      ),
    );
  }

  static Future<void> openWork(
    BuildContext context,
    WorkItem item, {
    Object? coverHeroTag,
  }) async {
    await _pushWork(context, item, coverHeroTag);
  }

  static Future<void> _pushWork(
    BuildContext context,
    WorkItem item,
    Object? coverHeroTag,
  ) => push(
    context,
    _short(item.source, item)
        ? ShortVideoPage(
            source: item.source,
            initial: item,
            feedIndex: _videoFeed(item.source),
          )
        : item.isSubscriptionPost
        ? SubscriptionWorkPage(item: item)
        : DetailPage(
            source: item.source,
            id: item.id,
            preview: item,
            coverHeroTag: coverHeroTag,
          ),
  );

  static Future<void> openRef(BuildContext context, String source, String id) =>
      push(
        context,
        _short(source)
            ? ShortVideoPage(source: source, initialId: id)
            : DetailPage(source: source, id: id),
      );

  static Future<void> openSource(BuildContext context, String source) =>
      _openSource(context, source);

  static Future<void> _openSource(BuildContext context, String source) {
    SourceManager.instance.cancelBackgroundFeeds(source);
    if (SourceManager.instance.manifest(source)?.reverseSearchOnly == true) {
      return push(context, ReverseSearchPage(sourceKey: source));
    }
    return push(context, SourcePage(sourceKey: source));
  }

  static Future<bool> confirmAccess(
    BuildContext context,
    String source, {
    String? url,
  }) async {
    final target = url ?? SourceManager.instance.manifest(source)?.homepage;
    if (target == null) return false;
    try {
      CookieStore.instance.checkBrowserUri(Uri.parse(target), source);
    } catch (_) {
      return false;
    }
    final ok =
        await push<bool>(
          context,
          WebVerifyPage.confirmation(source: source, url: target),
        ) ==
        true;
    return ok;
  }

  static Future<void> openSourceSearch(
    BuildContext context,
    String source, {
    String keyword = '',
    Map<String, Object?>? filters,
  }) => push(
    context,
    SourceSearchPage(
      sourceKey: source,
      initialKeyword: keyword,
      initialFilters: filters,
    ),
  );

  static Future<void> openAggregateSearch(
    BuildContext context, {
    String keyword = '',
    ContentScope scope = const ContentScope.all(),
  }) =>
      push(context, AggregateSearchPage(initialKeyword: keyword, scope: scope));

  static Future<void> openReader(
    BuildContext context,
    WorkDetail work, {
    Chapter? chapter,
    int startPage = 0,
  }) =>
      work.isGame ||
          SourceManager.instance.manifest(work.source)?.isGame == true
      ? openWork(context, work.toItem())
      : push(
          context,
          SourceManager.instance.manifest(work.source)?.isNovel == true ||
                  DownloadManager.instance.task(work.uid)?.isNovel == true ||
                  work.isNovel
              ? NovelReaderPage(
                  work: work,
                  chapter: chapter,
                  startOffset: startPage,
                )
              : ReaderPage(work: work, chapter: chapter, startPage: startPage),
        );

  /// [stored]: [work] was rebuilt from stored data, not loaded from the site.
  static Future<void> openVideo(
    BuildContext context,
    WorkDetail work, {
    String? episodeId,
    bool stored = false,
  }) => SourceManager.instance.manifest(work.source)?.opensExternally == true
      ? openWork(context, work.toItem())
      : push(
          context,
          SourceManager.instance.manifest(work.source)?.usesWebVideo == true
              ? WebVideoPage(work: work, episodeId: episodeId)
              : _short(work.source, work)
              ? ShortVideoPage(
                  source: work.source,
                  initial: work.toItem(),
                  feedIndex: _videoFeed(work.source),
                )
              : VideoPage(
                  work: work,
                  episodeId: episodeId,
                  fetchDetails: stored && work.source != localSource,
                ),
        );

  /// Opens the reader or player at [chapterId] from a stored chapter list.
  static Future<void> openChapter(
    BuildContext context,
    WorkItem item,
    String? chapterId, {
    int? page,
  }) async {
    final target = await PlaybackResolver.resolve(item, chapterId, page: page);
    if (!context.mounted) return;
    switch (target) {
      case OpenWorkPage():
        return openWork(context, item);
      case PlayVideo(work: final work?, :final episodeId):
        return openVideo(context, work, episodeId: episodeId, stored: true);
      case PlayVideo(:final episodeId):
        final detail = await guarded(
          context,
          item.source,
          () => SourceManager.instance.detail(item.source, item.id),
        );
        if (detail != null && context.mounted) {
          await openVideo(context, detail, episodeId: episodeId);
        }
      case ReadChapter(:final work, :final chapter, :final startPage):
        return openReader(
          context,
          work,
          chapter: chapter,
          startPage: startPage,
        );
    }
  }

  static Future<void> openSourceSettings(BuildContext context, String source) =>
      push(context, SourceSettingsPage(sourceKey: source));

  static Future<bool> login(BuildContext context, String source) async {
    final account = SourceManager.instance.manifest(source)?.account;
    if (account == null || account.loginUrl.isEmpty) {
      await openSourceSettings(context, source);
      return SourceManager.instance[source]?.account?.loggedIn == true;
    }
    return await push<bool>(
          context,
          WebVerifyPage.login(source: source, url: account.loginUrl),
        ) ==
        true;
  }

  static Future<void> openNetworkSettings(BuildContext context) =>
      push(context, const SettingsSectionPage(SettingsSection.network));

  /// Opens the site in the built-in browser so the user can pass a Cloudflare check.
  /// Returns true once the page loads normally and the cookies have been imported.
  static Future<bool> verifyCloudflare(
    BuildContext context,
    String source, {
    String? url,
  }) async {
    final m = SourceManager.instance.manifest(source);
    final target = (url != null && url.startsWith('http'))
        ? url
        : (m?.origin ?? m?.homepage ?? '');
    if (target.isEmpty) return false;
    try {
      CookieStore.instance.checkBrowserUri(Uri.parse(target), source);
    } catch (_) {
      return false;
    }
    final ok = await push<bool>(
      context,
      WebVerifyPage.cloudflare(source: source, url: target),
    );
    return ok == true;
  }

  static Future<void> random(BuildContext context, String source) async {
    final id = await guarded(
      context,
      source,
      () => SourceManager.instance.random(source),
    );
    if (id != null && context.mounted) await openRef(context, source, id);
  }
}
