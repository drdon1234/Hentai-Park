import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../../core/settings.dart';
import '../../engine/app_updater.dart';
import '../nav.dart';
import '../updates/update_prompt.dart';
import 'source_manage_page.dart';

class UpdateSettings extends StatelessWidget {
  const UpdateSettings({super.key, this.appUpdater});
  final AppUpdater? appUpdater;

  @override
  Widget build(BuildContext context) {
    AppLocalizations.of(context);
    final settings = AppSettings.instance;
    final updater = appUpdater ?? AppUpdater.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([settings, updater]),
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.system_update_alt_rounded),
            title: Text(tr('启动时检查软件更新')),
            subtitle: Text(tr('每次启动检查软件版本，有更新时提示，确认后在应用内下载并由系统确认安装。')),
            value: settings.autoAppUpdates,
            onChanged: (value) => settings.autoAppUpdates = value,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.extension_outlined),
            title: Text(tr('启动时检查插件更新')),
            subtitle: Text(tr('每次启动检查官方插件，有更新时提示，确认后才安装。')),
            value: settings.autoSourceUpdates,
            onChanged: (value) => settings.autoSourceUpdates = value,
          ),
          if (updater.lastResult?.currentVersion != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text('HentaiPark v${updater.lastResult!.currentVersion}'),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: FilledButton.tonalIcon(
              onPressed: updater.running
                  ? null
                  : () async {
                      final result = await updater.checkNow();
                      if (context.mounted) {
                        await showAppUpdateResult(context, result);
                      }
                    },
              icon: updater.running
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.update_rounded),
              label: Text(tr(updater.running ? '正在检查软件更新…' : '检查软件更新')),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.extension_outlined),
            title: Text(tr('源站管理')),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Nav.push(context, const SourceManagePage()),
          ),
        ],
      ),
    );
  }
}
