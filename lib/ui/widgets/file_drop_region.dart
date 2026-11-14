import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';

/// 桌面文件只交给当前可见路由，不让后台页面响应拖放。
class FileDropRegion extends StatelessWidget {
  const FileDropRegion({
    super.key,
    required this.onDrop,
    required this.message,
    required this.child,
    this.enabled = true,
  });
  final ValueChanged<List<XFile>> onDrop;
  final String message;
  final Widget child;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return child;
  }
}
