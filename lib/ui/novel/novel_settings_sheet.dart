import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../../core/settings.dart';

class NovelSettingsSheet extends StatelessWidget {
  const NovelSettingsSheet({super.key});
  @override
  Widget build(BuildContext context) {
    final s = AppSettings.instance;
    Widget slider(
      String label,
      double value,
      double min,
      double max,
      ValueChanged<double> change, {
      int? divisions,
    }) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label · ${value.toStringAsFixed(1)}'),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          onChanged: change,
        ),
      ],
    );
    Widget choices(
      String label,
      String value,
      Map<String, String> values,
      ValueChanged<String> change,
    ) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final entry in values.entries)
              ChoiceChip(
                label: Text(tr(entry.value)),
                selected: value == entry.key,
                onSelected: (_) => change(entry.key),
              ),
          ],
        ),
        const SizedBox(height: 16),
      ],
    );
    return SafeArea(
      child: ListenableBuilder(
        listenable: s,
        builder: (context, _) => SizedBox(
          height: MediaQuery.sizeOf(context).height * .78,
          child: Column(
            children: [
              ListTile(
                title: Text(tr('阅读设置')),
                trailing: IconButton(
                  tooltip: tr('关闭'),
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    choices(tr('阅读模式'), s.novelMode, {
                      'scroll': '上下滚动',
                      'paged': '左右翻页',
                    }, (v) => s.novelMode = v),
                    choices(tr('阅读主题'), s.novelTheme, {
                      'paper': '纸张',
                      'white': '白色',
                      'green': '护眼绿',
                      'dark': '夜间',
                      'system': '跟随系统',
                    }, (v) => s.novelTheme = v),
                    choices(tr('字体'), s.novelFont, {
                      'system': '系统字体',
                      'serif': '衬线字体',
                      'monospace': '等宽字体',
                    }, (v) => s.novelFont = v),
                    slider(
                      tr('字号'),
                      s.novelFontSize,
                      12,
                      42,
                      (v) => s.novelFontSize = v,
                      divisions: 30,
                    ),
                    slider(
                      tr('行距'),
                      s.novelLineHeight,
                      1.2,
                      2.8,
                      (v) => s.novelLineHeight = v,
                    ),
                    slider(
                      tr('字距'),
                      s.novelLetterSpacing,
                      0,
                      4,
                      (v) => s.novelLetterSpacing = v,
                    ),
                    slider(
                      tr('页边距'),
                      s.novelMargin,
                      8,
                      48,
                      (v) => s.novelMargin = v,
                      divisions: 40,
                    ),
                    slider(
                      tr('段间距'),
                      s.novelParagraphGap,
                      0,
                      36,
                      (v) => s.novelParagraphGap = v,
                      divisions: 36,
                    ),
                    slider(
                      tr('亮度遮罩'),
                      s.novelDim,
                      0,
                      .7,
                      (v) => s.novelDim = v,
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(tr('亮度跟随系统')),
                      value: s.novelBrightness < 0,
                      onChanged: (v) => s.novelBrightness = v ? -1 : .5,
                    ),
                    if (s.novelBrightness >= 0)
                      slider(
                        tr('亮度'),
                        s.novelBrightness,
                        0,
                        1,
                        (v) => s.novelBrightness = v,
                      ),
                    slider(
                      tr('自动滚动速度'),
                      s.novelAutoScroll,
                      10,
                      100,
                      (v) => s.novelAutoScroll = v,
                      divisions: 90,
                    ),
                    slider(
                      tr('朗读速度'),
                      s.novelSpeechRate,
                      .2,
                      .8,
                      (v) => s.novelSpeechRate = v,
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(tr('粗体')),
                      value: s.novelBold,
                      onChanged: (v) => s.novelBold = v,
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(tr('两端对齐')),
                      value: s.novelJustify,
                      onChanged: (v) => s.novelJustify = v,
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(tr('首行缩进')),
                      value: s.novelIndent,
                      onChanged: (v) => s.novelIndent = v,
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(tr('显示阅读状态')),
                      value: s.novelShowStatus,
                      onChanged: (v) => s.novelShowStatus = v,
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(tr('保持屏幕常亮')),
                      value: s.novelKeepScreenOn,
                      onChanged: (v) => s.novelKeepScreenOn = v,
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(tr('音量键翻页')),
                      value: s.novelVolumeKeys,
                      onChanged: (v) => s.novelVolumeKeys = v,
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(tr('点击翻页')),
                      value: s.novelTapToPage,
                      onChanged: (v) => s.novelTapToPage = v,
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(tr('翻页动画')),
                      value: s.novelAnimate,
                      onChanged: (v) => s.novelAnimate = v,
                    ),
                    choices(tr('屏幕方向'), s.novelOrientation, {
                      'auto': '自动',
                      'portrait': '竖屏',
                      'landscape': '横屏',
                    }, (v) => s.novelOrientation = v),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
