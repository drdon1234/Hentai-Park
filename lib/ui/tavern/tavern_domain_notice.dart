import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../kit/kit.dart';
import '../nav.dart';
import '../theme.dart';
import 'tavern_ai_draft_page.dart';
import 'tavern_editor_page.dart';
import 'tavern_import_action.dart';
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
        const SizedBox(height: Gap.m),
        Wrap(
          spacing: Gap.s,
          runSpacing: Gap.s,
          children: [
            FilledButton.tonalIcon(
              onPressed: () => Nav.push(context, const TavernAiDraftPage()),
              icon: const Icon(Icons.auto_awesome_outlined),
              label: Text(tr('AI 创作')),
            ),
            OutlinedButton.icon(
              onPressed: () => chooseAndImportTavern(context),
              icon: const Icon(Icons.file_open_outlined),
              label: Text(tr('导入')),
            ),
            OutlinedButton.icon(
              onPressed: () =>
                  Nav.push(context, TavernEditorPage.create('character')),
              icon: const Icon(Icons.person_add_alt_1_outlined),
              label: Text('${tr('新建')} ${tr('角色卡')}'),
            ),
            OutlinedButton.icon(
              onPressed: () =>
                  Nav.push(context, TavernEditorPage.create('lorebook')),
              icon: const Icon(Icons.menu_book_outlined),
              label: Text('${tr('新建')} ${tr('世界书')}'),
            ),
          ],
        ),
        const SizedBox(height: Gap.m),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
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
