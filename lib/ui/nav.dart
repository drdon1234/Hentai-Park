import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/content_scope.dart';
import '../core/localization.dart';
import '../core/models.dart';
import '../engine/age_confirmation.dart';
import '../engine/challenge.dart';
import '../engine/cookie_store.dart';
import '../engine/domains.dart';
import '../engine/http_service.dart';
import '../engine/source_manager.dart';
import '../library/downloads.dart';
import '../library/playback_resolver.dart';
import 'detail/detail_page.dart';
import 'discovery_navigation.dart';
import 'novel/novel_reader_page.dart';
import 'reader/reader_page.dart';
import 'search/aggregate_search_page.dart';
import 'search/reverse_search_page.dart';
import 'search/source_link_search_page.dart';
import 'search/source_search_page.dart';
import 'settings/settings_sections.dart';
import 'settings/source_settings_page.dart';
import 'short_video/post_video_feed.dart';
import 'short_video/short_video_page.dart';
import 'short_video/short_video_sequence.dart';
import 'source/source_page.dart';
import 'subscriptions/subscription_posts_page.dart';
import 'theme.dart';
import 'video/video_page.dart';
import 'web/web_verify_page.dart';
import 'web/web_video_page.dart';
import 'widgets/content_translation.dart';
import 'widgets/error_view.dart';

/// Central navigation so every entry point (cards, tags, links, history…) behaves the same.
class Nav {
  static Future<void> openContentLink(
    BuildContext context,
    String source,
    String url, {
    SourceManager? sourceManager,
  }) async {
    final manager = sourceManager ?? SourceManager.instance;
    final link = await guarded(
      context,
      source,
      () => manager.resolveContentLink(source, url),
    );
    if (link == null || !context.mounted) return;
    if (link.type == 'work') {
      await openRef(context, link.source!, link.value, sourceManager: manager);
    } else if (link.type == 'search') {
      await push(
        context,
        SourceLinkSearchPage(
          source: link.source!,
          url: link.value,
          manager: manager,
        ),
      );
    } else {
      var opened = false;
      try {
        opened = await launchUrl(
          Uri.parse(link.value),
          mode: LaunchMode.externalApplication,
        );
      } catch (_) {}
      if (!opened && context.mounted) context.toast(tr('无法打开原站'));
    }
  }

  // 播放器只随页面切换暂停，菜单、对话框和底部弹层不打断播放。
  static final routeObserver = _AppRouteObserver();
  static final _accessVerifications = Expando<Map<String, Future<bool>>>();

  static Future<bool> _verifyAccess(
    BuildContext context,
    String source,
    String target,
  ) async {
    if (!context.mounted) return false;
    final manifest = SourceManager.instance.manifest(source);
    if (manifest == null) return false;
    try {
      CookieStore.instance.checkBrowserUri(Uri.parse(target), source);
    } catch (_) {
      return false;
    }
    final pendingKey = '$source\u0000$target';
    final sessions = _accessVerifications[Navigator.of(context)] ??= {};
    final pending = sessions[pendingKey];
    if (pending != null) return pending;
    final result = HttpService.instance
        .sourceRequest(
          {
            'url': target,
            'origin': manifest.origin,
            'mode': 'browser',
            'method': 'GET',
          },
          partition: source,
          domains: declaredDomains(manifest.json),
          confirmation: AgeConfirmationConfig.fromNetwork(manifest.network),
        )
        .then((response) {
          final status = response['status'];
          final headers = response['headers'] as Map? ?? const {};
          final body = response['body']?.toString() ?? '';
          return status is num &&
              status >= 200 &&
              status < 400 &&
              body.isNotEmpty &&
              headers['cf-mitigated'] != 'challenge' &&
              !hasChallengeMarkers(body);
        })
        .catchError((_) => false);
    sessions[pendingKey] = result;
    try {
      return await result;
    } finally {
      sessions.removeWhere(
        (key, value) => key == pendingKey && identical(value, result),
      );
    }
  }

  static bool _short(String source, [WorkItem? item]) {
    final manifest = SourceManager.instance.manifest(source);
    return manifest?.category == SourceCategory.shortvideo ||
        (item?.isSubscriptionPost == true &&
            item?.mediaKind == MediaKind.video &&
            (item?.json['media'] as List? ?? const []).any(
              isPostVideoAttachment,
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
    ShortVideoSequence? sequence,
  }) async {
    await _pushWork(context, item, coverHeroTag, sequence);
  }

  static Future<void> _pushWork(
    BuildContext context,
    WorkItem item,
    Object? coverHeroTag,
    ShortVideoSequence? sequence,
  ) => push(
    context,
    _short(item.source, item)
        ? ShortVideoPage(
            source: item.source,
            initial: item,
            sequence: sequence,
            feedIndex: _videoFeed(item.source),
            postScope:
                SourceManager.instance
                        .manifest(item.source)
                        ?.json['postShortVideos'] ==
                    true
                ? PostVideoContext.of(context)
                : null,
          )
        : item.isSubscriptionPost
        ? SubscriptionWorkPage(
            item: item,
            postScope: PostVideoContext.of(context),
          )
        : DetailPage(
            source: item.source,
            id: item.id,
            preview: item,
            coverHeroTag: coverHeroTag,
          ),
  );

  static Future<void> openRef(
    BuildContext context,
    String source,
    String id, {
    SourceManager? sourceManager,
  }) async {
    final manager = sourceManager ?? SourceManager.instance;
    final resolved = await guarded(
      context,
      source,
      () => manager.resolveLink(source, id),
    );
    if (resolved == null || !context.mounted) return;
    await push(
      context,
      _short(source)
          ? ShortVideoPage(source: source, initialId: resolved)
          : DetailPage(
              source: source,
              id: resolved,
              sourceManager: sourceManager,
            ),
    );
  }

  static Future<void> openSource(BuildContext context, String source) =>
      _openSource(context, source);

  static Future<void> _openSource(BuildContext context, String source) {
    SourceManager.instance.cancelBackgroundFeeds(source);
    if (SourceManager.instance.manifest(source)?.reverseSearchOnly == true) {
      return push(context, ReverseSearchPage(sourceKey: source));
    }
    return push(context, SourcePage(sourceKey: source));
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
    bool downloadedOnly = false,
  }) =>
      !downloadedOnly &&
          (work.isGame ||
              SourceManager.instance.manifest(work.source)?.isGame == true)
      ? openWork(context, work.toItem())
      : push(
          context,
          (!downloadedOnly &&
                      SourceManager.instance.manifest(work.source)?.isNovel ==
                          true) ||
                  DownloadManager.instance.task(work.uid)?.isNovel == true ||
                  work.isNovel
              ? NovelReaderPage(
                  work: work,
                  chapter: chapter,
                  startOffset: startPage,
                  downloadedOnly: downloadedOnly,
                )
              : ReaderPage(
                  work: work,
                  chapter: chapter,
                  startPage: startPage,
                  downloadedOnly: downloadedOnly,
                ),
        );

  /// [stored]: [work] was rebuilt from stored data, not loaded from the site.
  static Future<void> openVideo(
    BuildContext context,
    WorkDetail work, {
    String? episodeId,
    bool stored = false,
    bool downloadedOnly = false,
  }) => downloadedOnly
      ? push(
          context,
          VideoPage(work: work, episodeId: episodeId, downloadedOnly: true),
        )
      : SourceManager.instance.manifest(work.source)?.opensExternally == true
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
                  postScope:
                      SourceManager.instance
                              .manifest(work.source)
                              ?.json['postShortVideos'] ==
                          true
                      ? PostVideoContext.of(context)
                      : null,
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
    bool downloadedOnly = false,
  }) async {
    final target = await PlaybackResolver.resolve(
      item,
      chapterId,
      page: page,
      downloadedOnly: downloadedOnly,
    );
    if (!context.mounted) return;
    switch (target) {
      case OpenWorkPage():
        if (downloadedOnly) {
          context.toast(tr('未完成'));
          return;
        }
        return openWork(context, item);
      case PlayVideo(
        work: final work?,
        :final episodeId,
        :final downloadedOnly,
      ):
        return openVideo(
          context,
          work,
          episodeId: episodeId,
          stored: true,
          downloadedOnly: downloadedOnly,
        );
      case PlayVideo(:final episodeId):
        final detail = await guarded(
          context,
          item.source,
          () => SourceManager.instance.detail(item.source, item.id),
        );
        if (detail != null && context.mounted) {
          await openVideo(context, detail, episodeId: episodeId);
        }
      case ReadChapter(
        :final work,
        :final chapter,
        :final startPage,
        :final downloadedOnly,
      ):
        return openReader(
          context,
          work,
          chapter: chapter,
          startPage: startPage,
          downloadedOnly: downloadedOnly,
        );
    }
  }

  static Future<void> openSourceSettings(BuildContext context, String source) =>
      push(context, SourceSettingsPage(sourceKey: source));

  static Future<bool> confirm(
    BuildContext context,
    String source,
    SourceError error,
  ) async {
    final url = error.url;
    if (!context.mounted || url == null) return false;
    try {
      CookieStore.instance.checkBrowserUri(Uri.parse(url), source);
    } catch (_) {
      return false;
    }
    return await push<bool>(
          context,
          WebVerifyPage.confirmation(
            source: source,
            url: url,
            message: error.friendly,
          ),
        ) ==
        true;
  }

  static Future<bool> login(BuildContext context, String source) async {
    final manifest = SourceManager.instance.manifest(source);
    final account = manifest?.account;
    if (account == null) {
      try {
        final url = Uri.parse(manifest?.homepage ?? '');
        CookieStore.instance.checkBrowserUri(url, source);
        if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
          throw const FormatException();
        }
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(tr('无法打开链接'))));
        }
      }
      // 原站登录不代表应用已获得会话。
      return false;
    }
    if (account.loginUrl.isEmpty) {
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

  /// Runs Cloudflare and declared age-gate handling in the hidden same-origin browser.
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
    return _verifyAccess(context, source, target);
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

/// SnackBars are hosted above the Navigator, so they otherwise survive a page
/// transition even though the page that created them is gone.
class _AppRouteObserver extends RouteObserver<PageRoute<dynamic>> {
  void _clearSnackBar(Route<dynamic>? route) {
    final navigator = route?.navigator;
    if (navigator == null) return;
    ScaffoldMessenger.maybeOf(navigator.context)?.hideCurrentSnackBar();
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _clearSnackBar(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _clearSnackBar(previousRoute ?? route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    _clearSnackBar(newRoute ?? oldRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    _clearSnackBar(previousRoute ?? route);
  }
}
