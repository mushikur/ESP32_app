import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/ui/app_motion.dart';

/// One complete set of brand colours. The dark and light palettes share the
/// same roles so every screen reads its colours by role, never by value.
class AppPalette {
  const AppPalette({
    required this.brightness,
    required this.background,
    required this.backgroundGlow,
    required this.surface,
    required this.elevated,
    required this.sunken,
    required this.line,
    required this.text,
    required this.muted,
    required this.cyan,
    required this.blue,
    required this.violet,
    required this.mint,
    required this.amber,
    required this.coral,
    required this.onAccent,
    required this.navigation,
    required this.shadow,
  });

  final Brightness brightness;

  /// Page background and the soft glow painted behind the top of each page.
  final Color background, backgroundGlow;

  /// Cards, raised controls, and recessed wells such as code and diagrams.
  final Color surface, elevated, sunken;
  final Color line;
  final Color text, muted;

  /// Brand accents. Cyan is primary, blue supports it, violet is used sparingly.
  final Color cyan, blue, violet;

  /// Status colours for success, caution, and failure.
  final Color mint, amber, coral;

  /// Text and icons placed on a filled accent.
  final Color onAccent;
  final Color navigation;
  final Color shadow;

  bool get isDark => brightness == Brightness.dark;

  static const dark = AppPalette(
    brightness: Brightness.dark,
    background: Color(0xFF070C17),
    backgroundGlow: Color(0xFF142644),
    surface: Color(0xFF0D1728),
    elevated: Color(0xFF14223A),
    sunken: Color(0xFF091222),
    line: Color(0xFF22324C),
    text: Color(0xFFF1F6FF),
    muted: Color(0xFFA2B4CE),
    cyan: Color(0xFF67E5F5),
    blue: Color(0xFF91B0FF),
    violet: Color(0xFFB8AAFF),
    mint: Color(0xFF83E5BE),
    amber: Color(0xFFFFCF76),
    coral: Color(0xFFFF848C),
    onAccent: Color(0xFF070C17),
    navigation: Color(0xFF0A1322),
    shadow: Color(0x66000000),
  );

  static const light = AppPalette(
    brightness: Brightness.light,
    background: Color(0xFFF3F6FB),
    backgroundGlow: Color(0xFFDDEBFB),
    surface: Color(0xFFFFFFFF),
    elevated: Color(0xFFEAF0F8),
    sunken: Color(0xFFEEF3FA),
    line: Color(0xFFD3DDEB),
    text: Color(0xFF0B1626),
    muted: Color(0xFF526480),
    cyan: Color(0xFF056B7D),
    blue: Color(0xFF2F58CC),
    violet: Color(0xFF6650CC),
    mint: Color(0xFF087453),
    amber: Color(0xFF9A6200),
    coral: Color(0xFFC2333D),
    onAccent: Color(0xFFFFFFFF),
    navigation: Color(0xFFFFFFFF),
    shadow: Color(0x1F1B2B45),
  );
}

/// Colour roles for the palette currently on screen.
///
/// [AppPaletteScope] switches the palette and rebuilds the tree, so widgets and
/// painters can read these at build or paint time.
abstract final class AppColors {
  static AppPalette _palette = AppPalette.dark;
  static AppPalette get palette => _palette;

  static Color get background => _palette.background;
  static Color get backgroundGlow => _palette.backgroundGlow;
  static Color get surface => _palette.surface;
  static Color get elevated => _palette.elevated;
  static Color get sunken => _palette.sunken;
  static Color get line => _palette.line;
  static Color get text => _palette.text;
  static Color get muted => _palette.muted;
  static Color get cyan => _palette.cyan;
  static Color get blue => _palette.blue;
  static Color get violet => _palette.violet;
  static Color get mint => _palette.mint;
  static Color get amber => _palette.amber;
  static Color get coral => _palette.coral;
  static Color get onAccent => _palette.onAccent;
  static Color get navigation => _palette.navigation;
  static Color get shadow => _palette.shadow;
  static bool get isDark => _palette.isDark;

  /// [accent] washed over the card surface, for selected and tinted fills.
  static Color tint(Color accent, [double strength = .14]) =>
      Color.alphaBlend(accent.withValues(alpha: strength), _palette.surface);

  /// A border that belongs to a [tint] fill.
  static Color tintLine(Color accent, [double strength = .34]) =>
      Color.alphaBlend(accent.withValues(alpha: strength), _palette.surface);
}

/// Shared geometry so corners and gaps stay consistent between screens.
abstract final class AppShape {
  static const double control = 14;
  static const double card = 20;
  static const double hero = 26;
  static const double well = 16;
}

abstract final class AppTheme {
  static SystemUiOverlayStyle get overlays => overlaysFor(AppColors.palette);

  static SystemUiOverlayStyle overlaysFor(AppPalette palette) {
    final icons = palette.isDark ? Brightness.light : Brightness.dark;
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: icons,
      statusBarBrightness: palette.brightness,
      systemNavigationBarColor: palette.navigation,
      systemNavigationBarIconBrightness: icons,
    );
  }

  static final dark = _build(AppPalette.dark);
  static final light = _build(AppPalette.light);

  static ThemeData of(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  static ThemeData _build(AppPalette p) {
    final colors =
        ColorScheme.fromSeed(
          seedColor: p.cyan,
          brightness: p.brightness,
        ).copyWith(
          primary: p.cyan,
          onPrimary: p.onAccent,
          secondary: p.violet,
          onSecondary: p.onAccent,
          surface: p.surface,
          onSurface: p.text,
          onSurfaceVariant: p.muted,
          outline: p.line,
          outlineVariant: p.line,
          error: p.coral,
          surfaceContainerHighest: p.elevated,
          surfaceContainerHigh: p.elevated,
          surfaceContainer: p.surface,
          surfaceContainerLow: p.surface,
          secondaryContainer: Color.alphaBlend(
            p.cyan.withValues(alpha: p.isDark ? .18 : .14),
            p.surface,
          ),
          onSecondaryContainer: p.text,
        );
    final control = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppShape.control),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colors,
      scaffoldBackgroundColor: p.background,
      dividerColor: p.line,
      splashFactory: InkSparkle.splashFactory,
      textTheme: const TextTheme(
        displaySmall: TextStyle(
          fontSize: 40,
          height: 1.05,
          fontWeight: FontWeight.w800,
          letterSpacing: -1.6,
        ),
        headlineLarge: TextStyle(
          fontSize: 31,
          height: 1.13,
          fontWeight: FontWeight.w800,
          letterSpacing: -1.0,
        ),
        headlineMedium: TextStyle(
          fontSize: 26,
          height: 1.14,
          fontWeight: FontWeight.w800,
          letterSpacing: -.7,
        ),
        titleLarge: TextStyle(
          fontSize: 20,
          height: 1.25,
          fontWeight: FontWeight.w700,
          letterSpacing: -.3,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          height: 1.3,
          fontWeight: FontWeight.w700,
        ),
        titleSmall: TextStyle(
          fontSize: 14,
          height: 1.3,
          fontWeight: FontWeight.w700,
        ),
        bodyLarge: TextStyle(fontSize: 16, height: 1.5),
        bodyMedium: TextStyle(fontSize: 14, height: 1.45),
        bodySmall: TextStyle(fontSize: 12, height: 1.4),
        labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ).apply(bodyColor: p.text, displayColor: p.text),
      appBarTheme: AppBarTheme(
        backgroundColor: p.surface,
        foregroundColor: p.text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: overlaysFor(p),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          animationDuration: AppMotion.quick,
          minimumSize: const Size(48, 50),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: control,
          textStyle: const TextStyle(
            fontFamily: 'Roboto',
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          animationDuration: AppMotion.quick,
          minimumSize: const Size(48, 48),
          shape: control,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          animationDuration: AppMotion.quick,
          minimumSize: const Size(48, 48),
          side: BorderSide(color: p.line),
          shape: control,
        ),
      ),
      chipTheme: ChipThemeData(
        side: BorderSide(color: p.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppShape.hero),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppShape.hero),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: p.isDark ? p.elevated : const Color(0xFF14223A),
        contentTextStyle: TextStyle(
          color: p.isDark ? p.text : const Color(0xFFF1F6FF),
        ),
        actionTextColor: AppPalette.dark.cyan,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}

/// The user's appearance choice. [ThemeMode.system] follows Android.
final themeModeProvider = NotifierProvider<ThemeModeSetting, ThemeMode>(
  ThemeModeSetting.new,
);

class ThemeModeSetting extends Notifier<ThemeMode> {
  static const _key = 'esp_iot_theme_mode';
  bool _chosen = false;

  @override
  ThemeMode build() {
    _restore();
    return ThemeMode.dark;
  }

  Future<void> _restore() async {
    try {
      final saved = await SharedPreferencesAsync().getString(_key);
      final mode = ThemeMode.values.where((mode) => mode.name == saved);
      if (ref.mounted && !_chosen && mode.isNotEmpty) state = mode.first;
    } on Object {
      // The default appearance stays in place when preferences are unreadable.
    }
  }

  Future<void> choose(ThemeMode mode) async {
    _chosen = true;
    state = mode;
    try {
      await SharedPreferencesAsync().setString(_key, mode.name);
    } on Object {
      // The choice still applies for this session.
    }
  }
}

/// Applies [palette] to [AppColors] and refreshes everything below it.
///
/// Widgets read colours through static getters, so a palette change has to
/// rebuild and repaint the subtree explicitly. Element state is kept.
class AppPaletteScope extends StatefulWidget {
  const AppPaletteScope({
    required this.palette,
    required this.child,
    super.key,
  });

  final AppPalette palette;
  final Widget child;

  @override
  State<AppPaletteScope> createState() => _AppPaletteScopeState();
}

class _AppPaletteScopeState extends State<AppPaletteScope> {
  bool _refreshScheduled = false;

  @override
  void initState() {
    super.initState();
    AppColors._palette = widget.palette;
  }

  @override
  void didUpdateWidget(covariant AppPaletteScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.palette, widget.palette)) {
      AppColors._palette = widget.palette;
      if (_refreshScheduled) return;
      _refreshScheduled = true;
      // Refresh the existing elements after Flutter unlocks the build tree.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _refreshScheduled = false;
        if (mounted) context.visitChildElements(_refresh);
      });
    }
  }

  static void _refresh(Element element) {
    element.markNeedsBuild();
    final render = element.renderObject;
    if (render != null && render.attached) render.markNeedsPaint();
    element.visitChildren(_refresh);
  }

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: AppTheme.overlaysFor(widget.palette),
    child: widget.child,
  );
}
