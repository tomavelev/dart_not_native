part of '../../widgets.dart';

// ---------------------------------------------------------------------------
// Theme data: text styles, the colour scheme and the ThemeData that holds
// them. Descriptions only - the `Theme` widget that hands one down the tree
// lives with the other inherited widgets.
// ---------------------------------------------------------------------------

/// How heavy text is, 100 (thin) to 900 (black).
class FontWeight {
  const FontWeight._(this.index, this.value);

  /// Where this weight sits in [values].
  final int index;

  /// The CSS weight, which is what the protocol carries.
  final int value;

  static const FontWeight w100 = FontWeight._(0, 100);
  static const FontWeight w200 = FontWeight._(1, 200);
  static const FontWeight w300 = FontWeight._(2, 300);
  static const FontWeight w400 = FontWeight._(3, 400);
  static const FontWeight w500 = FontWeight._(4, 500);
  static const FontWeight w600 = FontWeight._(5, 600);
  static const FontWeight w700 = FontWeight._(6, 700);
  static const FontWeight w800 = FontWeight._(7, 800);
  static const FontWeight w900 = FontWeight._(8, 900);
  static const FontWeight normal = w400;
  static const FontWeight bold = w700;

  static const List<FontWeight> values = <FontWeight>[
    w100,
    w200,
    w300,
    w400,
    w500,
    w600,
    w700,
    w800,
    w900,
  ];

  /// The weight [t] of the way from [a] to [b], snapped to a real one.
  static FontWeight? lerp(FontWeight? a, FontWeight? b, double t) {
    if (a == null && b == null) return null;
    final from = (a ?? normal).index;
    final to = (b ?? normal).index;
    return values[(from + (to - from) * t).round().clamp(0, 8)];
  }

  @override
  String toString() => 'FontWeight.w$value';
}

/// A line drawn through, under or over text.
class TextDecoration {
  const TextDecoration._(this._name);

  /// What the protocol calls it: 'none', 'lineThrough' or 'underline'.
  final String _name;

  static const TextDecoration none = TextDecoration._('none');
  static const TextDecoration lineThrough = TextDecoration._('lineThrough');
  static const TextDecoration underline = TextDecoration._('underline');

  /// A line above the text. The protocol has no word for it, so it draws as
  /// no decoration.
  static const TextDecoration overline = TextDecoration._('none');

  /// Several decorations at once. A text node carries one, so the first that
  /// draws anything is the one that travels.
  factory TextDecoration.combine(List<TextDecoration> decorations) =>
      decorations.firstWhere(
        (decoration) => decoration._name != 'none',
        orElse: () => none,
      );

  /// Whether this decoration includes [other].
  bool contains(TextDecoration other) => other._name == _name;

  @override
  bool operator ==(Object other) =>
      other is TextDecoration && other._name == _name;
  @override
  int get hashCode => _name.hashCode;
  @override
  String toString() => 'TextDecoration.$_name';
}

/// How a decoration line is drawn. Accepted for compatibility; every renderer
/// draws a solid line.
enum TextDecorationStyle { solid, double, dotted, dashed, wavy }

/// How text looks. Every field is optional: a style says only what it wants
/// to change, and [merge] lays one over another.
class TextStyle {
  const TextStyle({
    this.inherit = true,
    this.color,
    this.backgroundColor,
    this.fontSize,
    this.fontWeight,
    this.fontStyle,
    this.letterSpacing,
    this.wordSpacing,
    this.height,
    this.decoration,
    this.decorationColor,
    this.decorationStyle,
    this.decorationThickness,
    this.fontFamily,
    this.fontFamilyFallback,
    this.shadows,
    this.fontFeatures,
    this.textBaseline,
    this.debugLabel,
  });

  /// Whether the fields left null come from the style around this one. False
  /// makes [merge] replace rather than overlay, as in Flutter.
  final bool inherit;
  final Color? color;

  /// A fill behind the glyphs. Accepted for compatibility: a text node has no
  /// background of its own, so wrap the text in a `Container` for one.
  final Color? backgroundColor;
  final double? fontSize;
  final FontWeight? fontWeight;
  final FontStyle? fontStyle;
  final double? letterSpacing;

  /// Accepted for compatibility; the protocol spaces letters, not words.
  final double? wordSpacing;

  /// The line height as a multiple of the font size.
  final double? height;
  final TextDecoration? decoration;

  /// Accepted for compatibility: the line is drawn in the text's own colour.
  final Color? decorationColor;
  final TextDecorationStyle? decorationStyle;
  final double? decorationThickness;

  /// A family name, or the generic 'monospace' / 'serif'.
  final String? fontFamily;
  final List<String>? fontFamilyFallback;

  /// Accepted for compatibility: no renderer draws a shadow under text.
  final List<Shadow>? shadows;

  /// Accepted for compatibility - see [FontFeature].
  final List<FontFeature>? fontFeatures;
  final TextBaseline? textBaseline;
  final String? debugLabel;

  TextStyle copyWith({
    bool? inherit,
    Color? color,
    Color? backgroundColor,
    double? fontSize,
    FontWeight? fontWeight,
    FontStyle? fontStyle,
    double? letterSpacing,
    double? wordSpacing,
    double? height,
    TextDecoration? decoration,
    Color? decorationColor,
    TextDecorationStyle? decorationStyle,
    double? decorationThickness,
    String? fontFamily,
    List<String>? fontFamilyFallback,
    List<Shadow>? shadows,
    List<FontFeature>? fontFeatures,
    TextBaseline? textBaseline,
    String? debugLabel,
  }) => TextStyle(
    inherit: inherit ?? this.inherit,
    color: color ?? this.color,
    backgroundColor: backgroundColor ?? this.backgroundColor,
    fontSize: fontSize ?? this.fontSize,
    fontWeight: fontWeight ?? this.fontWeight,
    fontStyle: fontStyle ?? this.fontStyle,
    letterSpacing: letterSpacing ?? this.letterSpacing,
    wordSpacing: wordSpacing ?? this.wordSpacing,
    height: height ?? this.height,
    decoration: decoration ?? this.decoration,
    decorationColor: decorationColor ?? this.decorationColor,
    decorationStyle: decorationStyle ?? this.decorationStyle,
    decorationThickness: decorationThickness ?? this.decorationThickness,
    fontFamily: fontFamily ?? this.fontFamily,
    fontFamilyFallback: fontFamilyFallback ?? this.fontFamilyFallback,
    shadows: shadows ?? this.shadows,
    fontFeatures: fontFeatures ?? this.fontFeatures,
    textBaseline: textBaseline ?? this.textBaseline,
    debugLabel: debugLabel ?? this.debugLabel,
  );

  /// This style with [other] laid over it: whatever [other] says wins, and
  /// what it leaves null shows through.
  TextStyle merge(TextStyle? other) {
    if (other == null) return this;
    if (!other.inherit) return other;
    return copyWith(
      color: other.color,
      backgroundColor: other.backgroundColor,
      fontSize: other.fontSize,
      fontWeight: other.fontWeight,
      fontStyle: other.fontStyle,
      letterSpacing: other.letterSpacing,
      wordSpacing: other.wordSpacing,
      height: other.height,
      decoration: other.decoration,
      decorationColor: other.decorationColor,
      decorationStyle: other.decorationStyle,
      decorationThickness: other.decorationThickness,
      fontFamily: other.fontFamily,
      fontFamilyFallback: other.fontFamilyFallback,
      shadows: other.shadows,
      fontFeatures: other.fontFeatures,
      textBaseline: other.textBaseline,
      debugLabel: other.debugLabel,
    );
  }

  /// This style recoloured or rescaled: a size becomes
  /// `size * fontSizeFactor + fontSizeDelta`, and the other factors work the
  /// same way. [fontWeightDelta] moves the weight that many steps of 100.
  TextStyle apply({
    Color? color,
    Color? backgroundColor,
    TextDecoration? decoration,
    Color? decorationColor,
    String? fontFamily,
    double fontSizeFactor = 1.0,
    double fontSizeDelta = 0.0,
    int fontWeightDelta = 0,
    FontStyle? fontStyle,
    double letterSpacingFactor = 1.0,
    double letterSpacingDelta = 0.0,
    double heightFactor = 1.0,
    double heightDelta = 0.0,
  }) => TextStyle(
    inherit: inherit,
    color: color ?? this.color,
    backgroundColor: backgroundColor ?? this.backgroundColor,
    fontSize: fontSize == null
        ? null
        : fontSize! * fontSizeFactor + fontSizeDelta,
    fontWeight: fontWeight == null
        ? null
        : FontWeight.values[(fontWeight!.index + fontWeightDelta).clamp(0, 8)],
    fontStyle: fontStyle ?? this.fontStyle,
    letterSpacing: letterSpacing == null
        ? null
        : letterSpacing! * letterSpacingFactor + letterSpacingDelta,
    wordSpacing: wordSpacing,
    height: height == null ? null : height! * heightFactor + heightDelta,
    decoration: decoration ?? this.decoration,
    decorationColor: decorationColor ?? this.decorationColor,
    decorationStyle: decorationStyle,
    decorationThickness: decorationThickness,
    fontFamily: fontFamily ?? this.fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    shadows: shadows,
    fontFeatures: fontFeatures,
    textBaseline: textBaseline,
    debugLabel: debugLabel,
  );

  /// The style [t] of the way from [a] to [b]: numbers move, everything else
  /// switches half way.
  static TextStyle? lerp(TextStyle? a, TextStyle? b, double t) {
    if (a == null && b == null) return null;
    if (a == null) return b;
    if (b == null) return a;
    double? mix(double? from, double? to) => from == null || to == null
        ? (t < 0.5 ? from : to)
        : from + (to - from) * t;
    final pick = t < 0.5 ? a : b;
    return pick.copyWith(
      color: Color.lerp(a.color, b.color, t),
      fontSize: mix(a.fontSize, b.fontSize),
      fontWeight: FontWeight.lerp(a.fontWeight, b.fontWeight, t),
      letterSpacing: mix(a.letterSpacing, b.letterSpacing),
      height: mix(a.height, b.height),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TextStyle &&
      other.inherit == inherit &&
      other.color == color &&
      other.backgroundColor == backgroundColor &&
      other.fontSize == fontSize &&
      other.fontWeight == fontWeight &&
      other.fontStyle == fontStyle &&
      other.letterSpacing == letterSpacing &&
      other.wordSpacing == wordSpacing &&
      other.height == height &&
      other.decoration == decoration &&
      other.decorationColor == decorationColor &&
      other.fontFamily == fontFamily;

  @override
  int get hashCode => Object.hash(
    inherit,
    color,
    backgroundColor,
    fontSize,
    fontWeight,
    fontStyle,
    letterSpacing,
    wordSpacing,
    height,
    decoration,
    decorationColor,
    fontFamily,
  );

  @override
  String toString() =>
      'TextStyle(size: $fontSize, weight: $fontWeight, color: $color)';
}

/// Material 3's fifteen text styles: display, headline, title, body and label,
/// each in large, medium and small.
class TextTheme {
  const TextTheme({
    this.displayLarge,
    this.displayMedium,
    this.displaySmall,
    this.headlineLarge,
    this.headlineMedium,
    this.headlineSmall,
    this.titleLarge,
    this.titleMedium,
    this.titleSmall,
    this.bodyLarge,
    this.bodyMedium,
    this.bodySmall,
    this.labelLarge,
    this.labelMedium,
    this.labelSmall,
  });

  final TextStyle? displayLarge;
  final TextStyle? displayMedium;
  final TextStyle? displaySmall;
  final TextStyle? headlineLarge;
  final TextStyle? headlineMedium;
  final TextStyle? headlineSmall;
  final TextStyle? titleLarge;
  final TextStyle? titleMedium;
  final TextStyle? titleSmall;
  final TextStyle? bodyLarge;
  final TextStyle? bodyMedium;
  final TextStyle? bodySmall;
  final TextStyle? labelLarge;
  final TextStyle? labelMedium;
  final TextStyle? labelSmall;

  /// The Material 3 type scale: sizes, weights, letter spacing and line
  /// heights as the spec gives them, with no colour and no family - a
  /// [ThemeData] lays its own over these.
  static const TextTheme _material3 = TextTheme(
    displayLarge: TextStyle(
      fontSize: 57,
      fontWeight: FontWeight.w400,
      letterSpacing: -0.25,
      height: 1.12,
    ),
    displayMedium: TextStyle(
      fontSize: 45,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
      height: 1.16,
    ),
    displaySmall: TextStyle(
      fontSize: 36,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
      height: 1.22,
    ),
    headlineLarge: TextStyle(
      fontSize: 32,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
      height: 1.25,
    ),
    headlineMedium: TextStyle(
      fontSize: 28,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
      height: 1.29,
    ),
    headlineSmall: TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
      height: 1.33,
    ),
    titleLarge: TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
      height: 1.27,
    ),
    titleMedium: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.15,
      height: 1.50,
    ),
    titleSmall: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.1,
      height: 1.43,
    ),
    bodyLarge: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.5,
      height: 1.50,
    ),
    bodyMedium: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.25,
      height: 1.43,
    ),
    bodySmall: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.4,
      height: 1.33,
    ),
    labelLarge: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.1,
      height: 1.43,
    ),
    labelMedium: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.5,
      height: 1.33,
    ),
    labelSmall: TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.5,
      height: 1.45,
    ),
  );

  TextTheme copyWith({
    TextStyle? displayLarge,
    TextStyle? displayMedium,
    TextStyle? displaySmall,
    TextStyle? headlineLarge,
    TextStyle? headlineMedium,
    TextStyle? headlineSmall,
    TextStyle? titleLarge,
    TextStyle? titleMedium,
    TextStyle? titleSmall,
    TextStyle? bodyLarge,
    TextStyle? bodyMedium,
    TextStyle? bodySmall,
    TextStyle? labelLarge,
    TextStyle? labelMedium,
    TextStyle? labelSmall,
  }) => TextTheme(
    displayLarge: displayLarge ?? this.displayLarge,
    displayMedium: displayMedium ?? this.displayMedium,
    displaySmall: displaySmall ?? this.displaySmall,
    headlineLarge: headlineLarge ?? this.headlineLarge,
    headlineMedium: headlineMedium ?? this.headlineMedium,
    headlineSmall: headlineSmall ?? this.headlineSmall,
    titleLarge: titleLarge ?? this.titleLarge,
    titleMedium: titleMedium ?? this.titleMedium,
    titleSmall: titleSmall ?? this.titleSmall,
    bodyLarge: bodyLarge ?? this.bodyLarge,
    bodyMedium: bodyMedium ?? this.bodyMedium,
    bodySmall: bodySmall ?? this.bodySmall,
    labelLarge: labelLarge ?? this.labelLarge,
    labelMedium: labelMedium ?? this.labelMedium,
    labelSmall: labelSmall ?? this.labelSmall,
  );

  /// This theme with [other] laid over it, style by style - a theme that only
  /// names `titleLarge` changes only that.
  TextTheme merge(TextTheme? other) {
    if (other == null) return this;
    TextStyle? over(TextStyle? base, TextStyle? top) => base?.merge(top) ?? top;
    return TextTheme(
      displayLarge: over(displayLarge, other.displayLarge),
      displayMedium: over(displayMedium, other.displayMedium),
      displaySmall: over(displaySmall, other.displaySmall),
      headlineLarge: over(headlineLarge, other.headlineLarge),
      headlineMedium: over(headlineMedium, other.headlineMedium),
      headlineSmall: over(headlineSmall, other.headlineSmall),
      titleLarge: over(titleLarge, other.titleLarge),
      titleMedium: over(titleMedium, other.titleMedium),
      titleSmall: over(titleSmall, other.titleSmall),
      bodyLarge: over(bodyLarge, other.bodyLarge),
      bodyMedium: over(bodyMedium, other.bodyMedium),
      bodySmall: over(bodySmall, other.bodySmall),
      labelLarge: over(labelLarge, other.labelLarge),
      labelMedium: over(labelMedium, other.labelMedium),
      labelSmall: over(labelSmall, other.labelSmall),
    );
  }

  /// Every style recoloured, refamilied or rescaled at once.
  ///
  /// Flutter's split between the two colours is kept: [displayColor] goes to
  /// the display styles, the two larger headlines and `bodySmall`;
  /// [bodyColor] to everything else.
  TextTheme apply({
    String? fontFamily,
    double fontSizeFactor = 1.0,
    double fontSizeDelta = 0.0,
    Color? displayColor,
    Color? bodyColor,
    TextDecoration? decoration,
    Color? decorationColor,
  }) {
    TextStyle? restyle(TextStyle? style, Color? color) => style?.apply(
      color: color,
      decoration: decoration,
      decorationColor: decorationColor,
      fontFamily: fontFamily,
      fontSizeFactor: fontSizeFactor,
      fontSizeDelta: fontSizeDelta,
    );
    return TextTheme(
      displayLarge: restyle(displayLarge, displayColor),
      displayMedium: restyle(displayMedium, displayColor),
      displaySmall: restyle(displaySmall, displayColor),
      headlineLarge: restyle(headlineLarge, displayColor),
      headlineMedium: restyle(headlineMedium, displayColor),
      headlineSmall: restyle(headlineSmall, bodyColor),
      titleLarge: restyle(titleLarge, bodyColor),
      titleMedium: restyle(titleMedium, bodyColor),
      titleSmall: restyle(titleSmall, bodyColor),
      bodyLarge: restyle(bodyLarge, bodyColor),
      bodyMedium: restyle(bodyMedium, bodyColor),
      bodySmall: restyle(bodySmall, displayColor),
      labelLarge: restyle(labelLarge, bodyColor),
      labelMedium: restyle(labelMedium, bodyColor),
      labelSmall: restyle(labelSmall, bodyColor),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TextTheme &&
      other.displayLarge == displayLarge &&
      other.displayMedium == displayMedium &&
      other.displaySmall == displaySmall &&
      other.headlineLarge == headlineLarge &&
      other.headlineMedium == headlineMedium &&
      other.headlineSmall == headlineSmall &&
      other.titleLarge == titleLarge &&
      other.titleMedium == titleMedium &&
      other.titleSmall == titleSmall &&
      other.bodyLarge == bodyLarge &&
      other.bodyMedium == bodyMedium &&
      other.bodySmall == bodySmall &&
      other.labelLarge == labelLarge &&
      other.labelMedium == labelMedium &&
      other.labelSmall == labelSmall;

  @override
  int get hashCode => Object.hash(
    displayLarge,
    displayMedium,
    displaySmall,
    headlineLarge,
    headlineMedium,
    headlineSmall,
    titleLarge,
    titleMedium,
    titleSmall,
    bodyLarge,
    bodyMedium,
    bodySmall,
    labelLarge,
    labelMedium,
    labelSmall,
  );
}

/// The ways Material can derive a scheme from a seed. Accepted by
/// [ColorScheme.fromSeed] for compatibility; the scheme built here is always
/// [tonalSpot], Material's default.
enum DynamicSchemeVariant {
  tonalSpot,
  fidelity,
  monochrome,
  neutral,
  vibrant,
  expressive,
  content,
  rainbow,
  fruitSalad,
}

/// One hue at one colourfulness, readable at any tone from 0 (black) to 100
/// (white) - the building block of [ColorScheme.fromSeed].
///
/// A tone is CIE L*, the lightness the eye reports, which is what makes "tone
/// 40 on tone 100" a contrast promise whatever the hue. HSL lightness is not
/// that - a yellow and a blue at the same HSL lightness are nowhere near as
/// bright as each other - so the lightness is searched for rather than
/// assumed.
class _TonalPalette {
  _TonalPalette(double hue, this.spread) : hue = hue % 360;

  final double hue;

  /// The gap between the strongest and weakest channel, 0 to 1: HSL's
  /// saturation scaled by how much room the lightness leaves for it. Holding
  /// this steady, rather than the saturation, is what keeps a near-white tone
  /// tinted instead of washing out to grey.
  final double spread;

  Color _at(double lightness) {
    final room = 1 - (2 * lightness - 1).abs();
    final saturation = room <= 0 ? 0.0 : math.min(1.0, spread / room);
    return HSLColor.fromAHSL(1, hue, saturation, lightness).toColor();
  }

  static double _lstar(Color color) {
    final y = color.computeLuminance();
    return y <= 216 / 24389
        ? y * 24389 / 27
        : 116 * math.pow(y, 1 / 3).toDouble() - 16;
  }

  /// The colour of this palette whose perceptual lightness is [tone].
  Color tone(int tone) {
    if (tone <= 0) return const Color(0xFF000000);
    if (tone >= 100) return const Color(0xFFFFFFFF);
    // L* rises with HSL lightness for a fixed hue, so a bisection finds it;
    // twenty halvings is finer than one step of an 8-bit channel.
    var low = 0.0;
    var high = 1.0;
    for (var i = 0; i < 20; i++) {
      final mid = (low + high) / 2;
      if (_lstar(_at(mid)) < tone) {
        low = mid;
      } else {
        high = mid;
      }
    }
    return _at((low + high) / 2);
  }
}

/// The colours of a Material 3 app, by the role each plays.
///
/// A screen asks for a role - `colorScheme.primary`, `colorScheme.onSurface` -
/// rather than a colour, so the same screen is right in light and in dark.
/// Only eight roles are required; the rest fall back to the nearest of those,
/// as Flutter's do, so a scheme written by hand need not name all of them.
class ColorScheme {
  const ColorScheme({
    required this.brightness,
    required this.primary,
    required this.onPrimary,
    Color? primaryContainer,
    Color? onPrimaryContainer,
    Color? primaryFixed,
    Color? primaryFixedDim,
    Color? onPrimaryFixed,
    Color? onPrimaryFixedVariant,
    required this.secondary,
    required this.onSecondary,
    Color? secondaryContainer,
    Color? onSecondaryContainer,
    Color? secondaryFixed,
    Color? secondaryFixedDim,
    Color? onSecondaryFixed,
    Color? onSecondaryFixedVariant,
    Color? tertiary,
    Color? onTertiary,
    Color? tertiaryContainer,
    Color? onTertiaryContainer,
    Color? tertiaryFixed,
    Color? tertiaryFixedDim,
    Color? onTertiaryFixed,
    Color? onTertiaryFixedVariant,
    required this.error,
    required this.onError,
    Color? errorContainer,
    Color? onErrorContainer,
    required this.surface,
    required this.onSurface,
    Color? surfaceDim,
    Color? surfaceBright,
    Color? surfaceContainerLowest,
    Color? surfaceContainerLow,
    Color? surfaceContainer,
    Color? surfaceContainerHigh,
    Color? surfaceContainerHighest,
    Color? onSurfaceVariant,
    Color? outline,
    Color? outlineVariant,
    Color? shadow,
    Color? scrim,
    Color? inverseSurface,
    Color? onInverseSurface,
    Color? inversePrimary,
    Color? surfaceTint,
    Color? background,
    Color? onBackground,
    Color? surfaceVariant,
  }) : _primaryContainer = primaryContainer,
       _onPrimaryContainer = onPrimaryContainer,
       _primaryFixed = primaryFixed,
       _primaryFixedDim = primaryFixedDim,
       _onPrimaryFixed = onPrimaryFixed,
       _onPrimaryFixedVariant = onPrimaryFixedVariant,
       _secondaryContainer = secondaryContainer,
       _onSecondaryContainer = onSecondaryContainer,
       _secondaryFixed = secondaryFixed,
       _secondaryFixedDim = secondaryFixedDim,
       _onSecondaryFixed = onSecondaryFixed,
       _onSecondaryFixedVariant = onSecondaryFixedVariant,
       _tertiary = tertiary,
       _onTertiary = onTertiary,
       _tertiaryContainer = tertiaryContainer,
       _onTertiaryContainer = onTertiaryContainer,
       _tertiaryFixed = tertiaryFixed,
       _tertiaryFixedDim = tertiaryFixedDim,
       _onTertiaryFixed = onTertiaryFixed,
       _onTertiaryFixedVariant = onTertiaryFixedVariant,
       _errorContainer = errorContainer,
       _onErrorContainer = onErrorContainer,
       _surfaceDim = surfaceDim,
       _surfaceBright = surfaceBright,
       _surfaceContainerLowest = surfaceContainerLowest,
       _surfaceContainerLow = surfaceContainerLow,
       _surfaceContainer = surfaceContainer,
       _surfaceContainerHigh = surfaceContainerHigh,
       _surfaceContainerHighest = surfaceContainerHighest,
       _onSurfaceVariant = onSurfaceVariant,
       _outline = outline,
       _outlineVariant = outlineVariant,
       _shadow = shadow,
       _scrim = scrim,
       _inverseSurface = inverseSurface,
       _onInverseSurface = onInverseSurface,
       _inversePrimary = inversePrimary,
       _surfaceTint = surfaceTint,
       _background = background,
       _onBackground = onBackground,
       _surfaceVariant = surfaceVariant;

  /// A whole scheme from one colour.
  ///
  /// Material derives a scheme from a seed by building tonal palettes in the
  /// HCT colour space - a primary, a secondary, a tertiary and two neutrals -
  /// and reading each role off its palette at a fixed tone. This does the
  /// same, with the same tones for the same roles, but **the tones are
  /// approximated**: HCT is a few thousand lines of colour science, so the
  /// palettes here hold the seed's hue and a fixed colourfulness in HSL, and
  /// search for the lightness that gives each tone its real perceptual
  /// lightness (CIE L*). A colour lands close to Material's for common seeds
  /// and exactly on its lightness; its saturation can differ by a few percent.
  ///
  /// Any role passed is used as given, which is how an app pins its exact
  /// brand colour: `ColorScheme.fromSeed(seedColor: brand, primary: brand)`.
  ///
  /// [dynamicSchemeVariant] and [contrastLevel] are accepted for compatibility
  /// and not consulted: the scheme is always Material's default, `tonalSpot`,
  /// at standard contrast.
  factory ColorScheme.fromSeed({
    required Color seedColor,
    Brightness brightness = Brightness.light,
    DynamicSchemeVariant dynamicSchemeVariant = DynamicSchemeVariant.tonalSpot,
    double contrastLevel = 0.0,
    Color? primary,
    Color? onPrimary,
    Color? primaryContainer,
    Color? onPrimaryContainer,
    Color? primaryFixed,
    Color? primaryFixedDim,
    Color? onPrimaryFixed,
    Color? onPrimaryFixedVariant,
    Color? secondary,
    Color? onSecondary,
    Color? secondaryContainer,
    Color? onSecondaryContainer,
    Color? secondaryFixed,
    Color? secondaryFixedDim,
    Color? onSecondaryFixed,
    Color? onSecondaryFixedVariant,
    Color? tertiary,
    Color? onTertiary,
    Color? tertiaryContainer,
    Color? onTertiaryContainer,
    Color? tertiaryFixed,
    Color? tertiaryFixedDim,
    Color? onTertiaryFixed,
    Color? onTertiaryFixedVariant,
    Color? error,
    Color? onError,
    Color? errorContainer,
    Color? onErrorContainer,
    Color? surface,
    Color? onSurface,
    Color? surfaceDim,
    Color? surfaceBright,
    Color? surfaceContainerLowest,
    Color? surfaceContainerLow,
    Color? surfaceContainer,
    Color? surfaceContainerHigh,
    Color? surfaceContainerHighest,
    Color? onSurfaceVariant,
    Color? outline,
    Color? outlineVariant,
    Color? shadow,
    Color? scrim,
    Color? inverseSurface,
    Color? onInverseSurface,
    Color? inversePrimary,
    Color? surfaceTint,
    Color? background,
    Color? onBackground,
    Color? surfaceVariant,
  }) {
    final seed = HSLColor.fromColor(seedColor);
    // HSL's own measure of colourfulness: the spread between the strongest
    // and the weakest channel. Held within the band Material's primary
    // palette keeps to, so a grey seed still makes a coloured scheme and a
    // neon one does not make a garish one.
    final spread = seed.saturation * (1 - (2 * seed.lightness - 1).abs());
    final p = _TonalPalette(seed.hue, spread.clamp(0.34, 0.48));
    final s = _TonalPalette(seed.hue, 0.10);
    final t = _TonalPalette(seed.hue + 60, 0.17);
    final n = _TonalPalette(seed.hue, 0.03);
    final v = _TonalPalette(seed.hue, 0.045);
    final dark = brightness == Brightness.dark;
    return ColorScheme(
      brightness: brightness,
      primary: primary ?? (dark ? p.tone(80) : p.tone(40)),
      onPrimary: onPrimary ?? (dark ? p.tone(20) : p.tone(100)),
      primaryContainer: primaryContainer ?? (dark ? p.tone(30) : p.tone(90)),
      onPrimaryContainer:
          onPrimaryContainer ?? (dark ? p.tone(90) : p.tone(10)),
      primaryFixed: primaryFixed ?? (dark ? p.tone(90) : p.tone(90)),
      primaryFixedDim: primaryFixedDim ?? (dark ? p.tone(80) : p.tone(80)),
      onPrimaryFixed: onPrimaryFixed ?? (dark ? p.tone(10) : p.tone(10)),
      onPrimaryFixedVariant:
          onPrimaryFixedVariant ?? (dark ? p.tone(30) : p.tone(30)),
      secondary: secondary ?? (dark ? s.tone(80) : s.tone(40)),
      onSecondary: onSecondary ?? (dark ? s.tone(20) : s.tone(100)),
      secondaryContainer:
          secondaryContainer ?? (dark ? s.tone(30) : s.tone(90)),
      onSecondaryContainer:
          onSecondaryContainer ?? (dark ? s.tone(90) : s.tone(10)),
      secondaryFixed: secondaryFixed ?? (dark ? s.tone(90) : s.tone(90)),
      secondaryFixedDim: secondaryFixedDim ?? (dark ? s.tone(80) : s.tone(80)),
      onSecondaryFixed: onSecondaryFixed ?? (dark ? s.tone(10) : s.tone(10)),
      onSecondaryFixedVariant:
          onSecondaryFixedVariant ?? (dark ? s.tone(30) : s.tone(30)),
      tertiary: tertiary ?? (dark ? t.tone(80) : t.tone(40)),
      onTertiary: onTertiary ?? (dark ? t.tone(20) : t.tone(100)),
      tertiaryContainer: tertiaryContainer ?? (dark ? t.tone(30) : t.tone(90)),
      onTertiaryContainer:
          onTertiaryContainer ?? (dark ? t.tone(90) : t.tone(10)),
      tertiaryFixed: tertiaryFixed ?? (dark ? t.tone(90) : t.tone(90)),
      tertiaryFixedDim: tertiaryFixedDim ?? (dark ? t.tone(80) : t.tone(80)),
      onTertiaryFixed: onTertiaryFixed ?? (dark ? t.tone(10) : t.tone(10)),
      onTertiaryFixedVariant:
          onTertiaryFixedVariant ?? (dark ? t.tone(30) : t.tone(30)),
      error:
          error ?? (dark ? const Color(0xFFFFB4AB) : const Color(0xFFBA1A1A)),
      onError:
          onError ?? (dark ? const Color(0xFF690005) : const Color(0xFFFFFFFF)),
      errorContainer:
          errorContainer ??
          (dark ? const Color(0xFF93000A) : const Color(0xFFFFDAD6)),
      onErrorContainer:
          onErrorContainer ??
          (dark ? const Color(0xFFFFDAD6) : const Color(0xFF410002)),
      surface: surface ?? (dark ? n.tone(6) : n.tone(98)),
      onSurface: onSurface ?? (dark ? n.tone(90) : n.tone(10)),
      surfaceDim: surfaceDim ?? (dark ? n.tone(6) : n.tone(87)),
      surfaceBright: surfaceBright ?? (dark ? n.tone(24) : n.tone(98)),
      surfaceContainerLowest:
          surfaceContainerLowest ?? (dark ? n.tone(4) : n.tone(100)),
      surfaceContainerLow:
          surfaceContainerLow ?? (dark ? n.tone(10) : n.tone(96)),
      surfaceContainer: surfaceContainer ?? (dark ? n.tone(12) : n.tone(94)),
      surfaceContainerHigh:
          surfaceContainerHigh ?? (dark ? n.tone(17) : n.tone(92)),
      surfaceContainerHighest:
          surfaceContainerHighest ?? (dark ? n.tone(22) : n.tone(90)),
      onSurfaceVariant: onSurfaceVariant ?? (dark ? v.tone(80) : v.tone(30)),
      outline: outline ?? (dark ? v.tone(60) : v.tone(50)),
      outlineVariant: outlineVariant ?? (dark ? v.tone(30) : v.tone(80)),
      shadow:
          shadow ?? (dark ? const Color(0xFF000000) : const Color(0xFF000000)),
      scrim:
          scrim ?? (dark ? const Color(0xFF000000) : const Color(0xFF000000)),
      inverseSurface: inverseSurface ?? (dark ? n.tone(90) : n.tone(20)),
      onInverseSurface: onInverseSurface ?? (dark ? n.tone(20) : n.tone(95)),
      inversePrimary: inversePrimary ?? (dark ? p.tone(40) : p.tone(80)),
      surfaceTint: surfaceTint ?? (dark ? p.tone(80) : p.tone(40)),
      background: background ?? (dark ? n.tone(6) : n.tone(98)),
      onBackground: onBackground ?? (dark ? n.tone(90) : n.tone(10)),
      surfaceVariant: surfaceVariant ?? (dark ? v.tone(30) : v.tone(90)),
    );
  }

  /// Material 2's light scheme: purple and teal on white.
  const ColorScheme.light({
    this.brightness = Brightness.light,
    this.primary = const Color(0xFF6200EE),
    this.onPrimary = const Color(0xFFFFFFFF),
    this.secondary = const Color(0xFF03DAC6),
    this.onSecondary = const Color(0xFF000000),
    this.error = const Color(0xFFB00020),
    this.onError = const Color(0xFFFFFFFF),
    this.surface = const Color(0xFFFFFFFF),
    this.onSurface = const Color(0xFF000000),
    Color? primaryContainer,
    Color? onPrimaryContainer,
    Color? primaryFixed,
    Color? primaryFixedDim,
    Color? onPrimaryFixed,
    Color? onPrimaryFixedVariant,
    Color? secondaryContainer,
    Color? onSecondaryContainer,
    Color? secondaryFixed,
    Color? secondaryFixedDim,
    Color? onSecondaryFixed,
    Color? onSecondaryFixedVariant,
    Color? tertiary,
    Color? onTertiary,
    Color? tertiaryContainer,
    Color? onTertiaryContainer,
    Color? tertiaryFixed,
    Color? tertiaryFixedDim,
    Color? onTertiaryFixed,
    Color? onTertiaryFixedVariant,
    Color? errorContainer,
    Color? onErrorContainer,
    Color? surfaceDim,
    Color? surfaceBright,
    Color? surfaceContainerLowest,
    Color? surfaceContainerLow,
    Color? surfaceContainer,
    Color? surfaceContainerHigh,
    Color? surfaceContainerHighest,
    Color? onSurfaceVariant,
    Color? outline,
    Color? outlineVariant,
    Color? shadow,
    Color? scrim,
    Color? inverseSurface,
    Color? onInverseSurface,
    Color? inversePrimary,
    Color? surfaceTint,
    Color? background,
    Color? onBackground,
    Color? surfaceVariant,
  }) : _primaryContainer = primaryContainer,
       _onPrimaryContainer = onPrimaryContainer,
       _primaryFixed = primaryFixed,
       _primaryFixedDim = primaryFixedDim,
       _onPrimaryFixed = onPrimaryFixed,
       _onPrimaryFixedVariant = onPrimaryFixedVariant,
       _secondaryContainer = secondaryContainer,
       _onSecondaryContainer = onSecondaryContainer,
       _secondaryFixed = secondaryFixed,
       _secondaryFixedDim = secondaryFixedDim,
       _onSecondaryFixed = onSecondaryFixed,
       _onSecondaryFixedVariant = onSecondaryFixedVariant,
       _tertiary = tertiary,
       _onTertiary = onTertiary,
       _tertiaryContainer = tertiaryContainer,
       _onTertiaryContainer = onTertiaryContainer,
       _tertiaryFixed = tertiaryFixed,
       _tertiaryFixedDim = tertiaryFixedDim,
       _onTertiaryFixed = onTertiaryFixed,
       _onTertiaryFixedVariant = onTertiaryFixedVariant,
       _errorContainer = errorContainer,
       _onErrorContainer = onErrorContainer,
       _surfaceDim = surfaceDim,
       _surfaceBright = surfaceBright,
       _surfaceContainerLowest = surfaceContainerLowest,
       _surfaceContainerLow = surfaceContainerLow,
       _surfaceContainer = surfaceContainer,
       _surfaceContainerHigh = surfaceContainerHigh,
       _surfaceContainerHighest = surfaceContainerHighest,
       _onSurfaceVariant = onSurfaceVariant,
       _outline = outline,
       _outlineVariant = outlineVariant,
       _shadow = shadow,
       _scrim = scrim,
       _inverseSurface = inverseSurface,
       _onInverseSurface = onInverseSurface,
       _inversePrimary = inversePrimary,
       _surfaceTint = surfaceTint,
       _background = background,
       _onBackground = onBackground,
       _surfaceVariant = surfaceVariant;

  /// Material 2's dark scheme.
  const ColorScheme.dark({
    this.brightness = Brightness.dark,
    this.primary = const Color(0xFFBB86FC),
    this.onPrimary = const Color(0xFF000000),
    this.secondary = const Color(0xFF03DAC6),
    this.onSecondary = const Color(0xFF000000),
    this.error = const Color(0xFFCF6679),
    this.onError = const Color(0xFF000000),
    this.surface = const Color(0xFF121212),
    this.onSurface = const Color(0xFFFFFFFF),
    Color? primaryContainer,
    Color? onPrimaryContainer,
    Color? primaryFixed,
    Color? primaryFixedDim,
    Color? onPrimaryFixed,
    Color? onPrimaryFixedVariant,
    Color? secondaryContainer,
    Color? onSecondaryContainer,
    Color? secondaryFixed,
    Color? secondaryFixedDim,
    Color? onSecondaryFixed,
    Color? onSecondaryFixedVariant,
    Color? tertiary,
    Color? onTertiary,
    Color? tertiaryContainer,
    Color? onTertiaryContainer,
    Color? tertiaryFixed,
    Color? tertiaryFixedDim,
    Color? onTertiaryFixed,
    Color? onTertiaryFixedVariant,
    Color? errorContainer,
    Color? onErrorContainer,
    Color? surfaceDim,
    Color? surfaceBright,
    Color? surfaceContainerLowest,
    Color? surfaceContainerLow,
    Color? surfaceContainer,
    Color? surfaceContainerHigh,
    Color? surfaceContainerHighest,
    Color? onSurfaceVariant,
    Color? outline,
    Color? outlineVariant,
    Color? shadow,
    Color? scrim,
    Color? inverseSurface,
    Color? onInverseSurface,
    Color? inversePrimary,
    Color? surfaceTint,
    Color? background,
    Color? onBackground,
    Color? surfaceVariant,
  }) : _primaryContainer = primaryContainer,
       _onPrimaryContainer = onPrimaryContainer,
       _primaryFixed = primaryFixed,
       _primaryFixedDim = primaryFixedDim,
       _onPrimaryFixed = onPrimaryFixed,
       _onPrimaryFixedVariant = onPrimaryFixedVariant,
       _secondaryContainer = secondaryContainer,
       _onSecondaryContainer = onSecondaryContainer,
       _secondaryFixed = secondaryFixed,
       _secondaryFixedDim = secondaryFixedDim,
       _onSecondaryFixed = onSecondaryFixed,
       _onSecondaryFixedVariant = onSecondaryFixedVariant,
       _tertiary = tertiary,
       _onTertiary = onTertiary,
       _tertiaryContainer = tertiaryContainer,
       _onTertiaryContainer = onTertiaryContainer,
       _tertiaryFixed = tertiaryFixed,
       _tertiaryFixedDim = tertiaryFixedDim,
       _onTertiaryFixed = onTertiaryFixed,
       _onTertiaryFixedVariant = onTertiaryFixedVariant,
       _errorContainer = errorContainer,
       _onErrorContainer = onErrorContainer,
       _surfaceDim = surfaceDim,
       _surfaceBright = surfaceBright,
       _surfaceContainerLowest = surfaceContainerLowest,
       _surfaceContainerLow = surfaceContainerLow,
       _surfaceContainer = surfaceContainer,
       _surfaceContainerHigh = surfaceContainerHigh,
       _surfaceContainerHighest = surfaceContainerHighest,
       _onSurfaceVariant = onSurfaceVariant,
       _outline = outline,
       _outlineVariant = outlineVariant,
       _shadow = shadow,
       _scrim = scrim,
       _inverseSurface = inverseSurface,
       _onInverseSurface = onInverseSurface,
       _inversePrimary = inversePrimary,
       _surfaceTint = surfaceTint,
       _background = background,
       _onBackground = onBackground,
       _surfaceVariant = surfaceVariant;

  /// Whether this is a light scheme or a dark one.
  final Brightness brightness;

  /// The brand colour: filled buttons, the active state of a control.
  final Color primary;

  /// Text and icons drawn on [primary].
  final Color onPrimary;

  /// A quieter fill of the brand colour, for a tonal button or a selected chip.
  final Color? _primaryContainer;
  Color get primaryContainer => _primaryContainer ?? primary;
  final Color? _onPrimaryContainer;
  Color get onPrimaryContainer => _onPrimaryContainer ?? onPrimary;
  final Color? _primaryFixed;
  Color get primaryFixed => _primaryFixed ?? primary;
  final Color? _primaryFixedDim;
  Color get primaryFixedDim => _primaryFixedDim ?? primary;
  final Color? _onPrimaryFixed;
  Color get onPrimaryFixed => _onPrimaryFixed ?? onPrimary;
  final Color? _onPrimaryFixedVariant;
  Color get onPrimaryFixedVariant => _onPrimaryFixedVariant ?? onPrimary;

  /// A less prominent accent than [primary].
  final Color secondary;
  final Color onSecondary;
  final Color? _secondaryContainer;
  Color get secondaryContainer => _secondaryContainer ?? secondary;
  final Color? _onSecondaryContainer;
  Color get onSecondaryContainer => _onSecondaryContainer ?? onSecondary;
  final Color? _secondaryFixed;
  Color get secondaryFixed => _secondaryFixed ?? secondary;
  final Color? _secondaryFixedDim;
  Color get secondaryFixedDim => _secondaryFixedDim ?? secondary;
  final Color? _onSecondaryFixed;
  Color get onSecondaryFixed => _onSecondaryFixed ?? onSecondary;
  final Color? _onSecondaryFixedVariant;
  Color get onSecondaryFixedVariant => _onSecondaryFixedVariant ?? onSecondary;

  /// A contrasting accent, a step round the wheel from [primary].
  final Color? _tertiary;
  Color get tertiary => _tertiary ?? secondary;
  final Color? _onTertiary;
  Color get onTertiary => _onTertiary ?? onSecondary;
  final Color? _tertiaryContainer;
  Color get tertiaryContainer => _tertiaryContainer ?? tertiary;
  final Color? _onTertiaryContainer;
  Color get onTertiaryContainer => _onTertiaryContainer ?? onTertiary;
  final Color? _tertiaryFixed;
  Color get tertiaryFixed => _tertiaryFixed ?? tertiary;
  final Color? _tertiaryFixedDim;
  Color get tertiaryFixedDim => _tertiaryFixedDim ?? tertiary;
  final Color? _onTertiaryFixed;
  Color get onTertiaryFixed => _onTertiaryFixed ?? onTertiary;
  final Color? _onTertiaryFixedVariant;
  Color get onTertiaryFixedVariant => _onTertiaryFixedVariant ?? onTertiary;

  /// Error states.
  final Color error;
  final Color onError;
  final Color? _errorContainer;
  Color get errorContainer => _errorContainer ?? error;
  final Color? _onErrorContainer;
  Color get onErrorContainer => _onErrorContainer ?? onError;

  /// The background of a screen, a card, a sheet.
  final Color surface;

  /// Body text and icons on [surface].
  final Color onSurface;
  final Color? _surfaceDim;
  Color get surfaceDim => _surfaceDim ?? surface;
  final Color? _surfaceBright;
  Color get surfaceBright => _surfaceBright ?? surface;

  /// The surface containers, from the one closest to [surface] to the one that stands furthest off it.
  final Color? _surfaceContainerLowest;
  Color get surfaceContainerLowest => _surfaceContainerLowest ?? surface;
  final Color? _surfaceContainerLow;
  Color get surfaceContainerLow => _surfaceContainerLow ?? surface;
  final Color? _surfaceContainer;
  Color get surfaceContainer => _surfaceContainer ?? surface;
  final Color? _surfaceContainerHigh;
  Color get surfaceContainerHigh => _surfaceContainerHigh ?? surface;
  final Color? _surfaceContainerHighest;
  Color get surfaceContainerHighest => _surfaceContainerHighest ?? surface;

  /// Quieter text and icons on a surface: labels, hints.
  final Color? _onSurfaceVariant;
  Color get onSurfaceVariant => _onSurfaceVariant ?? onSurface;

  /// Borders that have to be seen: a text field, an outlined button.
  final Color? _outline;
  Color get outline => _outline ?? onSurface;

  /// Borders that only separate: a divider.
  final Color? _outlineVariant;
  Color get outlineVariant => _outlineVariant ?? onSurface;
  final Color? _shadow;
  Color get shadow => _shadow ?? const Color(0xFF000000);
  final Color? _scrim;
  Color get scrim => _scrim ?? const Color(0xFF000000);

  /// A surface that stands against the rest: a snackbar.
  final Color? _inverseSurface;
  Color get inverseSurface => _inverseSurface ?? onSurface;
  final Color? _onInverseSurface;
  Color get onInverseSurface => _onInverseSurface ?? surface;
  final Color? _inversePrimary;
  Color get inversePrimary => _inversePrimary ?? onPrimary;

  /// The colour elevation tints a surface with.
  final Color? _surfaceTint;
  Color get surfaceTint => _surfaceTint ?? primary;

  /// Material 2's names, kept because code still says them. Flutter deprecated them in favour of [surface], [onSurface] and [surfaceContainerHighest].
  final Color? _background;
  Color get background => _background ?? surface;
  final Color? _onBackground;
  Color get onBackground => _onBackground ?? onSurface;
  final Color? _surfaceVariant;
  Color get surfaceVariant => _surfaceVariant ?? surface;

  ColorScheme copyWith({
    Brightness? brightness,
    Color? primary,
    Color? onPrimary,
    Color? primaryContainer,
    Color? onPrimaryContainer,
    Color? primaryFixed,
    Color? primaryFixedDim,
    Color? onPrimaryFixed,
    Color? onPrimaryFixedVariant,
    Color? secondary,
    Color? onSecondary,
    Color? secondaryContainer,
    Color? onSecondaryContainer,
    Color? secondaryFixed,
    Color? secondaryFixedDim,
    Color? onSecondaryFixed,
    Color? onSecondaryFixedVariant,
    Color? tertiary,
    Color? onTertiary,
    Color? tertiaryContainer,
    Color? onTertiaryContainer,
    Color? tertiaryFixed,
    Color? tertiaryFixedDim,
    Color? onTertiaryFixed,
    Color? onTertiaryFixedVariant,
    Color? error,
    Color? onError,
    Color? errorContainer,
    Color? onErrorContainer,
    Color? surface,
    Color? onSurface,
    Color? surfaceDim,
    Color? surfaceBright,
    Color? surfaceContainerLowest,
    Color? surfaceContainerLow,
    Color? surfaceContainer,
    Color? surfaceContainerHigh,
    Color? surfaceContainerHighest,
    Color? onSurfaceVariant,
    Color? outline,
    Color? outlineVariant,
    Color? shadow,
    Color? scrim,
    Color? inverseSurface,
    Color? onInverseSurface,
    Color? inversePrimary,
    Color? surfaceTint,
    Color? background,
    Color? onBackground,
    Color? surfaceVariant,
  }) => ColorScheme(
    brightness: brightness ?? this.brightness,
    primary: primary ?? this.primary,
    onPrimary: onPrimary ?? this.onPrimary,
    primaryContainer: primaryContainer ?? _primaryContainer,
    onPrimaryContainer: onPrimaryContainer ?? _onPrimaryContainer,
    primaryFixed: primaryFixed ?? _primaryFixed,
    primaryFixedDim: primaryFixedDim ?? _primaryFixedDim,
    onPrimaryFixed: onPrimaryFixed ?? _onPrimaryFixed,
    onPrimaryFixedVariant: onPrimaryFixedVariant ?? _onPrimaryFixedVariant,
    secondary: secondary ?? this.secondary,
    onSecondary: onSecondary ?? this.onSecondary,
    secondaryContainer: secondaryContainer ?? _secondaryContainer,
    onSecondaryContainer: onSecondaryContainer ?? _onSecondaryContainer,
    secondaryFixed: secondaryFixed ?? _secondaryFixed,
    secondaryFixedDim: secondaryFixedDim ?? _secondaryFixedDim,
    onSecondaryFixed: onSecondaryFixed ?? _onSecondaryFixed,
    onSecondaryFixedVariant:
        onSecondaryFixedVariant ?? _onSecondaryFixedVariant,
    tertiary: tertiary ?? _tertiary,
    onTertiary: onTertiary ?? _onTertiary,
    tertiaryContainer: tertiaryContainer ?? _tertiaryContainer,
    onTertiaryContainer: onTertiaryContainer ?? _onTertiaryContainer,
    tertiaryFixed: tertiaryFixed ?? _tertiaryFixed,
    tertiaryFixedDim: tertiaryFixedDim ?? _tertiaryFixedDim,
    onTertiaryFixed: onTertiaryFixed ?? _onTertiaryFixed,
    onTertiaryFixedVariant: onTertiaryFixedVariant ?? _onTertiaryFixedVariant,
    error: error ?? this.error,
    onError: onError ?? this.onError,
    errorContainer: errorContainer ?? _errorContainer,
    onErrorContainer: onErrorContainer ?? _onErrorContainer,
    surface: surface ?? this.surface,
    onSurface: onSurface ?? this.onSurface,
    surfaceDim: surfaceDim ?? _surfaceDim,
    surfaceBright: surfaceBright ?? _surfaceBright,
    surfaceContainerLowest: surfaceContainerLowest ?? _surfaceContainerLowest,
    surfaceContainerLow: surfaceContainerLow ?? _surfaceContainerLow,
    surfaceContainer: surfaceContainer ?? _surfaceContainer,
    surfaceContainerHigh: surfaceContainerHigh ?? _surfaceContainerHigh,
    surfaceContainerHighest:
        surfaceContainerHighest ?? _surfaceContainerHighest,
    onSurfaceVariant: onSurfaceVariant ?? _onSurfaceVariant,
    outline: outline ?? _outline,
    outlineVariant: outlineVariant ?? _outlineVariant,
    shadow: shadow ?? _shadow,
    scrim: scrim ?? _scrim,
    inverseSurface: inverseSurface ?? _inverseSurface,
    onInverseSurface: onInverseSurface ?? _onInverseSurface,
    inversePrimary: inversePrimary ?? _inversePrimary,
    surfaceTint: surfaceTint ?? _surfaceTint,
    background: background ?? _background,
    onBackground: onBackground ?? _onBackground,
    surfaceVariant: surfaceVariant ?? _surfaceVariant,
  );

  @override
  bool operator ==(Object other) =>
      other is ColorScheme &&
      other.brightness == brightness &&
      other.primary == primary &&
      other.onPrimary == onPrimary &&
      other.primaryContainer == primaryContainer &&
      other.onPrimaryContainer == onPrimaryContainer &&
      other.primaryFixed == primaryFixed &&
      other.primaryFixedDim == primaryFixedDim &&
      other.onPrimaryFixed == onPrimaryFixed &&
      other.onPrimaryFixedVariant == onPrimaryFixedVariant &&
      other.secondary == secondary &&
      other.onSecondary == onSecondary &&
      other.secondaryContainer == secondaryContainer &&
      other.onSecondaryContainer == onSecondaryContainer &&
      other.secondaryFixed == secondaryFixed &&
      other.secondaryFixedDim == secondaryFixedDim &&
      other.onSecondaryFixed == onSecondaryFixed &&
      other.onSecondaryFixedVariant == onSecondaryFixedVariant &&
      other.tertiary == tertiary &&
      other.onTertiary == onTertiary &&
      other.tertiaryContainer == tertiaryContainer &&
      other.onTertiaryContainer == onTertiaryContainer &&
      other.tertiaryFixed == tertiaryFixed &&
      other.tertiaryFixedDim == tertiaryFixedDim &&
      other.onTertiaryFixed == onTertiaryFixed &&
      other.onTertiaryFixedVariant == onTertiaryFixedVariant &&
      other.error == error &&
      other.onError == onError &&
      other.errorContainer == errorContainer &&
      other.onErrorContainer == onErrorContainer &&
      other.surface == surface &&
      other.onSurface == onSurface &&
      other.surfaceDim == surfaceDim &&
      other.surfaceBright == surfaceBright &&
      other.surfaceContainerLowest == surfaceContainerLowest &&
      other.surfaceContainerLow == surfaceContainerLow &&
      other.surfaceContainer == surfaceContainer &&
      other.surfaceContainerHigh == surfaceContainerHigh &&
      other.surfaceContainerHighest == surfaceContainerHighest &&
      other.onSurfaceVariant == onSurfaceVariant &&
      other.outline == outline &&
      other.outlineVariant == outlineVariant &&
      other.shadow == shadow &&
      other.scrim == scrim &&
      other.inverseSurface == inverseSurface &&
      other.onInverseSurface == onInverseSurface &&
      other.inversePrimary == inversePrimary &&
      other.surfaceTint == surfaceTint &&
      other.background == background &&
      other.onBackground == onBackground &&
      other.surfaceVariant == surfaceVariant;

  @override
  int get hashCode => Object.hashAll([
    brightness,
    primary,
    onPrimary,
    primaryContainer,
    onPrimaryContainer,
    primaryFixed,
    primaryFixedDim,
    onPrimaryFixed,
    onPrimaryFixedVariant,
    secondary,
    onSecondary,
    secondaryContainer,
    onSecondaryContainer,
    secondaryFixed,
    secondaryFixedDim,
    onSecondaryFixed,
    onSecondaryFixedVariant,
    tertiary,
    onTertiary,
    tertiaryContainer,
    onTertiaryContainer,
    tertiaryFixed,
    tertiaryFixedDim,
    onTertiaryFixed,
    onTertiaryFixedVariant,
    error,
    onError,
    errorContainer,
    onErrorContainer,
    surface,
    onSurface,
    surfaceDim,
    surfaceBright,
    surfaceContainerLowest,
    surfaceContainerLow,
    surfaceContainer,
    surfaceContainerHigh,
    surfaceContainerHighest,
    onSurfaceVariant,
    outline,
    outlineVariant,
    shadow,
    scrim,
    inverseSurface,
    onInverseSurface,
    inversePrimary,
    surfaceTint,
    background,
    onBackground,
    surfaceVariant,
  ]);
}

/// A value an app adds to its theme: a set of brand colours, a spacing scale.
///
/// ```dart
/// class Brand extends ThemeExtension<Brand> {
///   const Brand(this.accent);
///   final Color accent;
///   @override
///   Brand copyWith({Color? accent}) => Brand(accent ?? this.accent);
///   @override
///   Brand lerp(Brand? other, double t) => this;
/// }
///
/// ThemeData(extensions: const [Brand(Colors.pink)]);
/// Theme.of(context).extension<Brand>()!.accent;
/// ```
abstract class ThemeExtension<T extends ThemeExtension<T>> {
  const ThemeExtension();

  /// What the extension is filed under: its own type.
  Object get type => T;

  ThemeExtension<T> copyWith();

  /// Flutter calls this while it animates between two themes. Nothing here
  /// animates a theme, so it is never called - it is part of the contract so
  /// an extension written for Flutter compiles.
  ThemeExtension<T> lerp(covariant ThemeExtension<T>? other, double t);
}

/// The colour and size icons take when they do not say.
class IconThemeData {
  const IconThemeData({this.color, this.size, this.opacity});

  final Color? color;
  final double? size;
  final double? opacity;

  IconThemeData copyWith({Color? color, double? size, double? opacity}) =>
      IconThemeData(
        color: color ?? this.color,
        size: size ?? this.size,
        opacity: opacity ?? this.opacity,
      );

  IconThemeData merge(IconThemeData? other) => other == null
      ? this
      : copyWith(color: other.color, size: other.size, opacity: other.opacity);

  @override
  bool operator ==(Object other) =>
      other is IconThemeData &&
      other.color == color &&
      other.size == size &&
      other.opacity == opacity;
  @override
  int get hashCode => Object.hash(color, size, opacity);
}

/// How app bars look when they do not say.
class AppBarTheme {
  const AppBarTheme({
    this.backgroundColor,
    this.foregroundColor,
    this.elevation,
    this.scrolledUnderElevation,
    this.shadowColor,
    this.surfaceTintColor,
    this.centerTitle,
    this.titleSpacing,
    this.toolbarHeight,
    this.titleTextStyle,
    this.toolbarTextStyle,
    this.iconTheme,
    this.actionsIconTheme,
  });

  final Color? backgroundColor;
  final Color? foregroundColor;
  final double? elevation;

  /// The rest are accepted so a theme written for Flutter compiles; an app
  /// bar is drawn by the platform, which decides these for itself.
  final double? scrolledUnderElevation;
  final Color? shadowColor;
  final Color? surfaceTintColor;
  final bool? centerTitle;
  final double? titleSpacing;
  final double? toolbarHeight;
  final TextStyle? titleTextStyle;
  final TextStyle? toolbarTextStyle;
  final IconThemeData? iconTheme;
  final IconThemeData? actionsIconTheme;

  AppBarTheme copyWith({
    Color? backgroundColor,
    Color? foregroundColor,
    double? elevation,
    double? scrolledUnderElevation,
    Color? shadowColor,
    Color? surfaceTintColor,
    bool? centerTitle,
    double? titleSpacing,
    double? toolbarHeight,
    TextStyle? titleTextStyle,
    TextStyle? toolbarTextStyle,
    IconThemeData? iconTheme,
    IconThemeData? actionsIconTheme,
  }) => AppBarTheme(
    backgroundColor: backgroundColor ?? this.backgroundColor,
    foregroundColor: foregroundColor ?? this.foregroundColor,
    elevation: elevation ?? this.elevation,
    scrolledUnderElevation:
        scrolledUnderElevation ?? this.scrolledUnderElevation,
    shadowColor: shadowColor ?? this.shadowColor,
    surfaceTintColor: surfaceTintColor ?? this.surfaceTintColor,
    centerTitle: centerTitle ?? this.centerTitle,
    titleSpacing: titleSpacing ?? this.titleSpacing,
    toolbarHeight: toolbarHeight ?? this.toolbarHeight,
    titleTextStyle: titleTextStyle ?? this.titleTextStyle,
    toolbarTextStyle: toolbarTextStyle ?? this.toolbarTextStyle,
    iconTheme: iconTheme ?? this.iconTheme,
    actionsIconTheme: actionsIconTheme ?? this.actionsIconTheme,
  );
}

/// Whether a snackbar is fixed to the bottom edge or floats above it.
enum SnackBarBehavior { fixed, floating }

/// How snackbars look when they do not say.
class SnackBarThemeData {
  const SnackBarThemeData({
    this.backgroundColor,
    this.actionTextColor,
    this.disabledActionTextColor,
    this.contentTextStyle,
    this.elevation,
    this.shape,
    this.behavior,
    this.width,
    this.insetPadding,
    this.showCloseIcon,
    this.closeIconColor,
  });

  final Color? backgroundColor;
  final Color? actionTextColor;
  final Color? disabledActionTextColor;
  final TextStyle? contentTextStyle;
  final double? elevation;
  final ShapeBorder? shape;
  final SnackBarBehavior? behavior;
  final double? width;
  final EdgeInsets? insetPadding;
  final bool? showCloseIcon;
  final Color? closeIconColor;

  SnackBarThemeData copyWith({
    Color? backgroundColor,
    Color? actionTextColor,
    Color? disabledActionTextColor,
    TextStyle? contentTextStyle,
    double? elevation,
    ShapeBorder? shape,
    SnackBarBehavior? behavior,
    double? width,
    EdgeInsets? insetPadding,
    bool? showCloseIcon,
    Color? closeIconColor,
  }) => SnackBarThemeData(
    backgroundColor: backgroundColor ?? this.backgroundColor,
    actionTextColor: actionTextColor ?? this.actionTextColor,
    disabledActionTextColor:
        disabledActionTextColor ?? this.disabledActionTextColor,
    contentTextStyle: contentTextStyle ?? this.contentTextStyle,
    elevation: elevation ?? this.elevation,
    shape: shape ?? this.shape,
    behavior: behavior ?? this.behavior,
    width: width ?? this.width,
    insetPadding: insetPadding ?? this.insetPadding,
    showCloseIcon: showCloseIcon ?? this.showCloseIcon,
    closeIconColor: closeIconColor ?? this.closeIconColor,
  );
}

/// How cards look when they do not say.
class CardThemeData {
  const CardThemeData({
    this.color,
    this.shadowColor,
    this.surfaceTintColor,
    this.elevation,
    this.margin,
    this.shape,
    this.clipBehavior,
  });

  final Color? color;
  final Color? shadowColor;
  final Color? surfaceTintColor;
  final double? elevation;
  final EdgeInsetsGeometry? margin;
  final ShapeBorder? shape;
  final Clip? clipBehavior;
}

/// How dividers look when they do not say.
class DividerThemeData {
  const DividerThemeData({
    this.color,
    this.space,
    this.thickness,
    this.indent,
    this.endIndent,
  });

  final Color? color;
  final double? space;
  final double? thickness;
  final double? indent;
  final double? endIndent;
}

/// Everything a Material app's look is derived from: a [ColorScheme], a
/// [TextTheme], and the per-component themes.
///
/// ```dart
/// ThemeData(colorSchemeSeed: Colors.teal, brightness: Brightness.dark)
/// ```
///
/// The colours come from [colorScheme] if one is given, from
/// [colorSchemeSeed] otherwise, and from Material 3's own purple seed when
/// neither is.
///
/// There are two audiences for a theme here. Widgets read it through
/// `Theme.of(context)`, exactly as in Flutter. The renderers - which colour
/// the app bar, the native buttons, the dialogs - read the protocol's small
/// [AppTheme] instead, handed to `runApp` before any widget builds;
/// [toAppTheme] makes that one from this one, so an app declares its colours
/// once.
class ThemeData {
  /// Builds a theme, deriving whatever is not given.
  factory ThemeData({
    ColorScheme? colorScheme,
    Color? colorSchemeSeed,
    Brightness? brightness,
    bool? useMaterial3,
    Iterable<ThemeExtension<dynamic>>? extensions,
    TextTheme? textTheme,
    String? fontFamily,
    Color? primaryColor,
    MaterialColor? primarySwatch,
    Color? scaffoldBackgroundColor,
    Color? canvasColor,
    Color? cardColor,
    Color? dividerColor,
    Color? disabledColor,
    Color? hintColor,
    IconThemeData? iconTheme,
    AppBarTheme? appBarTheme,
    SnackBarThemeData? snackBarTheme,
    CardThemeData? cardTheme,
    DividerThemeData? dividerTheme,
    VisualDensity? visualDensity,
    Object? inputDecorationTheme,
  }) {
    final scheme =
        colorScheme ??
        ColorScheme.fromSeed(
          seedColor:
              colorSchemeSeed ??
              primarySwatch ??
              primaryColor ??
              const Color(0xFF6750A4),
          brightness: brightness ?? Brightness.light,
        );
    final isDark = scheme.brightness == Brightness.dark;
    return ThemeData._(
      colorScheme: scheme,
      useMaterial3: useMaterial3 ?? true,
      extensions: {
        for (final extension in extensions ?? const <ThemeExtension<dynamic>>[])
          extension.type: extension,
      },
      textTheme: TextTheme._material3
          .apply(
            bodyColor: scheme.onSurface,
            displayColor: scheme.onSurface,
            fontFamily: fontFamily,
          )
          .merge(textTheme),
      // Flutter's own rule: the brand colour in light, the surface in dark,
      // because a saturated primary is too loud as a dark theme's app bar.
      primaryColor: primaryColor ?? (isDark ? scheme.surface : scheme.primary),
      scaffoldBackgroundColor: scaffoldBackgroundColor ?? scheme.surface,
      canvasColor: canvasColor ?? scheme.surface,
      cardColor: cardColor ?? scheme.surface,
      dividerColor: dividerColor ?? scheme.outlineVariant,
      disabledColor: disabledColor ?? scheme.onSurface.withOpacity(0.38),
      hintColor: hintColor ?? scheme.onSurface.withOpacity(0.6),
      iconTheme: iconTheme ?? IconThemeData(color: scheme.onSurface, size: 24),
      appBarTheme: appBarTheme ?? const AppBarTheme(),
      snackBarTheme: snackBarTheme ?? const SnackBarThemeData(),
      cardTheme: cardTheme ?? const CardThemeData(),
      dividerTheme: dividerTheme ?? const DividerThemeData(),
      visualDensity: visualDensity ?? VisualDensity.standard,
      inputDecorationTheme: inputDecorationTheme,
    );
  }

  /// The default light theme.
  /// Whether [color] is one to put dark or light text on, by Material's rule
  /// of thumb: a relative luminance past the point where black text has the
  /// better contrast is "light".
  static Brightness estimateBrightnessForColor(Color color) {
    final luminance = color.computeLuminance();
    const threshold = 0.15;
    return (luminance + 0.05) * (luminance + 0.05) > threshold
        ? Brightness.light
        : Brightness.dark;
  }

  factory ThemeData.light({bool? useMaterial3}) =>
      ThemeData(brightness: Brightness.light, useMaterial3: useMaterial3);

  /// The default dark theme.
  factory ThemeData.dark({bool? useMaterial3}) =>
      ThemeData(brightness: Brightness.dark, useMaterial3: useMaterial3);

  /// A widget-side theme from the protocol's palette, so `Theme.of(context)`
  /// agrees with what the renderers are drawing when an app only gave
  /// `runApp` an [AppTheme].
  ///
  /// The palette's colours become the roles they correspond to; the roles a
  /// palette has no word for are derived from its primary as
  /// [ColorScheme.fromSeed] would. [dark] reads [AppTheme.dark] instead of
  /// the theme's own colours. The palette itself is kept, and [appTheme]
  /// hands it back unchanged.
  factory ThemeData.fromAppTheme(AppTheme theme, {bool dark = false}) {
    final palette = dark ? theme.dark : theme;
    final surfaceVariant = Color.fromHex(palette.surfaceVariant);
    final surface = Color.fromHex(palette.surface);
    final data = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Color.fromHex(palette.primary),
        brightness: dark ? Brightness.dark : Brightness.light,
        primary: Color.fromHex(palette.primary),
        onPrimary: Color.fromHex(palette.onPrimary),
        secondary: Color.fromHex(palette.secondary),
        error: Color.fromHex(palette.error),
        surface: surface,
        surfaceContainerLowest: surface,
        surfaceContainerLow: surfaceVariant,
        surfaceContainer: surfaceVariant,
        surfaceContainerHigh: surfaceVariant,
        surfaceContainerHighest: surfaceVariant,
        onSurface: Color.fromHex(palette.text),
        onSurfaceVariant: Color.fromHex(palette.textSecondary),
        outlineVariant: Color.fromHex(palette.divider),
      ),
    );
    return data._withAppTheme(theme, dark);
  }

  ThemeData._({
    required this.colorScheme,
    required this.useMaterial3,
    required this.extensions,
    required this.textTheme,
    required this.primaryColor,
    required this.scaffoldBackgroundColor,
    required this.canvasColor,
    required this.cardColor,
    required this.dividerColor,
    required this.disabledColor,
    required this.hintColor,
    required this.iconTheme,
    required this.appBarTheme,
    required this.snackBarTheme,
    required this.cardTheme,
    required this.dividerTheme,
    required this.visualDensity,
    required this.inputDecorationTheme,
    AppTheme? appTheme,
    bool appThemeDark = false,
  }) : _appTheme = appTheme,
       _appThemeDark = appThemeDark;

  final ColorScheme colorScheme;

  /// True unless the app says otherwise, as in Flutter. What it decides here
  /// is the one thing the two generations visibly disagree on and the widget
  /// layer chooses: an [AppBar] with no colour of its own is the surface
  /// under Material 3 and the primary (in a light theme) under Material 2.
  /// Shapes and sizes are the renderers' and are Material 3's either way.
  final bool useMaterial3;

  /// The app's own additions, by type - see [ThemeExtension].
  final Map<Object, ThemeExtension<dynamic>> extensions;

  /// The fifteen Material 3 styles, coloured [ColorScheme.onSurface], with
  /// whatever the app passed laid over them.
  final TextTheme textTheme;
  final Color primaryColor;
  final Color scaffoldBackgroundColor;
  final Color canvasColor;
  final Color cardColor;
  final Color dividerColor;
  final Color disabledColor;
  final Color hintColor;
  final IconThemeData iconTheme;
  final AppBarTheme appBarTheme;
  final SnackBarThemeData snackBarTheme;
  final CardThemeData cardTheme;
  final DividerThemeData dividerTheme;

  /// Accepted for compatibility - see [VisualDensity].
  final VisualDensity visualDensity;

  /// Accepted and kept, typed loosely because the facade has no
  /// `InputDecorationTheme`: a text field is drawn by the platform, which has
  /// its own idea of an outline.
  final Object? inputDecorationTheme;

  /// The [AppTheme] this was made from, when it was made from one.
  final AppTheme? _appTheme;
  final bool _appThemeDark;

  Brightness get brightness => colorScheme.brightness;

  /// The app's addition of type [T], or null.
  T? extension<T>() => extensions[T] as T?;

  ThemeData _withAppTheme(AppTheme theme, bool dark) => ThemeData._(
    colorScheme: colorScheme,
    useMaterial3: useMaterial3,
    extensions: extensions,
    textTheme: textTheme,
    primaryColor: primaryColor,
    scaffoldBackgroundColor: scaffoldBackgroundColor,
    canvasColor: canvasColor,
    cardColor: cardColor,
    dividerColor: dividerColor,
    disabledColor: disabledColor,
    hintColor: hintColor,
    iconTheme: iconTheme,
    appBarTheme: appBarTheme,
    snackBarTheme: snackBarTheme,
    cardTheme: cardTheme,
    dividerTheme: dividerTheme,
    visualDensity: visualDensity,
    inputDecorationTheme: inputDecorationTheme,
    appTheme: theme,
    appThemeDark: dark,
  );

  /// This theme with some of it replaced.
  ///
  /// A new [colorScheme] replaces the scheme and nothing else: colours that
  /// were derived from the old one (the scaffold background, the text
  /// colours) stay as they were unless they are passed too, as in Flutter.
  ThemeData copyWith({
    ColorScheme? colorScheme,
    Brightness? brightness,
    bool? useMaterial3,
    Iterable<ThemeExtension<dynamic>>? extensions,
    TextTheme? textTheme,
    Color? primaryColor,
    Color? scaffoldBackgroundColor,
    Color? canvasColor,
    Color? cardColor,
    Color? dividerColor,
    Color? disabledColor,
    Color? hintColor,
    IconThemeData? iconTheme,
    AppBarTheme? appBarTheme,
    SnackBarThemeData? snackBarTheme,
    CardThemeData? cardTheme,
    DividerThemeData? dividerTheme,
    VisualDensity? visualDensity,
    Object? inputDecorationTheme,
  }) => ThemeData._(
    colorScheme: (colorScheme ?? this.colorScheme).copyWith(
      brightness: brightness,
    ),
    useMaterial3: useMaterial3 ?? this.useMaterial3,
    extensions: extensions == null
        ? this.extensions
        : {for (final extension in extensions) extension.type: extension},
    textTheme: textTheme ?? this.textTheme,
    primaryColor: primaryColor ?? this.primaryColor,
    scaffoldBackgroundColor:
        scaffoldBackgroundColor ?? this.scaffoldBackgroundColor,
    canvasColor: canvasColor ?? this.canvasColor,
    cardColor: cardColor ?? this.cardColor,
    dividerColor: dividerColor ?? this.dividerColor,
    disabledColor: disabledColor ?? this.disabledColor,
    hintColor: hintColor ?? this.hintColor,
    iconTheme: iconTheme ?? this.iconTheme,
    appBarTheme: appBarTheme ?? this.appBarTheme,
    snackBarTheme: snackBarTheme ?? this.snackBarTheme,
    cardTheme: cardTheme ?? this.cardTheme,
    dividerTheme: dividerTheme ?? this.dividerTheme,
    visualDensity: visualDensity ?? this.visualDensity,
    inputDecorationTheme: inputDecorationTheme ?? this.inputDecorationTheme,
  );

  /// The protocol's palette for this theme: the [AppTheme] it was made from
  /// if there was one, and otherwise this theme's own colours as one - the
  /// same in either mode, since a single [ThemeData] is a single appearance.
  AppTheme get appTheme => _appTheme ?? toAppTheme(mode: ThemeMode.light);

  /// The palette the renderers colour their own chrome from, made from this
  /// theme.
  ///
  /// An app hands the result to `runApp(appTheme:)` and the same themes to
  /// `MaterialApp`, so the app bar the platform draws and the widgets the app
  /// composes agree:
  ///
  /// ```dart
  /// final light = ThemeData(colorSchemeSeed: Colors.teal);
  /// final dark = ThemeData(
  ///   colorSchemeSeed: Colors.teal,
  ///   brightness: Brightness.dark,
  /// );
  /// runApp(
  ///   MaterialApp(theme: light, darkTheme: dark, home: const Home()),
  ///   appTheme: light.toAppTheme(dark: dark),
  /// );
  /// ```
  ///
  /// The mapping, role to palette entry: `primary`, `onPrimary`, `secondary`,
  /// `surface` and `error` are their namesakes; `text` is `onSurface`;
  /// `textSecondary` is `onSurfaceVariant`; `divider` is `outlineVariant`; and
  /// `surfaceVariant` - the palette's "raised surface", used for cards, field
  /// fills and sheets alike - is `surfaceContainer`, the middle of the five
  /// container roles Material splits that job between. The palette's
  /// `success`, `warning` and `info` have no Material role and keep the
  /// framework's defaults for the brightness.
  ///
  /// [dark] is the theme for dark mode; without one this theme is used in
  /// both, which is what Flutter's `MaterialApp` does with no `darkTheme`.
  /// [mode] picks between them, or leaves it to the device.
  AppTheme toAppTheme({ThemeData? dark, ThemeMode mode = ThemeMode.system}) =>
      _palette(
        mode: switch (mode) {
          ThemeMode.system => AppThemeMode.system,
          ThemeMode.light => AppThemeMode.light,
          ThemeMode.dark => AppThemeMode.dark,
        },
        dark: (dark ?? this)._palette(),
      );

  /// This theme's colours as one flat palette.
  AppTheme _palette({AppThemeMode mode = AppThemeMode.light, AppTheme? dark}) {
    final made = _appTheme;
    // The entries Material has no role for: from the palette this theme was
    // made from when there was one, else the framework's for the brightness.
    final extras = made != null
        ? (_appThemeDark ? made.dark : made)
        : (brightness == Brightness.dark
              ? AppTheme.darkFallback
              : AppTheme.fallback);
    return AppTheme(
      primary: colorScheme.primary._hex,
      onPrimary: colorScheme.onPrimary._hex,
      secondary: colorScheme.secondary._hex,
      surface: colorScheme.surface._hex,
      surfaceVariant: colorScheme.surfaceContainer._hex,
      text: colorScheme.onSurface._hex,
      textSecondary: colorScheme.onSurfaceVariant._hex,
      divider: colorScheme.outlineVariant._hex,
      error: colorScheme.error._hex,
      success: extras.success,
      warning: extras.warning,
      info: extras.info,
      glassTransparency: (made ?? AppTheme.fallback).glassTransparency,
      glassChrome: (made ?? AppTheme.fallback).glassChrome,
      mode: mode,
      dark: dark,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ThemeData &&
      other.colorScheme == colorScheme &&
      other.textTheme == textTheme &&
      other.primaryColor == primaryColor &&
      other.scaffoldBackgroundColor == scaffoldBackgroundColor &&
      other.canvasColor == canvasColor &&
      other.cardColor == cardColor &&
      other.dividerColor == dividerColor &&
      other.disabledColor == disabledColor &&
      other.hintColor == hintColor &&
      other.iconTheme == iconTheme &&
      other._appTheme == _appTheme &&
      other._appThemeDark == _appThemeDark &&
      _sameExtensions(other.extensions, extensions);

  static bool _sameExtensions(
    Map<Object, ThemeExtension<dynamic>> a,
    Map<Object, ThemeExtension<dynamic>> b,
  ) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    colorScheme,
    textTheme,
    primaryColor,
    scaffoldBackgroundColor,
    canvasColor,
    cardColor,
    dividerColor,
    disabledColor,
    hintColor,
    iconTheme,
    _appTheme,
    _appThemeDark,
  );
}
