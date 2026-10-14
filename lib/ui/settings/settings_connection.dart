import 'package:flutter/material.dart';

import '../../core/app_lock.dart';
import '../../core/localization.dart';
import '../../core/settings.dart';
import '../../core/translation_options.dart';
import '../kit/kit.dart';
import '../nav.dart';
import '../subscriptions/subscriptions_page.dart';
import '../theme.dart';
import '../widgets/content_translation.dart';
import 'settings_rows.dart';

// 搜索与翻译、网络、隐私与安全、订阅与通知。
List<Widget> searchSettings(BuildContext context, AppSettings s) => [
  RowGroup(
    title: tr('内容翻译'),
    children: [
      SwitchListTile(
        title: Text(tr('自动翻译可见内容')),
        subtitle: Text(tr('标题、简介等远端文字按界面语言显示，原文保留')),
        value: s.autoTranslateContent,
        onChanged: (v) => s.autoTranslateContent = v,
      ),
      ListRow(
        title: tr('翻译服务'),
        subtitle: tr(translateEngines[s.translateEngine] ?? s.translateEngine),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () async {
          final v = await chooseSetting<String>(context, tr('翻译服务'), {
            for (final e in translateEngines.entries) e.key: tr(e.value),
          }, s.translateEngine);
          if (v != null) s.translateEngine = v;
        },
      ),
      const _TranslationNotice(),
    ],
  ),
  RowGroup(
    title: tr('多语言搜索'),
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(Gap.page, Gap.m, Gap.page, Gap.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('目标语言'), style: context.text.bodyLarge),
            const SizedBox(height: Gap.s),
            Wrap(
              spacing: Gap.s - 2,
              runSpacing: Gap.s - 2,
              children: [
                for (final e in translateLanguages.entries)
                  FilterChip(
                    label: Text(tr(e.value)),
                    selected: s.translateTargets.contains(e.key),
                    onSelected: (on) {
                      final list = s.translateTargets;
                      on ? list.add(e.key) : list.remove(e.key);
                      s.translateTargets = list;
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
      ListRow(
        title: tr('标签翻译词库'),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => showTagTranslationPacks(context),
      ),
      SwitchListTile(
        title: Text(tr('提醒下载标签词库')),
        value: s.tagDownloadReminders,
        onChanged: (v) => s.tagDownloadReminders = v,
      ),
    ],
  ),
];

List<Widget> networkSettings(BuildContext context, AppSettings s) => [
  RowGroup(
    children: [
      ListRow(
        title: tr('HTTP 代理'),
        subtitle: s.proxy.isEmpty ? tr('未设置（使用系统网络 / VPN）') : s.proxy,
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () async {
          final v = await askSettingText(
            context,
            tr('HTTP 代理'),
            s.proxy,
            hint: tr('例如 127.0.0.1:7890，留空表示不使用'),
          );
          if (v != null) s.proxy = v;
        },
      ),
    ],
  ),
  RowGroup(
    title: tr('高级'),
    children: [
      SettingsSlider(
        title: tr('每个站点的图片并发数'),
        value: s.imageConcurrency,
        min: 2,
        max: 12,
        onChanged: (v) => s.imageConcurrency = v,
      ),
      SettingsSlider(
        title: tr('每个下载任务的并发页数'),
        value: s.downloadConcurrency,
        min: 1,
        max: 8,
        onChanged: (v) => s.downloadConcurrency = v,
      ),
    ],
  ),
];

List<Widget> privacySettings(BuildContext context, AppSettings s) => [
  RowGroup(
    children: [
      SwitchListTile(
        title: Text(tr('模糊封面')),
        subtitle: Text(tr('在列表与预览中模糊所有封面')),
        value: s.blurCovers,
        onChanged: (v) => s.blurCovers = v,
      ),
      SwitchListTile(
        title: Text(tr('应用锁')),
        subtitle: Text(tr('打开应用时需要指纹 / 面部 / 锁屏密码验证')),
        value: s.appLock,
        onChanged: AppLock.platformSupported
            ? (v) async {
                if (!v) {
                  AppLock.instance.disable();
                  return;
                }
                if (!await AppLock.instance.available()) {
                  if (context.mounted) {
                    context.toast(tr('设备没有设置锁屏或生物识别，无法开启'));
                  }
                  return;
                }
                await AppLock.instance.enable();
              }
            : null,
      ),
      if (s.appLock)
        ListRow(
          title: tr('离开多久后重新锁定'),
          subtitle: _relock[s.appLockAfter] ?? '${s.appLockAfter}s',
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () async {
            final v = await chooseSetting<int>(
              context,
              tr('离开多久后重新锁定'),
              _relock,
              s.appLockAfter,
            );
            if (v != null) s.appLockAfter = v;
          },
        ),
      SwitchListTile(
        title: Text(tr('防截屏与多任务预览')),
        subtitle: Text(tr('最近任务中隐藏内容，并禁止截屏（Android）')),
        value: s.secureScreen,
        onChanged: (v) => s.secureScreen = v,
      ),
    ],
  ),
];

Map<int, String> get _relock => {
  0: tr('立即'),
  60: tr('1 分钟'),
  300: tr('5 分钟'),
  900: tr('15 分钟'),
};

List<Widget> subscriptionSettings(BuildContext context, AppSettings s) => [
  RowGroup(
    children: [
      SwitchListTile(
        title: Text(tr('自动检查订阅更新')),
        value: s.subscriptionUpdateHours > 0,
        onChanged: (value) => s.subscriptionUpdateHours = value ? 6 : 0,
      ),
      ListRow(
        title: tr('订阅与通知设置'),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => Nav.push(context, const SubscriptionsPage()),
      ),
    ],
  ),
];

// ── 关于 ──

/// Where translated text goes: shown wherever translation is configured.
class _TranslationNotice extends StatelessWidget {
  const _TranslationNotice();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Gap.page, Gap.s, Gap.page, Gap.m),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.info_outline_rounded,
          size: 18,
          color: context.colors.onSurfaceVariant,
        ),
        const SizedBox(width: Gap.s),
        Expanded(
          child: Text(
            tr(
              '翻译时，标题、简介、标签和搜索词会发送给所选的翻译服务（Google 或 Microsoft）。不会发送账号、Cookie 或阅读记录。',
            ),
            style: context.text.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
        ),
      ],
    ),
  );
}
