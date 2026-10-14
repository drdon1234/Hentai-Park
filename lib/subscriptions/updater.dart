import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../core/localization.dart';
import '../core/models.dart';
import '../core/settings.dart';
import '../engine/platform_bridge.dart';
import '../engine/source_manager.dart';
import 'subscription_store.dart';
import 'update_store.dart';

typedef SubscriptionFetch = Future<Map<String, dynamic>> Function(
  SubscriptionEntry entry,
  String? cursor,
  CancelToken cancel,
);

class SubscriptionUpdater extends ChangeNotifier {
  SubscriptionUpdater({
    SubscriptionStore? store,
    SubscriptionFetch? fetch,
    int Function()? interval,
    Future<bool> Function(SubscriptionEvent)? deliver,
    Future<String> Function(SubscriptionEntry)? fingerprint,
  }) : store = store ?? SubscriptionStore.instance,
       fetch = fetch ?? _fetch,
       interval =
           interval ?? (() => AppSettings.instance.subscriptionUpdateHours),
       deliver = deliver ?? _deliver,
       fingerprint =
           fingerprint ??
           (fetch == null
               ? (e) async {
                   await SourceManager.instance.ready;
                   return SourceManager.instance.subscriptionContext(e.source);
                 }
               : (e) async => 'test');
  static final instance = SubscriptionUpdater();
  final SubscriptionStore store;
  final SubscriptionFetch fetch;
  final int Function() interval;
  final Future<bool> Function(SubscriptionEvent) deliver;
  final Future<String> Function(SubscriptionEntry) fingerprint;
  bool running = false;
  int failures = 0, checked = 0;
  Timer? _timer;
  bool cancelled = false;
  final _cancels = <CancelToken>{};
  void cancel() {
    cancelled = true;
    for (final token in _cancels) {
      token.cancel();
    }
  }

  void start() {
    _timer ??= Timer.periodic(
      const Duration(minutes: 1),
      (_) => unawaited(run()),
    );
    unawaited(run());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  static Future<Map<String, dynamic>> _fetch(
    SubscriptionEntry e,
    String? cursor,
    CancelToken cancel,
  ) async {
    final manager = SourceManager.instance;
    await manager.ready;
    if (manager[e.source]?.enabled != true ||
        manager.manifest(e.source)?.can('subscriptionUpdates') != true) {
      throw SourceError('UNSUPPORTED', '这个站点暂不支持更新订阅');
    }
    return manager.checkSubscription(
      e.source,
      e.dimension,
      e.target,
      cursor: cursor,
      cancelToken: cancel,
    );
  }

  static Future<bool> _deliver(SubscriptionEvent event) async {
    final settings = AppSettings.instance;
    if (!settings.subscriptionNotifications) return false;
    return PlatformBridge.notifyChecked(
      id: event.notificationId,
      title: tr('订阅内容有更新'),
      text: settings.subscriptionNotificationPreview
          ? event.title
          : tr('打开应用查看更新'),
      payload: 'subscriptions',
      channel: 'subscriptions',
      channelName: '订阅更新',
    );
  }

  Future<void> run({
    bool force = false,
    Duration budget = const Duration(minutes: 3),
  }) async {
    if (running || (!force && interval() == 0)) return;
    if (cancelled) return;
    running = true;
    failures = 0;
    checked = 0;
    notifyListeners();
    final deadline = DateTime.now().add(budget);
    try {
      await store.load();
      final updates = UpdateStore(store.database);
      // 同源串行，最多两源同时访问；后台与前台还共享数据库目标租约。
      final groups = <String, List<SubscriptionEntry>>{};
      for (final e in store.items.where((e) => e.enabled)) {
        groups.putIfAbsent(e.source, () => []).add(e);
      }
      final queue = groups.values.toList();
      var index = 0;
      Future<void> worker() async {
        while (!cancelled &&
            index < queue.length &&
            DateTime.now().isBefore(deadline)) {
          final group = queue[index++];
          for (final entry in group) {
            if (cancelled || DateTime.now().isAfter(deadline)) break;
            final lease = await updates.acquire(
              entry,
              now: DateTime.now().millisecondsSinceEpoch,
              force: force,
            );
            if (lease == null) continue;
            final cancel = CancelToken();
            _cancels.add(cancel);
            final timer = Timer(
              deadline.difference(DateTime.now()).isNegative
                  ? Duration.zero
                  : deadline.difference(DateTime.now()),
              () => cancel.cancel(),
            );
            try {
              final identity = await fingerprint(entry);
              await updates.ensureContext(entry, lease, identity);
              final state = await updates.state(entry);
              var cursor = state.cursor;
              final cursors = <String>{?cursor};
              final items = <UpdateItem>[];
              var complete = false;
              for (var page = 0; page < 3; page++) {
                final data = await fetch(entry, cursor, cancel);
                if (data['items'] is! List ||
                    data['hasNext'] is! bool ||
                    (data['items'] as List).length > 20000) {
                  throw const FormatException('订阅结果无效');
                }
                for (final item in data['items'] as List) {
                  if (item is! Map) throw const FormatException('订阅结果无效');
                  items.add(UpdateItem.parse(item));
                }
                // 搜索与动态跟踪最近三页的滚动窗口；章节目录必须完整，普通分页协议继续持久化续查。
                complete =
                    data['hasNext'] == false ||
                    (data['windowed'] == true && page == 2);
                if (complete) break;
                final next = data['cursor'];
                if (next is! String ||
                    next.isEmpty ||
                    next.length > 4096 ||
                    !cursors.add(next)) {
                  throw const FormatException('订阅分页无效');
                }
                cursor = next;
                await Future<void>.delayed(const Duration(milliseconds: 300));
              }
              if (identity != await fingerprint(entry)) {
                throw SourceError('CANCELLED', '账号或站点设置已改变，请重新检查');
              }
              if (cancelled || cancel.isCancelled) {
                throw SourceError('CANCELLED', '订阅检查已取消');
              }
              await updates.commit(
                entry,
                lease,
                items,
                now: DateTime.now().millisecondsSinceEpoch,
                complete: complete,
                cursor: cursor,
                intervalHours: interval() == 0 ? 6 : interval(),
              );
              checked++;
            } catch (error) {
              failures++;
              await updates.fail(
                entry,
                lease,
                now: DateTime.now().millisecondsSinceEpoch,
                code: error is FormatException
                    ? 'PARSE'
                    : error is SourceError
                    ? error.code
                    : cancel.isCancelled
                    ? 'CANCELLED'
                    : 'NETWORK',
              );
            } finally {
              timer.cancel();
              _cancels.remove(cancel);
            }
          }
        }
      }

      await Future.wait([worker(), worker()]);
      for (final event in await updates.events(
        pending: true,
        now: DateTime.now().millisecondsSinceEpoch,
      )) {
        if (cancelled) break;
        try {
          if (await deliver(event)) {
            await updates.delivered(event.key);
          } else {
            await updates.retryDelivery(
              event.key,
              DateTime.now().millisecondsSinceEpoch,
            );
          }
        } catch (_) {
          await updates.retryDelivery(
            event.key,
            DateTime.now().millisecondsSinceEpoch,
          );
        }
      }
    } catch (_) {
      // 数据库或配置读取失败也呈现失败状态，避免周期任务形成未处理异常。
      failures++;
    } finally {
      running = false;
      notifyListeners();
    }
  }
}
