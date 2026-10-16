import 'dart:async';

import 'package:drift/drift.dart' show Variable;
import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../../engine/source_manager.dart';
import '../../subscriptions/subscription_store.dart';
import '../../subscriptions/update_store.dart';
import '../../subscriptions/updater.dart';
import '../kit/kit.dart';
import '../nav.dart';
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

  Future<void> _load() async {
    try {
      await SubscriptionStore.instance.load();
      final result = await UpdateStore(SubscriptionStore.instance.database)
          .events();
      if (mounted) {
        setState(() {
          events = result;
          failed = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => failed = true);
    }
  }

  Future<void> _open(SubscriptionEvent event) async {
    await UpdateStore(SubscriptionStore.instance.database).markRead(event.key);
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
        await Nav.push(context, SubscriptionPostsPage(entry: entries.first));
      }
    } else {
      await Nav.openRef(context, event.source, event.route.workId);
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(tr('订阅更新')),
      actions: [
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
            padding: const EdgeInsets.all(12),
            child: Text(tr('部分订阅检查失败，请查看订阅状态')),
          ),
        Expanded(
          child: failed
              ? Center(
                  child: TextButton(
                    onPressed: _load,
                    child: SelectionContainer.disabled(child: Text(tr('重试'))),
                  ),
                )
              : events == null
              ? const Center(child: CircularProgressIndicator())
              : events!.isEmpty
              ? Center(child: Text(tr('暂无订阅更新')))
              : ParkRefresh(
                  onRefresh: () async {
                    await updater.run(force: true);
                    await _load();
                  },
                  child: ListView.builder(
                    itemCount: events!.length,
                    itemBuilder: (context, index) {
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
                        onTap: () => _open(event),
                      );
                    },
                  ),
                ),
        ),
      ],
    ),
  );
}
