import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../../engine/source_manager.dart';
import '../../subscriptions/subscription_store.dart';
import '../nav.dart';
import '../widgets/common.dart';
import '../widgets/error_view.dart';
import '../widgets/source_account_strip.dart';
import 'subscription_posts_page.dart';

/// 无公共首页的站点仍可直接访问公开频道或作者，无需先保存订阅。
class SubscriptionSourcePage extends StatefulWidget {
  const SubscriptionSourcePage({super.key, required this.source});
  final String source;
  @override
  State<SubscriptionSourcePage> createState() => _SubscriptionSourcePageState();
}

class _SubscriptionSourcePageState extends State<SubscriptionSourcePage> {
  final _target = TextEditingController();
  bool _busy = false;
  Object? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      await SubscriptionStore.instance.load();
      if (mounted) setState(() => _error = null);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  void dispose() {
    _target.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    if (_busy || _target.text.trim().isEmpty) return;
    setState(() => _busy = true);
    final target = await guarded(
      context,
      widget.source,
      () => SourceManager.instance.normalizeSubscription(
        widget.source,
        _target.text.trim(),
      ),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (target != null) {
      await Nav.push(
        context,
        SubscriptionPostsPage(
          entry: SubscriptionEntry(
            source: widget.source,
            target: target.id,
            label: target.label,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final manifest = SourceManager.instance.manifest(widget.source)!;
    final hint = (manifest.json['subscription'] as Map?)?['hint']?.toString();
    return Scaffold(
      appBar: AppBar(
        bottom: manifest.account != null
            ? PreferredSize(
                preferredSize: Size.fromHeight(
                  SourceAccountStrip.height(context),
                ),
                child: SourceAccountStrip(source: widget.source),
              )
            : null,
        title: Text(manifest.name),
        actions: [
          IconButton(
            tooltip: tr('站点设置'),
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Nav.openSourceSettings(context, widget.source),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: SubscriptionStore.instance,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(Gap.page),
          children: [
            if (_error != null)
              SourceErrorView(
                error: _error!,
                source: widget.source,
                onRetry: _load,
              ),
            Text(tr('访问频道或作者')),
            const SizedBox(height: Gap.m),
            if (hint != null) Text(manifest.copy.text(hint)),
            const SizedBox(height: Gap.m),
            TextField(
              controller: _target,
              enabled: !_busy,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: tr('订阅目标'),
                hintText: manifest.idExample,
              ),
              onSubmitted: (_) => _open(),
            ),
            const SizedBox(height: Gap.m),
            OutlinedButton(
              onPressed: _busy ? null : _open,
              child: Text(tr(_busy ? '加载中' : '打开')),
            ),
            const SizedBox(height: Gap.l),
            for (final entry in SubscriptionStore.instance.items.where(
              (e) => e.source == widget.source && e.dimension == 'posts',
            ))
              ListTile(
                title: Text(entry.label),
                trailing: const Icon(Icons.chevron_right),
                onTap: () =>
                    Nav.push(context, SubscriptionPostsPage(entry: entry)),
              ),
          ],
        ),
      ),
    );
  }
}
