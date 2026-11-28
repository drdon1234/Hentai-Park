import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/localization.dart';
import '../core/platform_capabilities.dart';
import '../engine/platform_bridge.dart';
import 'kit/tokens.dart';

/// 桌面只对进入的页面做短淡入，避免移动整张工作区。
class DesktopPageTransitionsBuilder extends PageTransitionsBuilder {
  const DesktopPageTransitionsBuilder();

  @override
  Duration get transitionDuration => Motion.short;

  @override
  Duration get reverseTransitionDuration => Motion.short;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    // 桌面只淡入新内容，不让两个大型页面同时平移、缩放与混合。
    return FadeTransition(opacity: animation, child: child);
  }
}

/// The app's visual language (docs/DESIGN.md): warm neutral surfaces so covers carry the color,
/// dark first, one accent reserved for primary actions, progress, unread and selection, hairlines
/// instead of shadows, and weights no heavier than 600.
class ParkTheme {
  /// Default accent: warm terracotta. The dark theme uses a slightly lighter tone.
  static const defaultAccent = 0xFFC96442;

  static Map<int, String> get accents => <int, String>{
    defaultAccent: tr('陶土'),
    0xFFB8862F: tr('琥珀'),
    0xFF5F8A62: tr('青苔'),
    0xFF4F6FB8: tr('靛蓝'),
    0xFF8A5C9E: tr('梅紫'),
    0xFFC25878: tr('樱粉'),
  };

  static final _cache =
      <(Brightness, int, TargetPlatform, String), ThemeData>{};

  /// Themes are cached; rebuilding the app never recomputes them.
  static ThemeData of(Brightness brightness, Color accent) =>
      _cache.putIfAbsent((
        brightness,
        accent.toARGB32(),
        defaultTargetPlatform,
        AppLocalizations.localeKey(AppLocalizations.instance.locale),
      ), () => _build(brightness, accent));

  static SystemUiOverlayStyle overlayStyle(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final icons = dark ? Brightness.light : Brightness.dark;
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: icons,
      statusBarBrightness: brightness,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
      systemNavigationBarIconBrightness: icons,
    );
  }

  /// Background of the navigation bar and of the strip under the system navigation bar.
  static Color navigationColor(ColorScheme scheme) => scheme.surface;

  static ColorScheme scheme(Brightness brightness, Color accent) {
    final dark = brightness == Brightness.dark;
    final ink = dark ? const Color(0xFFECE9E3) : const Color(0xFF1F1E1C);
    var primary = accent;
    if (dark) {
      primary = accent.toARGB32() == defaultAccent
          ? const Color(0xFFD97757)
          : _lighten(accent, .08);
    }
    // 强调色同时用于表面上的小字号文字，不能只检查实心按钮的前景色。
    final textSurface = dark
        ? const Color(0xFF34322E)
        : const Color(0xFFDCD8D0);
    for (var i = 0; i < 100 && _contrast(primary, textSurface) < 4.5; i++) {
      primary = _lighten(primary, dark ? .01 : -.01);
    }
    // Labels on filled accent buttons must reach WCAG AA (4.5:1) for any accent.
    const white = Color(0xFFFFFFFF);
    const deep = Color(0xFF1A1714);
    final onPrimary = _contrast(white, primary) >= _contrast(deep, primary)
        ? white
        : deep;
    for (var i = 0; i < 20 && _contrast(onPrimary, primary) < 4.5; i++) {
      primary = onPrimary == white
          ? _lighten(primary, -.02)
          : _lighten(primary, .02);
    }
    if (dark) {
      return ColorScheme(
        brightness: brightness,
        primary: primary,
        onPrimary: onPrimary,
        primaryContainer: Color.alphaBlend(
          primary.withValues(alpha: .18),
          const Color(0xFF11100F),
        ),
        onPrimaryContainer: _lighten(primary, .18),
        secondary: const Color(0xFFBFB9AE),
        onSecondary: const Color(0xFF1C1B19),
        secondaryContainer: Color.alphaBlend(
          primary.withValues(alpha: .16),
          const Color(0xFF1C1B19),
        ),
        onSecondaryContainer: _lighten(primary, .16),
        tertiary: const Color(0xFFD9D4CA),
        onTertiary: const Color(0xFF1C1B19),
        tertiaryContainer: const Color(0xFF2E2C29),
        onTertiaryContainer: ink,
        error: const Color(0xFFF08A84),
        onError: const Color(0xFF2B0B09),
        errorContainer: const Color(0xFF4A1F1C),
        onErrorContainer: const Color(0xFFFFDAD6),
        surface: const Color(0xFF11100F),
        onSurface: ink,
        onSurfaceVariant: const Color(0xFFA39E94),
        surfaceDim: const Color(0xFF0D0C0B),
        surfaceBright: const Color(0xFF34322E),
        surfaceContainerLowest: const Color(0xFF0B0A09),
        surfaceContainerLow: const Color(0xFF181715),
        surfaceContainer: const Color(0xFF1E1D1A),
        surfaceContainerHigh: const Color(0xFF272522),
        surfaceContainerHighest: const Color(0xFF312F2B),
        outline: const Color(0xFF827C72),
        outlineVariant: const Color(0xFF34322E),
        shadow: Colors.black,
        scrim: Colors.black,
        inverseSurface: const Color(0xFFECE9E3),
        onInverseSurface: const Color(0xFF1F1E1C),
        inversePrimary: accent,
        surfaceTint: Colors.transparent,
      );
    }
    return ColorScheme(
      brightness: brightness,
      primary: primary,
      onPrimary: onPrimary,
      primaryContainer: Color.alphaBlend(
        primary.withValues(alpha: .12),
        const Color(0xFFF5F3EF),
      ),
      onPrimaryContainer: _lighten(primary, -.16),
      secondary: const Color(0xFF5E5A53),
      onSecondary: Colors.white,
      secondaryContainer: Color.alphaBlend(
        primary.withValues(alpha: .12),
        const Color(0xFFF5F3EF),
      ),
      onSecondaryContainer: _lighten(primary, -.14),
      tertiary: const Color(0xFF3A3834),
      onTertiary: const Color(0xFFFAF9F6),
      tertiaryContainer: const Color(0xFFE9E6DF),
      onTertiaryContainer: ink,
      error: const Color(0xFFB3261E),
      onError: Colors.white,
      errorContainer: const Color(0xFFF9DEDC),
      onErrorContainer: const Color(0xFF410E0B),
      surface: const Color(0xFFF5F3EF),
      onSurface: ink,
      onSurfaceVariant: const Color(0xFF625E57),
      surfaceDim: const Color(0xFFDCD8D0),
      surfaceBright: const Color(0xFFFFFFFF),
      surfaceContainerLowest: const Color(0xFFFFFFFF),
      surfaceContainerLow: const Color(0xFFEFEDE8),
      surfaceContainer: const Color(0xFFEAE7E1),
      surfaceContainerHigh: const Color(0xFFE4E1DA),
      surfaceContainerHighest: const Color(0xFFDCD8D0),
      outline: const Color(0xFF827C72),
      outlineVariant: const Color(0xFFE0DCD4),
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: const Color(0xFF2B2926),
      onInverseSurface: const Color(0xFFF2EFE9),
      inversePrimary: const Color(0xFFD97757),
      surfaceTint: Colors.transparent,
    );
  }

  static ThemeData _build(Brightness brightness, Color accent) {
    final desktop = PlatformCapabilities.desktop;
    final dark = brightness == Brightness.dark;
    final scheme = ParkTheme.scheme(brightness, accent);
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
      splashFactory: desktop ? NoSplash.splashFactory : InkRipple.splashFactory,
      materialTapTargetSize: desktop
          ? MaterialTapTargetSize.shrinkWrap
          : MaterialTapTargetSize.padded,
      visualDensity: desktop ? VisualDensity.compact : VisualDensity.standard,
      fontFamily: ParkText.sansFamily,
      fontFamilyFallback: ParkText.sansFallback,
    );
    final text = _text(base.textTheme, scheme);
    final card = dark ? scheme.surfaceContainer : scheme.surfaceContainerLowest;
    final raised = dark
        ? scheme.surfaceContainerHigh
        : scheme.surfaceContainerLowest;
    final tonal = dark
        ? scheme.surfaceContainerHighest
        : scheme.surfaceContainerHigh;
    final hairline = BorderSide(color: scheme.outlineVariant, width: .8);
    final OutlinedBorder pill = desktop
        ? const RoundedRectangleBorder(borderRadius: Radii.tiny)
        : const StadiumBorder();
    final selectedTint = scheme.secondaryContainer;
    final focusRing = BorderSide(color: scheme.primary, width: 2);
    final label = text.labelLarge?.copyWith(fontWeight: FontWeight.w600);
    final menuShadow = Colors.black.withValues(alpha: dark ? .5 : .16);
    return base.copyWith(
      textTheme: text,
      scaffoldBackgroundColor: scheme.surface,
      canvasColor: scheme.surface,
      cardColor: card,
      dividerColor: scheme.outlineVariant,
      hoverColor: scheme.onSurface.withValues(alpha: .05),
      focusColor: scheme.onSurface.withValues(alpha: .08),
      appBarTheme: AppBarTheme(
        toolbarHeight: desktop ? 48 : null,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: Gap.page,
        actionsPadding: const EdgeInsetsDirectional.only(end: Gap.page),
        titleTextStyle: text.titleLarge?.copyWith(color: scheme.onSurface),
        systemOverlayStyle: overlayStyle(brightness),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: navigationColor(scheme),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        indicatorColor: selectedTint,
        indicatorShape: const StadiumBorder(),
        height: 68,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 24,
            color: states.contains(WidgetState.selected)
                ? scheme.onSecondaryContainer
                : scheme.onSurfaceVariant,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => text.labelMedium?.copyWith(
            color: states.contains(WidgetState.selected)
                ? scheme.onSurface
                : scheme.onSurfaceVariant,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w500,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: navigationColor(scheme),
        indicatorColor: selectedTint,
        indicatorShape: const StadiumBorder(),
        selectedIconTheme: IconThemeData(color: scheme.onSecondaryContainer),
        unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
        selectedLabelTextStyle: text.labelMedium?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelTextStyle: text.labelMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(borderRadius: Radii.medium),
        clipBehavior: Clip.antiAlias,
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: .8,
        space: 1,
      ),
      // 筛选项是胶囊：未选中为浅色填充，选中换成强调色调与强调色文字；两种状态都不画边框，
      // 切换时尺寸不变。
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: tonal,
        selectedColor: selectedTint,
        disabledColor: tonal.withValues(alpha: .5),
        showCheckmark: false,
        shape: pill,
        side: WidgetStateBorderSide.resolveWith(
          (states) => states.contains(WidgetState.focused)
              ? focusRing.copyWith(strokeAlign: BorderSide.strokeAlignInside)
              : BorderSide.none,
        ),
        labelStyle: text.labelLarge?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w500,
        ),
        secondaryLabelStyle: text.labelLarge?.copyWith(
          color: scheme.onSecondaryContainer,
          fontWeight: FontWeight.w600,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: Gap.s,
          vertical: Gap.xs,
        ),
        labelPadding: const EdgeInsets.symmetric(horizontal: Gap.xs),
        iconTheme: IconThemeData(size: 18, color: scheme.onSurfaceVariant),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: tonal,
        hintStyle: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
        border: const OutlineInputBorder(
          borderRadius: Radii.medium,
          borderSide: BorderSide.none,
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: Radii.medium,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: Radii.medium,
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: Radii.medium,
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: Radii.medium,
          borderSide: BorderSide(color: scheme.error, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Gap.l,
          vertical: Gap.m + 2,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: pill,
          textStyle: label,
          minimumSize: Size(64, desktop ? 36 : 48),
          padding: const EdgeInsets.symmetric(horizontal: Gap.xl),
        ).copyWith(side: _focusSide(scheme.onSurface)),
      ),
      // 次级按钮是浅色填充的胶囊，靠底色而不是描边形成边界；键盘焦点加强调色描边。
      outlinedButtonTheme: OutlinedButtonThemeData(
        style:
            OutlinedButton.styleFrom(
              foregroundColor: scheme.onSurface,
              backgroundColor: tonal,
              disabledBackgroundColor: tonal.withValues(alpha: .45),
              disabledForegroundColor: scheme.onSurface.withValues(alpha: .38),
              shape: pill,
              textStyle: label,
              minimumSize: Size(48, desktop ? 36 : 48),
              padding: const EdgeInsets.symmetric(horizontal: Gap.l),
            ).copyWith(
              side: WidgetStateBorderSide.resolveWith(
                (states) => states.contains(WidgetState.focused)
                    ? focusRing
                    : BorderSide.none,
              ),
            ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: Size(48, desktop ? 36 : 48),
          foregroundColor: scheme.primary,
          shape: pill,
          padding: const EdgeInsets.symmetric(horizontal: Gap.m),
          textStyle: label,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: scheme.onSurface,
          minimumSize: Size.square(desktop ? 36 : 48),
          shape: desktop
              ? const RoundedRectangleBorder(borderRadius: Radii.tiny)
              : null,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          foregroundColor: scheme.onSurface,
          selectedBackgroundColor: selectedTint,
          selectedForegroundColor: scheme.onSecondaryContainer,
          backgroundColor: tonal,
          // 分段是一条浅色轨道，选中段用强调色调填充；不画描边和分隔线。
          side: BorderSide.none,
          shape: pill,
          textStyle: text.labelLarge,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 2,
        highlightElevation: 3,
        focusElevation: 2,
        hoverElevation: 3,
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        shape: const RoundedRectangleBorder(borderRadius: Radii.medium),
        extendedTextStyle: label,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: raised,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: raised,
        modalBarrierColor: Scrims.medium,
        elevation: 0,
        modalElevation: 0,
        showDragHandle: true,
        dragHandleColor: scheme.outline,
        dragHandleSize: const Size(36, 4),
        clipBehavior: Clip.antiAlias,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.lg)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: raised,
        surfaceTintColor: Colors.transparent,
        barrierColor: Scrims.medium,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: desktop ? Radii.small : Radii.large,
        ),
        titleTextStyle: text.titleLarge?.copyWith(color: scheme.onSurface),
        contentTextStyle: text.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: raised,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shadowColor: menuShadow,
        shape: RoundedRectangleBorder(
          borderRadius: Radii.medium,
          side: dark ? hairline : BorderSide.none,
        ),
        textStyle: text.bodyLarge,
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(raised),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(6),
          shadowColor: WidgetStatePropertyAll(menuShadow),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(vertical: Gap.xs + 2),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: Radii.medium,
              side: dark ? hairline : BorderSide.none,
            ),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: text.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
        actionTextColor: scheme.inversePrimary,
        elevation: 0,
        insetPadding: const EdgeInsets.fromLTRB(
          Gap.page,
          Gap.s,
          Gap.page,
          Gap.m,
        ),
        shape: const RoundedRectangleBorder(borderRadius: Radii.medium),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: Gap.page),
        iconColor: scheme.onSurfaceVariant,
        titleTextStyle: text.bodyLarge?.copyWith(color: scheme.onSurface),
        subtitleTextStyle: text.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        selectedColor: scheme.onSecondaryContainer,
        selectedTileColor: selectedTint,
      ),
      expansionTileTheme: ExpansionTileThemeData(
        shape: const Border(),
        collapsedShape: const Border(),
        iconColor: scheme.onSurfaceVariant,
        collapsedIconColor: scheme.onSurfaceVariant,
        tilePadding: const EdgeInsets.symmetric(horizontal: Gap.page),
      ),
      tabBarTheme: TabBarThemeData(
        dividerColor: scheme.outlineVariant,
        dividerHeight: .8,
        indicatorSize: TabBarIndicatorSize.label,
        indicator: UnderlineTabIndicator(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
          borderSide: BorderSide(color: scheme.primary, width: 3),
        ),
        labelColor: scheme.onSurface,
        unselectedLabelColor: scheme.onSurfaceVariant,
        labelStyle: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        unselectedLabelStyle: text.titleSmall?.copyWith(
          fontWeight: FontWeight.w500,
        ),
        tabAlignment: TabAlignment.start,
      ),
      badgeTheme: BadgeThemeData(
        backgroundColor: scheme.primary,
        textColor: scheme.onPrimary,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHighest,
        circularTrackColor: Colors.transparent,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: scheme.primary,
        inactiveTrackColor: scheme.surfaceContainerHighest,
        thumbColor: scheme.primary,
        overlayColor: scheme.primary.withValues(alpha: .12),
        valueIndicatorColor: scheme.inverseSurface,
        valueIndicatorTextStyle: text.labelMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
      ),
      switchTheme: SwitchThemeData(
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.transparent
              : scheme.outline,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(5)),
        ),
        side: BorderSide(color: scheme.outline, width: 1.6),
      ),
      scrollbarTheme: ScrollbarThemeData(
        radius: const Radius.circular(4),
        thickness: const WidgetStatePropertyAll(6),
        thumbColor: WidgetStatePropertyAll(
          scheme.onSurfaceVariant.withValues(alpha: .4),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: Radii.small,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: Gap.s + 2,
          vertical: Gap.xs + 2,
        ),
        textStyle: text.bodySmall?.copyWith(color: scheme.onInverseSurface),
        waitDuration: const Duration(milliseconds: 400),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
        },
      ),
    );
  }

  /// Keyboard focus draws a ring around filled buttons; other states keep their own fill.
  static WidgetStateBorderSide _focusSide(Color color) =>
      WidgetStateBorderSide.resolveWith(
        (states) => states.contains(WidgetState.focused)
            ? BorderSide(color: color, width: 2)
            : BorderSide.none,
      );

  /// Material 3 type scale with weights capped at 600. [ParkText.display] marks titles
  /// that need to stand out.
  static TextTheme _text(TextTheme base, ColorScheme scheme) {
    TextStyle? cap(TextStyle? style, FontWeight weight) =>
        style?.copyWith(fontWeight: weight);
    if (ParkText.ios) base = ParkText.appleTracking(base);
    return base
        .copyWith(
          headlineLarge: cap(base.headlineLarge, FontWeight.w500),
          headlineMedium: cap(base.headlineMedium, FontWeight.w500),
          headlineSmall: cap(base.headlineSmall, FontWeight.w500),
          titleLarge: cap(base.titleLarge, FontWeight.w600),
          titleMedium: cap(base.titleMedium, FontWeight.w600),
          titleSmall: cap(base.titleSmall, FontWeight.w600),
          labelLarge: cap(base.labelLarge, FontWeight.w500),
          labelMedium: cap(base.labelMedium, FontWeight.w500),
          labelSmall: cap(base.labelSmall, FontWeight.w500),
        )
        .apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);
  }

  static Color _lighten(Color color, double amount) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness((hsl.lightness + amount).clamp(0.0, 1.0))
        .toColor();
  }

  static double _contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    return (math.max(la, lb) + .05) / (math.min(la, lb) + .05);
  }
}

/// The reading voice: page titles, work titles and novel text.
abstract final class ParkText {
  static String get _script => switch (AppLocalizations.instance.locale) {
    Locale(languageCode: 'ja') => 'JP',
    Locale(languageCode: 'ko') => 'KR',
    Locale(languageCode: 'zh', scriptCode: 'Hant') => 'TC',
    _ => 'SC',
  };

  static bool get ios => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  static bool get _ios => ios;

  /// iOS 系统字体（SF Pro）随字号变化的字距（Apple 人机界面指南），替换 Material 3 的正字距，
  /// 与原生应用一致；字号之间线性插值。
  static const _tracking = <(double, double)>[
    (11, .06),
    (12, 0),
    (13, -.08),
    (14, -.15),
    (15, -.23),
    (16, -.31),
    (17, -.43),
    (18, -.44),
    (19, -.45),
    (20, -.45),
    (21, -.36),
    (22, -.26),
    (24, .07),
    (26, .22),
    (28, .38),
    (30, .40),
    (32, .41),
    (34, .40),
    (36, .37),
    (40, .37),
    (48, .35),
    (56, .33),
    (64, .30),
  ];

  static double trackingFor(double size) {
    if (size <= _tracking.first.$1) return _tracking.first.$2;
    for (var i = 1; i < _tracking.length; i++) {
      final (s1, t1) = _tracking[i];
      if (size <= s1) {
        final (s0, t0) = _tracking[i - 1];
        return t0 + (t1 - t0) * (size - s0) / (s1 - s0);
      }
    }
    return _tracking.last.$2;
  }

  /// 主题文字此时只有颜色与字体，字号来自之后按语言合并的 Material 3 字号几何；
  /// 这里按同一套字号写入字距，合并时主题的字距优先于几何默认值。
  static TextTheme appleTracking(TextTheme theme) {
    final geometry = Typography.englishLike2021;
    TextStyle? track(TextStyle? style, TextStyle? sized) {
      final size = style?.fontSize ?? sized?.fontSize;
      return size == null
          ? style
          : (style ?? const TextStyle()).copyWith(
              letterSpacing: trackingFor(size),
            );
    }

    return theme.copyWith(
      displayLarge: track(theme.displayLarge, geometry.displayLarge),
      displayMedium: track(theme.displayMedium, geometry.displayMedium),
      displaySmall: track(theme.displaySmall, geometry.displaySmall),
      headlineLarge: track(theme.headlineLarge, geometry.headlineLarge),
      headlineMedium: track(theme.headlineMedium, geometry.headlineMedium),
      headlineSmall: track(theme.headlineSmall, geometry.headlineSmall),
      titleLarge: track(theme.titleLarge, geometry.titleLarge),
      titleMedium: track(theme.titleMedium, geometry.titleMedium),
      titleSmall: track(theme.titleSmall, geometry.titleSmall),
      bodyLarge: track(theme.bodyLarge, geometry.bodyLarge),
      bodyMedium: track(theme.bodyMedium, geometry.bodyMedium),
      bodySmall: track(theme.bodySmall, geometry.bodySmall),
      labelLarge: track(theme.labelLarge, geometry.labelLarge),
      labelMedium: track(theme.labelMedium, geometry.labelMedium),
      labelSmall: track(theme.labelSmall, geometry.labelSmall),
    );
  }

  /// iOS 预装的中文无衬线字体（苹方）；日文、韩文沿用各自的系统字体。
  static String? get _iosSans => switch (_script) {
    'SC' => 'PingFang SC',
    'TC' => 'PingFang TC',
    _ => null,
  };

  /// iOS 中文衬线字体（宋体）的 PostScript 名，由系统按需下载；
  /// 日文明朝体预装，韩文沿用原有回退。
  static List<String> get _iosSerifFaces => switch (_script) {
    'SC' => const ['STSongti-SC-Regular', 'STSongti-SC-Bold'],
    'TC' => const ['STSongti-TC-Regular', 'STSongti-TC-Bold'],
    _ => const [],
  };

  /// 已激活宋体的书写系统（仅小说正文的衬线选项使用）；未激活前中文衬线整体使用苹方，不与日文明朝体逐字混排。
  static final _activeSerif = ValueNotifier<String?>(null);

  /// 按当前界面语言激活 iOS 中文宋体；已下载时立即完成，首次使用时下载后整体切换。
  static bool _watchingLocale = false;

  static Future<void> activateSystemFonts() async {
    if (!_ios) return;
    if (!_watchingLocale) {
      _watchingLocale = true;
      AppLocalizations.instance.addListener(activateSystemFonts);
    }
    final script = _script;
    final faces = _iosSerifFaces;
    if (faces.isEmpty || _activeSerif.value == script) return;
    if (!await PlatformBridge.activateSystemFont(faces)) return;
    if (_script != script) return;
    _activeSerif.value = script;
    // 衬线样式在各处构建时读取，字体就绪后整树重建一次以换用新字体（不重建状态）。
    void rebuild(Element element) {
      element.markNeedsBuild();
      element.visitChildren(rebuild);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(rebuild);
  }

  /// 直接选择具有 CJK 字形的字体，避免拉丁字体逐字回退造成笔画混杂。
  /// Android 保留平台原有选择。
  static String? get sansFamily => !PlatformCapabilities.desktop
      ? null
      : switch (_script) {
          'JP' => 'Yu Gothic UI',
          'KR' => 'Malgun Gothic',
          'TC' => 'Microsoft JhengHei',
          _ => 'Microsoft YaHei',
        };

  static List<String>? get sansFallback => !PlatformCapabilities.desktop
      ? (_ios && _iosSans != null ? [_iosSans!] : null)
      : [
          'Noto Sans CJK $_script',
          'Noto Sans $_script',
          'Microsoft YaHei',
          'Noto Sans CJK SC',
          'sans-serif',
        ];

  static String get serifFamily => _ios && _iosSans != null
      ? (_activeSerif.value == _script
            ? (_script == 'TC' ? 'Songti TC' : 'Songti SC')
            : _iosSans!)
      : !PlatformCapabilities.desktop
      ? 'serif'
      : switch (_script) {
          'JP' => 'Yu Mincho',
          'KR' => 'Batang',
          'TC' => 'PMingLiU',
          _ => 'SimSun',
        };

  static List<String> get serifFallback => _ios && _iosSans != null
      ? [_iosSans!]
      : [
          'Noto Serif CJK $_script',
          'Noto Serif $_script',
          if (PlatformCapabilities.desktop) 'SimSun',
          switch (_script) {
            'JP' => 'Hiragino Mincho ProN',
            'KR' => 'AppleMyungjo',
            'TC' => 'Songti TC',
            _ => 'Songti SC',
          },
          'Songti SC',
          'Songti TC',
          'STSong',
          'Hiragino Mincho ProN',
          'AppleMyungjo',
          'Noto Serif CJK SC',
          'Noto Serif CJK TC',
          'Noto Serif CJK JP',
          'Noto Serif CJK KR',
          'Source Han Serif',
          'serif',
        ];

  /// 标题、作品名等需要醒目的文字：使用系统无衬线字体，标题级字号（≥ 20）至少 600 字重。
  static TextStyle? display(TextStyle? style) {
    if (style == null) return null;
    final weight = style.fontWeight ?? FontWeight.w400;
    final size = style.fontSize ?? 14;
    return style.copyWith(
      fontFamily: sansFamily,
      fontFamilyFallback: sansFallback,
      fontWeight: size >= 20 && weight.value < 600 ? FontWeight.w600 : weight,
    );
  }

  /// Logs, cookies and checksums.
  static TextStyle? mono(TextStyle? style) => style?.copyWith(
    // iOS 没有 monospace 通用字体名，使用系统预装的 Menlo。
    fontFamily: _ios ? 'Menlo' : 'monospace',
    fontFamilyFallback: sansFallback,
    letterSpacing: _ios ? 0 : null,
  );

  /// Novel body text; every value comes from the reader's own settings.
  static TextStyle novel({
    required double size,
    required double height,
    required double letterSpacing,
    required Color color,
    required bool bold,
    required String font,
  }) => TextStyle(
    fontSize: size,
    height: height,
    letterSpacing: letterSpacing,
    color: color,
    fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
    fontFamily: switch (font) {
      'system' => sansFamily,
      'serif' => serifFamily,
      _ => font,
    },
    fontFamilyFallback: font == 'serif' ? serifFallback : sansFallback,
  );
}

extension ContextX on BuildContext {
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;

  void toast(String message, {SnackBarAction? action}) {
    ScaffoldMessenger.of(this)
      ..removeCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          action: action,
          duration: const Duration(seconds: 3),
        ),
      );
  }
}

String formatCount(int? n) {
  if (n == null) return '';
  final language = AppLocalizations.instance.locale.languageCode;
  if (const {'zh', 'ja', 'ko'}.contains(language)) {
    if (n >= 100000000) {
      return tr('{value0}亿', {'value0': (n / 100000000).toStringAsFixed(1)});
    }
    if (n >= 10000) {
      return tr('{value0}万', {
        'value0': (n / 10000).toStringAsFixed(n >= 100000 ? 0 : 1),
      });
    }
  }
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
  return '$n';
}

String formatBytes(int bytes) {
  if (bytes >= 1 << 30) return '${(bytes / (1 << 30)).toStringAsFixed(2)} GB';
  if (bytes >= 1 << 20) return '${(bytes / (1 << 20)).toStringAsFixed(1)} MB';
  if (bytes >= 1 << 10) return '${(bytes / (1 << 10)).toStringAsFixed(0)} KB';
  return '$bytes B';
}

String timeAgo(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return tr('刚刚');
  if (d.inHours < 1) return tr('{value0} 分钟前', {'value0': d.inMinutes});
  if (d.inDays < 1) return tr('{value0} 小时前', {'value0': d.inHours});
  if (d.inDays < 30) return tr('{value0} 天前', {'value0': d.inDays});
  return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
}

/// Day header for date-grouped lists: 今天 / 昨天 / 2026-10-08.
String dayLabel(DateTime t) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(t.year, t.month, t.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return tr('今天');
  if (diff == 1) return tr('昨天');
  if (diff < 7 && diff > 1) return tr('{value0} 天前', {'value0': diff});
  return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
}
