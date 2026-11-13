import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../kit/kit.dart';
import '../nav.dart';
import '../theme.dart';
import 'tavern_library_page.dart';
import 'tavern_settings_page.dart';

class TavernDomainNotice extends StatelessWidget {
  const TavernDomainNotice({super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Gap.page, Gap.l, Gap.page, Gap.s),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(tr('酒馆需要自行配置 AI 服务'), style: context.text.titleMedium),
        const SizedBox(height: Gap.xs),
        Text(tr('浏览角色卡和世界书；配置自己的接口后即可开始对话。'), style: context.text.bodyMedium),
        const SizedBox(height: Gap.s),
        Wrap(
          spacing: Gap.s,
          runSpacing: Gap.s,
          children: [
            FilledButton.tonalIcon(
              onPressed: () => Nav.push(context, const TavernSettingsPage()),
              icon: const Icon(Icons.settings_outlined),
              label: Text(tr('AI 服务设置')),
            ),
            OutlinedButton.icon(
              onPressed: () => Nav.push(context, const TavernLibraryPage()),
              icon: const Icon(Icons.collections_bookmark_outlined),
              label: Text(tr('已保存与会话')),
            ),
          ],
        ),
      ],
    ),
  );
}
