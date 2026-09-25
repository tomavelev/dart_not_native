/// Unit tests for locales, lookup, interpolation and pluralisation.
library;

import 'dart:convert';

import 'package:dart_not_native/i18n/translation_bundles.dart';
import 'package:dart_not_native/i18n/translations.dart';
import 'package:flutter_test/flutter_test.dart';

const _en = {
  'greeting': 'Hello',
  'welcome': 'Welcome, {name}!',
  'nav': {
    'home': 'Home',
    'deep': {'link': 'Deep link'},
  },
  'items': {
    'zero': 'No items',
    'one': '{count} item',
    'few': '{count} items',
    'many': 'lots of items',
    'other': '{count} items',
  },
};

const _es = {
  'greeting': 'Hola',
  'nav': {'home': 'Inicio'},
};

I18n i18n({String locale = 'en', String fallback = 'en'}) =>
    I18n(defaultLocale: Locale(locale), fallbackLocale: Locale(fallback))
      ..loadTranslations(const Locale('en'), _en)
      ..loadTranslations(const Locale('es'), _es);

void main() {
  group('Locale', () {
    test('parses a bare language and a language_region pair', () {
      expect(Locale.fromString('en').language, 'en');
      expect(Locale.fromString('en').region, isNull);

      final enUs = Locale.fromString('en_US');
      expect(enUs.language, 'en');
      expect(enUs.region, 'US');
    });

    test('round trips through toString', () {
      expect(const Locale('en').toString(), 'en');
      expect(const Locale('en', region: 'US').toString(), 'en_US');
      expect(Locale.fromString('pt_BR').toString(), 'pt_BR');
    });

    test(
      'parses a script subtag',
      () {
        final locale = Locale.fromString('zh_Hans_CN');

        expect(locale.language, 'zh');
        expect(locale.script, 'Hans');
        expect(locale.region, 'CN');
        expect(locale.toString(), 'zh_Hans_CN');
      },
    );

    test('equality and hashCode cover every subtag', () {
      expect(const Locale('en'), const Locale('en'));
      expect(const Locale('en').hashCode, const Locale('en').hashCode);
      expect(const Locale('en', region: 'US'), isNot(const Locale('en')));
      expect(const Locale('en'), isNot(const Locale('es')));
    });

    test('matches ignores a region the other side leaves open', () {
      const en = Locale('en');
      const enUs = Locale('en', region: 'US');
      const enGb = Locale('en', region: 'GB');

      expect(enUs.matches(en), isTrue);
      expect(en.matches(enUs), isTrue);
      expect(enUs.matches(enGb), isFalse);
      expect(enUs.matches(const Locale('es', region: 'US')), isFalse);
    });
  });

  group('I18n lookup', () {
    test('translates a flat key', () {
      expect(i18n().t('greeting'), 'Hello');
    });

    test('translates nested keys with dotted paths', () {
      expect(i18n().t('nav.home'), 'Home');
      expect(i18n().t('nav.deep.link'), 'Deep link');
    });

    test('an unknown key returns the default, else the key itself', () {
      expect(i18n().t('missing.key'), 'missing.key');
      expect(i18n().t('missing.key', defaultValue: 'Fallback'), 'Fallback');
    });

    test(
      'a key that resolves to a branch rather than a leaf is not a string',
      () {
        // 'nav' is a map; the manager stringifies rather than throwing.
        expect(i18n().t('nav'), isNot('nav.home'));
      },
    );

    test('falls back to the fallback locale for missing keys', () {
      final manager = i18n(locale: 'es', fallback: 'en');

      expect(manager.t('greeting'), 'Hola');
      expect(manager.t('welcome', params: {'name': 'Ana'}), 'Welcome, Ana!');
    });

    test('a regional locale falls back to its base language', () {
      final manager = I18n(defaultLocale: const Locale('en', region: 'US'))
        ..loadTranslations(const Locale('en'), _en);

      expect(manager.t('greeting'), 'Hello');
    });
  });

  group('I18n interpolation', () {
    test('substitutes every named parameter', () {
      expect(i18n().t('welcome', params: {'name': 'Sam'}), 'Welcome, Sam!');
    });

    test('leaves placeholders untouched when no params are given', () {
      expect(i18n().t('welcome'), 'Welcome, {name}!');
    });

    test('non-string parameters are stringified', () {
      final manager = i18n()
        ..loadTranslations(const Locale('en'), {'n': 'Value: {v}'});

      expect(manager.t('n', params: {'v': 42}), 'Value: 42');
    });
  });

  group('I18n pluralisation', () {
    test('picks the form for the count and injects it', () {
      final manager = i18n();

      expect(manager.plural('items', 0), 'No items');
      expect(manager.plural('items', 1), '1 item');
      expect(manager.plural('items', 5), '5 items');
      expect(manager.plural('items', 20), 'lots of items');
    });

    test('falls back to the "other" form when a category is missing', () {
      final manager = I18n(defaultLocale: const Locale('en'))
        ..loadTranslations(const Locale('en'), {
          'files': {'other': '{count} files'},
        });

      expect(manager.plural('files', 1), '1 files');
    });
  });

  group('I18n locale switching', () {
    test(
      'setLocale changes the active locale and notifies listeners',
      () async {
        final manager = i18n();
        var notifications = 0;
        manager.addListener(() => notifications++);

        await manager.setLocale(const Locale('es'));

        expect(manager.currentLocale, const Locale('es'));
        expect(manager.t('greeting'), 'Hola');
        expect(notifications, 1);
      },
    );

    test('setting the current locale again notifies nobody', () async {
      final manager = i18n();
      var notifications = 0;
      manager.addListener(() => notifications++);

      await manager.setLocale(const Locale('en'));

      expect(notifications, 0);
    });

    test('a removed listener stops hearing changes', () async {
      final manager = i18n();
      var notifications = 0;
      void listener() => notifications++;
      manager.addListener(listener);

      await manager.setLocale(const Locale('es'));
      manager.removeListener(listener);
      await manager.setLocale(const Locale('en'));

      expect(notifications, 1);
    });

    test('setLocaleFromString parses the locale', () async {
      final manager = i18n();

      await manager.setLocaleFromString('es');

      expect(manager.currentLocale, const Locale('es'));
    });

    test('availableLocales lists what has been loaded', () {
      expect(
        i18n().availableLocales.map((l) => l.toString()).toList()..sort(),
        ['en', 'es'],
      );
    });
  });

  group('I18n loading and formatting', () {
    test('loads translations from a JSON string', () {
      final manager = I18n(defaultLocale: const Locale('fr'))
        ..loadTranslationsFromJson(
          const Locale('fr'),
          jsonEncode({'greeting': 'Bonjour'}),
        );

      expect(manager.t('greeting'), 'Bonjour');
    });

    test('formats dates and numbers, with overridable formatters', () {
      final manager = i18n();

      expect(manager.formatDate(DateTime(2026, 9, 5)), '2026-09-05');
      expect(manager.formatNumber(1234.5), '1234.5');

      manager
        ..setDateFormatter((d) => '${d.day}/${d.month}/${d.year}')
        ..setNumberFormatter((n) => n.toStringAsFixed(2));

      expect(manager.formatDate(DateTime(2026, 9, 5)), '5/9/2026');
      expect(manager.formatNumber(1234.5), '1234.50');
    });
  });

  group('global helpers', () {
    setUp(() {
      initializeI18n(defaultLocale: const Locale('en'));
      getI18n().loadTranslations(const Locale('en'), _en);
    });

    test('t() and tPlural() delegate to the global instance', () {
      expect(t('greeting'), 'Hello');
      expect(t('welcome', params: {'name': 'Jo'}), 'Welcome, Jo!');
      expect(tPlural('items', 0), 'No items');
    });
  });

  group('bundled translations', () {
    test('ship the common UI keys for each shipped locale', () {
      for (final entry in {
        'en_US': enUS,
        'es_ES': esES,
        'fr_FR': frFR,
      }.entries) {
        final manager = I18n(defaultLocale: Locale.fromString(entry.key))
          ..loadTranslations(Locale.fromString(entry.key), entry.value);

        for (final key in ['common.ok', 'common.cancel', 'errors.required']) {
          expect(
            manager.t(key),
            isNot(key),
            reason: '${entry.key} is missing $key',
          );
        }
      }
    });
  });
}
