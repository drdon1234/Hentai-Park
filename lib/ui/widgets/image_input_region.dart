import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/localization.dart';
import '../../core/platform_capabilities.dart';
import 'file_drop_region.dart';

/// 仅在当前路由接收桌面文件；输入框及选择区保留自身的粘贴行为。
class ImageInputRegion extends StatelessWidget {
  const ImageInputRegion({
    super.key,
    required this.onDrop,
    required this.onPaste,
    required this.child,
  });
  final ValueChanged<List<DropItem>> onDrop;
  final VoidCallback onPaste;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!PlatformCapabilities.desktop) return child;
    return Shortcuts(
      shortcuts: {
        const SingleActivator(LogicalKeyboardKey.keyV, control: true):
            const PasteTextIntent(SelectionChangedCause.keyboard),
      },
      child: Actions(
        actions: {
          PasteTextIntent: _ImagePasteAction(() {
            if (TickerMode.valuesOf(context).enabled &&
                (ModalRoute.of(context)?.isCurrent ?? true)) {
              onPaste();
            }
          }),
        },
        child: Focus(
          autofocus: true,
          child: FileDropRegion(
            message: tr('松开以使用这张图片反搜'),
            onDrop: onDrop,
            child: child,
          ),
        ),
      ),
    );
  }
}

class _ImagePasteAction extends Action<PasteTextIntent> {
  _ImagePasteAction(this.onPaste);
  final VoidCallback onPaste;

  @override
  Object? invoke(PasteTextIntent intent) {
    // EditableText 的动作允许祖先覆写；必须交还其默认粘贴动作。
    if (callingAction case final textAction?) return textAction.invoke(intent);
    onPaste();
    return null;
  }
}
