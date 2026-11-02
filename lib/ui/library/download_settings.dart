import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../../core/settings.dart';
import '../kit/adaptive_sheet.dart';
import '../kit/kit.dart';
import '../settings/settings_rows.dart';
import '../theme.dart';

Future<void> showDownloadConcurrencySettings(BuildContext context) =>
    showAdaptiveSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .85,
        ),
        child: const SingleChildScrollView(
          padding: EdgeInsets.only(bottom: Gap.l),
          child: DownloadConcurrencySettings(),
        ),
      ),
    );

/// 下载页与设置页共享同一组取值和即时保存行为。
class DownloadConcurrencySettings extends StatelessWidget {
  const DownloadConcurrencySettings({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = AppSettings.instance;
    return ListenableBuilder(
      listenable: settings.watch(const {
        'downloadSiteConcurrency',
        'downloadTaskConcurrency',
        'downloadConcurrency',
      }),
      builder: (context, _) => RowGroup(
        title: tr('下载并发'),
        children: [
          SettingsSlider(
            title: tr('同时下载站点数'),
            value: settings.downloadSiteConcurrency,
            min: 1,
            max: 8,
            onChanged: (value) => settings.downloadSiteConcurrency = value,
          ),
          SettingsSlider(
            title: tr('每站同时下载作品数'),
            value: settings.downloadTaskConcurrency,
            min: 1,
            max: 8,
            onChanged: (value) => settings.downloadTaskConcurrency = value,
          ),
          SettingsSlider(
            title: tr('每个下载任务的并发页数'),
            value: settings.downloadConcurrency,
            min: 1,
            max: 8,
            onChanged: (value) => settings.downloadConcurrency = value,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.l),
            child: Text(
              tr('站点与作品并发适用于漫画、视频、小说和游戏直链。并发页数仅用于漫画图片。调低上限不会中断正在下载的任务。'),
              style: context.text.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
