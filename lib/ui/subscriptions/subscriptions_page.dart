import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../../core/settings.dart';
import '../../engine/platform_bridge.dart';
import '../../engine/source_manager.dart';
import '../../subscriptions/subscription_store.dart';
import '../../subscriptions/update_store.dart';
import '../../subscriptions/updater.dart';
import '../nav.dart';
import '../settings/source_manage_page.dart';
import '../settings/source_settings_page.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'subscription_posts_page.dart';
import 'subscription_updates_page.dart';

class SubscriptionsPage extends StatefulWidget {
  const SubscriptionsPage({super.key, this.embedded = false});
  final bool embedded;
  @override
  State<SubscriptionsPage> createState() => _SubscriptionsPageState();
}

class _SubscriptionsPageState extends State<SubscriptionsPage> {
  final store = SubscriptionStore.instance;
  final manager = SourceManager.instance;
  Object? error;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => error = null);
    try {
      await store.load();
    } catch (e) {
      if (mounted) setState(() => error = e);
    }
  }

  Future<void> _add() async {
    final providers = manager.enabled
        .where((s) => s.manifest!.can('subscriptionUpdates'))
        .toList();
    if (providers.isEmpty) {
      await Nav.push(context, const SourceManagePage());
      return;
    }
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SubscriptionDialog(providers: providers),
    );
    if (saved == true) {
      unawaited(SubscriptionUpdater.instance.run(force: true));
    }
  }

  Future<void> _edit(SubscriptionEntry entry) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SubscriptionDialog(providers: const [], entry: entry),
    );
    if (saved == true) {
      unawaited(SubscriptionUpdater.instance.run(force: true));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        store,
        manager,
        SubscriptionUpdater.instance,
      ]),
      builder: (context, _) => Scaffold(
        appBar: widget.embedded
            ? null
            : AppBar(
                title: Text(tr('订阅')),
                actions: [
                  IconButton(
                    tooltip: tr('站点管理'),
                    onPressed: () =>
                        Nav.push(context, const SourceManagePage()),
                    icon: const Icon(Icons.tune),
                  ),
                ],
              ),
        floatingActionButton: store.loaded
            ? FloatingActionButton.extended(
                onPressed: _add,
                icon: const Icon(Icons.add),
                label: Text(tr('添加订阅')),
              )
            : null,
        body: error != null
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(tr('订阅记录读取失败')),
                    TextButton(onPressed: _load, child: Text(tr('重试'))),
                  ],
                ),
              )
            : !store.loaded
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                children: [
                  ListTile(
                    title: Text(tr('订阅更新')),
                    leading: const Icon(Icons.notifications_outlined),
                    onTap: () =>
                        Nav.push(context, const SubscriptionUpdatesPage()),
                  ),
                  ListTile(
                    title: Text(tr('自动检查订阅')),
                    subtitle: DropdownButton<int>(
                      isExpanded: true,
                      value: AppSettings.instance.subscriptionUpdateHours,
                      items: [
                        for (final hours in [0, 1, 3, 6, 12, 24])
                          DropdownMenuItem(
                            value: hours,
                            child: Text(
                              hours == 0
                                  ? tr('关闭')
                                  : tr('每 {hours} 小时', {'hours': hours}),
                            ),
                          ),
                      ],
                      onChanged: (value) {
                        AppSettings.instance.subscriptionUpdateHours =
                            value ?? 6;
                        setState(() {});
                      },
                    ),
                  ),
                  SwitchListTile(
                    title: Text(tr('订阅系统通知')),
                    value: AppSettings.instance.subscriptionNotifications,
                    onChanged: (value) async {
                      if (value) {
                        await PlatformBridge.requestNotificationPermission();
                      }
                      AppSettings.instance.subscriptionNotifications = value;
                      if (mounted) setState(() {});
                    },
                  ),
                  if (AppSettings.instance.subscriptionNotifications)
                    SwitchListTile(
                      title: Text(tr('通知中显示内容标题')),
                      subtitle: Text(tr('关闭时仅提示有更新')),
                      value:
                          AppSettings.instance.subscriptionNotificationPreview,
                      onChanged: (value) {
                        AppSettings.instance.subscriptionNotificationPreview =
                            value;
                        setState(() {});
                      },
                    ),
                  TextButton.icon(
                    onPressed: SubscriptionUpdater.instance.running
                        ? null
                        : () => SubscriptionUpdater.instance.run(force: true),
                    icon: SubscriptionUpdater.instance.running
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                    label: Text(tr('检查订阅更新')),
                  ),
                  Text(
                    tr('无需登录即可保存订阅；媒体访问取决于原站权限。'),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  if (store.items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 48),
                      child: Center(child: Text(tr('还没有订阅'))),
                    ),
                  for (final entry in store.items)
                    Card(
                      child: ListTile(
                        title: Text(entry.label),
                        subtitle: Text(
                          '${manager.manifest(entry.source)?.name ?? entry.source} · ${entry.label}\n${tr(entry.enabled ? '检查已开启' : '检查已暂停')}',
                        ),
                        isThreeLine: true,
                        onTap: () => entry.dimension == 'posts'
                            ? Nav.push(
                                context,
                                SubscriptionPostsPage(entry: entry),
                              )
                            : entry.dimension == 'work'
                            ? Nav.openRef(context, entry.source, entry.target)
                            : Nav.push(
                                context,
                                const SubscriptionUpdatesPage(),
                              ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (action) async {
                            try {
                              if (action == 'edit') {
                                await _edit(entry);
                              } else if (action == 'status') {
                                final state = await UpdateStore(store.database)
                                    .state(entry);
                                if (!context.mounted) return;
                                await showDialog<void>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: Text(tr('订阅状态')),
                                    content: Text(
                                      '${tr(state.baseline ? '基线已建立' : '正在建立首次基线')}\n${state.error.isEmpty ? tr('检查正常') : tr('检查失败：{code}', {'code': state.error})}\n${state.lastSuccess == 0 ? '' : DateTime.fromMillisecondsSinceEpoch(state.lastSuccess).toLocal()}',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: Text(tr('关闭')),
                                      ),
                                    ],
                                  ),
                                );
                              } else if (action == 'pause' ||
                                  action == 'notify') {
                                await store.add(
                                  source: entry.source,
                                  target: entry.target,
                                  label: entry.label,
                                  dimension: entry.dimension,
                                  enabled: action == 'pause'
                                      ? !entry.enabled
                                      : entry.enabled,
                                  notify: action == 'notify'
                                      ? !entry.notify
                                      : entry.notify,
                                );
                              } else if (action == 'login') {
                                await Nav.push(
                                  context,
                                  SourceSettingsPage(sourceKey: entry.source),
                                );
                              } else if (action == 'remove') {
                                final ok = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: Text(tr('移除订阅')),
                                    content: Text(entry.label),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, false),
                                        child: Text(tr('取消')),
                                      ),
                                      FilledButton(
                                        onPressed: () =>
                                            Navigator.pop(context, true),
                                        child: Text(tr('移除')),
                                      ),
                                    ],
                                  ),
                                );
                                if (ok == true) {
                                  try {
                                    await store.remove(
                                      entry.source,
                                      entry.target,
                                      dimension: entry.dimension,
                                    );
                                  } catch (_) {
                                    if (context.mounted) {
                                      context.toast(tr('订阅保存失败，请重试'));
                                    }
                                  }
                                }
                              }
                            } catch (_) {
                              if (context.mounted) {
                                context.toast(tr('订阅保存失败，请重试'));
                              }
                            }
                          },
                          itemBuilder: (_) => [
                            PopupMenuItem(
                              value: 'edit',
                              child: Text(tr('编辑订阅')),
                            ),
                            PopupMenuItem(
                              value: 'status',
                              child: Text(tr('订阅状态')),
                            ),
                            PopupMenuItem(
                              value: 'pause',
                              child: Text(tr(entry.enabled ? '暂停检查' : '恢复检查')),
                            ),
                            PopupMenuItem(
                              value: 'notify',
                              child: Text(
                                tr(entry.notify ? '关闭此订阅通知' : '开启此订阅通知'),
                              ),
                            ),
                            PopupMenuItem(
                              value: 'login',
                              child: Text(tr('账号与站点设置')),
                            ),
                            PopupMenuItem(
                              value: 'remove',
                              child: Text(tr('移除订阅')),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _SubscriptionDialog extends StatefulWidget {
  const _SubscriptionDialog({required this.providers, this.entry});
  final List<InstalledSource> providers;
  final SubscriptionEntry? entry;
  @override
  State<_SubscriptionDialog> createState() => _SubscriptionDialogState();
}

class _SubscriptionDialogState extends State<_SubscriptionDialog> {
  late String source = widget.entry?.source ?? widget.providers.first.key;
  late String dimension =
      widget.entry?.dimension ?? dimensions.first['key'].toString();
  List<Map> get dimensions =>
      ((SourceManager.instance.manifest(source)?.json['updateSubscriptions']
                      as Map?)?['dimensions']
                  as List? ??
              [])
          .whereType<Map>()
          .toList();
  late final target = TextEditingController(text: widget.entry?.target);
  late final label = TextEditingController(text: widget.entry?.label);
  bool busy = false;
  String? failure;
  @override
  void dispose() {
    target.dispose();
    label.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      busy = true;
      failure = null;
    });
    try {
      final original = widget.entry;
      var id = target.text.trim();
      var name = label.text.trim();
      if (original == null || id != original.target) {
        final t = await SourceManager.instance.normalizeSubscription(
          source,
          id,
          dimension: dimension,
        );
        id = t.id;
        if (name.isEmpty) name = t.label;
      }
      if (original == null) {
        await SubscriptionStore.instance.add(
          source: source,
          target: id,
          label: name,
          dimension: dimension,
        );
      } else {
        await SubscriptionStore.instance.edit(
          original,
          target: id,
          label: name,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(
          () => failure = e is FormatException
              ? e.message
              : e.asSourceError.code != 'UNKNOWN'
              ? e.asSourceError.message
              : tr('订阅保存失败，请重试'),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _choose() async {
    setState(() {
      busy = true;
      failure = null;
    });
    try {
      final targets = await SourceManager.instance.subscriptionTargets(source);
      if (!mounted) return;
      final chosen = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: Text(tr('选择已加入的频道')),
          children: [
            for (final t in targets)
              SimpleDialogOption(
                onPressed: () {
                  label.text = t.label;
                  Navigator.pop(context, t.id);
                },
                child: Text(t.label),
              ),
          ],
        ),
      );
      if (chosen != null) target.text = chosen;
    } catch (e) {
      if (mounted) setState(() => failure = e.asSourceError.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final manager = SourceManager.instance;
    final manifest = manager.manifest(source);
    final account = manager[source]?.account;
    return PopScope(
      canPop: !busy,
      child: AlertDialog(
        title: Text(tr(widget.entry == null ? '添加订阅' : '编辑订阅')),
        content: SingleChildScrollView(
          child: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.entry != null)
                  Text(manifest?.name ?? source)
                else
                  DropdownButtonFormField<String>(
                    initialValue: source,
                    isExpanded: true,
                    items: [
                      for (final p in widget.providers)
                        DropdownMenuItem(
                          value: p.key,
                          child: Text(p.name, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: busy
                        ? null
                        : (value) => setState(() {
                            source = value!;
                            dimension = dimensions.first['key'].toString();
                            target.clear();
                            label.clear();
                            failure = null;
                          }),
                    decoration: InputDecoration(labelText: tr('订阅站点')),
                  ),
                const SizedBox(height: 12),
                if (widget.entry == null)
                  DropdownButtonFormField<String>(
                    key: ValueKey(source),
                    initialValue: dimension,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: tr('订阅维度')),
                    items: [
                      for (final d in dimensions.where(
                        (d) => d['key'] != 'filter',
                      ))
                        DropdownMenuItem(
                          value: d['key'].toString(),
                          child: Text(tr(d['label'].toString())),
                        ),
                    ],
                    onChanged: busy
                        ? null
                        : (value) => setState(() {
                            dimension = value!;
                            target.clear();
                            failure = null;
                          }),
                  ),
                const SizedBox(height: 12),
                Text(
                  tr(
                    (manifest?.json['subscription'] as Map?)?['hint']
                            ?.toString() ??
                        '无需登录即可保存订阅；媒体访问取决于原站权限。',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: target,
                  enabled: !busy,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: tr(
                      dimensions
                              .where((d) => d['key'] == dimension)
                              .firstOrNull?['hint']
                              ?.toString() ??
                          '订阅目标',
                    ),
                    hintText: manifest?.idExample,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: label,
                  enabled: !busy,
                  decoration: InputDecoration(labelText: tr('备注名称（可选）')),
                ),
                if (dimension == 'posts' &&
                    account?.loggedIn == true &&
                    manifest?.json['subscription'] is Map &&
                    manifest!.json['subscription']['joinedTargets'] == true)
                  TextButton(
                    onPressed: busy ? null : _choose,
                    child: Text(tr('选择已加入的频道')),
                  ),
                if (manifest?.account != null)
                  TextButton.icon(
                    onPressed: busy
                        ? null
                        : () async {
                            await Nav.push(
                              context,
                              SourceSettingsPage(sourceKey: source),
                            );
                            if (mounted) setState(() {});
                          },
                    icon: const Icon(Icons.login),
                    label: Text(
                      tr(account?.loggedIn == true ? '账号与站点设置' : '登录（可选）'),
                    ),
                  ),
                if (failure != null)
                  Text(
                    tr(failure!),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(context),
            child: Text(tr('取消')),
          ),
          FilledButton(
            onPressed: busy ? null : _save,
            child: busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(tr('保存订阅')),
          ),
        ],
      ),
    );
  }
}
