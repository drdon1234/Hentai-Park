import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../core/platform_capabilities.dart';
import '../theme.dart';
import 'common.dart';

/// 桌面文件只交给当前可见路由，不让后台页面响应拖放。
class FileDropRegion extends StatefulWidget {
  const FileDropRegion({
    super.key,
    required this.onDrop,
    required this.message,
    required this.child,
    this.enabled = true,
  });
  final ValueChanged<List<DropItem>> onDrop;
  final String message;
  final Widget child;
  final bool enabled;

  @override
  State<FileDropRegion> createState() => _FileDropRegionState();
}

class _FileDropRegionState extends State<FileDropRegion> {
  bool _hovering = false;

  bool get _active =>
      widget.enabled &&
      TickerMode.valuesOf(context).enabled &&
      (ModalRoute.of(context)?.isCurrent ?? true);

  @override
  Widget build(BuildContext context) {
    if (!PlatformCapabilities.desktop) return widget.child;
    final active = _active;
    return DropTarget(
      enable: active,
      onDragEntered: (_) => setState(() => _hovering = true),
      onDragExited: (_) {
        // DropTarget 在路由覆盖它的构建过程中也会发出退出事件。
        void clear() {
          if (mounted && _hovering) setState(() => _hovering = false);
        }

        if (SchedulerBinding.instance.schedulerPhase ==
            SchedulerPhase.persistentCallbacks) {
          WidgetsBinding.instance.addPostFrameCallback((_) => clear());
        } else {
          clear();
        }
      },
      onDragDone: (details) {
        setState(() => _hovering = false);
        if (_active) widget.onDrop(details.files);
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (_hovering && active)
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(
                  color: context.colors.surfaceContainerHigh,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(Gap.page),
                      child: Text(
                        widget.message,
                        textAlign: TextAlign.center,
                        style: context.text.titleMedium,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
