/// `TimeOfDay.format`, writing a time as the app's locale does - which is to
/// say as Flutter does for that locale, since the conventions are Flutter's.
library;

import 'package:dart_not_native/src/time_formats.dart';
import 'package:dart_not_native/testing.dart';
import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// [time] as an app in [locale] writes it.
String written(
  TimeOfDay time,
  Locale locale, {
  bool alwaysUse24HourFormat = false,
}) {
  late String text;
  AppTester.widget(
    MaterialApp(
      locale: locale,
      supportedLocales: [locale],
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(alwaysUse24HourFormat: alwaysUse24HourFormat),
          child: Builder(
            builder: (context) {
              text = time.format(context);
              return const Scaffold(body: SizedBox.shrink());
            },
          ),
        ),
      ),
    ),
  ).app.unmount();
  return text;
}

void main() {
  const afternoon = TimeOfDay(hour: 15, minute: 5);
  const morning = TimeOfDay(hour: 9, minute: 30);
  const midnight = TimeOfDay(hour: 0, minute: 0);
  const noon = TimeOfDay(hour: 12, minute: 0);

  group('each way a locale writes a time', () {
    test('h:mm a - American English', () {
      expect(written(afternoon, const Locale('en', 'US')), '3:05 PM');
      expect(written(morning, const Locale('en')), '9:30 AM');
    });

    test('HH:mm - German, and British English', () {
      expect(written(afternoon, const Locale('de')), '15:05');
      expect(written(morning, const Locale('de')), '09:30');
      expect(written(afternoon, const Locale('en', 'GB')), '15:05');
    });

    test('H:mm - Spanish, with no zero before a single hour', () {
      expect(written(morning, const Locale('es')), '9:30');
      expect(written(afternoon, const Locale('es')), '15:05');
    });

    test('HH.mm - Finnish', () {
      expect(written(afternoon, const Locale('fi')), '15.05');
      expect(written(morning, const Locale('fi')), '09.30');
    });

    test('a h:mm - Chinese and Korean, the half of the day first', () {
      expect(written(afternoon, const Locale('zh')), '下午 3:05');
      expect(written(morning, const Locale('ko')), '오전 9:30');
    });

    test("HH 'h' mm - Canadian French", () {
      expect(written(afternoon, const Locale('fr', 'CA')), '15 h 05');
      expect(written(afternoon, const Locale('fr')), '15:05');
    });
  });

  test('the halves of the day are in the language', () {
    expect(written(afternoon, const Locale('ar')), '3:05 م');
    expect(written(morning, const Locale('ar')), '9:30 ص');
    expect(written(afternoon, const Locale('es', 'US')), '3:05 p.m.');
  });

  test('midnight and noon are twelve on a twelve-hour clock', () {
    expect(written(midnight, const Locale('en')), '12:00 AM');
    expect(written(noon, const Locale('en')), '12:00 PM');
    expect(written(midnight, const Locale('de')), '00:00');
    expect(written(midnight, const Locale('es')), '0:00');
  });

  group('a region', () {
    test('that writes what its language does falls back to it', () {
      expect(timeOfDayFormats.containsKey('en_CA'), isFalse);
      expect(written(afternoon, const Locale('en', 'CA')), '3:05 PM');
      expect(written(afternoon, const Locale('de', 'AT')), '15:05');
    });

    test('with a script is found with it and without it', () {
      const withScript = Locale.fromSubtags(
        languageCode: 'zh',
        scriptCode: 'Hant',
        countryCode: 'TW',
      );
      expect(written(afternoon, withScript), '下午 3:05');
      expect(written(afternoon, const Locale('zh', 'TW')), '下午 3:05');
    });
  });

  test('a language Flutter has no localization for gets HH:mm', () {
    expect(timeOfDayFormats.containsKey('tlh'), isFalse);
    expect(written(afternoon, const Locale('tlh')), '15:05');
  });

  group('alwaysUse24HourFormat', () {
    test('turns a twelve-hour locale to HH:mm', () {
      expect(
        written(
          afternoon,
          const Locale('en'),
          alwaysUse24HourFormat: true,
        ),
        '15:05',
      );
      expect(
        written(morning, const Locale('zh'), alwaysUse24HourFormat: true),
        '09:30',
      );
    });

    test('leaves a locale that already writes twenty-four hours as it is', () {
      expect(
        written(morning, const Locale('es'), alwaysUse24HourFormat: true),
        '9:30',
      );
      expect(
        written(afternoon, const Locale('fi'), alwaysUse24HourFormat: true),
        '15.05',
      );
    });

    test('is false unless a MediaQuery says so, and is part of what it is',
        () {
      const data = MediaQueryData();
      expect(data.alwaysUse24HourFormat, isFalse);
      expect(data.copyWith(alwaysUse24HourFormat: true), isNot(data));
    });
  });

  test('every pattern in the table is one format knows how to write', () {
    expect(
      {for (final entry in timeOfDayFormats.values) entry.$1},
      {'H:mm', 'HH:mm', 'HH.mm', 'h:mm a', 'a h:mm', "HH 'h' mm"},
    );
    expect(timeOfDayFormats.length, greaterThan(100));
  });
}
