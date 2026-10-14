import 'package:flutter/material.dart';

/// Spacing scale. Pages use [page] as their horizontal margin.
abstract final class Gap {
  static const double xs = 4;
  static const double s = 8;
  static const double m = 12;
  static const double l = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double page = l;
}

/// Corner radii: covers and controls, panels, bottom sheets and dialogs.
abstract final class Radii {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 20;

  static const small = BorderRadius.all(Radius.circular(sm));
  static const medium = BorderRadius.all(Radius.circular(md));
  static const large = BorderRadius.all(Radius.circular(lg));
}

/// Short, meaningful motion; [of] honours the system "remove animations" setting.
abstract final class Motion {
  static const short = Duration(milliseconds: 150);
  static const medium = Duration(milliseconds: 250);
  static const curve = Curves.easeOutCubic;

  static Duration of(BuildContext context, Duration duration) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;
}

/// Reading surfaces chosen by the reader, independent of the app theme.
abstract final class ReaderPalette {
  static const Color gray = Color(0xFF303030);

  /// Night-light overlay; its strength is a reader setting.
  static const Color warm = Color(0xFFFF9800);

  /// Novel themes as (background, text).
  static const novel = <String, (Color, Color)>{
    'paper': (Color(0xFFF2E8D3), Color(0xFF3E352B)),
    'white': (Color(0xFFFFFFFF), Color(0xFF252525)),
    'green': (Color(0xFFCCE2CB), Color(0xFF243429)),
    'dark': (Color(0xFF191919), Color(0xFFBCB7AD)),
  };
}

/// Colors that are not part of [ColorScheme]: overlays drawn on top of images.
abstract final class Scrims {
  static const Color strong = Color(0xB3000000);
  static const Color medium = Color(0x80000000);
  static const Color soft = Color(0x4D000000);
  static const Color onScrim = Color(0xFFFFFFFF);
}
