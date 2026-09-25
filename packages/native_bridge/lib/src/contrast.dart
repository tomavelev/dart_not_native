/// What text drawn over an app-chosen colour looks like.
///
/// A theme says what text on the *surface* is, and the renderers use it for
/// everything they draw. That is wrong the moment an app states a colour of
/// its own - a card's `backgroundColor`, a button's `color`, a badge, an
/// `AnimatedContainer` - because the theme's text colour was chosen against
/// the surface, not against whatever the app picked. A near-black label on a
/// navy card is not a style, it is unreadable.
///
/// So: text over a stated colour is [onDark] or [onLight], whichever contrasts
/// more. The rule is WCAG's relative luminance, and every renderer carries its
/// own copy of it - Kotlin and Swift cannot call this one - so the same card
/// reads the same on all four.
library;

import 'dart:math' as math;

/// Near-black text, for a light background. The default theme's own text
/// colour, so a light card looks like the rest of the app rather than like
/// pure black on white.
const String onLight = '#212121';

/// White text, for a dark background.
const String onDark = '#ffffff';

/// [onLight] or [onDark], whichever is more readable over [background].
///
/// [background] is `#rgb`, `#rrggbb` or `#aarrggbb`; anything else answers
/// [onLight], since a colour a renderer cannot parse is not one it drew.
///
/// The threshold is 0.179, where white and black contrast equally by WCAG's
/// formula - above it the background is light enough that dark text wins.
String textOn(String background) =>
    (relativeLuminance(background) ?? 1) > 0.179 ? onLight : onDark;

/// The WCAG relative luminance of [color], or null if it cannot be read.
///
/// Channels are linearised before they are weighted, which is the whole point
/// of the formula: a mid green is far brighter to the eye than a mid blue, and
/// averaging the three would call them the same.
double? relativeLuminance(String color) {
  final rgb = _rgb(color);
  if (rgb == null) return null;
  final (r, g, b) = rgb;
  return 0.2126 * _linear(r) + 0.7152 * _linear(g) + 0.0722 * _linear(b);
}

double _linear(int channel) {
  final value = channel / 255;
  return value <= 0.03928
      ? value / 12.92
      : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
}

/// The red, green and blue of `#rgb`, `#rrggbb` or `#aarrggbb`.
(int, int, int)? _rgb(String color) {
  var hex = color.trim();
  if (!hex.startsWith('#')) return null;
  hex = hex.substring(1);
  if (hex.length == 3) {
    hex = hex.split('').map((c) => '$c$c').join();
  }
  if (hex.length == 8) hex = hex.substring(2);
  if (hex.length != 6) return null;
  final value = int.tryParse(hex, radix: 16);
  if (value == null) return null;
  return ((value >> 16) & 0xff, (value >> 8) & 0xff, value & 0xff);
}
