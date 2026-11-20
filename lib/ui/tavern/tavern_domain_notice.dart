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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(tr('创作与导入'), style: context.text.titleMedium),
        const SizedBox(height: Gap.s),
        _ActionGroup(
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
        const SizedBox(height: Gap.l),
        Text(tr('管理'), style: context.text.titleMedium),
        const SizedBox(height: Gap.s),
        _ActionGroup(
          children: [
            TextButton.icon(
              onPressed: () => Nav.push(context, const TavernLibraryPage()),
              icon: const Icon(Icons.collections_bookmark_outlined),
              label: Text(tr('已保存与会话')),
            ),
            TextButton.icon(
              onPressed: () => Nav.push(context, const TavernSettingsPage()),
              icon: const Icon(Icons.settings_outlined),
              label: Text(tr('AI 服务设置')),
            ),
          ],
        ),
      ],
    ),
  );
}

class _ActionGroup extends StatelessWidget {
  const _ActionGroup({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final minimumWidth = MediaQuery.textScalerOf(context).scale(132);
      final columns = ((constraints.maxWidth + Gap.s) / (minimumWidth + Gap.s))
          .floor()
          .clamp(1, children.length);
      final count = columns == 3 ? 2 : columns;
      final width = (constraints.maxWidth - (count - 1) * Gap.s) / count;
      return Wrap(
        spacing: Gap.s,
        runSpacing: Gap.s,
        children: [
          for (final child in children)
            SizedBox(
              width: width,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: child,
              ),
            ),
        ],
      );
    },
  );
}
