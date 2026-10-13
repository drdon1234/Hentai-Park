import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../../engine/source_manager.dart';
import '../nav.dart';
import '../settings/source_settings_page.dart';
import '../source/source_page.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'source_poster.dart';

/// 每站点拥有海报、说明、账号提示与快速操作，内容自然决定卡片高度。
class SourceTile extends StatelessWidget {
  const SourceTile({super.key, required this.source});
  final InstalledSource source;
  @override
  Widget build(BuildContext context) {
    final m = source.manifest!;
    final needsLogin =
        m.account?.required == true && source.account?.loggedIn != true;
    final managedNotice =
        m.account?.managedAccount == true && source.account?.loggedIn != true;
    int? ranking;
    for (final key in ['rank', 'toplist', 'popular']) {
      final index = m.feeds.indexWhere(
        (f) => f.key.toLowerCase().contains(key),
      );
      if (index >= 0) {
        ranking = index;
        break;
      }
    }
    return Material(
      color: context.colors.surfaceContainer,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            children: [
              InkWell(
                onTap: () => Nav.openSource(context, source.key),
                onLongPress: () => Nav.openSourceSettings(context, source.key),
                child: SourcePoster(source: source),
              ),
              PositionedDirectional(
                top: 4,
                end: 4,
                child: SourcePosterMenu(source: source.key),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    Pill(m.category.label, color: m.color),
                    if (needsLogin)
                      Pill(
                        tr('未登录'),
                        color: context.colors.error,
                        icon: Icons.lock_outline_rounded,
                      ),
                    if (source.account?.loggedIn == true)
                      Pill(
                        tr('已登录'),
                        color: Colors.green,
                        icon: Icons.person_rounded,
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  m.description,
                  style: context.text.bodySmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
                if (managedNotice) ...[
                  const SizedBox(height: 12),
                  _AccountNotice(source: source),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    TextButton.icon(
                      onPressed: () => Nav.openSource(context, source.key),
                      icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                      label: Text(tr('进入站点')),
                    ),
                    if (ranking != null)
                      TextButton.icon(
                        onPressed: () => Nav.push(
                          context,
                          SourcePage(
                            sourceKey: source.key,
                            initialFeed: ranking,
                          ),
                        ),
                        icon: const Icon(Icons.leaderboard_outlined, size: 18),
                        label: Text(tr('排行')),
                      ),
                    if (m.can('search'))
                      TextButton.icon(
                        onPressed: () =>
                            Nav.openSourceSearch(context, source.key),
                        icon: const Icon(Icons.search_rounded, size: 18),
                        label: Text(tr('搜索')),
                      ),
                    if (m.can('random'))
                      TextButton.icon(
                        onPressed: () => Nav.random(context, source.key),
                        icon: const Icon(Icons.casino_outlined, size: 18),
                        label: Text(tr('随机')),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountNotice extends StatelessWidget {
  const _AccountNotice({required this.source});
  final InstalledSource source;
  @override
  Widget build(BuildContext context) {
    final configured = source.account?.configured == true;
    final managed =
        SourceManager.instance.settingsOf(source.key)['managedAccount'] == true;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.colors.errorContainer.withValues(alpha: .4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr(configured ? '{source}账号尚未登录' : '{source}尚未配置账号', {
              'source': source.name,
            }),
            style: context.text.titleSmall,
          ),
          const SizedBox(height: 6),
          Text(
            tr(
              configured ? '打开账号设置完成登录，或重试已保存的专用账号。' : '请选择自行配置账号，或自动注册一个专用账号。',
            ),
            style: context.text.bodySmall,
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              TextButton(
                onPressed: () => Nav.openSourceSettings(context, source.key),
                child: Text(tr(configured ? '账号设置' : '自行配置')),
              ),
              if (!configured || managed)
                FilledButton.tonal(
                  onPressed: () => Nav.push(
                    context,
                    SourceSettingsPage(
                      sourceKey: source.key,
                      showManagedAccountPrompt: true,
                    ),
                  ),
                  child: Text(tr(managed ? '重试专用账号' : '自动注册专用账号')),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
