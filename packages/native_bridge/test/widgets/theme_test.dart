/// ThemeData, ColorScheme and the text styles: Flutter's shapes, and the
/// bridge to the protocol's AppTheme.
library;

import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// WCAG contrast between two colours, 1 (none) to 21 (black on white).
double _contrast(Color a, Color b) {
  final one = a.computeLuminance() + 0.05;
  final two = b.computeLuminance() + 0.05;
  return one > two ? one / two : two / one;
}

void main() {
  group('ColorScheme.fromSeed', () {
    test('keeps the hue of the seed and stays colourful', () {
      final scheme = ColorScheme.fromSeed(seedColor: Colors.teal);
      final seed = HSLColor.fromColor(Colors.teal);
      final primary = HSLColor.fromColor(scheme.primary);
      expect((primary.hue - seed.hue).abs(), lessThan(25));
      expect(primary.saturation, greaterThan(0.4));
    });

    test('a light surface is near white and a dark one near black', () {
      final light = ColorScheme.fromSeed(seedColor: Colors.teal);
      final dark = ColorScheme.fromSeed(
        seedColor: Colors.teal,
        brightness: Brightness.dark,
      );
      expect(light.brightness, Brightness.light);
      expect(dark.brightness, Brightness.dark);
      expect(light.surface.computeLuminance(), greaterThan(0.9));
      expect(dark.surface.computeLuminance(), lessThan(0.05));
    });

    test('every "on" colour reads on what it sits on, in both modes', () {
      for (final seed in [
        Colors.teal,
        Colors.blue,
        Colors.amber,
        Colors.grey,
      ]) {
        for (final brightness in Brightness.values) {
          final s = ColorScheme.fromSeed(
            seedColor: seed,
            brightness: brightness,
          );
          expect(_contrast(s.onPrimary, s.primary), greaterThan(4.5));
          expect(_contrast(s.onSurface, s.surface), greaterThan(7));
          expect(
            _contrast(s.onPrimaryContainer, s.primaryContainer),
            greaterThan(4.5),
          );
          expect(_contrast(s.onError, s.error), greaterThan(4.5));
          expect(_contrast(s.onSurfaceVariant, s.surface), greaterThan(4.5));
        }
      }
    });

    test('the surface containers step away from the surface in order', () {
      final light = ColorScheme.fromSeed(seedColor: Colors.indigo);
      final steps = [
        light.surfaceContainerLowest,
        light.surfaceContainerLow,
        light.surfaceContainer,
        light.surfaceContainerHigh,
        light.surfaceContainerHighest,
      ].map((c) => c.computeLuminance()).toList();
      for (var i = 1; i < steps.length; i++) {
        expect(steps[i], lessThan(steps[i - 1]));
      }
    });

    test('a role passed in is used as given', () {
      final scheme = ColorScheme.fromSeed(
        seedColor: Colors.teal,
        primary: Colors.pink,
      );
      expect(scheme.primary, Colors.pink);
      expect(scheme.surfaceTint, isNot(Colors.pink));
    });
  });

  group('ColorScheme', () {
    test('roles left out fall back to the required ones', () {
      const scheme = ColorScheme.light();
      expect(scheme.primary, const Color(0xFF6200EE));
      expect(scheme.primaryContainer, scheme.primary);
      expect(scheme.tertiary, scheme.secondary);
      expect(scheme.surfaceContainerHighest, scheme.surface);
      expect(scheme.outline, scheme.onSurface);
      expect(const ColorScheme.dark().surface, const Color(0xFF121212));
      expect(const ColorScheme.dark().brightness, Brightness.dark);
    });

    test('copyWith replaces one role', () {
      const scheme = ColorScheme.light();
      final changed = scheme.copyWith(primary: Colors.green);
      expect(changed.primary, Colors.green);
      expect(changed.secondary, scheme.secondary);
      expect(changed, isNot(scheme));
      expect(scheme.copyWith(), scheme);
    });
  });

  group('TextStyle', () {
    test('copyWith and merge overlay only what is set', () {
      const base = TextStyle(fontSize: 14, color: Colors.black);
      expect(
        base.copyWith(fontWeight: FontWeight.bold),
        const TextStyle(
          fontSize: 14,
          color: Colors.black,
          fontWeight: FontWeight.bold,
        ),
      );
      final merged = base.merge(const TextStyle(color: Colors.red, height: 2));
      expect(merged.fontSize, 14);
      expect(merged.color, Colors.red);
      expect(merged.height, 2);
      expect(base.merge(null), base);
    });

    test('a style that does not inherit replaces instead', () {
      const base = TextStyle(fontSize: 14, color: Colors.black);
      const other = TextStyle(inherit: false, color: Colors.red);
      expect(base.merge(other).fontSize, isNull);
    });

    test('FontWeight spans 100 to 900', () {
      expect(FontWeight.w100.value, 100);
      expect(FontWeight.w900.value, 900);
      expect(FontWeight.normal, FontWeight.w400);
      expect(FontWeight.bold, FontWeight.w700);
      expect(FontWeight.values, hasLength(9));
    });
  });

  group('ThemeData', () {
    test('derives its colours from a seed', () {
      final theme = ThemeData(colorSchemeSeed: Colors.teal);
      expect(theme.brightness, Brightness.light);
      expect(theme.useMaterial3, isTrue);
      expect(theme.scaffoldBackgroundColor, theme.colorScheme.surface);
      expect(theme.primaryColor, theme.colorScheme.primary);
      expect(theme.dividerColor, theme.colorScheme.outlineVariant);
      expect(theme.disabledColor.alpha, lessThan(255));
    });

    test('dark() is dark', () {
      final theme = ThemeData.dark();
      expect(theme.brightness, Brightness.dark);
      expect(theme.colorScheme.surface.computeLuminance(), lessThan(0.05));
      expect(ThemeData.light().brightness, Brightness.light);
    });

    test('the text theme has the Material 3 scale, coloured onSurface', () {
      final theme = ThemeData(colorSchemeSeed: Colors.teal);
      final text = theme.textTheme;
      expect(text.displayLarge!.fontSize, 57);
      expect(text.headlineMedium!.fontSize, 28);
      expect(text.titleLarge!.fontSize, 22);
      expect(text.titleMedium!.fontWeight, FontWeight.w500);
      expect(text.bodyLarge!.fontSize, 16);
      expect(text.bodyMedium!.fontSize, 14);
      expect(text.bodyMedium!.letterSpacing, 0.25);
      expect(text.labelSmall!.fontSize, 11);
      expect(text.bodyMedium!.color, theme.colorScheme.onSurface);
    });

    test('a passed text theme overlays the scale', () {
      final theme = ThemeData(
        textTheme: const TextTheme(titleLarge: TextStyle(fontSize: 30)),
      );
      expect(theme.textTheme.titleLarge!.fontSize, 30);
      expect(theme.textTheme.titleLarge!.color, theme.colorScheme.onSurface);
      expect(theme.textTheme.bodyMedium!.fontSize, 14);
    });

    test('copyWith keeps what it is not given', () {
      final theme = ThemeData(colorSchemeSeed: Colors.teal);
      final changed = theme.copyWith(scaffoldBackgroundColor: Colors.pink);
      expect(changed.scaffoldBackgroundColor, Colors.pink);
      expect(changed.colorScheme, theme.colorScheme);
      expect(
        theme
            .copyWith(appBarTheme: const AppBarTheme(centerTitle: true))
            .appBarTheme
            .centerTitle,
        isTrue,
      );
    });

    test('extensions are found by type', () {
      final theme = ThemeData(extensions: const [_Brand(Colors.pink)]);
      expect(theme.extension<_Brand>()!.accent, Colors.pink);
      expect(ThemeData().extension<_Brand>(), isNull);
      expect(
        theme
            .copyWith(extensions: const [_Brand(Colors.blue)])
            .extension<_Brand>()!
            .accent,
        Colors.blue,
      );
    });
  });

  group('ThemeData and AppTheme', () {
    test('toAppTheme maps the roles the renderers draw with', () {
      final light = ThemeData(colorSchemeSeed: Colors.teal);
      final dark = ThemeData(
        colorSchemeSeed: Colors.teal,
        brightness: Brightness.dark,
      );
      final app = light.toAppTheme(dark: dark);
      expect(app.mode, AppThemeMode.system);
      expect(Color.fromHex(app.primary), light.colorScheme.primary);
      expect(Color.fromHex(app.onPrimary), light.colorScheme.onPrimary);
      expect(Color.fromHex(app.surface), light.colorScheme.surface);
      expect(Color.fromHex(app.text), light.colorScheme.onSurface);
      expect(Color.fromHex(app.error), light.colorScheme.error);
      expect(Color.fromHex(app.dark.primary), dark.colorScheme.primary);
      expect(Color.fromHex(app.dark.surface), dark.colorScheme.surface);
      // Opaque colours travel in the short form every renderer has always
      // read.
      expect(app.primary, hasLength(7));
    });

    test('toAppTheme follows the mode asked for', () {
      final theme = ThemeData();
      expect(theme.toAppTheme(mode: ThemeMode.dark).mode, AppThemeMode.dark);
      expect(theme.toAppTheme(mode: ThemeMode.light).mode, AppThemeMode.light);
    });

    test('with no dark theme, the one theme serves both modes', () {
      final theme = ThemeData(colorSchemeSeed: Colors.teal);
      final app = theme.toAppTheme();
      expect(app.dark.primary, app.primary);
      expect(app.dark.surface, app.surface);
    });

    test('a theme made from an AppTheme hands it back unchanged', () {
      const palette = AppTheme(primary: '#6200ee', mode: AppThemeMode.system);
      final theme = ThemeData.fromAppTheme(palette);
      expect(theme.appTheme, same(palette));
      expect(theme.colorScheme.primary, const Color(0xFF6200EE));
      expect(theme.colorScheme.surface, Color.fromHex(palette.surface));
      expect(theme.colorScheme.onSurface, Color.fromHex(palette.text));
      expect(theme.brightness, Brightness.light);

      final dark = ThemeData.fromAppTheme(palette, dark: true);
      expect(dark.brightness, Brightness.dark);
      expect(dark.colorScheme.surface, Color.fromHex(palette.dark.surface));
    });

    test('an AppTheme survives the trip through ThemeData', () {
      final back = ThemeData.fromAppTheme(
        AppTheme.fallback,
      ).toAppTheme(mode: ThemeMode.light);
      expect(back.primary, AppTheme.fallback.primary);
      expect(back.surface, AppTheme.fallback.surface);
      expect(back.surfaceVariant, AppTheme.fallback.surfaceVariant);
      expect(back.text, AppTheme.fallback.text);
      expect(back.textSecondary, AppTheme.fallback.textSecondary);
      expect(back.divider, AppTheme.fallback.divider);
      expect(back.success, AppTheme.fallback.success);
    });

    test('a theme not made from one still has an appTheme', () {
      final theme = ThemeData(colorSchemeSeed: Colors.teal);
      expect(Color.fromHex(theme.appTheme.primary), theme.colorScheme.primary);
    });
  });
}

class _Brand extends ThemeExtension<_Brand> {
  const _Brand(this.accent);
  final Color accent;

  @override
  _Brand copyWith({Color? accent}) => _Brand(accent ?? this.accent);

  @override
  _Brand lerp(_Brand? other, double t) => this;
}
