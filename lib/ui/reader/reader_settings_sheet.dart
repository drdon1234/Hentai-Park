import 'package:flutter/material.dart';

import '../../core/settings.dart';
import 'reader_layout.dart';

/// Reader options in three tabs (Mihon's reader settings sheet). Changes apply live: the reader
/// listens to [AppSettings]. The reading mode is per work; [onMode] receives the user's choice.
Future<void> showReaderSettings(
  BuildContext context, {
  required ReaderMode mode,
  required bool modeIsOverride,
  required void Function(ReaderMode mode) onMode,
  required VoidCallback onUseDefault,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ReaderSettings(mode: mode, modeIsOverride: modeIsOverride, onMode: onMode, onUseDefault: onUseDefault),
  );
}

class _ReaderSettings extends StatefulWidget {
  const _ReaderSettings({required this.mode, required this.modeIsOverride, required this.onMode, required this.onUseDefault});
  final ReaderMode mode;
  final bool modeIsOverride;
  final void Function(ReaderMode mode) onMode;
  final VoidCallback onUseDefault;

  @override
  State<_ReaderSettings> createState() => _ReaderSettingsState();
}

class _ReaderSettingsState extends State<_ReaderSettings> {
  late ReaderMode _mode = widget.mode;
  late bool _override = widget.modeIsOverride;

  @override
  Widget build(BuildContext context) {
    final s = AppSettings.instance;
    return DefaultTabController(
      length: 3,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.6,
        child: ListenableBuilder(
          listenable: s,
          builder: (context, _) => Column(
            children: [
              const TabBar(
                tabs: [
                  Tab(text: '阅读模式'),
                  Tab(text: '通用'),
                  Tab(text: '滤镜'),
                ],
              ),
              Expanded(
                child: TabBarView(children: [_modeTab(s), _generalTab(s), _filterTab(s)]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _segmented<T>(T value, List<(T, String)> options, ValueChanged<T> onChanged) => SegmentedButton<T>(
    showSelectedIcon: false,
    segments: [for (final o in options) ButtonSegment(value: o.$1, label: Text(o.$2))],
    selected: {value},
    onSelectionChanged: (v) => onChanged(v.first),
  );

  Widget _modeTab(AppSettings s) {
    final paged = _mode != ReaderMode.vertical;
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        RadioGroup<ReaderMode>(
          groupValue: _mode,
          onChanged: (v) {
            if (v == null) return;
            setState(() {
              _mode = v;
              _override = true;
            });
            widget.onMode(v);
          },
          child: Column(
            children: [
              for (final m in ReaderMode.values) RadioListTile<ReaderMode>(value: m, secondary: Icon(m.icon), title: Text(m.label)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _override ? '仅对本作生效（默认：${s.readerMode.label}）' : '使用默认阅读模式',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              if (_override && s.readerMode != _mode) TextButton(onPressed: () => s.readerMode = _mode, child: const Text('设为默认')),
              if (_override)
                TextButton(
                  onPressed: () {
                    widget.onUseDefault();
                    setState(() {
                      _override = false;
                      _mode = s.readerMode;
                    });
                  },
                  child: const Text('跟随默认'),
                ),
            ],
          ),
        ),
        const Divider(),
        if (paged) ...[
          ListTile(
            title: const Text('双页显示'),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _segmented(s.readerDual, const [('off', '关闭'), ('landscape', '横屏时'), ('always', '总是')], (v) => s.readerDual = v),
            ),
          ),
          SwitchListTile(
            title: const Text('首页单独显示'),
            subtitle: const Text('双页时让封面独占一屏，使后续页面正确配对'),
            value: s.readerCoverSingle,
            onChanged: s.readerDual == 'off' ? null : (v) => s.readerCoverSingle = v,
          ),
          SwitchListTile(
            title: const Text('拆分宽页'),
            subtitle: const Text('单页显示时把跨页大图拆成两屏'),
            value: s.readerSplitWide,
            onChanged: (v) => s.readerSplitWide = v,
          ),
          SwitchListTile(title: const Text('翻页动画'), value: s.readerAnimate, onChanged: (v) => s.readerAnimate = v),
        ] else
          ListTile(
            title: const Text('页间距'),
            subtitle: Slider(value: s.readerGap.clamp(0, 32), min: 0, max: 32, divisions: 8, label: '${s.readerGap.round()}', onChanged: (v) => s.readerGap = v),
          ),
        SwitchListTile(title: const Text('裁剪白边'), subtitle: const Text('去掉页面四周的纯色空白'), value: s.readerCrop, onChanged: (v) => s.readerCrop = v),
      ],
    );
  }

  Widget _generalTab(AppSettings s) {
    final layout = TapLayout.values[s.readerTapLayout.clamp(0, TapLayout.values.length - 1)];
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        SwitchListTile(title: const Text('点击翻页'), value: s.tapToPage, onChanged: (v) => s.tapToPage = v),
        ListTile(
          title: const Text('点击区域'),
          enabled: s.tapToPage,
          trailing: DropdownButton<TapLayout>(
            value: layout,
            underline: const SizedBox.shrink(),
            items: [for (final l in TapLayout.values) DropdownMenuItem(value: l, child: Text(l.label))],
            onChanged: s.tapToPage ? (v) => s.readerTapLayout = (v ?? TapLayout.auto).index : null,
          ),
        ),
        SwitchListTile(title: const Text('左右反转点击区域'), value: s.readerTapInvertH, onChanged: s.tapToPage ? (v) => s.readerTapInvertH = v : null),
        SwitchListTile(title: const Text('上下反转点击区域'), value: s.readerTapInvertV, onChanged: s.tapToPage ? (v) => s.readerTapInvertV = v : null),
        SwitchListTile(title: const Text('音量键翻页'), value: s.volumeKeyPaging, onChanged: (v) => s.volumeKeyPaging = v),
        ListTile(
          title: const Text('背景颜色'),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _segmented(s.readerBackground, const [('black', '黑'), ('gray', '灰'), ('white', '白')], (v) => s.readerBackground = v),
          ),
        ),
        ListTile(
          title: const Text('屏幕方向'),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _segmented(s.readerOrientation, const [('auto', '跟随系统'), ('portrait', '竖屏'), ('landscape', '横屏')], (v) => s.readerOrientation = v),
          ),
        ),
        SwitchListTile(title: const Text('显示页码'), value: s.readerShowPageNumber, onChanged: (v) => s.readerShowPageNumber = v),
        SwitchListTile(title: const Text('保持屏幕常亮'), value: s.keepScreenOn, onChanged: (v) => s.keepScreenOn = v),
      ],
    );
  }

  Widget _filterTab(AppSettings s) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        ListTile(
          title: const Text('调暗'),
          subtitle: Slider(value: s.readerDim.clamp(0, 0.8), max: 0.8, divisions: 16, label: '${(s.readerDim * 100).round()}%', onChanged: (v) => s.readerDim = v),
        ),
        ListTile(
          title: const Text('护眼（暖色）'),
          subtitle: Slider(value: s.readerWarm.clamp(0, 0.5), max: 0.5, divisions: 10, label: '${(s.readerWarm * 200).round()}%', onChanged: (v) => s.readerWarm = v),
        ),
        SwitchListTile(title: const Text('灰度'), value: s.readerGrayscale, onChanged: (v) => s.readerGrayscale = v),
        SwitchListTile(title: const Text('反色'), value: s.readerInvert, onChanged: (v) => s.readerInvert = v),
        Center(
          child: TextButton(
            onPressed: () {
              s.readerDim = 0;
              s.readerWarm = 0;
              s.readerGrayscale = false;
              s.readerInvert = false;
            },
            child: const Text('重置滤镜'),
          ),
        ),
      ],
    );
  }
}
