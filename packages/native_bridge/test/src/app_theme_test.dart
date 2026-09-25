import 'package:dart_not_native/core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppTheme', () {
    test('the fallback is the Material palette', () {
      expect(AppTheme.fallback.primary, '#1976d2');
      expect(AppTheme.fallback.onPrimary, '#ffffff');
      expect(AppTheme.fallback.secondary, '#f57c00');
      expect(AppTheme.fallback.surface, '#ffffff');
      expect(AppTheme.fallback.error, '#d32f2f');
    });

    test('round trips the whole palette through json', () {
      const theme = AppTheme(
        primary: '#e91e63',
        onPrimary: '#000000',
        secondary: '#00bcd4',
        surface: '#fafafa',
        error: '#b00020',
      );
      expect(theme.toJson(), {
        'primary': '#e91e63',
        'onPrimary': '#000000',
        'secondary': '#00bcd4',
        'surface': '#fafafa',
        'surfaceVariant': '#f5f5f5',
        'text': '#212121',
        'textSecondary': '#757575',
        'divider': '#e0e0e0',
        'error': '#b00020',
        'success': '#388e3c',
        'warning': '#fbc02d',
        'info': '#0288d1',
        'glassTransparency': 0.0,
        'glassChrome': true,
        'mode': 'light',
        // The dark counterpart travels with it, so a renderer can follow the
        // device without asking Dart again. One level deep: it carries colours
        // only, no mode and no dark of its own.
        'dark': AppTheme.darkFallback.toJson()
          ..remove('glassTransparency')
          ..remove('glassChrome')
          ..remove('mode')
          ..remove('dark'),
      });
      expect(AppTheme.fromJson(theme.toJson()), theme);
    });

    test('fromJson falls back for a null map or a missing field', () {
      expect(AppTheme.fromJson(null), AppTheme.fallback);
      final partial = AppTheme.fromJson({'primary': '#123456'});
      expect(partial.primary, '#123456');
      expect(partial.onPrimary, AppTheme.fallback.onPrimary);
      expect(partial.secondary, AppTheme.fallback.secondary);
      expect(partial.error, AppTheme.fallback.error);
    });

    test('resolve picks the appearance the mode asks for', () {
      const dark = AppTheme(text: '#eeeeee');

      const always = AppTheme(text: '#111111', dark: dark);
      expect(always.resolve(platformIsDark: true), same(always));
      expect(always.isDark(platformIsDark: true), isFalse);

      const never = AppTheme(
        text: '#111111', mode: AppThemeMode.dark, dark: dark);
      expect(never.resolve(platformIsDark: false).text, '#eeeeee');
      expect(never.isDark(platformIsDark: false), isTrue);

      const follows = AppTheme(
        text: '#111111', mode: AppThemeMode.system, dark: dark);
      expect(follows.resolve(platformIsDark: false).text, '#111111');
      expect(follows.resolve(platformIsDark: true).text, '#eeeeee');
    });

    test('a theme with no dark palette of its own gets the built-in one', () {
      const theme = AppTheme(mode: AppThemeMode.dark);

      expect(theme.dark, AppTheme.darkFallback);
      expect(theme.resolve(platformIsDark: false).surface, '#121212');
    });

    test('the dark palette is only ever one level deep', () {
      // Every palette answers `dark`, including the dark ones, so a renderer
      // that resolved an appearance must not find another choice waiting.
      expect(AppTheme.darkFallback.mode, AppThemeMode.light);
      expect(
        AppTheme.darkFallback.resolve(platformIsDark: true),
        AppTheme.darkFallback,
      );
    });

    test('equality covers every colour', () {
      expect(const AppTheme(primary: '#111111'),
          const AppTheme(primary: '#111111'));
      expect(const AppTheme(primary: '#111111'),
          isNot(const AppTheme(primary: '#222222')));
      expect(const AppTheme(secondary: '#111111'),
          isNot(const AppTheme(secondary: '#222222')));
      expect(const AppTheme(error: '#111111'),
          isNot(const AppTheme(error: '#222222')));
      expect(const AppTheme(text: '#111111'),
          isNot(const AppTheme(text: '#222222')));
      expect(const AppTheme(divider: '#111111'),
          isNot(const AppTheme(divider: '#222222')));
      expect(const AppTheme(mode: AppThemeMode.dark),
          isNot(const AppTheme(mode: AppThemeMode.system)));
      // Leaving the dark palette out is the same as passing the built-in one.
      expect(const AppTheme(), const AppTheme(dark: AppTheme.darkFallback));
      expect(const AppTheme(),
          isNot(const AppTheme(dark: AppTheme(surface: '#010101'))));
    });
  });
}
