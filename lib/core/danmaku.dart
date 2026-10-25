import 'localization.dart';

enum DanmakuArea {
  topQuarter,
  topHalf,
  bottomHalf,
  full;

  String get label => switch (this) {
    topQuarter => tr('上方四分之一'),
    topHalf => tr('上半屏'),
    bottomHalf => tr('下半屏'),
    full => tr('全屏'),
  };

  double get fraction => switch (this) {
    topQuarter => .25,
    topHalf || bottomHalf => .5,
    full => 1,
  };
}
