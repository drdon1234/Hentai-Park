import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/models.dart';
import '../../core/settings.dart';
import '../../engine/home_cache.dart';
import '../../engine/home_metadata.dart';
import '../../engine/shared_feed.dart';
import '../../engine/source_manager.dart';
import '../../subscriptions/subscription_store.dart';

/// 由发现页持有；主页与所有分类页使用同一组默认推荐会话。
class FeedSessions {
  FeedSessions(this.sources, {SubscriptionStore? subscriptions})
    : _subscriptions = subscriptions ?? SubscriptionStore.instance {
    sources.addListener(_changed);
    _authentication = sources.authenticationChanges.listen((key) {
      if (_entries.containsKey(key)) _entry(key, refresh: true);
    });
    _settings.addListener(_changed);
    _subscriptions.addListener(_changed);
  }

  final SourceManager sources;
  final SubscriptionStore _subscriptions;
  final _entries = <String, _FeedEntry>{};
  late final StreamSubscription<String> _authentication;
  final Listenable _settings = AppSettings.instance.watch(const {
    'proxy',
    'dataSavingMode',
    'homeHiddenSources',
  });

  static Object? _canonical(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      return {for (final key in keys) key: _canonical(value[key])};
    }
    if (value is List) return value.map(_canonical).toList();
    return value;
  }

  _FeedEntry? _entry(String key, {bool refresh = false}) {
    if (AppSettings.instance.dataSaver ||
        sources[key]?.enabled == false ||
        !AppSettings.instance.homeSourceVisible(key)) {
      return null;
    }
    final manifest = sources.manifest(key);
    if (manifest == null ||
        (manifest.feeds.isEmpty && !manifest.can('subscription'))) {
      return null;
    }
    final feed = manifest.feeds.isEmpty
        ? null
        : manifest.feeds[sources.entryFeedIndex(key)];
    final options = feed?.defaultOptions() ?? const <String, Object?>{};
    final identity = jsonEncode(
      _canonical([
        manifest.json,
        sources[key]?.sha256,
        sources.settingsOf(key),
        AppSettings.instance.proxy,
        feed?.key,
        options,
        if (manifest.can('subscription')) _target(key)?.target,
      ]),
    );
    final existing = _entries[key];
    if (existing?.identity == identity && !refresh) return existing;
    var usingSubscriptionTarget = feed == null;
    var target = _target(key);
    Map<String, Object?>? albumScope() => usingSubscriptionTarget
        ? (target == null ? null : {'target': target!.target})
        : (feed == null ? null : {'feed': feed.key, 'options': options});
    Future<WorkPage?> posts(
      int page,
      String? cursor,
      CancelToken cancelToken,
    ) async {
      await _subscriptions.load();
      if (cancelToken.cancelError case final error?) throw error;
      target ??= _target(key);
      if (target == null) return null;
      return _posts(key, target!.target, page, cursor, cancelToken);
    }

    // 配置在创建时取快照，避免旧请求读取后续选项。
    Future<WorkPage> loadRemote(
      int page,
      String? cursor, {
      required bool refresh,
      required CancelToken cancelToken,
      void Function(WorkPage)? onCached,
    }) async {
      if (feed != null && !usingSubscriptionTarget) {
        try {
          return await sources.feed(
            key,
            feed.key,
            page: page,
            cursor: cursor,
            options: options,
            refresh: refresh,
            cancelToken: cancelToken,
            onCached: onCached,
          );
        } on SourceError catch (error) {
          if (!error.needsLogin || !manifest.can('subscription') || page != 1) {
            rethrow;
          }
          final result = await posts(page, cursor, cancelToken);
          usingSubscriptionTarget = result != null;
          if (result != null) return result;
          rethrow;
        }
      }
      return await posts(page, cursor, cancelToken) ??
          WorkPage(page: page, items: []);
    }

    Future<WorkPage> load(
      int page,
      String? cursor, {
      required bool refresh,
      required CancelToken cancelToken,
      void Function(WorkPage)? onCached,
    }) async {
      if (page != 1) {
        return loadRemote(
          page,
          cursor,
          refresh: refresh,
          cancelToken: cancelToken,
        );
      }
      // 推荐快照只使用稳定的入口身份；Cookie 的更新时间、插件临时数据不属于展示身份。
      final account = sources.accountListenable(key)?.value;
      final result = await HomeCache.instance.request(
        [
          'recommendations',
          key,
          sources[key]?.sha256,
          manifest.version,
          sources.settingsOf(key),
          feed?.key,
          options,
          target?.target,
          account?.loggedIn,
          account?.name,
        ],
        () async {
          final result = await loadRemote(
            page,
            cursor,
            refresh: true,
            cancelToken: cancelToken,
          );
          if (cancelToken.cancelError case final error?) throw error;
          return {
            'items': result.items.map((item) => item.toJson()).toList(),
            if (result.sections != null)
              'sections': [
                for (final section in result.sections!)
                  {
                    'title': section.title,
                    'items': section.items
                        .map((item) => item.toJson())
                        .toList(),
                  },
              ],
            'page': result.page,
            'cursor': result.cursor,
            'hasNext': result.hasNext,
          };
        },
        source: key,
        refresh: true,
        serialize: HomeMetadata.serialize,
        onCached:
            refresh ||
                (manifest.account?.required == true &&
                    account?.loggedIn != true)
            ? null
            : (data) {
                if (!cancelToken.isCancelled) {
                  onCached?.call(WorkPage.fromJson(data, key));
                }
              },
      );
      return WorkPage.fromJson(result.data, key);
    }

    if (existing != null) {
      existing.identity = identity;
      existing.albumScope = albumScope;
      existing.session.reset(loader: load);
      return existing;
    }
    return _entries[key] = _FeedEntry(
      identity,
      SharedFeedSession(load),
      albumScope,
    );
  }

  SharedFeedSession? session(String key) => _entry(key)?.session;

  Map<String, Object?>? albumScope(String key) {
    final manifest = sources.manifest(key);
    if (manifest == null || !manifest.can('album')) return null;
    return _entry(key)?.albumScope();
  }

  SubscriptionEntry? _target(String key) => _subscriptions.items
      .where((entry) => entry.source == key && entry.dimension == 'posts')
      .firstOrNull;

  Future<WorkPage?> _posts(
    String key,
    String target,
    int page,
    String? cursor,
    CancelToken cancelToken,
  ) async {
    final posts = await sources.subscriptionPosts(
      key,
      target,
      cursor: cursor,
      cancelToken: cancelToken,
    );
    return WorkPage(
      page: page,
      cursor: posts.cursor,
      hasNext: posts.hasNext,
      items: [
        for (final post in posts.items)
          WorkItem({
            ...post.json,
            'cover': post.media.firstOrNull?.preview ?? '',
            'coverBlurred': post.media.firstOrNull?.json['blurred'] == true,
            'mediaKind': post.media.firstOrNull?.type == 'video'
                ? 'video'
                : 'comic',
            'subtitle': post.text,
          }, key),
      ],
    );
  }

  void _changed() {
    if (AppSettings.instance.dataSaver) {
      _clear();
      return;
    }
    for (final key in _entries.keys.toList()) {
      if (_entry(key) == null) _entries[key]?.session.reset();
    }
  }

  void refreshAll() {
    for (final entry in _entries.values) {
      entry.session.reset();
    }
  }

  void dispose() {
    sources.removeListener(_changed);
    _settings.removeListener(_changed);
    _subscriptions.removeListener(_changed);
    unawaited(_authentication.cancel());
    _clear();
  }

  void _clear() {
    for (final entry in _entries.values) {
      entry.session.dispose();
    }
    _entries.clear();
  }
}

class _FeedEntry {
  _FeedEntry(this.identity, this.session, this.albumScope);
  String identity;
  final SharedFeedSession session;
  Map<String, Object?>? Function() albumScope;
}
