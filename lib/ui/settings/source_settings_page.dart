import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/localization.dart';
import '../../core/models.dart';
import '../../engine/source_manager.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/content_translation.dart';
import 'login_panel.dart';
import 'source_install.dart';

/// Per-source page: account, the source's own settings, network verification and maintenance.
class SourceSettingsPage extends StatefulWidget {
  const SourceSettingsPage({
    super.key,
    required this.sourceKey,
    this.showManagedAccountPrompt = false,
  });
  final String sourceKey;
  final bool showManagedAccountPrompt;

  @override
  State<SourceSettingsPage> createState() => _SourceSettingsPageState();
}

class _SourceSettingsPageState extends State<SourceSettingsPage> {
  final sm = SourceManager.instance;
  bool _accountBusy = false;

  @override
  void initState() {
    super.initState();
    sm.refreshAccount(widget.sourceKey);
    if (widget.showManagedAccountPrompt) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _changeManagedAccount(true);
      });
    }
  }

  Future<void> _changeManagedAccount(bool enabled) async {
    if (_accountBusy) return;
    final active = sm.settingsOf(widget.sourceKey)['managedAccount'] == true;
    if (enabled && !active) {
      final confirmed = await confirmManagedAccount(context);
      if (confirmed != true || !mounted) return;
    }
    setState(() => _accountBusy = true);
    try {
      if (enabled && active) {
        await sm.retryManagedAccount(widget.sourceKey);
      } else {
        await sm.setManagedAccount(widget.sourceKey, enabled);
      }
      if (mounted) {
        context.toast(context.tr(enabled ? '专用账号已就绪' : '已关闭专用自动维护账号'));
      }
    } catch (e) {
      if (mounted) {
        context.toast(
          context.tr('账号操作失败：{error}', {'error': e.asSourceError.message}),
        );
      }
    } finally {
      if (mounted) setState(() => _accountBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        sm,
        ?sm.accountListenable(widget.sourceKey),
      ]),
      builder: (context, _) {
        final s = sm[widget.sourceKey];
        final m = s?.manifest;
        if (s == null || m == null) {
          return Scaffold(
            appBar: AppBar(),
            body: EmptyState(
              icon: Icons.error_outline_rounded,
              title: context.tr('站点未加载'),
              message: s?.loadError,
            ),
          );
        }
        final managed = s.origin == 'builtin' || s.origin == 'official';
        final canRestore = managed && sm.isBuiltin(s.key);
        return Theme(
          data: Theme.of(context),
          child: Builder(
            builder: (context) {
              return Scaffold(
                appBar: AppBar(
                  title: Row(
                    children: [
                      SourceAvatar(m.key, size: 28),
                      const SizedBox(width: 10),
                      Text(m.name),
                    ],
                  ),
                ),
                body: ListView(
                  padding: const EdgeInsets.fromLTRB(0, 4, 0, 32),
                  children: [
                    RowGroup(
                      children: [
                        ListTile(
                          title: Text(m.description),
                          subtitle: Text(
                            'v${m.version} · ${context.tr(s.origin == 'official'
                                ? '官方'
                                : s.origin == 'builtin'
                                ? '内置站点'
                                : '第三方站点')}${m.homepage.isNotEmpty ? ' · ${Uri.parse(m.homepage).host}' : ''}',
                          ),
                          trailing: m.homepage.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: tr('在浏览器中打开'),
                                  icon: const Icon(Icons.open_in_new_rounded),
                                  onPressed: () => launchUrl(
                                    Uri.parse(m.homepage),
                                    mode: LaunchMode.externalApplication,
                                  ),
                                ),
                        ),
                      ],
                    ),
                    RowGroup(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.translate_rounded),
                          title: Text(context.tr('官方标签翻译包')),
                          onTap: () => showTagTranslationPacks(
                            context,
                            source: widget.sourceKey,
                          ),
                        ),
                      ],
                    ),
                    if (m.account != null) ...[
                      _header(context, context.tr('账号')),
                      _account(context, s, m.account!),
                    ],
                    if (m.settings.isNotEmpty) ...[
                      _header(context, context.tr('站点设置')),
                      RowGroup(
                        children: [
                          for (final o in m.settings) _setting(context, m, o),
                        ],
                      ),
                    ],
                    _header(context, context.tr('网络')),
                    RowGroup(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.verified_user_outlined),
                          title: Text(context.tr('打开站点进行人机验证')),
                          subtitle: Text(
                            context.tr(
                              m.usesBrowserNetwork
                                  ? '这个站点通过内置浏览器访问，遇到验证时在这里完成'
                                  : '遇到 Cloudflare 验证时使用',
                            ),
                          ),
                          onTap: () async {
                            final ok = await Nav.verifyCloudflare(
                              context,
                              m.key,
                            );
                            if (context.mounted && ok) {
                              context.toast(context.tr('验证完成'));
                            }
                          },
                        ),
                      ],
                    ),
                    if (canRestore || !managed)
                      _header(context, context.tr('维护')),
                    if (canRestore || !managed)
                      RowGroup(
                        children: [
                          if (canRestore)
                            ListTile(
                              leading: const Icon(Icons.restore_rounded),
                              title: Text(context.tr('恢复内置版本')),
                              onTap: () async {
                                await sm.resetBuiltin(m.key);
                                if (context.mounted) {
                                  context.toast(context.tr('已恢复'));
                                }
                              },
                            ),
                          if (!managed && s.url.isNotEmpty)
                            ListTile(
                              leading: const Icon(
                                Icons.system_update_alt_rounded,
                              ),
                              title: Text(context.tr('从原地址更新')),
                              subtitle: Text(
                                s.url,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () => installSourceFromUrl(context, s.url),
                            ),
                          if (!managed)
                            ListTile(
                              leading: Icon(
                                Icons.delete_outline_rounded,
                                color: context.colors.error,
                              ),
                              title: Text(
                                context.tr('卸载此站点'),
                                style: TextStyle(color: context.colors.error),
                              ),
                              onTap: () async {
                                final ok = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: Text(
                                      context.tr('卸载「{name}」？', {
                                        'name': m.name,
                                      }),
                                    ),
                                    content: Text(
                                      context.tr(
                                        '这个站点的设置、登录信息与 Cookie 都会被删除。书架中的收藏与下载不受影响。',
                                      ),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, false),
                                        child: Text(context.tr('取消')),
                                      ),
                                      FilledButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, true),
                                        child: Text(context.tr('卸载')),
                                      ),
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
      style: context.text.labelLarge?.copyWith(
        color: context.colors.primary,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  Widget _account(BuildContext context, InstalledSource s, AccountDef a) {
    final status = s.account;
    final managed =
        a.managedAccount && sm.settingsOf(s.key)['managedAccount'] == true;
    if (status == null && s.manifest!.can('status')) {
      return const Center(child: CircularProgressIndicator());
    }
    if (status?.loggedIn == true) {
      return RowGroup(
        children: [
          ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person_rounded)),
            title: Text(status!.name.isEmpty ? context.tr('已登录') : status.name),
            subtitle: Text(managed ? context.tr('专用自动维护账号') : a.title),
            trailing: TextButton(
              onPressed: () async {
                await sm.logout(s.key);
                if (context.mounted) context.toast(context.tr('已退出登录'));
              },
              child: Text(context.tr('退出')),
            ),
          ),
        ],
      );
    }
    if (managed) {
      return RowGroup(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(context.tr('专用账号尚未就绪。重试会继续使用已保存的账号，不会重复创建。')),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _accountBusy
                      ? null
                      : () => _changeManagedAccount(true),
                  icon: _accountBusy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded),
                  label: Text(
                    context.tr(_accountBusy ? '正在准备专用账号…' : '重试专用账号'),
                  ),
                ),
              ],
            ),
          ),
        ],
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
          onChanged: _accountBusy && o.key == 'managedAccount'
              ? null
              : (v) =>
                    o.key == 'managedAccount' &&
                        m.account?.managedAccount == true
                    ? _changeManagedAccount(v)
                    : sm.setSetting(m.key, o.key, v),
        );
      case 'select':
        return ListTile(
          title: Text(o.label),
          subtitle: Text(
            o.description.isEmpty
                ? o.labelOf(value)
                : '${o.labelOf(value)}\n${o.description}',
          ),
          isThreeLine: o.description.isNotEmpty,
          trailing: const Icon(Icons.unfold_more_rounded),
          onTap: () async {
            final picked = await showModalBottomSheet<Choice>(
              context: context,
              isScrollControlled: true,
              builder: (ctx) => SafeArea(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(ctx).height * 0.7,
                  ),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      ListTile(
                        title: Text(
                          o.label,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      for (final c in o.values)
                        ListTile(
                          title: Text(c.label),
                          trailing: c.value == value
                              ? const Icon(Icons.check_rounded)
                              : null,
                          onTap: () => Navigator.pop(ctx, c),
                        ),
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
          subtitle: Text(
            '${value ?? ''}'.isEmpty
                ? context.tr('未设置')
                : (o.type == 'password' ? '••••••' : '$value'),
          ),
          onTap: () async {
            final c = TextEditingController(text: '${value ?? ''}');
            final v = await showDialog<String>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text(o.label),
                content: TextField(
                  controller: c,
                  obscureText: o.type == 'password',
                  autofocus: true,
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(context.tr('取消')),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, c.text),
                    child: Text(context.tr('保存')),
                  ),
                ],
              ),
            );
            if (v != null) await sm.setSetting(m.key, o.key, v);
          },
        );
    }
  }
}

Future<bool?> confirmManagedAccount(BuildContext context) => showDialog<bool>(
  context: context,
  builder: (ctx) => AlertDialog(
    title: Text(ctx.tr('启用专用自动维护账号？')),
    content: Text(
      ctx.tr(
        '启用后将自动向哔咔注册一个专用账号。账号和密码只保存在本机，登录过期后自动重新登录；失败重试会复用同一账号。已有手动账号不会被替换。',
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(ctx, false),
        child: Text(ctx.tr('取消')),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(ctx, true),
        child: Text(ctx.tr('确认并注册')),
      ),
    ],
  ),
);
