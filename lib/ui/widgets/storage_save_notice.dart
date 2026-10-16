import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../../core/storage.dart';

/// 持久化失败持续可见，成功落盘后自动移除；不展示文件名或账号数据。
class StorageSaveNotice extends StatelessWidget {
  const StorageSaveNotice({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      child,
      Align(
        alignment: Alignment.topCenter,
        child: ValueListenableBuilder<int>(
          valueListenable: JsonStore.failedWrites,
          builder: (context, count, _) => count == 0
              ? const SizedBox.shrink()
              : Material(
                  child: SafeArea(
                    bottom: false,
                    child: MaterialBanner(
                      content: Text(tr('部分更改尚未保存，请检查存储空间和访问权限。应用会自动重试。')),
                      actions: [
                        TextButton(
                          onPressed: JsonStore.retryFailed,
                          child: SelectionContainer.disabled(
                            child: Text(tr('重试')),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    ],
  );
}
