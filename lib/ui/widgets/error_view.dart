import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../nav.dart';
import 'common.dart';

/// Error state that offers the action that actually fixes the problem:
/// Cloudflare → verify in the built-in browser, login required → account page, otherwise retry.
class SourceErrorView extends StatelessWidget {
  const SourceErrorView({super.key, required this.error, required this.source, required this.onRetry, this.compact = false});
  final Object error;
  final String source;
  final VoidCallback onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final e = error.asSourceError;
    final (icon, title) = switch (e.code) {
      'CLOUDFLARE' => (Icons.verified_user_outlined, '需要通过人机验证'),
      'LOGIN_REQUIRED' => (Icons.lock_outline_rounded, '需要登录'),
      'BLOCKED' => (Icons.block_rounded, '访问受限'),
      'NOT_FOUND' => (Icons.search_off_rounded, '内容不存在'),
      'NETWORK' => (Icons.wifi_off_rounded, '网络连接失败'),
      _ => (Icons.error_outline_rounded, '加载失败'),
    };
    final actions = <Widget>[
      if (e.isCloudflare)
        FilledButton.icon(
          icon: const Icon(Icons.open_in_browser_rounded),
          label: const Text('去验证'),
          onPressed: () async {
            if (await Nav.verifyCloudflare(context, source, url: e.url)) onRetry();
          },
        ),
      if (e.needsLogin)
        FilledButton.icon(
          icon: const Icon(Icons.login_rounded),
          label: const Text('去登录'),
          onPressed: () async {
            await Nav.openSourceSettings(context, source);
            onRetry();
          },
        ),
      if (e.isCloudflare || e.needsLogin)
        OutlinedButton(onPressed: onRetry, child: const Text('重试'))
      else
        FilledButton.tonalIcon(onPressed: onRetry, icon: const Icon(Icons.refresh_rounded), label: const Text('重试')),
      if (e.isNetwork) TextButton(onPressed: () => Nav.openNetworkSettings(context), child: const Text('网络设置')),
    ];
    return MessageView(icon: icon, title: title, message: e.isCloudflare ? e.friendly : e.message, actions: actions, compact: compact);
  }
}

/// Runs [action] and turns Cloudflare / login errors into guided UI, returning null on failure.
Future<T?> guarded<T>(BuildContext context, String source, Future<T> Function() action) async {
  try {
    return await action();
  } on SourceError catch (e) {
    if (!context.mounted) return null;
    if (e.isCloudflare && await Nav.verifyCloudflare(context, source, url: e.url)) {
      if (context.mounted) return guarded(context, source, action);
      return null;
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.friendly),
          action: e.needsLogin ? SnackBarAction(label: '去登录', onPressed: () => Nav.openSourceSettings(context, source)) : null,
        ),
      );
    }
    return null;
  }
}
