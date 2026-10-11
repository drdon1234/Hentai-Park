import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/models.dart';
import '../../engine/source_manager.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'login_panel.dart';
import 'source_install.dart';

/// Per-source page: account, the source's own settings, network verification and maintenance.
class SourceSettingsPage extends StatefulWidget {
  const SourceSettingsPage({super.key, required this.sourceKey});
  final String sourceKey;

  @override
  State<SourceSettingsPage> createState() => _SourceSettingsPageState();
}

class _SourceSettingsPageState extends State<SourceSettingsPage> {
  final sm = SourceManager.instance;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: sm,
      builder: (context, _) {
        final s = sm[widget.sourceKey];
        final m = s?.manifest;
        if (s == null || m == null) {
          return Scaffold(
            appBar: AppBar(),
            body: MessageView(icon: Icons.error_outline_rounded, title: '源未加载', message: s?.loadError),
          );
        }
        return Theme(
          data: ParkTheme.build(Theme.of(context).brightness, m.color),
          child: Builder(
            builder: (context) {
              return Scaffold(
                appBar: AppBar(title: Row(children: [SourceAvatar(m.key, size: 28), const SizedBox(width: 10), Text(m.name)])),
                body: ListView(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 32),
                  children: [
                    Card(
                      child: ListTile(
                        title: Text(m.description),
                        subtitle: Text(
                          'v${m.version} · ${s.origin == 'builtin' ? '内置源' : '第三方源'}${m.homepage.isNotEmpty ? ' · ${Uri.parse(m.homepage).host}' : ''}',
                        ),
                        trailing: m.homepage.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.open_in_new_rounded),
                                onPressed: () => launchUrl(Uri.parse(m.homepage), mode: LaunchMode.externalApplication),
                              ),
                      ),
                    ),
                    if (m.account != null) ...[_header(context, '账号'), _account(context, s, m.account!)],
                    if (m.settings.isNotEmpty) ...[
                      _header(context, '源设置'),
                      Card(child: Column(children: [for (final o in m.settings) _setting(context, m, o)])),
                    ],
                    _header(context, '网络'),
                    Card(
                      child: Column(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.verified_user_outlined),
                            title: const Text('打开站点进行人机验证'),
                            subtitle: Text(m.usesBrowserNetwork ? '该源通过内置浏览器内核访问，遇到验证时在这里完成' : '遇到 Cloudflare 验证时使用'),
                            onTap: () async {
                              final ok = await Nav.verifyCloudflare(context, m.key);
                              if (context.mounted && ok) context.toast('验证完成');
                            },
                          ),
                        ],
                      ),
                    ),
                    _header(context, '维护'),
                    Card(
                      child: Column(
                        children: [
                          if (s.origin == 'builtin')
                            ListTile(
                              leading: const Icon(Icons.restore_rounded),
                              title: const Text('恢复内置版本'),
                              onTap: () async {
                                await sm.resetBuiltin(m.key);
                                if (context.mounted) context.toast('已恢复');
                              },
                            ),
                          if (s.origin != 'builtin' && s.url.isNotEmpty)
                            ListTile(
                              leading: const Icon(Icons.system_update_alt_rounded),
                              title: const Text('从原地址更新'),
                              subtitle: Text(s.url, maxLines: 1, overflow: TextOverflow.ellipsis),
                              onTap: () => installSourceFromUrl(context, s.url),
                            ),
                          if (s.origin != 'builtin')
                            ListTile(
                              leading: Icon(Icons.delete_outline_rounded, color: context.colors.error),
                              title: Text('卸载此源', style: TextStyle(color: context.colors.error)),
                              onTap: () async {
                                final ok = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: Text('卸载「${m.name}」？'),
                                    content: const Text('该源的设置、登录信息与 Cookie 都会被删除。书架中的收藏与下载不受影响。'),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
                                      FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('卸载')),
                                    ],
                                  ),
                                );
                                if (ok != true) return;
                                await sm.uninstall(m.key);
                                if (context.mounted) Navigator.pop(context);
                              },
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _header(BuildContext context, String title) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 20, 8, 6),
    child: Text(
      title,
      style: context.text.labelLarge?.copyWith(color: context.colors.primary, fontWeight: FontWeight.w700),
    ),
  );

  Widget _account(BuildContext context, InstalledSource s, AccountDef a) {
    final status = s.account;
    if (status?.loggedIn == true) {
      return Card(
        child: ListTile(
          leading: const CircleAvatar(child: Icon(Icons.person_rounded)),
          title: Text(status!.name.isEmpty ? '已登录' : status.name),
          subtitle: Text(a.title),
          trailing: TextButton(
            onPressed: () async {
              await sm.logout(s.key);
              if (context.mounted) context.toast('已退出登录');
            },
            child: const Text('退出'),
          ),
        ),
      );
    }
    return LoginPanel(source: s.key, account: a);
  }

  Widget _setting(BuildContext context, SourceManifest m, OptionDef o) {
    final value = sm.settingValue(m.key, o);
    switch (o.type) {
      case 'switch':
        return SwitchListTile(
          title: Text(o.label),
          subtitle: o.description.isEmpty ? null : Text(o.description),
          value: value == true,
          onChanged: (v) => sm.setSetting(m.key, o.key, v),
        );
      case 'select':
        return ListTile(
          title: Text(o.label),
          subtitle: Text(o.description.isEmpty ? o.labelOf(value) : '${o.labelOf(value)}\n${o.description}'),
          isThreeLine: o.description.isNotEmpty,
          trailing: const Icon(Icons.unfold_more_rounded),
          onTap: () async {
            final picked = await showModalBottomSheet<Choice>(
              context: context,
              isScrollControlled: true,
              builder: (ctx) => SafeArea(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      ListTile(
                        title: Text(o.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                      for (final c in o.values)
                        ListTile(title: Text(c.label), trailing: c.value == value ? const Icon(Icons.check_rounded) : null, onTap: () => Navigator.pop(ctx, c)),
                    ],
                  ),
                ),
              ),
            );
            if (picked != null) await sm.setSetting(m.key, o.key, picked.value);
          },
        );
      default:
        return ListTile(
          title: Text(o.label),
          subtitle: Text('${value ?? ''}'.isEmpty ? '未设置' : (o.type == 'password' ? '••••••' : '$value')),
          onTap: () async {
            final c = TextEditingController(text: '${value ?? ''}');
            final v = await showDialog<String>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text(o.label),
                content: TextField(controller: c, obscureText: o.type == 'password', autofocus: true),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
                  FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('保存')),
                ],
              ),
            );
            if (v != null) await sm.setSetting(m.key, o.key, v);
          },
        );
    }
  }
}
