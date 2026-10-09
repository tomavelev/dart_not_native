part of '../../widgets.dart';

// ---------------------------------------------------------------------------
// Painting value types: colours, geometry, borders, decorations, alignment.
//
// These are Flutter's shapes, written out in pure Dart, so a screen that says
// `BoxDecoration(color: Colors.teal.shade50, borderRadius:
// BorderRadius.circular(12))` compiles here unchanged. None of them draws
// anything: each is a description the widgets turn into node props, and the
// private getters at the bottom of a class (`_hex`, `_ltrb`, `_json`) are the
// one place that description becomes the wire form.
// ---------------------------------------------------------------------------

/// A 0xAARRGGBB colour, like Flutter's.
///
/// Alpha travels: an opaque colour reaches the renderers as `#rrggbb` and a
/// translucent one as `#aarrggbb`, which all four accept.
class Color {
  /// A colour from the low 32 bits of [value], as `0xAARRGGBB`.
  const Color(int value) : value = value & 0xFFFFFFFF;

  /// A colour from four 0..255 channels.
  const Color.fromARGB(int a, int r, int g, int b)
    : value =
          (((a & 0xff) << 24) |
              ((r & 0xff) << 16) |
              ((g & 0xff) << 8) |
              ((b & 0xff) << 0)) &
          0xFFFFFFFF;

  /// A colour from three 0..255 channels and an opacity from 0 to 1, the way
  /// CSS spells `rgba()`.
  const Color.fromRGBO(int r, int g, int b, double opacity)
    : value =
          ((((opacity * 0xff ~/ 1) & 0xff) << 24) |
              ((r & 0xff) << 16) |
              ((g & 0xff) << 8) |
              ((b & 0xff) << 0)) &
          0xFFFFFFFF;

  /// A colour from four 0..1 channels, Flutter's newer spelling.
  factory Color.from({
    required double alpha,
    required double red,
    required double green,
    required double blue,
  }) => Color.fromARGB(
    _channel(alpha),
    _channel(red),
    _channel(green),
    _channel(blue),
  );

  /// A colour from a `#RRGGBB` (or `#AARRGGBB`) string, for design-system tokens
  /// that are hex strings. Not Flutter's; the protocol's colours are strings,
  /// and this is the way back from one.
  factory Color.fromHex(String hex) {
    var h = hex.replaceFirst('#', '');
    if (h.length == 6) h = 'FF$h';
    return Color(int.parse(h, radix: 16));
  }

  /// The colour as `0xAARRGGBB`.
  final int value;

  /// The same number, under the name Flutter gave it when [value] was
  /// deprecated there.
  int toARGB32() => value;

  /// The channels as 0..1 doubles.
  double get a => alpha / 255;
  double get r => red / 255;
  double get g => green / 255;
  double get b => blue / 255;

  /// The channels as 0..255 integers.
  int get alpha => (value >> 24) & 0xff;
  int get red => (value >> 16) & 0xff;
  int get green => (value >> 8) & 0xff;
  int get blue => value & 0xff;

  /// The alpha channel as 0..1.
  double get opacity => alpha / 255;

  /// This colour with the given channels (0..1) replaced.
  Color withValues({double? alpha, double? red, double? green, double? blue}) =>
      Color.fromARGB(
        alpha == null ? this.alpha : _channel(alpha),
        red == null ? this.red : _channel(red),
        green == null ? this.green : _channel(green),
        blue == null ? this.blue : _channel(blue),
      );

  /// This colour at [opacity] (0..1).
  Color withOpacity(double opacity) => withAlpha((255.0 * opacity).round());

  /// This colour with its alpha replaced by [a] (0..255).
  Color withAlpha(int a) => Color.fromARGB(a, red, green, blue);
  Color withRed(int r) => Color.fromARGB(alpha, r, green, blue);
  Color withGreen(int g) => Color.fromARGB(alpha, red, g, blue);
  Color withBlue(int b) => Color.fromARGB(alpha, red, green, b);

  /// How bright the colour reads, 0 (black) to 1 (white), by the WCAG formula -
  /// the number to compare when choosing black or white text for a fill.
  double computeLuminance() =>
      0.2126 * _linear(red / 255) +
      0.7152 * _linear(green / 255) +
      0.0722 * _linear(blue / 255);

  /// The colour [t] of the way from [a] to [b], channel by channel. A null end
  /// is treated as the other end made transparent, as Flutter does.
  static Color? lerp(Color? a, Color? b, double t) {
    if (b == null) {
      return a == null ? null : _scaleAlpha(a, 1.0 - t);
    }
    if (a == null) return _scaleAlpha(b, t);
    int mix(int from, int to) => (from + (to - from) * t).round().clamp(0, 255);
    return Color.fromARGB(
      mix(a.alpha, b.alpha),
      mix(a.red, b.red),
      mix(a.green, b.green),
      mix(a.blue, b.blue),
    );
  }

  /// [foreground] painted over [background], as one colour.
  static Color alphaBlend(Color foreground, Color background) {
    final alpha = foreground.alpha;
    if (alpha == 0x00) return background;
    final invAlpha = 0xff - alpha;
    var backAlpha = background.alpha;
    if (backAlpha == 0xff) {
      return Color.fromARGB(
        0xff,
        (alpha * foreground.red + invAlpha * background.red) ~/ 0xff,
        (alpha * foreground.green + invAlpha * background.green) ~/ 0xff,
        (alpha * foreground.blue + invAlpha * background.blue) ~/ 0xff,
      );
    }
    backAlpha = (backAlpha * invAlpha) ~/ 0xff;
    final outAlpha = alpha + backAlpha;
    return Color.fromARGB(
      outAlpha,
      (foreground.red * alpha + background.red * backAlpha) ~/ outAlpha,
      (foreground.green * alpha + background.green * backAlpha) ~/ outAlpha,
      (foreground.blue * alpha + background.blue * backAlpha) ~/ outAlpha,
    );
  }

  static int _channel(double v) => (v * 255).round().clamp(0, 255);

  static Color _scaleAlpha(Color c, double factor) =>
      c.withAlpha((c.alpha * factor).round().clamp(0, 255));

  static double _linear(double c) =>
      c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

  /// The wire form: `#rrggbb` when opaque, `#aarrggbb` otherwise. The short
  /// form is kept for opaque colours because it is what every tree written
  /// before alpha travelled already says.
  String get _hex => alpha == 0xff
      ? '#${(value & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}'
      : '#${value.toRadixString(16).padLeft(8, '0')}';

  @override
  bool operator ==(Object other) => other is Color && other.value == value;
  @override
  int get hashCode => value.hashCode;
  @override
  String toString() => 'Color(0x${value.toRadixString(16).padLeft(8, '0')})';
}

/// A colour as hue, saturation and lightness - the form in which "the same
/// colour, lighter" is one number changed.
class HSLColor {
  const HSLColor.fromAHSL(
    this.alpha,
    this.hue,
    this.saturation,
    this.lightness,
  );

  factory HSLColor.fromColor(Color color) {
    final red = color.red / 255;
    final green = color.green / 255;
    final blue = color.blue / 255;
    final max = math.max(red, math.max(green, blue));
    final min = math.min(red, math.min(green, blue));
    final delta = max - min;
    var hue = 0.0;
    if (delta != 0) {
      if (max == red) {
        hue = 60 * (((green - blue) / delta) % 6);
      } else if (max == green) {
        hue = 60 * (((blue - red) / delta) + 2);
      } else {
        hue = 60 * (((red - green) / delta) + 4);
      }
    }
    if (hue < 0) hue += 360;
    final lightness = (max + min) / 2;
    final saturation = lightness == 1 || lightness == 0
        ? 0.0
        : (delta / (1 - (2 * lightness - 1).abs())).clamp(0.0, 1.0);
    return HSLColor.fromAHSL(color.alpha / 255, hue, saturation, lightness);
  }

  /// 0 (transparent) to 1 (opaque).
  final double alpha;

  /// Degrees round the colour wheel, 0 to 360: 0 is red, 120 green, 240 blue.
  final double hue;

  /// 0 (grey) to 1 (as vivid as this lightness allows).
  final double saturation;

  /// 0 (black) to 1 (white).
  final double lightness;

  HSLColor withAlpha(double alpha) =>
      HSLColor.fromAHSL(alpha, hue, saturation, lightness);
  HSLColor withHue(double hue) =>
      HSLColor.fromAHSL(alpha, hue, saturation, lightness);
  HSLColor withSaturation(double saturation) =>
      HSLColor.fromAHSL(alpha, hue, saturation, lightness);
  HSLColor withLightness(double lightness) =>
      HSLColor.fromAHSL(alpha, hue, saturation, lightness);

  Color toColor() {
    final chroma = (1 - (2 * lightness - 1).abs()) * saturation;
    final h = (hue % 360) / 60;
    final secondary = chroma * (1 - ((h % 2) - 1).abs());
    final match = lightness - chroma / 2;
    double red, green, blue;
    if (h < 1) {
      (red, green, blue) = (chroma, secondary, 0.0);
    } else if (h < 2) {
      (red, green, blue) = (secondary, chroma, 0.0);
    } else if (h < 3) {
      (red, green, blue) = (0.0, chroma, secondary);
    } else if (h < 4) {
      (red, green, blue) = (0.0, secondary, chroma);
    } else if (h < 5) {
      (red, green, blue) = (secondary, 0.0, chroma);
    } else {
      (red, green, blue) = (chroma, 0.0, secondary);
    }
    return Color.fromARGB(
      (alpha * 255).round().clamp(0, 255),
      ((red + match) * 255).round().clamp(0, 255),
      ((green + match) * 255).round().clamp(0, 255),
      ((blue + match) * 255).round().clamp(0, 255),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is HSLColor &&
      other.alpha == alpha &&
      other.hue == hue &&
      other.saturation == saturation &&
      other.lightness == lightness;
  @override
  int get hashCode => Object.hash(alpha, hue, saturation, lightness);
  @override
  String toString() => 'HSLColor($alpha, $hue, $saturation, $lightness)';
}

/// A colour that also has a table of related colours, reached with `[]`.
class ColorSwatch<T> extends Color {
  const ColorSwatch(super.primary, this._swatch);

  final Map<T, Color> _swatch;

  /// The shade filed under [key], or null.
  Color? operator [](T key) => _swatch[key];

  /// The keys this swatch has a colour for.
  Iterable<T> get keys => _swatch.keys;
}

/// A Material colour and its ten shades, 50 (lightest) to 900 (darkest). The
/// colour itself is shade 500.
class MaterialColor extends ColorSwatch<int> {
  const MaterialColor(super.primary, super.swatch);

  Color get shade50 => this[50]!;
  Color get shade100 => this[100]!;
  Color get shade200 => this[200]!;
  Color get shade300 => this[300]!;
  Color get shade400 => this[400]!;
  Color get shade500 => this[500]!;
  Color get shade600 => this[600]!;
  Color get shade700 => this[700]!;
  Color get shade800 => this[800]!;
  Color get shade900 => this[900]!;
}

/// A Material accent colour and its four shades. The colour itself is shade
/// 200.
class MaterialAccentColor extends ColorSwatch<int> {
  const MaterialAccentColor(super.primary, super.swatch);

  Color get shade100 => this[100]!;
  Color get shade200 => this[200]!;
  Color get shade400 => this[400]!;
  Color get shade700 => this[700]!;
}

/// The Material palette, with Flutter's names and Flutter's values.
///
/// A colour with shades is a [MaterialColor]: `Colors.teal` is its 500, and
/// `Colors.teal.shade50` or `Colors.teal[50]` the lightest of the ten. The
/// accent families are [MaterialAccentColor]s with four shades each.
abstract final class Colors {
  /// Nothing at all: fully transparent.
  static const Color transparent = Color(0x00000000);

  static const Color black = Color(0xFF000000);

  /// Black at 87%, 54%, 45%, 38%, 26% and 12% - Material's text, icon and
  /// divider greys on a light ground.
  static const Color black87 = Color(0xDD000000);
  static const Color black54 = Color(0x8A000000);
  static const Color black45 = Color(0x73000000);
  static const Color black38 = Color(0x61000000);
  static const Color black26 = Color(0x42000000);
  static const Color black12 = Color(0x1F000000);

  static const Color white = Color(0xFFFFFFFF);

  /// White at 70% down to 10% - the same greys on a dark ground.
  static const Color white70 = Color(0xB3FFFFFF);
  static const Color white60 = Color(0x99FFFFFF);
  static const Color white54 = Color(0x8AFFFFFF);
  static const Color white38 = Color(0x62FFFFFF);
  static const Color white30 = Color(0x4DFFFFFF);
  static const Color white24 = Color(0x3DFFFFFF);
  static const Color white12 = Color(0x1FFFFFFF);
  static const Color white10 = Color(0x1AFFFFFF);

  static const MaterialColor red = MaterialColor(0xFFF44336, <int, Color>{
    50: Color(0xFFFFEBEE),
    100: Color(0xFFFFCDD2),
    200: Color(0xFFEF9A9A),
    300: Color(0xFFE57373),
    400: Color(0xFFEF5350),
    500: Color(0xFFF44336),
    600: Color(0xFFE53935),
    700: Color(0xFFD32F2F),
    800: Color(0xFFC62828),
    900: Color(0xFFB71C1C),
  });

  static const MaterialAccentColor redAccent =
      MaterialAccentColor(0xFFFF5252, <int, Color>{
        100: Color(0xFFFF8A80),
        200: Color(0xFFFF5252),
        400: Color(0xFFFF1744),
        700: Color(0xFFD50000),
      });

  static const MaterialColor pink = MaterialColor(0xFFE91E63, <int, Color>{
    50: Color(0xFFFCE4EC),
    100: Color(0xFFF8BBD0),
    200: Color(0xFFF48FB1),
    300: Color(0xFFF06292),
    400: Color(0xFFEC407A),
    500: Color(0xFFE91E63),
    600: Color(0xFFD81B60),
    700: Color(0xFFC2185B),
    800: Color(0xFFAD1457),
    900: Color(0xFF880E4F),
  });

  static const MaterialAccentColor pinkAccent =
      MaterialAccentColor(0xFFFF4081, <int, Color>{
        100: Color(0xFFFF80AB),
        200: Color(0xFFFF4081),
        400: Color(0xFFF50057),
        700: Color(0xFFC51162),
      });

  static const MaterialColor purple = MaterialColor(0xFF9C27B0, <int, Color>{
    50: Color(0xFFF3E5F5),
    100: Color(0xFFE1BEE7),
    200: Color(0xFFCE93D8),
    300: Color(0xFFBA68C8),
    400: Color(0xFFAB47BC),
    500: Color(0xFF9C27B0),
    600: Color(0xFF8E24AA),
    700: Color(0xFF7B1FA2),
    800: Color(0xFF6A1B9A),
    900: Color(0xFF4A148C),
  });

  static const MaterialAccentColor purpleAccent =
      MaterialAccentColor(0xFFE040FB, <int, Color>{
        100: Color(0xFFEA80FC),
        200: Color(0xFFE040FB),
        400: Color(0xFFD500F9),
        700: Color(0xFFAA00FF),
      });

  static const MaterialColor deepPurple =
      MaterialColor(0xFF673AB7, <int, Color>{
        50: Color(0xFFEDE7F6),
        100: Color(0xFFD1C4E9),
        200: Color(0xFFB39DDB),
        300: Color(0xFF9575CD),
        400: Color(0xFF7E57C2),
        500: Color(0xFF673AB7),
        600: Color(0xFF5E35B1),
        700: Color(0xFF512DA8),
        800: Color(0xFF4527A0),
        900: Color(0xFF311B92),
      });

  static const MaterialAccentColor deepPurpleAccent =
      MaterialAccentColor(0xFF7C4DFF, <int, Color>{
        100: Color(0xFFB388FF),
        200: Color(0xFF7C4DFF),
        400: Color(0xFF651FFF),
        700: Color(0xFF6200EA),
      });

  static const MaterialColor indigo = MaterialColor(0xFF3F51B5, <int, Color>{
    50: Color(0xFFE8EAF6),
    100: Color(0xFFC5CAE9),
    200: Color(0xFF9FA8DA),
    300: Color(0xFF7986CB),
    400: Color(0xFF5C6BC0),
    500: Color(0xFF3F51B5),
    600: Color(0xFF3949AB),
    700: Color(0xFF303F9F),
    800: Color(0xFF283593),
    900: Color(0xFF1A237E),
  });

  static const MaterialAccentColor indigoAccent =
      MaterialAccentColor(0xFF536DFE, <int, Color>{
        100: Color(0xFF8C9EFF),
        200: Color(0xFF536DFE),
        400: Color(0xFF3D5AFE),
        700: Color(0xFF304FFE),
      });

  static const MaterialColor blue = MaterialColor(0xFF2196F3, <int, Color>{
    50: Color(0xFFE3F2FD),
    100: Color(0xFFBBDEFB),
    200: Color(0xFF90CAF9),
    300: Color(0xFF64B5F6),
    400: Color(0xFF42A5F5),
    500: Color(0xFF2196F3),
    600: Color(0xFF1E88E5),
    700: Color(0xFF1976D2),
    800: Color(0xFF1565C0),
    900: Color(0xFF0D47A1),
  });

  static const MaterialAccentColor blueAccent =
      MaterialAccentColor(0xFF448AFF, <int, Color>{
        100: Color(0xFF82B1FF),
        200: Color(0xFF448AFF),
        400: Color(0xFF2979FF),
        700: Color(0xFF2962FF),
      });

  static const MaterialColor lightBlue = MaterialColor(0xFF03A9F4, <int, Color>{
    50: Color(0xFFE1F5FE),
    100: Color(0xFFB3E5FC),
    200: Color(0xFF81D4FA),
    300: Color(0xFF4FC3F7),
    400: Color(0xFF29B6F6),
    500: Color(0xFF03A9F4),
    600: Color(0xFF039BE5),
    700: Color(0xFF0288D1),
    800: Color(0xFF0277BD),
    900: Color(0xFF01579B),
  });

  static const MaterialAccentColor lightBlueAccent =
      MaterialAccentColor(0xFF40C4FF, <int, Color>{
        100: Color(0xFF80D8FF),
        200: Color(0xFF40C4FF),
        400: Color(0xFF00B0FF),
        700: Color(0xFF0091EA),
      });

  static const MaterialColor cyan = MaterialColor(0xFF00BCD4, <int, Color>{
    50: Color(0xFFE0F7FA),
    100: Color(0xFFB2EBF2),
    200: Color(0xFF80DEEA),
    300: Color(0xFF4DD0E1),
    400: Color(0xFF26C6DA),
    500: Color(0xFF00BCD4),
    600: Color(0xFF00ACC1),
    700: Color(0xFF0097A7),
    800: Color(0xFF00838F),
    900: Color(0xFF006064),
  });

  static const MaterialAccentColor cyanAccent =
      MaterialAccentColor(0xFF18FFFF, <int, Color>{
        100: Color(0xFF84FFFF),
        200: Color(0xFF18FFFF),
        400: Color(0xFF00E5FF),
        700: Color(0xFF00B8D4),
      });

  static const MaterialColor teal = MaterialColor(0xFF009688, <int, Color>{
    50: Color(0xFFE0F2F1),
    100: Color(0xFFB2DFDB),
    200: Color(0xFF80CBC4),
    300: Color(0xFF4DB6AC),
    400: Color(0xFF26A69A),
    500: Color(0xFF009688),
    600: Color(0xFF00897B),
    700: Color(0xFF00796B),
    800: Color(0xFF00695C),
    900: Color(0xFF004D40),
  });

  static const MaterialAccentColor tealAccent =
      MaterialAccentColor(0xFF64FFDA, <int, Color>{
        100: Color(0xFFA7FFEB),
        200: Color(0xFF64FFDA),
        400: Color(0xFF1DE9B6),
        700: Color(0xFF00BFA5),
      });

  static const MaterialColor green = MaterialColor(0xFF4CAF50, <int, Color>{
    50: Color(0xFFE8F5E9),
    100: Color(0xFFC8E6C9),
    200: Color(0xFFA5D6A7),
    300: Color(0xFF81C784),
    400: Color(0xFF66BB6A),
    500: Color(0xFF4CAF50),
    600: Color(0xFF43A047),
    700: Color(0xFF388E3C),
    800: Color(0xFF2E7D32),
    900: Color(0xFF1B5E20),
  });

  static const MaterialAccentColor greenAccent =
      MaterialAccentColor(0xFF69F0AE, <int, Color>{
        100: Color(0xFFB9F6CA),
        200: Color(0xFF69F0AE),
        400: Color(0xFF00E676),
        700: Color(0xFF00C853),
      });

  static const MaterialColor lightGreen =
      MaterialColor(0xFF8BC34A, <int, Color>{
        50: Color(0xFFF1F8E9),
        100: Color(0xFFDCEDC8),
        200: Color(0xFFC5E1A5),
        300: Color(0xFFAED581),
        400: Color(0xFF9CCC65),
        500: Color(0xFF8BC34A),
        600: Color(0xFF7CB342),
        700: Color(0xFF689F38),
        800: Color(0xFF558B2F),
        900: Color(0xFF33691E),
      });

  static const MaterialAccentColor lightGreenAccent =
      MaterialAccentColor(0xFFB2FF59, <int, Color>{
        100: Color(0xFFCCFF90),
        200: Color(0xFFB2FF59),
        400: Color(0xFF76FF03),
        700: Color(0xFF64DD17),
      });

  static const MaterialColor lime = MaterialColor(0xFFCDDC39, <int, Color>{
    50: Color(0xFFF9FBE7),
    100: Color(0xFFF0F4C3),
    200: Color(0xFFE6EE9C),
    300: Color(0xFFDCE775),
    400: Color(0xFFD4E157),
    500: Color(0xFFCDDC39),
    600: Color(0xFFC0CA33),
    700: Color(0xFFAFB42B),
    800: Color(0xFF9E9D24),
    900: Color(0xFF827717),
  });

  static const MaterialAccentColor limeAccent =
      MaterialAccentColor(0xFFEEFF41, <int, Color>{
        100: Color(0xFFF4FF81),
        200: Color(0xFFEEFF41),
        400: Color(0xFFC6FF00),
        700: Color(0xFFAEEA00),
      });

  static const MaterialColor yellow = MaterialColor(0xFFFFEB3B, <int, Color>{
    50: Color(0xFFFFFDE7),
    100: Color(0xFFFFF9C4),
    200: Color(0xFFFFF59D),
    300: Color(0xFFFFF176),
    400: Color(0xFFFFEE58),
    500: Color(0xFFFFEB3B),
    600: Color(0xFFFDD835),
    700: Color(0xFFFBC02D),
    800: Color(0xFFF9A825),
    900: Color(0xFFF57F17),
  });

  static const MaterialAccentColor yellowAccent =
      MaterialAccentColor(0xFFFFFF00, <int, Color>{
        100: Color(0xFFFFFF8D),
        200: Color(0xFFFFFF00),
        400: Color(0xFFFFEA00),
        700: Color(0xFFFFD600),
      });

  static const MaterialColor amber = MaterialColor(0xFFFFC107, <int, Color>{
    50: Color(0xFFFFF8E1),
    100: Color(0xFFFFECB3),
    200: Color(0xFFFFE082),
    300: Color(0xFFFFD54F),
    400: Color(0xFFFFCA28),
    500: Color(0xFFFFC107),
    600: Color(0xFFFFB300),
    700: Color(0xFFFFA000),
    800: Color(0xFFFF8F00),
    900: Color(0xFFFF6F00),
  });

  static const MaterialAccentColor amberAccent =
      MaterialAccentColor(0xFFFFD740, <int, Color>{
        100: Color(0xFFFFE57F),
        200: Color(0xFFFFD740),
        400: Color(0xFFFFC400),
        700: Color(0xFFFFAB00),
      });

  static const MaterialColor orange = MaterialColor(0xFFFF9800, <int, Color>{
    50: Color(0xFFFFF3E0),
    100: Color(0xFFFFE0B2),
    200: Color(0xFFFFCC80),
    300: Color(0xFFFFB74D),
    400: Color(0xFFFFA726),
    500: Color(0xFFFF9800),
    600: Color(0xFFFB8C00),
    700: Color(0xFFF57C00),
    800: Color(0xFFEF6C00),
    900: Color(0xFFE65100),
  });

  static const MaterialAccentColor orangeAccent =
      MaterialAccentColor(0xFFFFAB40, <int, Color>{
        100: Color(0xFFFFD180),
        200: Color(0xFFFFAB40),
        400: Color(0xFFFF9100),
        700: Color(0xFFFF6D00),
      });

  static const MaterialColor deepOrange =
      MaterialColor(0xFFFF5722, <int, Color>{
        50: Color(0xFFFBE9E7),
        100: Color(0xFFFFCCBC),
        200: Color(0xFFFFAB91),
        300: Color(0xFFFF8A65),
        400: Color(0xFFFF7043),
        500: Color(0xFFFF5722),
        600: Color(0xFFF4511E),
        700: Color(0xFFE64A19),
        800: Color(0xFFD84315),
        900: Color(0xFFBF360C),
      });

  static const MaterialAccentColor deepOrangeAccent =
      MaterialAccentColor(0xFFFF6E40, <int, Color>{
        100: Color(0xFFFF9E80),
        200: Color(0xFFFF6E40),
        400: Color(0xFFFF3D00),
        700: Color(0xFFDD2C00),
      });

  static const MaterialColor brown = MaterialColor(0xFF795548, <int, Color>{
    50: Color(0xFFEFEBE9),
    100: Color(0xFFD7CCC8),
    200: Color(0xFFBCAAA4),
    300: Color(0xFFA1887F),
    400: Color(0xFF8D6E63),
    500: Color(0xFF795548),
    600: Color(0xFF6D4C41),
    700: Color(0xFF5D4037),
    800: Color(0xFF4E342E),
    900: Color(0xFF3E2723),
  });

  /// Grey has two shades the others do not: 350 and 850, which Material uses
  /// for a raised button's disabled fill and the dark theme's background.
  static const MaterialColor grey = MaterialColor(0xFF9E9E9E, <int, Color>{
    50: Color(0xFFFAFAFA),
    100: Color(0xFFF5F5F5),
    200: Color(0xFFEEEEEE),
    300: Color(0xFFE0E0E0),
    350: Color(0xFFD6D6D6),
    400: Color(0xFFBDBDBD),
    500: Color(0xFF9E9E9E),
    600: Color(0xFF757575),
    700: Color(0xFF616161),
    800: Color(0xFF424242),
    850: Color(0xFF303030),
    900: Color(0xFF212121),
  });

  static const MaterialColor blueGrey = MaterialColor(0xFF607D8B, <int, Color>{
    50: Color(0xFFECEFF1),
    100: Color(0xFFCFD8DC),
    200: Color(0xFFB0BEC5),
    300: Color(0xFF90A4AE),
    400: Color(0xFF78909C),
    500: Color(0xFF607D8B),
    600: Color(0xFF546E7A),
    700: Color(0xFF455A64),
    800: Color(0xFF37474F),
    900: Color(0xFF263238),
  });

  /// The colours with ten shades, in the order of the wheel.
  static const List<MaterialColor> primaries = <MaterialColor>[
    red,
    pink,
    purple,
    deepPurple,
    indigo,
    blue,
    lightBlue,
    cyan,
    teal,
    green,
    lightGreen,
    lime,
    yellow,
    amber,
    orange,
    deepOrange,
    brown,
    blueGrey,
  ];

  /// The accent families, in the same order.
  static const List<MaterialAccentColor> accents = <MaterialAccentColor>[
    redAccent,
    pinkAccent,
    purpleAccent,
    deepPurpleAccent,
    indigoAccent,
    blueAccent,
    lightBlueAccent,
    cyanAccent,
    tealAccent,
    greenAccent,
    lightGreenAccent,
    limeAccent,
    yellowAccent,
    amberAccent,
    orangeAccent,
    deepOrangeAccent,
  ];
}

// ---------------------------------------------------------------------------
// Geometry.
// ---------------------------------------------------------------------------

/// What an [Offset] and a [Size] have in common: two numbers. It exists so
/// `size - offset` and `size - size` can share an operator, as in Flutter.
abstract class OffsetBase {
  const OffsetBase(this._dx, this._dy);
  final double _dx;
  final double _dy;

  bool get isInfinite => _dx >= double.infinity || _dy >= double.infinity;
  bool get isFinite => _dx.isFinite && _dy.isFinite;

  @override
  bool operator ==(Object other) =>
      other is OffsetBase &&
      other.runtimeType == runtimeType &&
      other._dx == _dx &&
      other._dy == _dy;
  @override
  int get hashCode => Object.hash(_dx, _dy);
}

/// A point, or a movement: [dx] to the right and [dy] down, in logical pixels.
class Offset extends OffsetBase {
  const Offset(super.dx, super.dy);

  /// The point [distance] away from the origin in [direction] (radians,
  /// clockwise from the x axis).
  factory Offset.fromDirection(double direction, [double distance = 1.0]) =>
      Offset(distance * math.cos(direction), distance * math.sin(direction));

  double get dx => _dx;
  double get dy => _dy;

  static const Offset zero = Offset(0, 0);
  static const Offset infinite = Offset(double.infinity, double.infinity);

  /// How long the offset is.
  double get distance => math.sqrt(dx * dx + dy * dy);
  double get distanceSquared => dx * dx + dy * dy;

  /// The angle of the offset in radians, clockwise from the x axis.
  double get direction => math.atan2(dy, dx);

  Offset scale(double scaleX, double scaleY) =>
      Offset(dx * scaleX, dy * scaleY);
  Offset translate(double translateX, double translateY) =>
      Offset(dx + translateX, dy + translateY);

  Offset operator -() => Offset(-dx, -dy);
  Offset operator -(Offset other) => Offset(dx - other.dx, dy - other.dy);
  Offset operator +(Offset other) => Offset(dx + other.dx, dy + other.dy);
  Offset operator *(double operand) => Offset(dx * operand, dy * operand);
  Offset operator /(double operand) => Offset(dx / operand, dy / operand);
  Offset operator ~/(double operand) =>
      Offset((dx ~/ operand).toDouble(), (dy ~/ operand).toDouble());
  Offset operator %(double operand) => Offset(dx % operand, dy % operand);

  /// The rectangle with this point as its top left corner and [other] as its
  /// size.
  Rect operator &(Size other) =>
      Rect.fromLTWH(dx, dy, other.width, other.height);

  static Offset? lerp(Offset? a, Offset? b, double t) {
    if (a == null && b == null) return null;
    a ??= Offset.zero;
    b ??= Offset.zero;
    return Offset(a.dx + (b.dx - a.dx) * t, a.dy + (b.dy - a.dy) * t);
  }

  @override
  String toString() => 'Offset($dx, $dy)';
}

/// A width and a height, as Flutter spells it.
class Size extends OffsetBase {
  const Size(super.width, super.height);
  const Size.square(double dimension) : super(dimension, dimension);
  const Size.fromWidth(double width) : super(width, double.infinity);
  const Size.fromHeight(double height) : super(double.infinity, height);
  const Size.fromRadius(double radius) : super(radius * 2.0, radius * 2.0);

  double get width => _dx;
  double get height => _dy;

  static const Size zero = Size(0, 0);
  static const Size infinite = Size(double.infinity, double.infinity);

  /// Width over height; 0 when there is no height to divide by.
  double get aspectRatio {
    if (height != 0.0) return width / height;
    if (width > 0.0) return double.infinity;
    if (width < 0.0) return double.negativeInfinity;
    return 0.0;
  }

  bool get isEmpty => width <= 0.0 || height <= 0.0;
  double get shortestSide => math.min(width.abs(), height.abs());
  double get longestSide => math.max(width.abs(), height.abs());
  Size get flipped => Size(height, width);

  /// `size - offset` is a smaller size; `size - size` is the offset between
  /// their bottom right corners.
  OffsetBase operator -(OffsetBase other) {
    if (other is Size) {
      return Offset(width - other.width, height - other.height);
    }
    if (other is Offset) return Size(width - other.dx, height - other.dy);
    throw ArgumentError(other);
  }

  Size operator +(Offset other) => Size(width + other.dx, height + other.dy);
  Size operator *(double operand) => Size(width * operand, height * operand);
  Size operator /(double operand) => Size(width / operand, height / operand);

  Offset topLeft(Offset origin) => origin;
  Offset topCenter(Offset origin) => Offset(origin.dx + width / 2, origin.dy);
  Offset topRight(Offset origin) => Offset(origin.dx + width, origin.dy);
  Offset centerLeft(Offset origin) => Offset(origin.dx, origin.dy + height / 2);
  Offset center(Offset origin) =>
      Offset(origin.dx + width / 2, origin.dy + height / 2);
  Offset centerRight(Offset origin) =>
      Offset(origin.dx + width, origin.dy + height / 2);
  Offset bottomLeft(Offset origin) => Offset(origin.dx, origin.dy + height);
  Offset bottomCenter(Offset origin) =>
      Offset(origin.dx + width / 2, origin.dy + height);
  Offset bottomRight(Offset origin) =>
      Offset(origin.dx + width, origin.dy + height);

  /// Whether [offset] falls inside a box of this size placed at the origin.
  bool contains(Offset offset) =>
      offset.dx >= 0.0 &&
      offset.dx < width &&
      offset.dy >= 0.0 &&
      offset.dy < height;

  static Size? lerp(Size? a, Size? b, double t) {
    if (a == null && b == null) return null;
    a ??= Size.zero;
    b ??= Size.zero;
    return Size(
      a.width + (b.width - a.width) * t,
      a.height + (b.height - a.height) * t,
    );
  }

  @override
  String toString() => 'Size($width, $height)';
}

/// A rectangle, by its four edges.
class Rect {
  const Rect.fromLTRB(this.left, this.top, this.right, this.bottom);
  const Rect.fromLTWH(double left, double top, double width, double height)
    : this.fromLTRB(left, top, left + width, top + height);

  /// The square around a circle.
  Rect.fromCircle({required Offset center, required double radius})
    : this.fromCenter(center: center, width: radius * 2, height: radius * 2);

  Rect.fromCenter({
    required Offset center,
    required double width,
    required double height,
  }) : this.fromLTRB(
         center.dx - width / 2,
         center.dy - height / 2,
         center.dx + width / 2,
         center.dy + height / 2,
       );

  /// The smallest rectangle holding both points.
  Rect.fromPoints(Offset a, Offset b)
    : this.fromLTRB(
        math.min(a.dx, b.dx),
        math.min(a.dy, b.dy),
        math.max(a.dx, b.dx),
        math.max(a.dy, b.dy),
      );

  final double left;
  final double top;
  final double right;
  final double bottom;

  static const Rect zero = Rect.fromLTRB(0, 0, 0, 0);
  static const Rect largest = Rect.fromLTRB(-1e9, -1e9, 1e9, 1e9);

  double get width => right - left;
  double get height => bottom - top;
  Size get size => Size(width, height);
  bool get isEmpty => left >= right || top >= bottom;
  bool get isFinite =>
      left.isFinite && top.isFinite && right.isFinite && bottom.isFinite;
  double get shortestSide => math.min(width.abs(), height.abs());
  double get longestSide => math.max(width.abs(), height.abs());

  Offset get topLeft => Offset(left, top);
  Offset get topCenter => Offset(left + width / 2, top);
  Offset get topRight => Offset(right, top);
  Offset get centerLeft => Offset(left, top + height / 2);
  Offset get center => Offset(left + width / 2, top + height / 2);
  Offset get centerRight => Offset(right, top + height / 2);
  Offset get bottomLeft => Offset(left, bottom);
  Offset get bottomCenter => Offset(left + width / 2, bottom);
  Offset get bottomRight => Offset(right, bottom);

  /// The same rectangle moved by [offset].
  Rect shift(Offset offset) => Rect.fromLTRB(
    left + offset.dx,
    top + offset.dy,
    right + offset.dx,
    bottom + offset.dy,
  );
  Rect translate(double translateX, double translateY) => Rect.fromLTRB(
    left + translateX,
    top + translateY,
    right + translateX,
    bottom + translateY,
  );

  /// The rectangle with every edge moved outwards by [delta].
  Rect inflate(double delta) =>
      Rect.fromLTRB(left - delta, top - delta, right + delta, bottom + delta);
  Rect deflate(double delta) => inflate(-delta);

  /// The part both rectangles cover.
  Rect intersect(Rect other) => Rect.fromLTRB(
    math.max(left, other.left),
    math.max(top, other.top),
    math.min(right, other.right),
    math.min(bottom, other.bottom),
  );

  /// The smallest rectangle covering both.
  Rect expandToInclude(Rect other) => Rect.fromLTRB(
    math.min(left, other.left),
    math.min(top, other.top),
    math.max(right, other.right),
    math.max(bottom, other.bottom),
  );

  bool overlaps(Rect other) =>
      !(right <= other.left ||
          other.right <= left ||
          bottom <= other.top ||
          other.bottom <= top);

  /// Whether [offset] is inside: the left and top edges count, the right and
  /// bottom do not.
  bool contains(Offset offset) =>
      offset.dx >= left &&
      offset.dx < right &&
      offset.dy >= top &&
      offset.dy < bottom;

  static Rect? lerp(Rect? a, Rect? b, double t) {
    if (a == null && b == null) return null;
    a ??= Rect.zero;
    b ??= Rect.zero;
    double mix(double from, double to) => from + (to - from) * t;
    return Rect.fromLTRB(
      mix(a.left, b.left),
      mix(a.top, b.top),
      mix(a.right, b.right),
      mix(a.bottom, b.bottom),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Rect &&
      other.left == left &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom;
  @override
  int get hashCode => Object.hash(left, top, right, bottom);
  @override
  String toString() => 'Rect.fromLTRB($left, $top, $right, $bottom)';
}

/// How round a corner is: a circle's radius, or an ellipse's two.
class Radius {
  const Radius.circular(double radius) : this.elliptical(radius, radius);
  const Radius.elliptical(this.x, this.y);

  final double x;
  final double y;

  static const Radius zero = Radius.circular(0);

  Radius operator +(Radius other) =>
      Radius.elliptical(x + other.x, y + other.y);
  Radius operator -(Radius other) =>
      Radius.elliptical(x - other.x, y - other.y);
  Radius operator *(double operand) =>
      Radius.elliptical(x * operand, y * operand);
  Radius operator /(double operand) =>
      Radius.elliptical(x / operand, y / operand);

  static Radius? lerp(Radius? a, Radius? b, double t) {
    if (a == null && b == null) return null;
    a ??= Radius.zero;
    b ??= Radius.zero;
    return Radius.elliptical(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t);
  }

  @override
  bool operator ==(Object other) =>
      other is Radius && other.x == x && other.y == y;
  @override
  int get hashCode => Object.hash(x, y);
  @override
  String toString() =>
      x == y ? 'Radius.circular($x)' : 'Radius.elliptical($x, $y)';
}

/// A rectangle with rounded corners.
class RRect {
  const RRect.fromLTRBXY(
    double left,
    double top,
    double right,
    double bottom,
    double radiusX,
    double radiusY,
  ) : this._raw(
        left,
        top,
        right,
        bottom,
        radiusX,
        radiusY,
        radiusX,
        radiusY,
        radiusX,
        radiusY,
        radiusX,
        radiusY,
      );

  RRect.fromLTRBR(
    double left,
    double top,
    double right,
    double bottom,
    Radius radius,
  ) : this.fromLTRBXY(left, top, right, bottom, radius.x, radius.y);

  RRect.fromRectXY(Rect rect, double radiusX, double radiusY)
    : this.fromLTRBXY(
        rect.left,
        rect.top,
        rect.right,
        rect.bottom,
        radiusX,
        radiusY,
      );

  RRect.fromRectAndRadius(Rect rect, Radius radius)
    : this.fromLTRBXY(
        rect.left,
        rect.top,
        rect.right,
        rect.bottom,
        radius.x,
        radius.y,
      );

  RRect.fromLTRBAndCorners(
    double left,
    double top,
    double right,
    double bottom, {
    Radius topLeft = Radius.zero,
    Radius topRight = Radius.zero,
    Radius bottomRight = Radius.zero,
    Radius bottomLeft = Radius.zero,
  }) : this._raw(
         left,
         top,
         right,
         bottom,
         topLeft.x,
         topLeft.y,
         topRight.x,
         topRight.y,
         bottomRight.x,
         bottomRight.y,
         bottomLeft.x,
         bottomLeft.y,
       );

  RRect.fromRectAndCorners(
    Rect rect, {
    Radius topLeft = Radius.zero,
    Radius topRight = Radius.zero,
    Radius bottomRight = Radius.zero,
    Radius bottomLeft = Radius.zero,
  }) : this.fromLTRBAndCorners(
         rect.left,
         rect.top,
         rect.right,
         rect.bottom,
         topLeft: topLeft,
         topRight: topRight,
         bottomRight: bottomRight,
         bottomLeft: bottomLeft,
       );

  const RRect._raw(
    this.left,
    this.top,
    this.right,
    this.bottom,
    this.tlRadiusX,
    this.tlRadiusY,
    this.trRadiusX,
    this.trRadiusY,
    this.brRadiusX,
    this.brRadiusY,
    this.blRadiusX,
    this.blRadiusY,
  );

  final double left;
  final double top;
  final double right;
  final double bottom;
  final double tlRadiusX;
  final double tlRadiusY;
  final double trRadiusX;
  final double trRadiusY;
  final double brRadiusX;
  final double brRadiusY;
  final double blRadiusX;
  final double blRadiusY;

  static const RRect zero = RRect._raw(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);

  Radius get tlRadius => Radius.elliptical(tlRadiusX, tlRadiusY);
  Radius get trRadius => Radius.elliptical(trRadiusX, trRadiusY);
  Radius get brRadius => Radius.elliptical(brRadiusX, brRadiusY);
  Radius get blRadius => Radius.elliptical(blRadiusX, blRadiusY);

  double get width => right - left;
  double get height => bottom - top;
  Offset get center => Offset(left + width / 2, top + height / 2);

  /// The rectangle the corners were rounded from.
  Rect get outerRect => Rect.fromLTRB(left, top, right, bottom);

  RRect shift(Offset offset) => RRect._raw(
    left + offset.dx,
    top + offset.dy,
    right + offset.dx,
    bottom + offset.dy,
    tlRadiusX,
    tlRadiusY,
    trRadiusX,
    trRadiusY,
    brRadiusX,
    brRadiusY,
    blRadiusX,
    blRadiusY,
  );

  /// Every edge moved outwards by [delta], the corners growing with it.
  RRect inflate(double delta) => RRect._raw(
    left - delta,
    top - delta,
    right + delta,
    bottom + delta,
    math.max(0.0, tlRadiusX + delta),
    math.max(0.0, tlRadiusY + delta),
    math.max(0.0, trRadiusX + delta),
    math.max(0.0, trRadiusY + delta),
    math.max(0.0, brRadiusX + delta),
    math.max(0.0, brRadiusY + delta),
    math.max(0.0, blRadiusX + delta),
    math.max(0.0, blRadiusY + delta),
  );
  RRect deflate(double delta) => inflate(-delta);

  /// Whether [point] is inside the outer rectangle. The corners are not cut
  /// out of the test - close enough for a hit test, and it is said here so a
  /// caller that needs the exact shape knows to do its own.
  bool contains(Offset point) => outerRect.contains(point);

  @override
  bool operator ==(Object other) =>
      other is RRect &&
      other.left == left &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom &&
      other.tlRadiusX == tlRadiusX &&
      other.tlRadiusY == tlRadiusY &&
      other.trRadiusX == trRadiusX &&
      other.trRadiusY == trRadiusY &&
      other.brRadiusX == brRadiusX &&
      other.brRadiusY == brRadiusY &&
      other.blRadiusX == blRadiusX &&
      other.blRadiusY == blRadiusY;
  @override
  int get hashCode => Object.hash(
    left,
    top,
    right,
    bottom,
    tlRadiusX,
    tlRadiusY,
    trRadiusX,
    trRadiusY,
    brRadiusX,
    brRadiusY,
    blRadiusX,
    blRadiusY,
  );
  @override
  String toString() =>
      'RRect.fromLTRBR($left, $top, $right, $bottom, $tlRadius)';
}

/// The room a parent offers a child: the least and the most it may be on each
/// axis. What a `LayoutBuilder` is handed.
class BoxConstraints {
  const BoxConstraints({
    this.minWidth = 0.0,
    this.maxWidth = double.infinity,
    this.minHeight = 0.0,
    this.maxHeight = double.infinity,
  });

  /// Exactly [size], no choice.
  BoxConstraints.tight(Size size)
    : minWidth = size.width,
      maxWidth = size.width,
      minHeight = size.height,
      maxHeight = size.height;

  /// Exactly the given dimensions; an axis left out is unconstrained.
  const BoxConstraints.tightFor({double? width, double? height})
    : minWidth = width ?? 0.0,
      maxWidth = width ?? double.infinity,
      minHeight = height ?? 0.0,
      maxHeight = height ?? double.infinity;

  const BoxConstraints.tightForFinite({
    double width = double.infinity,
    double height = double.infinity,
  }) : minWidth = width != double.infinity ? width : 0.0,
       maxWidth = width != double.infinity ? width : double.infinity,
       minHeight = height != double.infinity ? height : 0.0,
       maxHeight = height != double.infinity ? height : double.infinity;

  /// Anything up to [size].
  BoxConstraints.loose(Size size)
    : minWidth = 0.0,
      maxWidth = size.width,
      minHeight = 0.0,
      maxHeight = size.height;

  /// As big as the parent allows; a given dimension is fixed instead.
  const BoxConstraints.expand({double? width, double? height})
    : minWidth = width ?? double.infinity,
      maxWidth = width ?? double.infinity,
      minHeight = height ?? double.infinity,
      maxHeight = height ?? double.infinity;

  final double minWidth;
  final double maxWidth;
  final double minHeight;
  final double maxHeight;

  BoxConstraints copyWith({
    double? minWidth,
    double? maxWidth,
    double? minHeight,
    double? maxHeight,
  }) => BoxConstraints(
    minWidth: minWidth ?? this.minWidth,
    maxWidth: maxWidth ?? this.maxWidth,
    minHeight: minHeight ?? this.minHeight,
    maxHeight: maxHeight ?? this.maxHeight,
  );

  /// The same limits with [edges] taken out of them.
  BoxConstraints deflate(EdgeInsetsGeometry edges) {
    final horizontal = edges.horizontal;
    final vertical = edges.vertical;
    final deflatedMinWidth = math.max(0.0, minWidth - horizontal);
    final deflatedMinHeight = math.max(0.0, minHeight - vertical);
    return BoxConstraints(
      minWidth: deflatedMinWidth,
      maxWidth: math.max(deflatedMinWidth, maxWidth - horizontal),
      minHeight: deflatedMinHeight,
      maxHeight: math.max(deflatedMinHeight, maxHeight - vertical),
    );
  }

  /// The same maximums with no minimums.
  BoxConstraints loosen() =>
      BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight);

  /// These constraints with the given dimensions pinned, as far as the
  /// constraints allow.
  BoxConstraints tighten({double? width, double? height}) => BoxConstraints(
    minWidth: width == null ? minWidth : width.clamp(minWidth, maxWidth),
    maxWidth: width == null ? maxWidth : width.clamp(minWidth, maxWidth),
    minHeight: height == null ? minHeight : height.clamp(minHeight, maxHeight),
    maxHeight: height == null ? maxHeight : height.clamp(minHeight, maxHeight),
  );

  /// These constraints kept within [constraints].
  BoxConstraints enforce(BoxConstraints constraints) => BoxConstraints(
    minWidth: minWidth.clamp(constraints.minWidth, constraints.maxWidth),
    maxWidth: maxWidth.clamp(constraints.minWidth, constraints.maxWidth),
    minHeight: minHeight.clamp(constraints.minHeight, constraints.maxHeight),
    maxHeight: maxHeight.clamp(constraints.minHeight, constraints.maxHeight),
  );

  BoxConstraints get flipped => BoxConstraints(
    minWidth: minHeight,
    maxWidth: maxHeight,
    minHeight: minWidth,
    maxHeight: maxWidth,
  );

  BoxConstraints widthConstraints() =>
      BoxConstraints(minWidth: minWidth, maxWidth: maxWidth);
  BoxConstraints heightConstraints() =>
      BoxConstraints(minHeight: minHeight, maxHeight: maxHeight);

  /// [width] brought inside the limits.
  double constrainWidth([double width = double.infinity]) =>
      width.clamp(minWidth, maxWidth);
  double constrainHeight([double height = double.infinity]) =>
      height.clamp(minHeight, maxHeight);

  /// [size] brought inside the limits.
  Size constrain(Size size) =>
      Size(constrainWidth(size.width), constrainHeight(size.height));

  /// The largest size allowed.
  Size get biggest => Size(constrainWidth(), constrainHeight());

  /// The smallest size allowed.
  Size get smallest => Size(constrainWidth(0.0), constrainHeight(0.0));

  bool get hasTightWidth => minWidth >= maxWidth;
  bool get hasTightHeight => minHeight >= maxHeight;
  bool get isTight => hasTightWidth && hasTightHeight;
  bool get hasBoundedWidth => maxWidth < double.infinity;
  bool get hasBoundedHeight => maxHeight < double.infinity;
  bool get hasInfiniteWidth => minWidth >= double.infinity;
  bool get hasInfiniteHeight => minHeight >= double.infinity;

  bool isSatisfiedBy(Size size) =>
      (minWidth <= size.width) &&
      (size.width <= maxWidth) &&
      (minHeight <= size.height) &&
      (size.height <= maxHeight);

  @override
  bool operator ==(Object other) =>
      other is BoxConstraints &&
      other.minWidth == minWidth &&
      other.maxWidth == maxWidth &&
      other.minHeight == minHeight &&
      other.maxHeight == maxHeight;
  @override
  int get hashCode => Object.hash(minWidth, maxWidth, minHeight, maxHeight);
  @override
  String toString() =>
      'BoxConstraints($minWidth<=w<=$maxWidth, $minHeight<=h<=$maxHeight)';
}

// ---------------------------------------------------------------------------
// Insets.
// ---------------------------------------------------------------------------

/// The reading direction of the build in progress - the nearest
/// [Directionality] above whatever is being built - and left to right when
/// nothing is being built at all.
///
/// A directional value has no context of its own, so this is how it finds the
/// direction to become physical in at the moment a widget turns it into the
/// numbers the protocol carries.
TextDirection get _ambientDirection =>
    _Owner._current?._direction ?? TextDirection.ltr;

/// Space around something, in a form that may depend on the reading
/// direction. [EdgeInsets] names the edges outright and never turns;
/// [EdgeInsetsDirectional] names start and end, which are resolved against
/// the [Directionality] it is built under.
abstract class EdgeInsetsGeometry {
  const EdgeInsetsGeometry();

  /// The four physical edges, in the direction being built in - the form the
  /// protocol carries.
  EdgeInsets get _resolved;

  /// The space on both sides together.
  double get horizontal => _resolved.left + _resolved.right;

  /// The space above and below together.
  double get vertical => _resolved.top + _resolved.bottom;

  /// The space this takes up when there is nothing inside it.
  Size get collapsedSize => Size(horizontal, vertical);

  bool get isNonNegative =>
      _resolved.left >= 0 &&
      _resolved.top >= 0 &&
      _resolved.right >= 0 &&
      _resolved.bottom >= 0;

  /// The edges for a reading direction. Left-to-right when none is given.
  EdgeInsets resolve(TextDirection? direction);

  /// Both insets together.
  EdgeInsetsGeometry add(EdgeInsetsGeometry other) =>
      _resolved + other._resolved;

  /// These insets with [other] taken away.
  EdgeInsetsGeometry subtract(EdgeInsetsGeometry other) =>
      _resolved - other._resolved;
}

/// Space around something, one edge at a time - Flutter's own shape, and the
/// protocol carries all four.
class EdgeInsets extends EdgeInsetsGeometry {
  const EdgeInsets.all(double value)
    : left = value,
      top = value,
      right = value,
      bottom = value;

  const EdgeInsets.symmetric({double horizontal = 0, double vertical = 0})
    : left = horizontal,
      right = horizontal,
      top = vertical,
      bottom = vertical;

  const EdgeInsets.only({
    this.left = 0,
    this.top = 0,
    this.right = 0,
    this.bottom = 0,
  });

  const EdgeInsets.fromLTRB(this.left, this.top, this.right, this.bottom);

  final double left;
  final double top;
  final double right;
  final double bottom;

  static const EdgeInsets zero = EdgeInsets.only();

  /// Whether every edge is the same, which is how the node is written.
  bool get isUniform => left == top && top == right && right == bottom;

  @override
  EdgeInsets get _resolved => this;

  /// `[left, top, right, bottom]`, the order a `box` node takes them in.
  List<double> get _ltrb => [left, top, right, bottom];

  @override
  EdgeInsets resolve(TextDirection? direction) => this;

  Offset get topLeft => Offset(left, top);
  Offset get topRight => Offset(-right, top);
  Offset get bottomLeft => Offset(left, -bottom);
  Offset get bottomRight => Offset(-right, -bottom);

  /// Left and right swapped, top and bottom swapped.
  EdgeInsets get flipped => EdgeInsets.fromLTRB(right, bottom, left, top);

  /// The total along [axis].
  double along(Axis axis) => axis == Axis.horizontal ? horizontal : vertical;

  /// [size] with these insets added around it.
  Size inflateSize(Size size) =>
      Size(size.width + horizontal, size.height + vertical);

  /// [size] with these insets taken out of it.
  Size deflateSize(Size size) =>
      Size(size.width - horizontal, size.height - vertical);

  Rect inflateRect(Rect rect) => Rect.fromLTRB(
    rect.left - left,
    rect.top - top,
    rect.right + right,
    rect.bottom + bottom,
  );

  Rect deflateRect(Rect rect) => Rect.fromLTRB(
    rect.left + left,
    rect.top + top,
    rect.right - right,
    rect.bottom - bottom,
  );

  EdgeInsets operator +(EdgeInsets other) => EdgeInsets.fromLTRB(
    left + other.left,
    top + other.top,
    right + other.right,
    bottom + other.bottom,
  );
  EdgeInsets operator -(EdgeInsets other) => EdgeInsets.fromLTRB(
    left - other.left,
    top - other.top,
    right - other.right,
    bottom - other.bottom,
  );
  EdgeInsets operator -() => EdgeInsets.fromLTRB(-left, -top, -right, -bottom);
  EdgeInsets operator *(double other) => EdgeInsets.fromLTRB(
    left * other,
    top * other,
    right * other,
    bottom * other,
  );
  EdgeInsets operator /(double other) => EdgeInsets.fromLTRB(
    left / other,
    top / other,
    right / other,
    bottom / other,
  );

  EdgeInsets copyWith({
    double? left,
    double? top,
    double? right,
    double? bottom,
  }) => EdgeInsets.only(
    left: left ?? this.left,
    top: top ?? this.top,
    right: right ?? this.right,
    bottom: bottom ?? this.bottom,
  );

  static EdgeInsets? lerp(EdgeInsets? a, EdgeInsets? b, double t) {
    if (a == null && b == null) return null;
    a ??= EdgeInsets.zero;
    b ??= EdgeInsets.zero;
    double mix(double from, double to) => from + (to - from) * t;
    return EdgeInsets.fromLTRB(
      mix(a.left, b.left),
      mix(a.top, b.top),
      mix(a.right, b.right),
      mix(a.bottom, b.bottom),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is EdgeInsets &&
      other.left == left &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom;
  @override
  int get hashCode => Object.hash(left, top, right, bottom);
  @override
  String toString() => 'EdgeInsets($left, $top, $right, $bottom)';
}

/// [EdgeInsets] that names the start and end of a line instead of left and
/// right.
///
/// Resolved against the ambient [Directionality], as in Flutter: start is the
/// left under a left-to-right one (or none) and the right under a
/// right-to-left one. The tree the renderers get carries the four physical
/// edges that came to, so nothing downstream has to know which it was.
class EdgeInsetsDirectional extends EdgeInsetsGeometry {
  const EdgeInsetsDirectional.fromSTEB(
    this.start,
    this.top,
    this.end,
    this.bottom,
  );

  const EdgeInsetsDirectional.only({
    this.start = 0,
    this.top = 0,
    this.end = 0,
    this.bottom = 0,
  });

  const EdgeInsetsDirectional.symmetric({
    double horizontal = 0,
    double vertical = 0,
  }) : start = horizontal,
       end = horizontal,
       top = vertical,
       bottom = vertical;

  const EdgeInsetsDirectional.all(double value)
    : start = value,
      top = value,
      end = value,
      bottom = value;

  final double start;
  final double top;
  final double end;
  final double bottom;

  static const EdgeInsetsDirectional zero = EdgeInsetsDirectional.only();

  @override
  EdgeInsets get _resolved => resolve(_ambientDirection);

  @override
  EdgeInsets resolve(TextDirection? direction) => direction == TextDirection.rtl
      ? EdgeInsets.fromLTRB(end, top, start, bottom)
      : EdgeInsets.fromLTRB(start, top, end, bottom);

  EdgeInsetsDirectional copyWith({
    double? start,
    double? top,
    double? end,
    double? bottom,
  }) => EdgeInsetsDirectional.only(
    start: start ?? this.start,
    top: top ?? this.top,
    end: end ?? this.end,
    bottom: bottom ?? this.bottom,
  );

  @override
  bool operator ==(Object other) =>
      other is EdgeInsetsDirectional &&
      other.start == start &&
      other.top == top &&
      other.end == end &&
      other.bottom == bottom;
  @override
  int get hashCode => Object.hash(start, top, end, bottom);
  @override
  String toString() => 'EdgeInsetsDirectional($start, $top, $end, $bottom)';
}

// ---------------------------------------------------------------------------
// Alignment.
// ---------------------------------------------------------------------------

/// Where something sits inside a larger box, in a form that may depend on the
/// reading direction. Resolved against the [Directionality] it is built
/// under, as [EdgeInsetsDirectional] is.
abstract class AlignmentGeometry {
  const AlignmentGeometry();

  /// The physical alignment, in the direction being built in - the form the
  /// protocol carries.
  Alignment get _resolved;

  /// The alignment for a reading direction. Left-to-right when none is given.
  Alignment resolve(TextDirection? direction);
}

/// A point in a box: (-1, -1) is the top left corner, (0, 0) the centre,
/// (1, 1) the bottom right.
class Alignment extends AlignmentGeometry {
  const Alignment(this.x, this.y);

  final double x;
  final double y;

  static const Alignment topLeft = Alignment(-1.0, -1.0);
  static const Alignment topCenter = Alignment(0.0, -1.0);
  static const Alignment topRight = Alignment(1.0, -1.0);
  static const Alignment centerLeft = Alignment(-1.0, 0.0);
  static const Alignment center = Alignment(0.0, 0.0);
  static const Alignment centerRight = Alignment(1.0, 0.0);
  static const Alignment bottomLeft = Alignment(-1.0, 1.0);
  static const Alignment bottomCenter = Alignment(0.0, 1.0);
  static const Alignment bottomRight = Alignment(1.0, 1.0);

  @override
  Alignment get _resolved => this;

  /// `[x, y]`, as `box(alignment:)` and `stack(alignment:)` take it.
  List<double> get _xy => [x, y];

  @override
  Alignment resolve(TextDirection? direction) => this;

  Alignment operator -(Alignment other) => Alignment(x - other.x, y - other.y);
  Alignment operator +(Alignment other) => Alignment(x + other.x, y + other.y);
  Alignment operator -() => Alignment(-x, -y);
  Alignment operator *(double other) => Alignment(x * other, y * other);
  Alignment operator /(double other) => Alignment(x / other, y / other);

  /// The point this alignment names in a box of [other] placed at the origin.
  Offset alongSize(Size other) {
    final centerX = other.width / 2.0;
    final centerY = other.height / 2.0;
    return Offset(centerX + x * centerX, centerY + y * centerY);
  }

  /// The same, for a box whose bottom right corner is [other].
  Offset alongOffset(Offset other) {
    final centerX = other.dx / 2.0;
    final centerY = other.dy / 2.0;
    return Offset(centerX + x * centerX, centerY + y * centerY);
  }

  /// The point this alignment names inside [rect].
  Offset withinRect(Rect rect) {
    final halfWidth = rect.width / 2.0;
    final halfHeight = rect.height / 2.0;
    return Offset(
      rect.left + halfWidth + x * halfWidth,
      rect.top + halfHeight + y * halfHeight,
    );
  }

  /// Where a box of [size] lands when aligned this way inside [rect].
  Rect inscribe(Size size, Rect rect) {
    final halfWidthDelta = (rect.width - size.width) / 2.0;
    final halfHeightDelta = (rect.height - size.height) / 2.0;
    return Rect.fromLTWH(
      rect.left + halfWidthDelta + x * halfWidthDelta,
      rect.top + halfHeightDelta + y * halfHeightDelta,
      size.width,
      size.height,
    );
  }

  static Alignment? lerp(Alignment? a, Alignment? b, double t) {
    if (a == null && b == null) return null;
    a ??= Alignment.center;
    b ??= Alignment.center;
    return Alignment(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t);
  }

  @override
  bool operator ==(Object other) =>
      other is Alignment && other.x == x && other.y == y;
  @override
  int get hashCode => Object.hash(x, y);
  @override
  String toString() => 'Alignment($x, $y)';
}

/// An [Alignment] whose horizontal axis runs from the start of a line to its
/// end, resolved against the ambient [Directionality] - see
/// [EdgeInsetsDirectional].
class AlignmentDirectional extends AlignmentGeometry {
  const AlignmentDirectional(this.start, this.y);

  final double start;
  final double y;

  static const AlignmentDirectional topStart = AlignmentDirectional(-1.0, -1.0);
  static const AlignmentDirectional topCenter = AlignmentDirectional(0.0, -1.0);
  static const AlignmentDirectional topEnd = AlignmentDirectional(1.0, -1.0);
  static const AlignmentDirectional centerStart = AlignmentDirectional(
    -1.0,
    0.0,
  );
  static const AlignmentDirectional center = AlignmentDirectional(0.0, 0.0);
  static const AlignmentDirectional centerEnd = AlignmentDirectional(1.0, 0.0);
  static const AlignmentDirectional bottomStart = AlignmentDirectional(
    -1.0,
    1.0,
  );
  static const AlignmentDirectional bottomCenter = AlignmentDirectional(
    0.0,
    1.0,
  );
  static const AlignmentDirectional bottomEnd = AlignmentDirectional(1.0, 1.0);

  @override
  Alignment get _resolved => resolve(_ambientDirection);

  @override
  Alignment resolve(TextDirection? direction) =>
      direction == TextDirection.rtl ? Alignment(-start, y) : Alignment(start, y);

  @override
  bool operator ==(Object other) =>
      other is AlignmentDirectional && other.start == start && other.y == y;
  @override
  int get hashCode => Object.hash(start, y);
  @override
  String toString() => 'AlignmentDirectional($start, $y)';
}

// ---------------------------------------------------------------------------
// Borders and corners.
// ---------------------------------------------------------------------------

/// Corner radii in a form that may depend on the reading direction.
abstract class BorderRadiusGeometry {
  const BorderRadiusGeometry();

  /// The four physical corners, in the direction being built in.
  BorderRadius get _resolved;

  /// The corners for a reading direction. Left-to-right when none is given.
  BorderRadius resolve(TextDirection? direction);
}

/// How round each corner of a box is.
class BorderRadius extends BorderRadiusGeometry {
  const BorderRadius.all(Radius radius)
    : this.only(
        topLeft: radius,
        topRight: radius,
        bottomLeft: radius,
        bottomRight: radius,
      );

  BorderRadius.circular(double radius) : this.all(Radius.circular(radius));

  /// The top pair and the bottom pair.
  const BorderRadius.vertical({
    Radius top = Radius.zero,
    Radius bottom = Radius.zero,
  }) : this.only(
         topLeft: top,
         topRight: top,
         bottomLeft: bottom,
         bottomRight: bottom,
       );

  /// The left pair and the right pair.
  const BorderRadius.horizontal({
    Radius left = Radius.zero,
    Radius right = Radius.zero,
  }) : this.only(
         topLeft: left,
         topRight: right,
         bottomLeft: left,
         bottomRight: right,
       );

  const BorderRadius.only({
    this.topLeft = Radius.zero,
    this.topRight = Radius.zero,
    this.bottomLeft = Radius.zero,
    this.bottomRight = Radius.zero,
  });

  final Radius topLeft;
  final Radius topRight;
  final Radius bottomLeft;
  final Radius bottomRight;

  static const BorderRadius zero = BorderRadius.all(Radius.zero);

  @override
  BorderRadius get _resolved => this;

  @override
  BorderRadius resolve(TextDirection? direction) => this;

  /// The one radius every corner has, or null when they differ - which is
  /// whether a `box` node says `borderRadius` or `borderRadii`.
  double? get _uniform =>
      topLeft == topRight &&
          topRight == bottomRight &&
          bottomRight == bottomLeft
      ? topLeft.x
      : null;

  /// `[topLeft, topRight, bottomRight, bottomLeft]`, clockwise, as
  /// `box(borderRadii:)` takes them. A corner is one number in the protocol,
  /// so an elliptical radius travels as its horizontal half.
  List<double> get _radii => [
    topLeft.x,
    topRight.x,
    bottomRight.x,
    bottomLeft.x,
  ];

  BorderRadius copyWith({
    Radius? topLeft,
    Radius? topRight,
    Radius? bottomLeft,
    Radius? bottomRight,
  }) => BorderRadius.only(
    topLeft: topLeft ?? this.topLeft,
    topRight: topRight ?? this.topRight,
    bottomLeft: bottomLeft ?? this.bottomLeft,
    bottomRight: bottomRight ?? this.bottomRight,
  );

  /// [rect] with these corners.
  RRect toRRect(Rect rect) => RRect.fromRectAndCorners(
    rect,
    topLeft: topLeft,
    topRight: topRight,
    bottomLeft: bottomLeft,
    bottomRight: bottomRight,
  );

  BorderRadius operator +(BorderRadius other) => BorderRadius.only(
    topLeft: topLeft + other.topLeft,
    topRight: topRight + other.topRight,
    bottomLeft: bottomLeft + other.bottomLeft,
    bottomRight: bottomRight + other.bottomRight,
  );
  BorderRadius operator -(BorderRadius other) => BorderRadius.only(
    topLeft: topLeft - other.topLeft,
    topRight: topRight - other.topRight,
    bottomLeft: bottomLeft - other.bottomLeft,
    bottomRight: bottomRight - other.bottomRight,
  );
  BorderRadius operator *(double other) => BorderRadius.only(
    topLeft: topLeft * other,
    topRight: topRight * other,
    bottomLeft: bottomLeft * other,
    bottomRight: bottomRight * other,
  );

  static BorderRadius? lerp(BorderRadius? a, BorderRadius? b, double t) {
    if (a == null && b == null) return null;
    a ??= BorderRadius.zero;
    b ??= BorderRadius.zero;
    return BorderRadius.only(
      topLeft: Radius.lerp(a.topLeft, b.topLeft, t)!,
      topRight: Radius.lerp(a.topRight, b.topRight, t)!,
      bottomLeft: Radius.lerp(a.bottomLeft, b.bottomLeft, t)!,
      bottomRight: Radius.lerp(a.bottomRight, b.bottomRight, t)!,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is BorderRadius &&
      other.topLeft == topLeft &&
      other.topRight == topRight &&
      other.bottomLeft == bottomLeft &&
      other.bottomRight == bottomRight;
  @override
  int get hashCode => Object.hash(topLeft, topRight, bottomLeft, bottomRight);
  @override
  String toString() =>
      'BorderRadius($topLeft, $topRight, $bottomRight, $bottomLeft)';
}

/// [BorderRadius] with start and end for left and right, resolved against the
/// ambient [Directionality] - see [EdgeInsetsDirectional].
class BorderRadiusDirectional extends BorderRadiusGeometry {
  const BorderRadiusDirectional.all(Radius radius)
    : this.only(
        topStart: radius,
        topEnd: radius,
        bottomStart: radius,
        bottomEnd: radius,
      );

  BorderRadiusDirectional.circular(double radius)
    : this.all(Radius.circular(radius));

  const BorderRadiusDirectional.vertical({
    Radius top = Radius.zero,
    Radius bottom = Radius.zero,
  }) : this.only(
         topStart: top,
         topEnd: top,
         bottomStart: bottom,
         bottomEnd: bottom,
       );

  const BorderRadiusDirectional.horizontal({
    Radius start = Radius.zero,
    Radius end = Radius.zero,
  }) : this.only(
         topStart: start,
         topEnd: end,
         bottomStart: start,
         bottomEnd: end,
       );

  const BorderRadiusDirectional.only({
    this.topStart = Radius.zero,
    this.topEnd = Radius.zero,
    this.bottomStart = Radius.zero,
    this.bottomEnd = Radius.zero,
  });

  final Radius topStart;
  final Radius topEnd;
  final Radius bottomStart;
  final Radius bottomEnd;

  static const BorderRadiusDirectional zero = BorderRadiusDirectional.all(
    Radius.zero,
  );

  @override
  BorderRadius get _resolved => resolve(_ambientDirection);

  @override
  BorderRadius resolve(TextDirection? direction) =>
      direction == TextDirection.rtl
      ? BorderRadius.only(
          topLeft: topEnd,
          topRight: topStart,
          bottomLeft: bottomEnd,
          bottomRight: bottomStart,
        )
      : BorderRadius.only(
          topLeft: topStart,
          topRight: topEnd,
          bottomLeft: bottomStart,
          bottomRight: bottomEnd,
        );

  @override
  bool operator ==(Object other) =>
      other is BorderRadiusDirectional &&
      other.topStart == topStart &&
      other.topEnd == topEnd &&
      other.bottomStart == bottomStart &&
      other.bottomEnd == bottomEnd;
  @override
  int get hashCode => Object.hash(topStart, topEnd, bottomStart, bottomEnd);
}

/// Whether a border side is drawn.
enum BorderStyle { none, solid }

/// One side of a border: a colour and a thickness.
class BorderSide {
  const BorderSide({
    this.color = const Color(0xFF000000),
    this.width = 1.0,
    this.style = BorderStyle.solid,
    this.strokeAlign = strokeAlignInside,
  });

  final Color color;
  final double width;
  final BorderStyle style;

  /// Where the stroke sits relative to the edge. Accepted for compatibility:
  /// every renderer draws a border inside the box, which is Flutter's default.
  final double strokeAlign;

  static const double strokeAlignInside = -1.0;
  static const double strokeAlignCenter = 0.0;
  static const double strokeAlignOutside = 1.0;

  /// No border at all.
  static const BorderSide none = BorderSide(
    width: 0.0,
    style: BorderStyle.none,
  );

  BorderSide copyWith({
    Color? color,
    double? width,
    BorderStyle? style,
    double? strokeAlign,
  }) => BorderSide(
    color: color ?? this.color,
    width: width ?? this.width,
    style: style ?? this.style,
    strokeAlign: strokeAlign ?? this.strokeAlign,
  );

  /// The same side, [t] times as thick.
  BorderSide scale(double t) => BorderSide(
    color: color,
    width: math.max(0.0, width * t),
    style: t <= 0.0 ? BorderStyle.none : style,
  );

  static BorderSide lerp(BorderSide a, BorderSide b, double t) {
    if (t == 0.0) return a;
    if (t == 1.0) return b;
    return BorderSide(
      color: Color.lerp(a.color, b.color, t)!,
      width: math.max(0.0, a.width + (b.width - a.width) * t),
      style: t < 0.5 ? a.style : b.style,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is BorderSide &&
      other.color == color &&
      other.width == width &&
      other.style == style;
  @override
  int get hashCode => Object.hash(color, width, style);
  @override
  String toString() => 'BorderSide($color, $width, ${style.name})';
}

/// The border of a box.
abstract class BoxBorder {
  const BoxBorder();

  BorderSide get top;
  BorderSide get bottom;

  /// Whether every side is the same - the only kind a `box` node can say in
  /// one breath. Anything else is drawn as separate strips.
  bool get isUniform;

  /// How much room the border takes on each edge.
  EdgeInsetsGeometry get dimensions;
}

/// A border with four sides, each its own [BorderSide].
class Border extends BoxBorder {
  const Border({
    this.top = BorderSide.none,
    this.right = BorderSide.none,
    this.bottom = BorderSide.none,
    this.left = BorderSide.none,
  });

  /// The same [side] all the way round.
  const Border.fromBorderSide(BorderSide side)
    : top = side,
      right = side,
      bottom = side,
      left = side;

  /// [vertical] is the left and right sides - the ones that run vertically -
  /// and [horizontal] the top and bottom, as in Flutter.
  const Border.symmetric({
    BorderSide vertical = BorderSide.none,
    BorderSide horizontal = BorderSide.none,
  }) : left = vertical,
       top = horizontal,
       right = vertical,
       bottom = horizontal;

  /// A solid border all the way round.
  factory Border.all({
    Color color = const Color(0xFF000000),
    double width = 1.0,
    BorderStyle style = BorderStyle.solid,
    double strokeAlign = BorderSide.strokeAlignInside,
  }) => Border.fromBorderSide(
    BorderSide(
      color: color,
      width: width,
      style: style,
      strokeAlign: strokeAlign,
    ),
  );

  @override
  final BorderSide top;
  final BorderSide right;
  @override
  final BorderSide bottom;
  final BorderSide left;

  @override
  bool get isUniform => top == right && right == bottom && bottom == left;

  @override
  EdgeInsetsGeometry get dimensions =>
      EdgeInsets.fromLTRB(left.width, top.width, right.width, bottom.width);

  /// Two borders as one: a side one of them leaves out is taken from the
  /// other.
  static Border merge(Border a, Border b) => Border(
    top: a.top == BorderSide.none ? b.top : a.top,
    right: a.right == BorderSide.none ? b.right : a.right,
    bottom: a.bottom == BorderSide.none ? b.bottom : a.bottom,
    left: a.left == BorderSide.none ? b.left : a.left,
  );

  @override
  bool operator ==(Object other) =>
      other is Border &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom &&
      other.left == left;
  @override
  int get hashCode => Object.hash(top, right, bottom, left);
  @override
  String toString() => 'Border($top, $right, $bottom, $left)';
}

/// A shadow: a colour, how far it falls and how soft it is.
class Shadow {
  const Shadow({
    this.color = const Color(0xFF000000),
    this.offset = Offset.zero,
    this.blurRadius = 0.0,
  });

  final Color color;
  final Offset offset;
  final double blurRadius;

  @override
  bool operator ==(Object other) =>
      other is Shadow &&
      other.runtimeType == runtimeType &&
      other.color == color &&
      other.offset == offset &&
      other.blurRadius == blurRadius;
  @override
  int get hashCode => Object.hash(color, offset, blurRadius);
}

/// The shadow a box casts.
///
/// [spreadRadius] is accepted and does not travel: a `box` node's shadow is
/// `{color, blur, dx, dy}`, because a spread is not something Android's
/// elevation or a UIKit layer shadow can be asked for. A box also carries one
/// shadow, so the first of a list is the one drawn.
class BoxShadow extends Shadow {
  const BoxShadow({
    super.color,
    super.offset,
    super.blurRadius,
    this.spreadRadius = 0.0,
  });

  final double spreadRadius;

  /// The node's `shadow` prop.
  Map<String, dynamic> get _json => {
    'color': color._hex,
    'blur': blurRadius,
    'dx': offset.dx,
    'dy': offset.dy,
  };

  BoxShadow scale(double factor) => BoxShadow(
    color: color,
    offset: offset * factor,
    blurRadius: blurRadius * factor,
    spreadRadius: spreadRadius * factor,
  );

  @override
  bool operator ==(Object other) =>
      other is BoxShadow &&
      other.color == color &&
      other.offset == offset &&
      other.blurRadius == blurRadius &&
      other.spreadRadius == spreadRadius;
  @override
  int get hashCode => Object.hash(color, offset, blurRadius, spreadRadius);
}

/// Whether a box is a rectangle or a circle.
enum BoxShape { rectangle, circle }

/// What a gradient does beyond its ends. Accepted for compatibility; the
/// renderers clamp.
enum TileMode { clamp, repeated, mirror, decal }

/// A fill that changes colour across the box.
abstract class Gradient {
  const Gradient({required this.colors, this.stops});

  /// The colours, in order.
  final List<Color> colors;

  /// Where each colour sits, 0 to 1. Evenly spaced when left out.
  final List<double>? stops;

  /// The node's `gradient` prop.
  Map<String, dynamic> get _json;
}

/// A gradient along a line from [begin] to [end].
class LinearGradient extends Gradient {
  const LinearGradient({
    this.begin = Alignment.centerLeft,
    this.end = Alignment.centerRight,
    required super.colors,
    super.stops,
    this.tileMode = TileMode.clamp,
  });

  final AlignmentGeometry begin;
  final AlignmentGeometry end;
  final TileMode tileMode;

  @override
  Map<String, dynamic> get _json => {
    'type': 'linear',
    'colors': [for (final color in colors) color._hex],
    if (stops != null) 'stops': stops,
    'begin': begin._resolved._xy,
    'end': end._resolved._xy,
  };
}

/// A gradient outwards from [center].
///
/// [radius] is a fraction of the box's shorter side, as in Flutter. The
/// protocol describes every gradient by two points, so this one travels as its
/// centre and the point one radius to the right of it - in alignment units,
/// where a whole side is 2, hence the doubling.
class RadialGradient extends Gradient {
  const RadialGradient({
    this.center = Alignment.center,
    this.radius = 0.5,
    required super.colors,
    super.stops,
    this.tileMode = TileMode.clamp,
  });

  final AlignmentGeometry center;
  final double radius;
  final TileMode tileMode;

  @override
  Map<String, dynamic> get _json {
    final middle = center._resolved;
    return {
      'type': 'radial',
      'colors': [for (final color in colors) color._hex],
      if (stops != null) 'stops': stops,
      'begin': middle._xy,
      'end': [middle.x + radius * 2, middle.y],
    };
  }
}

/// How a box is painted. [BoxDecoration] is the one the facade draws.
abstract class Decoration {
  const Decoration();

  /// The room the decoration itself takes up inside the box - its border.
  EdgeInsetsGeometry get padding => EdgeInsets.zero;
}

/// A fill, a border, rounded corners and a shadow - what a `box` node paints.
class BoxDecoration extends Decoration {
  const BoxDecoration({
    this.color,
    this.border,
    this.borderRadius,
    this.boxShadow,
    this.gradient,
    this.backgroundBlendMode,
    this.shape = BoxShape.rectangle,
  });

  final Color? color;
  final BoxBorder? border;
  final BorderRadiusGeometry? borderRadius;

  /// The shadows the box casts. The protocol carries one, so the first is the
  /// one drawn.
  final List<BoxShadow>? boxShadow;

  /// Painted over [color] when both are given.
  final Gradient? gradient;

  /// Accepted for compatibility and not applied: no renderer blends a box's
  /// fill with what is behind it.
  final BlendMode? backgroundBlendMode;
  final BoxShape shape;

  @override
  EdgeInsetsGeometry get padding => border?.dimensions ?? EdgeInsets.zero;

  BoxDecoration copyWith({
    Color? color,
    BoxBorder? border,
    BorderRadiusGeometry? borderRadius,
    List<BoxShadow>? boxShadow,
    Gradient? gradient,
    BlendMode? backgroundBlendMode,
    BoxShape? shape,
  }) => BoxDecoration(
    color: color ?? this.color,
    border: border ?? this.border,
    borderRadius: borderRadius ?? this.borderRadius,
    boxShadow: boxShadow ?? this.boxShadow,
    gradient: gradient ?? this.gradient,
    backgroundBlendMode: backgroundBlendMode ?? this.backgroundBlendMode,
    shape: shape ?? this.shape,
  );
}

/// The outline of a Material component: a card, a button, a chip.
abstract class ShapeBorder {
  const ShapeBorder();
}

/// A [ShapeBorder] with a stroke.
abstract class OutlinedBorder extends ShapeBorder {
  const OutlinedBorder({this.side = BorderSide.none});

  /// The stroke round the shape; none by default.
  final BorderSide side;

  /// The same shape with another stroke.
  OutlinedBorder copyWith({BorderSide? side});
}

/// A rectangle with rounded corners.
class RoundedRectangleBorder extends OutlinedBorder {
  const RoundedRectangleBorder({
    super.side,
    this.borderRadius = BorderRadius.zero,
  });

  final BorderRadiusGeometry borderRadius;

  @override
  RoundedRectangleBorder copyWith({
    BorderSide? side,
    BorderRadiusGeometry? borderRadius,
  }) => RoundedRectangleBorder(
    side: side ?? this.side,
    borderRadius: borderRadius ?? this.borderRadius,
  );

  @override
  bool operator ==(Object other) =>
      other is RoundedRectangleBorder &&
      other.side == side &&
      other.borderRadius == borderRadius;
  @override
  int get hashCode => Object.hash(side, borderRadius);
}

/// A circle.
class CircleBorder extends OutlinedBorder {
  const CircleBorder({super.side});

  @override
  CircleBorder copyWith({BorderSide? side}) =>
      CircleBorder(side: side ?? this.side);

  @override
  bool operator ==(Object other) => other is CircleBorder && other.side == side;
  @override
  int get hashCode => side.hashCode;
}

/// A pill: a rectangle whose short ends are half circles.
class StadiumBorder extends OutlinedBorder {
  const StadiumBorder({super.side});

  @override
  StadiumBorder copyWith({BorderSide? side}) =>
      StadiumBorder(side: side ?? this.side);

  @override
  bool operator ==(Object other) =>
      other is StadiumBorder && other.side == side;
  @override
  int get hashCode => side.hashCode;
}

// ---------------------------------------------------------------------------
// Transforms.
// ---------------------------------------------------------------------------

/// A 2D transform with Flutter's `Matrix4` name on it.
///
/// A `box` node's transform is `{rotate, scale, dx, dy}` applied about the
/// centre, so that is what this holds: a turn about the z axis, one scale and
/// a shift. It is not a matrix. Calls compose naively - translations add,
/// scales multiply, rotations add - which is right for the common
/// `Matrix4.identity()..translate(x, y)..scale(s)` and wrong for anything that
/// depends on the order (a translate after a rotate moves along the screen's
/// axes here, not the rotated ones). Skew, perspective and a different scale
/// per axis have nowhere to go; a non-uniform scale travels as its x factor.
class Matrix4 {
  Matrix4.identity();

  /// A shift by ([x], [y]). [z] has no meaning on a flat screen.
  Matrix4.translationValues(double x, double y, double z) : _dx = x, _dy = y;

  /// A turn of [radians] about the z axis - clockwise on screen.
  Matrix4.rotationZ(double radians) : _rotate = radians;

  /// A scale by [x] across and [y] down. The protocol has one scale, so [x]
  /// is the one that travels.
  Matrix4.diagonal3Values(double x, double y, double z)
    : _scaleX = x,
      _scaleY = y;

  double _rotate = 0;
  double _scaleX = 1;
  double _scaleY = 1;
  double _dx = 0;
  double _dy = 0;

  /// Back to doing nothing.
  void setIdentity() {
    _rotate = 0;
    _scaleX = 1;
    _scaleY = 1;
    _dx = 0;
    _dy = 0;
  }

  bool isIdentity() =>
      _rotate == 0 && _scaleX == 1 && _scaleY == 1 && _dx == 0 && _dy == 0;

  /// Shifts by ([x], [y]) more.
  void translate(double x, [double y = 0.0, double z = 0.0]) {
    _dx += x;
    _dy += y;
  }

  /// Flutter's newer spelling of [translate].
  void translateByDouble(double x, double y, double z, double w) =>
      translate(x, y);

  /// Scales by [x] more; [y] defaults to [x].
  void scale(double x, [double? y, double? z]) {
    _scaleX *= x;
    _scaleY *= y ?? x;
  }

  /// Flutter's newer spelling of [scale].
  void scaleByDouble(double x, double y, double z, double w) => scale(x, y);

  /// Turns by [radians] more.
  void rotateZ(double radians) => _rotate += radians;

  /// A copy, for a transform built up from another.
  Matrix4 clone() => Matrix4.identity()
    .._rotate = _rotate
    .._scaleX = _scaleX
    .._scaleY = _scaleY
    .._dx = _dx
    .._dy = _dy;

  /// The node's `transform` prop: only what differs from doing nothing, and
  /// null when nothing does.
  Map<String, dynamic>? get _transform => isIdentity()
      ? null
      : {
          if (_rotate != 0) 'rotate': _rotate,
          if (_scaleX != 1) 'scale': _scaleX,
          if (_dx != 0) 'dx': _dx,
          if (_dy != 0) 'dy': _dy,
        };

  @override
  bool operator ==(Object other) =>
      other is Matrix4 &&
      other._rotate == _rotate &&
      other._scaleX == _scaleX &&
      other._scaleY == _scaleY &&
      other._dx == _dx &&
      other._dy == _dy;
  @override
  int get hashCode => Object.hash(_rotate, _scaleX, _scaleY, _dx, _dy);
}

// ---------------------------------------------------------------------------
// Enums and small descriptions, Flutter's names.
// ---------------------------------------------------------------------------

/// The two directions something can run in.
enum Axis { horizontal, vertical }

/// How an image is fitted into the box it is given.
enum BoxFit { fill, contain, cover, fitWidth, fitHeight, none, scaleDown }

/// Whether content is cut to its box. The renderers have one way of clipping,
/// so everything but [none] means "clip".
enum Clip { none, hardEdge, antiAlias, antiAliasWithSaveLayer }

/// How lines of text sit across their box. [left] and [right] are the left
/// and the right whichever way the screen reads; [start] and [end] follow the
/// ambient [Directionality].
enum TextAlign { left, right, center, justify, start, end }

/// The direction text reads in.
enum TextDirection { rtl, ltr }

/// How the unpositioned children of a `Stack` are sized.
enum StackFit { loose, expand, passthrough }

/// Which way a column counts its children.
enum VerticalDirection { up, down }

/// Whether a row or column takes all the room on its main axis or only what
/// its children need.
enum MainAxisSize { min, max }

/// How children are distributed along a row or column.
enum MainAxisAlignment {
  start,
  end,
  center,
  spaceBetween,
  spaceAround,
  spaceEvenly,
}

/// How children are placed across a row or column. [baseline] needs font
/// metrics the protocol does not carry, and is treated as [start].
enum CrossAxisAlignment { start, end, center, stretch, baseline }

/// How the children of a `Wrap` are distributed along each line.
enum WrapAlignment {
  start,
  end,
  center,
  spaceBetween,
  spaceAround,
  spaceEvenly,
}

/// How the children of a `Wrap` are placed across each line.
enum WrapCrossAlignment { start, end, center }

/// Which touches a gesture detector takes.
enum HitTestBehavior { deferToChild, opaque, translucent }

/// Light or dark.
enum Brightness { dark, light }

/// Which of an app's two themes is shown.
enum ThemeMode { system, light, dark }

/// Upright or slanted.
enum FontStyle { normal, italic }

/// The line text sits on.
enum TextBaseline { alphabetic, ideographic }

/// How a paint is combined with what is under it. Accepted where Flutter
/// takes one; the renderers always draw source-over.
enum BlendMode {
  clear,
  src,
  dst,
  srcOver,
  dstOver,
  srcIn,
  dstIn,
  srcOut,
  dstOut,
  srcATop,
  dstATop,
  xor,
  plus,
  modulate,
  screen,
  overlay,
  darken,
  lighten,
  multiply,
  color,
}

/// How tightly a component is packed. Accepted for compatibility: each
/// renderer draws its platform's own density.
class VisualDensity {
  const VisualDensity({this.horizontal = 0.0, this.vertical = 0.0});

  final double horizontal;
  final double vertical;

  static const double minimumDensity = -4.0;
  static const double maximumDensity = 4.0;

  static const VisualDensity standard = VisualDensity();
  static const VisualDensity comfortable = VisualDensity(
    horizontal: -1.0,
    vertical: -1.0,
  );
  static const VisualDensity compact = VisualDensity(
    horizontal: -2.0,
    vertical: -2.0,
  );

  /// The density for the platform the app is on. Standard here, since the
  /// renderers choose their own.
  static VisualDensity get adaptivePlatformDensity => standard;

  VisualDensity copyWith({double? horizontal, double? vertical}) =>
      VisualDensity(
        horizontal: horizontal ?? this.horizontal,
        vertical: vertical ?? this.vertical,
      );

  @override
  bool operator ==(Object other) =>
      other is VisualDensity &&
      other.horizontal == horizontal &&
      other.vertical == vertical;
  @override
  int get hashCode => Object.hash(horizontal, vertical);
}

/// An OpenType feature (`tnum`, `smcp`). Accepted so a `TextStyle` written for
/// Flutter compiles; no renderer is told about it.
class FontFeature {
  const FontFeature(this.feature, [this.value = 1]);
  const FontFeature.enable(this.feature) : value = 1;
  const FontFeature.disable(this.feature) : value = 0;
  const FontFeature.tabularFigures() : feature = 'tnum', value = 1;
  const FontFeature.proportionalFigures() : feature = 'pnum', value = 1;
  const FontFeature.liningFigures() : feature = 'lnum', value = 1;
  const FontFeature.oldstyleFigures() : feature = 'onum', value = 1;
  const FontFeature.slashedZero() : feature = 'zero', value = 1;
  const FontFeature.superscripts() : feature = 'sups', value = 1;
  const FontFeature.subscripts() : feature = 'subs', value = 1;

  final String feature;
  final int value;

  @override
  bool operator ==(Object other) =>
      other is FontFeature && other.feature == feature && other.value == value;
  @override
  int get hashCode => Object.hash(feature, value);
}
