import 'package:flutter/material.dart';

/// 分集只在吸附完成后提交；未完成的拖动不改变播放会话。
class VideoEpisodePager extends StatefulWidget {
  const VideoEpisodePager({
    super.key,
    required this.index,
    required this.count,
    required this.itemBuilder,
    required this.onSettled,
    required this.onInteractionChanged,
  });
  final int index;
  final int count;
  final IndexedWidgetBuilder itemBuilder;
  final ValueChanged<int> onSettled;
  final ValueChanged<bool> onInteractionChanged;

  @override
  State<VideoEpisodePager> createState() => _VideoEpisodePagerState();
}

class _VideoEpisodePagerState extends State<VideoEpisodePager> {
  late final _pages = PageController(
    initialPage: widget.index,
    keepPage: false,
  );
  bool _scrolling = false;
  bool _selectionPending = false;

  void _syncSelection() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _scrolling || !_pages.hasClients) return;
      _selectionPending = false;
      if (_pages.page?.round() != widget.index) {
        _pages.jumpToPage(widget.index);
      }
    });
  }

  @override
  void didUpdateWidget(covariant VideoEpisodePager oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) {
      _selectionPending = true;
      _syncSelection();
    }
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.depth != 0) return false;
          if (notification is ScrollStartNotification) {
            _scrolling = true;
            widget.onInteractionChanged(true);
          } else if (notification is ScrollEndNotification) {
            _scrolling = false;
            if (_selectionPending) {
              _syncSelection();
            } else {
              final index = _pages.page?.round();
              if (index != null && index != widget.index) {
                widget.onSettled(index);
              }
            }
            widget.onInteractionChanged(false);
          }
          return false;
        },
        child: PageView.builder(
          controller: _pages,
          scrollDirection: Axis.vertical,
          itemCount: widget.count,
          itemBuilder: widget.itemBuilder,
        ),
      );
}
