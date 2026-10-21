import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/localization.dart';
import '../../core/models.dart';
import '../../engine/source_manager.dart';
import '../kit/adaptive_sheet.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/confirm_reset.dart';
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
    sm.refreshAccount(widget.sourceKey).ignore();
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
        final webUrl = sm.webUrl(widget.sourceKey);
        if (s == null || m == null) {
          return Scaffold(
            appBar: AppBar(actions: _webActions(context, webUrl)),
            body: SettingsBody(
              child: EmptyState(
                icon: Icons.error_outline_rounded,
                title: context.tr('站点未加载'),
                message: s?.loadError,
              ),
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
                      Expanded(
                        child: Text(
                          m.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  actions: _webActions(context, webUrl),
                ),
                body: SettingsBody(
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: Gap.xxl),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          Gap.page,
                          Gap.m,
                          Gap.page,
                          Gap.s,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(m.description, style: context.text.bodyLarge),
                            const SizedBox(height: Gap.s),
                            Text(
                              'v${m.version} · ${context.tr(s.origin == 'official'
                                  ? '官方'
                                  : s.origin == 'builtin'
                                  ? '内置站点'
                                  : '第三方站点')}',
                              style: context.text.bodySmall?.copyWith(
                                color: context.colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
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
                      RowGroup(
                        title: context.tr('翻译'),
                        children: [
                          ListTile(
                            leading: const Icon(Icons.translate_rounded),
                            title: Text(context.tr('官方标签翻译包')),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () => showTagTranslationPacks(
                              context,
                              source: widget.sourceKey,
                            ),
                          ),
                        ],
                      ),
                      _header(context, context.tr('网络')),
                      RowGroup(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.verified_user_outlined),
                            title: SelectionContainer.disabled(
                              child: Text(context.tr('后台自动处理站点验证')),
                            ),
                            subtitle: SelectionContainer.disabled(
                              child: Text(
                                context.tr(
                                  m.usesBrowserNetwork
                                      ? '受支持的站点验证会在后台自动处理'
                                      : 'Cloudflare 验证会在后台自动尝试',
                                ),
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
                                title: SelectionContainer.disabled(
                                  child: Text(context.tr('恢复内置版本')),
                                ),
                                onTap: () async {
                                  await confirmReset(
                                    context,
                                    title: '恢复内置版本',
                                    message: '将使用安装包内置的站点插件，账号与设置保留。是否继续？',
                                    reset: () => sm.resetBuiltin(m.key),
                                  );
                                },
                              ),
                            if (!managed && s.url.isNotEmpty)
                              ListTile(
                                leading: const Icon(
                                  Icons.system_update_alt_rounded,
                                ),
                                title: SelectionContainer.disabled(
                                  child: Text(context.tr('从原地址更新')),
                                ),
                                subtitle: SelectionContainer.disabled(
                                  child: Text(
                                    s.url,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                onTap: () =>
                                    installSourceFromUrl(context, s.url),
                              ),
                            if (!managed)
                              ListTile(
                                leading: Icon(
                                  Icons.delete_outline_rounded,
                                  color: context.colors.error,
                                ),
                                title: SelectionContainer.disabled(
                                  child: Text(
                                    context.tr('卸载此站点'),
                                    style: TextStyle(
                                      color: context.colors.error,
                                    ),
                                  ),
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
                                          child: SelectionContainer.disabled(
                                            child: Text(context.tr('取消')),
                                          ),
                                        ),
                                        FilledButton(
                                          onPressed: () =>
                                              Navigator.pop(ctx, true),
                                          child: SelectionContainer.disabled(
                                            child: Text(context.tr('卸载')),
                                          ),
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
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _header(BuildContext context, String title) => Padding(
    padding: const EdgeInsets.fromLTRB(Gap.page, Gap.xl, Gap.page, Gap.xs),
    child: Text(
      title,
      style: context.text.labelLarge?.copyWith(
        color: context.colors.onSurfaceVariant,
      ),
    ),
  );

  List<Widget> _webActions(BuildContext context, String? url) => [
    if (url != null)
      IconButton(
        tooltip: context.tr('打开原站'),
        icon: const Icon(Icons.open_in_new_rounded),
        onPressed: () => _openWebsite(context, url),
      ),
  ];

  Future<void> _openWebsite(BuildContext context, String url) async {
    final opened = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && context.mounted) {
      context.toast(context.tr('无法打开原站，请稍后重试'));
    }
  }

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
            title: SelectionContainer.disabled(
              child: Text(
                status!.name.isEmpty ? context.tr('已登录') : status.name,
              ),
            ),
            subtitle: SelectionContainer.disabled(
              child: Text(managed ? context.tr('专用自动维护账号') : a.title),
            ),
            trailing: SelectionContainer.disabled(
              child: OutlinedButton(
                onPressed: () async {
                  await sm.logout(s.key);
                  if (context.mounted) context.toast(context.tr('已退出登录'));
                },
                child: Text(context.tr('退出')),
              ),
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
                  label: SelectionContainer.disabled(
                    child: Text(
                      context.tr(_accountBusy ? '正在准备专用账号…' : '重试专用账号'),
                    ),
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
        return SwitchListTile.adaptive(
          title: SelectionContainer.disabled(child: Text(o.label)),
          subtitle: o.description.isEmpty
              ? null
              : SelectionContainer.disabled(child: Text(o.description)),
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
          title: SelectionContainer.disabled(child: Text(o.label)),
          subtitle: SelectionContainer.disabled(
            child: Text(
              o.description.isEmpty
                  ? o.labelOf(value)
                  : '${o.labelOf(value)}\n${o.description}',
            ),
          ),
          isThreeLine: o.description.isNotEmpty,
          trailing: const Icon(Icons.unfold_more_rounded),
          onTap: () async {
            final picked = await showAdaptiveSheet<Choice>(
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
                        title: SelectionContainer.disabled(
                          child: Text(
                            o.label,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      for (final c in o.values)
                        ListTile(
                          title: SelectionContainer.disabled(
                            child: Text(c.label),
                          ),
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
          title: SelectionContainer.disabled(child: Text(o.label)),
          subtitle: SelectionContainer.disabled(
            child: Text(
              '${value ?? ''}'.isEmpty
                  ? context.tr('未设置')
                  : (o.type == 'password' ? '••••••' : '$value'),
            ),
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
                    child: SelectionContainer.disabled(
                      child: Text(context.tr('取消')),
                    ),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, c.text),
                    child: SelectionContainer.disabled(
                      child: Text(context.tr('保存')),
                    ),
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
        child: SelectionContainer.disabled(child: Text(ctx.tr('取消'))),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(ctx, true),
        child: SelectionContainer.disabled(child: Text(ctx.tr('确认并注册'))),
      ),
    ],
  ),
);
