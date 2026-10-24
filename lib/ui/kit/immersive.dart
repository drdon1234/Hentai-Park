import 'package:flutter/widgets.dart';

/// Pages that draw edge to edge (readers, the short-video feed) register here while they are
/// mounted, so the app stops painting its own strip under the system navigation bar and the
/// page's own background shows through instead.
abstract final class Immersive {
  static final depth = ValueNotifier<int>(0);
}

class ImmersiveRegion extends StatefulWidget {
  const ImmersiveRegion({super.key, required this.child});
  final Widget child;

  @override
  State<ImmersiveRegion> createState() => _ImmersiveRegionState();
}

class _ImmersiveRegionState extends State<ImmersiveRegion> {
  // The app root listens to the depth, so changes wait until the current frame is built.
  static void _change(int delta) {
    WidgetsBinding.instance
      ..addPostFrameCallback((_) => Immersive.depth.value += delta)
      ..scheduleFrame();
  }

  @override
  void initState() {
    super.initState();
    _change(1);
  }

  @override
  void dispose() {
    _change(-1);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
