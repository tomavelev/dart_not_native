/// Tests for the i18n example: switching language re-renders every string.
library;

import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/widgets.dart' show hostApp;
import 'package:dart_not_native_example/examples/apps/i18n_example_app.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dart_not_native/testing.dart';

void main() {
  late AppTester tester;

  setUp(() =>
      tester = AppTester.mount(hostApp(I18nExampleApp(setUpDemoI18n()))));

  test('starts in English', () {
    expect(tester.text('current_locale'), 'Language: en');
    expect(tester.text('value_ok'), 'OK');
    expect(tester.text('value_cancel'), 'Cancel');
  });

  test('offers every bundled language', () {
    for (final (code, label) in i18nLanguages) {
      expect(tester.get('lang_$code').props['label'], label);
    }
  });

  test('tapping a language re-renders the screen in it', () async {
    await tester.tap('lang_es');

    expect(tester.text('current_locale'), 'Language: es');
    expect(tester.text('value_ok'), 'Aceptar');
    expect(tester.text('value_email'), 'Correo electrónico');
  });

  test('the active language is highlighted', () async {
    expect(tester.get('lang_en').props['variant'], 'primary');
    expect(tester.get('lang_fr').props['variant'], 'tertiary');

    await tester.tap('lang_fr');

    expect(tester.get('lang_fr').props['variant'], 'primary');
    expect(tester.get('lang_en').props['variant'], 'tertiary');
  });

  test('switching back restores the first language', () async {
    await tester.tap('lang_ja');
    expect(tester.text('current_locale'), 'Language: ja');

    await tester.tap('lang_en');

    expect(tester.text('value_ok'), 'OK');
  });

  test('plural forms follow the count', () {
    expect(tester.text('value_items_0'), isNot(tester.text('value_items_1')));
    expect(tester.text('value_items_1'), contains('1'));
    expect(tester.text('value_items_3'), contains('3'));
  });

  test('a missing key falls back to the supplied default', () {
    expect(tester.text('value_fallback'), 'Custom default');
  });

  test('every language renders without leaking raw keys', () async {
    for (final (code, _) in i18nLanguages) {
      await tester.tap('lang_$code');

      for (final id in [
        'value_ok',
        'value_cancel',
        'value_email',
        'value_required',
        'value_just_now',
      ]) {
        final value = tester.text(id);
        expect(value, isNotEmpty, reason: '$id is empty in $code');
        expect(
          value,
          isNot(contains('.')),
          reason: '$id fell through to the raw key in $code',
        );
      }
    }
  });

  test(
    'the app re-renders from the I18n listener, not only from taps',
    () async {
      final i18n = getI18n();

      await i18n.setLocale(const Locale('de'));

      expect(tester.text('current_locale'), 'Language: de');
    },
  );
}
