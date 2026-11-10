import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../../core/models.dart';
import '../../core/voice.dart';
import '../kit/tokens.dart';
import '../theme.dart';
import '../widgets/option_bar.dart';
import '../widgets/paged_grid.dart';

/// 使用源提供的作品标签筛选；未知值保留为独立选项。
class VoiceWorkFilters extends StatelessWidget {
  VoiceWorkFilters({super.key, required this.controller});

  final PagedController controller;

  final _options = [
    OptionDef.fromJson({
      'key': 'media',
      'label': '类型',
      'default': 'all',
      'values': [
        {'value': 'all', 'label': '全部'},
        {'value': 'audioOnly', 'label': '纯音频'},
        {'value': 'videoOnly', 'label': '带视频'},
        {'value': 'mixed', 'label': '音画混合'},
        {'value': 'unknown', 'label': '未标注'},
      ],
    }),
    OptionDef.fromJson({
      'key': 'language',
      'label': '语言',
      'default': 'all',
      'values': [
        {'value': 'all', 'label': '全部'},
        {'value': 'chineseSpoken', 'label': '中文配音'},
        {'value': 'chineseSubtitled', 'label': '中文字幕'},
        {'value': 'foreignOriginal', 'label': '外语原版'},
        {'value': 'unknown', 'label': '未标注'},
      ],
    }),
  ];

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OptionBar(
          options: _options,
          values: {
            'media': controller.voiceForm?.name ?? 'all',
            'language': controller.voiceLanguage?.name ?? 'all',
          },
          onChanged: (values) => controller.setVoiceFilters(
            form: values['media'] == 'all'
                ? null
                : VoiceMediaForm.fromJson(values['media']),
            language: values['language'] == 'all'
                ? null
                : VoiceLanguageStatus.fromJson(values['language']),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.xs),
          child: Text(
            tr('依据站点提供的标签筛选，未标注的作品可单独查看'),
            style: context.text.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
        ),
      ],
    ),
  );
}
