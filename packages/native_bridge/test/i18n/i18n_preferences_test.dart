/// Unit tests for locale preference persistence and selection.
library;

import 'package:dart_not_native/i18n/i18n_preferences.dart';
import 'package:dart_not_native/i18n/translations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The preference store is a process-wide singleton, so each test starts
  // from a clean slate.
  setUp(() async => getI18nPreferences().clear());

  test('is a singleton', () {
    expect(identical(I18nPreferences(), getI18nPreferences()), isTrue);
  });

  group('preferred locale', () {
    test('is null until one is saved', () async {
      expect(await loadLocalePreference(), isNull);
    });

    test('round trips through the store', () async {
      await saveLocalePreference(const Locale('es', region: 'MX'));

      final loaded = await loadLocalePreference();

      expect(loaded, const Locale('es', region: 'MX'));
      expect(getI18nPreferences().get('preferred_locale'), 'es_MX');
    });

    test('clear forgets it', () async {
      await saveLocalePreference(const Locale('fr'));

      await getI18nPreferences().clear();

      expect(await loadLocalePreference(), isNull);
    });
  });

  group('getBestLocale', () {
    const available = [Locale('en'), Locale('es'), Locale('fr')];

    test('prefers the saved locale when it is available', () async {
      await saveLocalePreference(const Locale('fr'));

      expect(await getBestAvailableLocale(available), const Locale('fr'));
    });

    test('ignores a saved locale that is not available', () async {
      await saveLocalePreference(const Locale('de'));

      expect(
        await getBestAvailableLocale(available),
        const Locale('en'),
        reason: 'falls through to the system locale',
      );
    });

    test('falls back to the system locale', () async {
      expect(await getBestAvailableLocale(available), const Locale('en'));
    });

    test(
      'matches on language when the exact system locale is missing',
      () async {
        const regional = [Locale('en', region: 'GB'), Locale('es')];

        expect(
          await getBestAvailableLocale(regional),
          const Locale('en', region: 'GB'),
        );
      },
    );

    test('takes the first available locale when nothing matches', () async {
      expect(
        await getBestAvailableLocale(const [Locale('es'), Locale('fr')]),
        const Locale('es'),
      );
    });

    test('defaults to English when nothing is available', () async {
      expect(await getBestAvailableLocale(const []), const Locale('en'));
    });
  });
}
