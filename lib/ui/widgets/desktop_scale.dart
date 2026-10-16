import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../core/platform_capabilities.dart';
import '../../core/settings.dart';

/// 缩放整个导航与弹窗，包括布局、指针命中区域和系统字体比例。
class DesktopScale extends StatelessWidget {
  const DesktopScale({super.key, required this.child});
  final Widget child;
  static void change(int delta) {
    final settings = AppSettings.instance;
    settings.desktopScale = delta == 0 ? 100 : settings.desktopScale + delta;
  }

  @override
  Widget build(BuildContext context) {
    if (!PlatformCapabilities.desktop) return child;
    final scale = AppSettings.instance.desktopScale / 100;
    final media = MediaQuery.of(context);
    return CallbackShortcuts(
      bindings: {
        for (final modifier in [true, false]) ...{
          SingleActivator(
            LogicalKeyboardKey.equal,
            control: modifier,
            meta: !modifier,
          ): () =>
              change(10),
          SingleActivator(
            LogicalKeyboardKey.equal,
            control: modifier,
            meta: !modifier,
            shift: true,
          ): () =>
              change(10),
          SingleActivator(
            LogicalKeyboardKey.numpadAdd,
            control: modifier,
            meta: !modifier,
          ): () =>
              change(10),
          SingleActivator(
            LogicalKeyboardKey.minus,
            control: modifier,
            meta: !modifier,
          ): () =>
              change(-10),
          SingleActivator(
            LogicalKeyboardKey.numpadSubtract,
            control: modifier,
            meta: !modifier,
          ): () =>
              change(-10),
          SingleActivator(
            LogicalKeyboardKey.digit0,
            control: modifier,
            meta: !modifier,
          ): () =>
              change(0),
        },
      },
      child: _ScaleWheelRegion(
        child: LayoutBuilder(
          builder: (context, constraints) => FittedBox(
            fit: BoxFit.fill,
            child: SizedBox(
              width: constraints.maxWidth / scale,
              height: constraints.maxHeight / scale,
              child: MediaQuery(
                data: media.copyWith(
                  size: Size(
                    constraints.maxWidth / scale,
                    constraints.maxHeight / scale,
                  ),
                  devicePixelRatio: media.devicePixelRatio * scale,
                  padding: media.padding / scale,
                  viewPadding: media.viewPadding / scale,
                  viewInsets: media.viewInsets / scale,
                ),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 在子列表注册滚轮信号前处理缩放，不改变各页的滚动物理规则。
class _ScaleWheelRegion extends SingleChildRenderObjectWidget {
  const _ScaleWheelRegion({required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _ScaleWheelRenderBox();
}

class _ScaleWheelRenderBox extends RenderProxyBox {
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!size.contains(position)) return false;
    // 信号解析器采用首个注册者，必须让缩放区域先于子节点接收事件。
    result.add(BoxHitTestEntry(this, position));
    hitTestChildren(result, position: position);
    return true;
  }

  @override
  void handleEvent(PointerEvent event, HitTestEntry entry) {
    if (event is PointerScrollEvent &&
        HardwareKeyboard.instance.isControlPressed &&
        event.scrollDelta.dy != 0) {
      GestureBinding.instance.pointerSignalResolver.register(
        event,
        (_) => DesktopScale.change(event.scrollDelta.dy < 0 ? 10 : -10),
      );
    }
  }
}
