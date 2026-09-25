/// The global translation table, before anyone has set it up.
///
/// A file of its own: the global is set once per isolate, and every other test
/// that touches it would hide what this one is checking.
library;

import 'package:dart_not_native/i18n/translations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('says so when nothing has been loaded', () {
    expect(isI18nInitialized, isFalse);

    // Rather than a LateInitializationError naming a private field, which
    // tells the reader nothing about translations.
    expect(
      () => getI18n(),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('initializeI18n'),
        ),
      ),
    );
  });

  test('and stops saying so once it is', () {
    initializeI18n(defaultLocale: const Locale('en'));

    expect(isI18nInitialized, isTrue);
    expect(getI18n().currentLocale, const Locale('en'));
  });
}
