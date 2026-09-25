/// The app-level colour theme carried to every renderer.
///
/// Renderers draw the app bar, buttons and FAB in a primary colour; without a
/// theme they fall back to Material defaults. Pass an [AppTheme] to `runApp` /
/// `runNativeApp` to give them a brand palette once, instead of setting
/// `color:` on every node. The theme travels to the native renderers with the
/// `initialize` message and is applied by the web and Flutter renderers
/// directly.
///
/// A theme carries *both* appearances: its own colours are the light ones, and
/// [dark] is the dark counterpart (the built-in dark palette unless the app
/// supplies its own). [mode] says which to use, and `AppThemeMode.system`
/// leaves the choice to the device, which every renderer re-reads when the
/// device changes its mind.
library;

/// Which appearance an [AppTheme] paints.
enum AppThemeMode {
  /// Always the theme's own (light) colours.
  light,

  /// Always the theme's [AppTheme.dark] colours.
  dark,

  /// Follow the device. Each renderer asks the platform - the trait collection
  /// on iOS, the night ui-mode on Android, `prefers-color-scheme` on web,
  /// `MediaQuery.platformBrightness` on Flutter - and repaints when it changes.
  system,
}

/// A small colour palette every renderer understands. Colours are `#rrggbb`
/// strings, the same form nodes carry.
class AppTheme {
  const AppTheme({
    this.primary = '#1976d2',
    this.onPrimary = '#ffffff',
    this.secondary = '#f57c00',
    this.surface = '#ffffff',
    this.surfaceVariant = '#f5f5f5',
    this.text = '#212121',
    this.textSecondary = '#757575',
    this.divider = '#e0e0e0',
    this.error = '#d32f2f',
    this.success = '#388e3c',
    this.warning = '#fbc02d',
    this.info = '#0288d1',
    this.glassTransparency = 0.0,
    this.glassChrome = true,
    this.mode = AppThemeMode.light,
    AppTheme? dark,
  }) : _dark = dark;

  /// The brand colour: app bar, primary buttons, the FAB.
  final String primary;

  /// The colour of text and icons drawn on [primary].
  final String onPrimary;

  /// The accent for secondary buttons and badges.
  final String secondary;

  /// The background of a scaffold.
  final String surface;

  /// Raised surfaces that have to read as *on* [surface]: cards, a text
  /// field's fill, the sheet and dialog panels. Slightly darker than [surface]
  /// in the light palette and slightly lighter in the dark one, which is why it
  /// cannot be derived from [surface] by a renderer.
  final String surfaceVariant;

  /// Body text and headings drawn on [surface].
  final String text;

  /// Text that is deliberately quieter than [text]: labels, hints, helper
  /// lines, and the default icon tint.
  final String textSecondary;

  /// Dividers, card outlines and text-field borders.
  final String divider;

  /// Error states: the error button/badge variant and a field's error text.
  final String error;

  /// The remaining semantic colours: the matching button, badge and alert
  /// variants. They have a dark counterpart like everything else, because a
  /// colour picked to read on white - a deep green, a mid blue - goes muddy on
  /// a dark ground.
  final String success;
  final String warning;
  final String info;

  /// How see-through the iOS 26 Liquid Glass modal surfaces (bottom sheet and
  /// dialog) are: 0 is a solid frosted panel, 1 is barely there - the backdrop
  /// shows through more sharply and the scrim behind the surface lightens with
  /// it. Only the iOS native renderer on iOS 26+ reads this; every other
  /// renderer and older iOS ignore it.
  final double glassTransparency;

  /// Whether the app bar and the FAB use Liquid Glass on iOS 26 (the default),
  /// or the flat brand-colour fill. Set false for, say, a solid branded app bar.
  /// The modal sheet and dialog glass is separate - see [glassTransparency].
  /// Only the iOS native renderer on iOS 26+ reads this.
  final bool glassChrome;

  /// Which appearance to paint. The default stays [AppThemeMode.light], so a
  /// theme written before there was a dark one keeps the colours it had.
  final AppThemeMode mode;

  final AppTheme? _dark;

  /// The dark counterpart of this theme - what [mode] selects when it is
  /// [AppThemeMode.dark], or when it is [AppThemeMode.system] on a device in
  /// dark mode. An app that does not supply one gets [darkFallback], so
  /// `mode: AppThemeMode.system` alone is enough to be dark-mode-correct.
  ///
  /// Only its colours are read, never its own [mode] or [dark], so a resolved
  /// appearance is a flat palette rather than a chain.
  AppTheme get dark => _dark ?? darkFallback;

  /// The palette for the appearance [mode] selects, given what the platform
  /// reports. [platformIsDark] is ignored unless [mode] is
  /// [AppThemeMode.system].
  AppTheme resolve({required bool platformIsDark}) => switch (mode) {
        AppThemeMode.light => this,
        AppThemeMode.dark => dark,
        AppThemeMode.system => platformIsDark ? dark : this,
      };

  /// Whether [resolve] would pick the dark palette.
  bool isDark({required bool platformIsDark}) => switch (mode) {
        AppThemeMode.light => false,
        AppThemeMode.dark => true,
        AppThemeMode.system => platformIsDark,
      };

  /// The Material defaults used when no theme is given.
  static const AppTheme fallback = AppTheme();

  /// The dark palette a theme gets when it asks for dark without supplying one.
  ///
  /// Material's dark-surface greys rather than pure black, a lightened primary
  /// (a saturated brand colour on a dark ground is hard to read), and text that
  /// stops short of pure white to keep the contrast from vibrating.
  static const AppTheme darkFallback = AppTheme(
    primary: '#90caf9',
    onPrimary: '#00325b',
    secondary: '#ffb74d',
    surface: '#121212',
    surfaceVariant: '#1e1e1e',
    text: '#ececec',
    textSecondary: '#a8a8a8',
    divider: '#323232',
    error: '#ef5350',
    success: '#66bb6a',
    warning: '#ffca28',
    info: '#4fc3f7',
  );

  Map<String, Object?> toJson() => {
        'primary': primary,
        'onPrimary': onPrimary,
        'secondary': secondary,
        'surface': surface,
        'surfaceVariant': surfaceVariant,
        'text': text,
        'textSecondary': textSecondary,
        'divider': divider,
        'error': error,
        'success': success,
        'warning': warning,
        'info': info,
        'glassTransparency': glassTransparency,
        'glassChrome': glassChrome,
        'mode': mode.name,
        // One level only: the dark palette's own `dark` is never consulted.
        'dark': (_dark ?? darkFallback)._paletteJson(),
      };

  Map<String, Object?> _paletteJson() => {
        'primary': primary,
        'onPrimary': onPrimary,
        'secondary': secondary,
        'surface': surface,
        'surfaceVariant': surfaceVariant,
        'text': text,
        'textSecondary': textSecondary,
        'divider': divider,
        'error': error,
        'success': success,
        'warning': warning,
        'info': info,
      };

  /// Reads a theme from the map a renderer received, or the [fallback].
  factory AppTheme.fromJson(Map<dynamic, dynamic>? json) {
    if (json == null) return fallback;
    return AppTheme(
      primary: json['primary'] as String? ?? fallback.primary,
      onPrimary: json['onPrimary'] as String? ?? fallback.onPrimary,
      secondary: json['secondary'] as String? ?? fallback.secondary,
      surface: json['surface'] as String? ?? fallback.surface,
      surfaceVariant:
          json['surfaceVariant'] as String? ?? fallback.surfaceVariant,
      text: json['text'] as String? ?? fallback.text,
      textSecondary: json['textSecondary'] as String? ?? fallback.textSecondary,
      divider: json['divider'] as String? ?? fallback.divider,
      error: json['error'] as String? ?? fallback.error,
      success: json['success'] as String? ?? fallback.success,
      warning: json['warning'] as String? ?? fallback.warning,
      info: json['info'] as String? ?? fallback.info,
      glassTransparency: (json['glassTransparency'] as num?)?.toDouble() ??
          fallback.glassTransparency,
      glassChrome: json['glassChrome'] as bool? ?? fallback.glassChrome,
      mode: AppThemeMode.values.firstWhere(
        (m) => m.name == json['mode'],
        orElse: () => fallback.mode,
      ),
      dark: json['dark'] == null
          ? null
          : AppTheme.fromJson(json['dark'] as Map<dynamic, dynamic>),
    );
  }

  AppTheme copyWith({AppThemeMode? mode, AppTheme? dark}) => AppTheme(
        primary: primary,
        onPrimary: onPrimary,
        secondary: secondary,
        surface: surface,
        surfaceVariant: surfaceVariant,
        text: text,
        textSecondary: textSecondary,
        divider: divider,
        error: error,
        success: success,
        warning: warning,
        info: info,
        glassTransparency: glassTransparency,
        glassChrome: glassChrome,
        mode: mode ?? this.mode,
        dark: dark ?? _dark,
      );

  /// This appearance's nine colours, in a fixed order, for comparison.
  List<String> get _colours => [
        primary,
        onPrimary,
        secondary,
        surface,
        surfaceVariant,
        text,
        textSecondary,
        divider,
        error,
        success,
        warning,
        info,
      ];

  static bool _sameColours(AppTheme a, AppTheme b) {
    final one = a._colours;
    final two = b._colours;
    for (var i = 0; i < one.length; i++) {
      if (one[i] != two[i]) return false;
    }
    return true;
  }

  /// Two themes are equal when they *resolve* the same, so leaving [dark]
  /// unset and passing [darkFallback] explicitly are the same theme - which is
  /// what makes a theme survive a round trip through [toJson], where the
  /// implicit dark palette is written out.
  ///
  /// The dark counterparts are compared by colour rather than with `==`, which
  /// would recurse: every palette has a dark counterpart, including the dark
  /// ones.
  @override
  bool operator ==(Object other) =>
      other is AppTheme &&
      _sameColours(other, this) &&
      other.glassTransparency == glassTransparency &&
      other.glassChrome == glassChrome &&
      other.mode == mode &&
      _sameColours(other.dark, dark);

  @override
  int get hashCode => Object.hash(
        Object.hashAll(_colours),
        glassTransparency,
        glassChrome,
        mode,
        Object.hashAll(dark._colours),
      );
}
