import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../../core/models.dart';
import '../../engine/source_manager.dart';
import '../nav.dart';
import '../subscriptions/subscription_source_page.dart';
import 'common.dart';
import 'source_network_hint.dart';

/// Error state for access failures that could not be resolved in the hidden browser.
class SourceErrorView extends StatelessWidget {
  const SourceErrorView({
    super.key,
    required this.error,
    required this.source,
    required this.onRetry,
    this.compact = false,
  });
  final Object error;
  final String source;
  final VoidCallback onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final e = error.asSourceError;
    final (icon, title) = switch (e.code) {
      'CLOUDFLARE' => (Icons.verified_user_outlined, tr('站点验证暂未完成')),
      'CONFIRM_REQUIRED' => (Icons.verified_user_outlined, tr('站点验证暂未完成')),
      'LOGIN_REQUIRED' => (Icons.lock_outline_rounded, tr('需要登录')),
      'BLOCKED' => (Icons.block_rounded, tr('访问受限')),
      'NOT_FOUND' => (Icons.search_off_rounded, tr('内容不存在')),
      'NETWORK' => (Icons.wifi_off_rounded, tr('网络连接失败')),
      _ => (Icons.error_outline_rounded, tr('加载失败')),
    };
    final canLogin =
        e.needsLogin ||
        (e.code == 'BLOCKED' &&
            SourceManager.instance.manifest(source)?.account != null);
    final actions = <Widget>[
      if ((e.isCloudflare || e.needsConfirmation) && e.url != null)
        FilledButton.icon(
          icon: const Icon(Icons.verified_user_outlined),
          label: Text(tr('去确认')),
          onPressed: () async {
            if (await Nav.confirm(context, source, e) && context.mounted) {
              onRetry();
            }
          },
        ),
      if (canLogin)
        FilledButton.icon(
          icon: const Icon(Icons.login_rounded),
          label: SelectionContainer.disabled(
            child: Text(
              tr(
                SourceManager.instance.manifest(source)?.account == null
                    ? '在原站登录'
                    : '去登录',
              ),
            ),
          ),
          onPressed: () async {
            if (await Nav.login(context, source) && context.mounted) onRetry();
          },
        ),
      if (canLogin)
        OutlinedButton(
          onPressed: onRetry,
          child: SelectionContainer.disabled(child: Text(tr('重试'))),
        )
      else
        FilledButton.tonalIcon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: SelectionContainer.disabled(child: Text(tr('重试'))),
        ),
      if (e.needsLogin &&
          SourceManager.instance.manifest(source)?.can('subscription') == true)
        TextButton(
          onPressed: () =>
              Nav.push(context, SubscriptionSourcePage(source: source)),
          child: SelectionContainer.disabled(child: Text(tr('访问频道或作者'))),
        ),
      if (e.isNetwork)
        TextButton(
          onPressed: () => Nav.openNetworkSettings(context),
          child: SelectionContainer.disabled(child: Text(tr('网络设置'))),
        ),
    ];
    final view = EmptyState(
      icon: icon,
      title: title,
      message: e.isCloudflare || e.needsConfirmation ? e.friendly : e.message,
      actions: actions,
      compact: compact,
    );
    final content =
        e.isNetwork &&
            SourceManager.instance.manifest(source)?.network['vpnHint'] == true
        ? Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [view, const NetworkAccessHint(showSettings: false)],
          )
        : view;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: constraints.hasBoundedHeight ? constraints.maxHeight : 0,
          ),
          child: content,
        ),
      ),
    );
  }
}

/// Runs [action] and reports unresolved access failures in the app, returning null on failure.
Future<T?> guarded<T>(
  BuildContext context,
  String source,
  Future<T> Function() action,
) async {
  while (context.mounted) {
    try {
      return await action();
    } on SourceError catch (e) {
      if (!context.mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.friendly),
          action: e.needsLogin
              ? SnackBarAction(
                  label: tr(
                    SourceManager.instance.manifest(source)?.account == null
                        ? '在原站登录'
                        : '去登录',
                  ),
                  onPressed: () => Nav.login(context, source),
                )
              : (e.isCloudflare || e.needsConfirmation) && e.url != null
              ? SnackBarAction(
                  label: tr('去确认'),
                  onPressed: () => Nav.confirm(context, source, e),
                )
              : null,
        ),
      );
      return null;
    }
  }
  return null;
}
