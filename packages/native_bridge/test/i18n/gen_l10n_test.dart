/// `GeneratedL10n` looks gen-l10n's strings up for the locale an app shows,
/// once each, falling back to the locale the app chose.
library;

import 'dart:ui' as ui;

import 'package:dart_not_native/gen_l10n.dart';
import 'package:dart_not_native/testing.dart';
import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class _Strings {
  _Strings(this.locale);
  final ui.Locale locale;
  String get hello => switch (locale.languageCode) {
    'bg' => 'Здравей',
    'pt' => locale.countryCode == 'BR' ? 'Olá (BR)' : 'Olá',
    _ => 'Hello',
  };
}

void main() {
  final looked = <ui.Locale>[];
  final l10n = GeneratedL10n(
    (locale) {
      looked.add(locale);
      return _Strings(locale);
    },
    supportedLocales: const [
      ui.Locale('bg'),
      ui.Locale('en'),
      ui.Locale('pt'),
      ui.Locale('pt', 'BR'),
    ],
  );
  setUp(looked.clear);

  test('the nearest supported locale, and English for the rest', () {
    expect(l10n.forLocale(const Locale('bg')).hello, 'Здравей');
    expect(l10n.forLocale(const Locale('pt', 'BR')).hello, 'Olá (BR)');
    expect(l10n.forLocale(const Locale('pt', 'PT')).hello, 'Olá');
    // Not the first, alphabetically - Bulgarian - but the one said.
    expect(l10n.forLocale(const Locale('de')).hello, 'Hello');
  });

  test('each locale is looked up once', () {
    final fresh = GeneratedL10n(
      (locale) {
        looked.add(locale);
        return _Strings(locale);
      },
      supportedLocales: const [ui.Locale('en')],
    );
    fresh.forLocale(const Locale('en'));
    fresh.forLocale(const Locale('en'));
    expect(looked, hasLength(1));
  });

  test('of a context is the locale the app shows', () {
    String? said;
    AppTester.widget(
      MaterialApp(
        locale: const Locale('bg'),
        supportedLocales: const [Locale('bg'), Locale('en')],
        home: Builder(
          builder: (context) {
            said = l10n.of(context).hello;
            return Text(said!);
          },
        ),
      ),
    );
    expect(said, 'Здравей');
  });
}
