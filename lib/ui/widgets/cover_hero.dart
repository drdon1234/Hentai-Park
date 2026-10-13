import 'package:flutter/material.dart';

/// 封面只与发起导航的入口配对；飞行时保持两端解码尺寸并渐变换图。
class CoverHero extends StatelessWidget {
  const CoverHero({super.key, required this.tag, required this.child});

  final Object? tag;
  final Widget child;

  @override
  Widget build(BuildContext context) => tag == null
      ? child
      : Hero(tag: tag!, flightShuttleBuilder: _flight, child: child);

  static Widget _flight(
    BuildContext context,
    Animation<double> animation,
    HeroFlightDirection direction,
    BuildContext fromContext,
    BuildContext toContext,
  ) {
    final from = fromContext.widget as Hero;
    final to = toContext.widget as Hero;
    Widget endpoint(BuildContext context, Widget child) => FittedBox(
      fit: BoxFit.cover,
      child: SizedBox.fromSize(
        size: (context.findRenderObject()! as RenderBox).size,
        child: child,
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        fit: StackFit.expand,
        children: [
          endpoint(fromContext, from.child),
          FadeTransition(
            opacity: direction == HeroFlightDirection.push
                ? animation
                : ReverseAnimation(animation),
            child: endpoint(toContext, to.child),
          ),
        ],
      ),
    );
  }
}
