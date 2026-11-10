import 'dart:async';

import 'package:drift/drift.dart' show Variable;
import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../../core/models.dart';
import '../../engine/source_manager.dart';
import '../../subscriptions/subscription_store.dart';
import '../../subscriptions/update_navigation.dart';
import '../../subscriptions/update_store.dart';
import '../../subscriptions/updater.dart';
import '../detail/detail_page.dart';
import '../kit/kit.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets/error_view.dart';
import 'subscription_posts_page.dart';

class SubscriptionUpdatesPage extends StatefulWidget {
  const SubscriptionUpdatesPage({super.key});
  @override
  State<SubscriptionUpdatesPage> createState() =>
      _SubscriptionUpdatesPageState();
}

class _SubscriptionUpdatesPageState extends State<SubscriptionUpdatesPage> {
  List<SubscriptionEvent>? events;
  bool failed = false;
  bool _editing = false;
  bool _more = false, _loadingMore = false, _moreFailed = false;
  static const _pageSize = 100;
  int _loadGeneration = 0;
  final updater = SubscriptionUpdater.instance;
  @override
  void initState() {
    super.initState();
    updater.addListener(_changed);
    unawaited(_load());
  }

  @override
  void dispose() {
    updater.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (!updater.running) unawaited(_load());
    if (mounted) setState(() {});
  }

  Future<void> _load({bool more = false}) async {
    if (!mounted) return;
    if (more && (_loadingMore || !_more)) return;
    final generation = ++_loadGeneration;
    setState(() {
      _loadingMore = more;
      _moreFailed = false;
    });
    try {
      await SubscriptionStore.instance.load();
      final result = await UpdateStore(SubscriptionStore.instance.database)
          .events(after: more ? events?.lastOrNull : null, limit: _pageSize);
      if (mounted && generation == _loadGeneration) {
        setState(() {
          events = more ? [...?events, ...result] : result;
          _more = result.length == _pageSize;
          failed = false;
        });
      }
    } catch (_) {
      if (mounted && generation == _loadGeneration) {
        setState(() {
          if (more) {
            _moreFailed = true;
          } else {
            failed = true;
          }
        });
      }
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() => _loadingMore = false);
      }
    }
  }

  Future<void> _manage(String action, [SubscriptionEvent? event]) async {
    if (_editing) return;
    setState(() => _editing = true);
    try {
      if (action != 'read') {
        final confirmed = await confirmAction(
          context,
          title: tr(event == null ? '清空订阅更新' : '删除订阅更新'),
          message: tr('仅删除更新记录，保留订阅和已检查状态，不会重复推送已发现的内容。'),
          confirmLabel: tr(event == null ? '清空' : '删除'),
          destructive: true,
        );
        if (!confirmed || !mounted) return;
      }
      final store = UpdateStore(SubscriptionStore.instance.database);
      switch (action) {
        case 'read':
          await store.markAllRead();
        case 'delete':
          await store.remove(event!.key);
        case 'clear':
          await store.clear();
      }
      await _load();
    } catch (_) {
      if (mounted) context.toast(tr('操作失败，请重试'));
    } finally {
      if (mounted) setState(() => _editing = false);
    }
  }

  Future<void> _open(SubscriptionEvent event) async {
    if (_editing) return;
    setState(() => _editing = true);
    try {
      if (!mounted) return;
      if (event.route.kind == 'post') {
        final links = await SubscriptionStore.instance.database
            .customSelect(
              'SELECT identity FROM subscription_event_targets WHERE event_key=?',
              variables: [Variable(event.key)],
            )
            .get();
        final identities = {
          for (final row in links) row.read<String>('identity'),
        };
        final entries = SubscriptionStore.instance.items.where(
          (e) => identities.contains(e.identity),
        );
        if (!mounted) return;
        if (entries.isNotEmpty) {
          await Nav.push(
            context,
            SubscriptionPostsPage(
              entry: entries.first,
              initialPostId: event.route.id,
              onPostOpened: () =>
                  UpdateStore(SubscriptionStore.instance.database)
                      .markRead(event.key),
            ),
          );
        } else {
          context.toast(tr('内容不存在或已被删除'));
        }
      } else if (event.route.kind == 'chapter') {
        if (event.route.workId.isEmpty || event.route.chapterId.isEmpty) return;
        final detail = await guarded(
          context,
          event.source,
          () => SourceManager.instance.detail(event.source, event.route.workId),
        );
        if (!mounted) return;
        if (detail != null) {
          final chapter = findUpdateChapter(
            detail,
            workId: event.route.workId,
            chapterId: event.route.chapterId,
          );
          if (chapter != null) {
            await UpdateStore(SubscriptionStore.instance.database)
                .markRead(event.key);
            if (!mounted) return;
          }
          final kind = SourceManager.instance.kindOf(detail);
          if (chapter == null) {
            await Nav.push(
              context,
              DetailPage(
                source: event.source,
                id: event.route.workId,
                preview: detail,
              ),
            );
          } else if (kind.isPlayable) {
            await Nav.openVideo(context, detail, episodeId: chapter.id);
          } else if (kind == MediaKind.comic || kind == MediaKind.novel) {
            await Nav.openReader(context, detail, chapter: chapter);
          } else {
            await Nav.openWork(context, detail.toItem());
          }
        }
      } else {
        final detail = await guarded(
          context,
          event.source,
          () => SourceManager.instance.detail(
            event.source,
            event.route.workId.isEmpty ? event.route.id : event.route.workId,
          ),
        );
        if (!mounted || detail == null) return;
        await UpdateStore(SubscriptionStore.instance.database)
            .markRead(event.key);
        if (!mounted) return;
        await Nav.openWork(context, detail.toItem());
      }
      await _load();
    } catch (_) {
      if (mounted) context.toast(tr('操作失败，请重试'));
    } finally {
      if (mounted) setState(() => _editing = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(tr('订阅更新')),
      actions: [
        PopupMenuButton<String>(
          tooltip: tr('管理'),
          enabled: !_editing && events?.isNotEmpty == true,
          onSelected: _manage,
          itemBuilder: (context) => [
            PopupMenuItem(value: 'read', child: Text(tr('全部标为已读'))),
            PopupMenuItem(value: 'clear', child: Text(tr('清空订阅更新'))),
          ],
        ),
        IconButton(
          tooltip: tr('检查订阅更新'),
          onPressed: updater.running ? null : () => updater.run(force: true),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: Column(
      children: [
        if (updater.running) const LinearProgressIndicator(),
        if (updater.failures > 0)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Gap.page,
              vertical: Gap.m,
            ),
            child: Text(tr('部分订阅检查失败，请查看订阅状态')),
          ),
        Expanded(
          child: failed
              ? EmptyState(
                  icon: Icons.error_outline_rounded,
                  title: tr('加载失败'),
                  actions: [
                    OutlinedButton(onPressed: _load, child: Text(tr('重试'))),
                  ],
                )
              : events == null
              ? const Center(child: CircularProgressIndicator())
              : events!.isEmpty
              ? EmptyState(
                  icon: Icons.notifications_none_rounded,
                  title: tr('暂无订阅更新'),
                  actions: [
                    OutlinedButton.icon(
                      onPressed: updater.running
                          ? null
                          : () => updater.run(force: true),
                      icon: const Icon(Icons.refresh),
                      label: Text(tr('检查订阅更新')),
                    ),
                  ],
                )
              : ParkRefresh(
                  showRefreshButton: false,
                  onRefresh: () async {
                    await updater.run(force: true);
                    await _load();
                  },
                  child: ListView.builder(
                    itemCount: events!.length + (_more ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == events!.length) {
                        return Padding(
                          padding: const EdgeInsets.all(Gap.page),
                          child: _loadingMore
                              ? const Center(child: CircularProgressIndicator())
                              : OutlinedButton(
                                  onPressed: () => _load(more: true),
                                  child: Text(tr(_moreFailed ? '重试' : '加载更多')),
                                ),
                        );
                      }
                      final event = events![index];
                      return ListTile(
                        leading: Icon(
                          event.unread ? Icons.fiber_new : Icons.done,
                        ),
                        title: SelectionContainer.disabled(
                          child: Text(
                            event.title,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        subtitle: SelectionContainer.disabled(
                          child: Text(
                            '${SourceManager.instance[event.source]?.name ?? event.source} · ${MaterialLocalizations.of(context).formatShortDate(DateTime.fromMillisecondsSinceEpoch(event.createdAt))}',
                          ),
                        ),
                        trailing: IconButton(
                          tooltip: tr('删除订阅更新'),
                          onPressed: _editing
                              ? null
                              : () => _manage('delete', event),
                          icon: const Icon(Icons.delete_outline_rounded),
                        ),
                        onTap: _editing ? null : () => _open(event),
                      );
                    },
                  ),
                ),
        ),
      ],
    ),
  );
}
