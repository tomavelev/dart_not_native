/// `Tr` - a string from the translation table, drawn where it is needed.
///
/// What used to be the app's job: look the key up, and keep a listener so the
/// screen repaints when the locale changes. Both belong to the framework now,
/// and these tests are about exactly that split.
library;

import 'package:dart_not_native/core.dart' show SystemBack;
import 'package:dart_not_native/i18n/translations.dart';
import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/app_tester.dart';

const _en = {
  'common': {'ok': 'OK'},
  'greeting': 'Hello, {name}!',
  'items': {'zero': 'No items', 'one': '1 item', 'few': '{count} items'},
};

const _es = {
  'common': {'ok': 'Aceptar'},
  'greeting': '¡Hola, {name}!',
  'items': {'zero': 'Sin artículos', 'one': '1 artículo', 'few': '{count} artículos'},
};

I18n _table() {
  initializeI18n(defaultLocale: const Locale('en'));
  final i18n = getI18n()
    ..loadTranslations(const Locale('en'), _en)
    ..loadTranslations(const Locale('es'), _es);
  return i18n;
}

/// One screen, no `State`, no listener - which is the point.
class _Screen extends StatelessWidget {
  const _Screen({this.table});

  final I18n? table;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Tr('common.ok', i18n: table)),
        body: Column(
          children: [
            Tr('common.ok', key: const ValueKey('ok'), i18n: table),
            Tr('greeting',
                key: const ValueKey('greeting'),
                params: const {'name': 'Ada'},
                i18n: table),
            Tr('items', key: const ValueKey('none'), count: 0, i18n: table),
            Tr('items', key: const ValueKey('three'), count: 3, i18n: table),
            Tr('missing.key',
                key: const ValueKey('missing'),
                defaultValue: 'Fallback',
                i18n: table),
            Tr('no.default', key: const ValueKey('bare'), i18n: table),
            ElevatedButton(
              key: const ValueKey('button'),
              onPressed: () {},
              child: Tr('common.ok', i18n: table),
            ),
          ],
        ),
      );
}

/// A routed app, to watch the locale subscription come and go with the screen.
class _Routed extends StatelessWidget {
  const _Routed(this.table);

  final I18n table;

  @override
  Widget build(BuildContext context) => MaterialApp(
        initialRoute: '/',
        routes: {
          '/': (context, params) => Scaffold(
                body: ElevatedButton(
                  key: const ValueKey('to_translated'),
                  onPressed: () => Navigator.of(context).pushNamed('/other'),
                  child: const Text('Go'),
                ),
              ),
          '/other': (context, params) => Scaffold(
                body: Tr('common.ok', key: const ValueKey('ok'), i18n: table),
              ),
        },
      );
}

void main() {
  late I18n i18n;
  AppTester? tester;

  setUp(() {
    SystemBack.clearHandlers();
    i18n = _table();
  });

  tearDown(() {
    tester?.app.unmount();
    tester = null;
    SystemBack.clearHandlers();
  });

  AppTester mount(Widget widget) => tester = AppTester.mount(hostApp(widget));

  group('resolving', () {
    test('a key, including a nested one', () {
      final app = mount(_Screen(table: i18n));

      expect(app.text('ok'), 'OK');
    });

    test('a key with parameters', () {
      final app = mount(_Screen(table: i18n));

      expect(app.text('greeting'), 'Hello, Ada!');
    });

    test('a plural, by count', () {
      final app = mount(_Screen(table: i18n));

      expect(app.text('none'), 'No items');
      expect(app.text('three'), '3 items');
    });

    test('a missing key falls back to the default, then to the key', () {
      final app = mount(_Screen(table: i18n));

      expect(app.text('missing'), 'Fallback');
      // What I18n.t does: a missing string shows up on screen rather than
      // taking the app down.
      expect(app.text('bare'), 'no.default');
    });

    test('in a title and a label, which carry text rather than a subtree', () {
      final app = mount(_Screen(table: i18n));

      expect(app.ofType('AppBar').single.props['title'], 'OK');
      expect(app.get('button').props['label'], 'OK');
    });

    test('against the global table when given none', () {
      final app = mount(const _Screen());

      expect(app.text('ok'), 'OK');
    });
  });

  group('following the locale', () {
    test('a language change redraws every Tr, with no listener in the app', () {
      final app = mount(_Screen(table: i18n));
      expect(app.text('ok'), 'OK');

      i18n.setLocale(const Locale('es'));

      expect(app.text('ok'), 'Aceptar');
      expect(app.text('greeting'), '¡Hola, Ada!');
      expect(app.ofType('AppBar').single.props['title'], 'Aceptar');
      expect(app.get('button').props['label'], 'Aceptar');
    });

    test('a screen without a Tr does not hold the table', () async {
      final app = mount(_Routed(i18n));
      expect(i18n.hasListeners, isFalse);

      await app.tap('to_translated');
      expect(app.text('ok'), 'OK');
      expect(i18n.hasListeners, isTrue);

      expect(SystemBack.dispatch(), isTrue);
      expect(i18n.hasListeners, isFalse, reason: 'the screen reading it left');
    });

    test('unmounting the app lets the table go', () {
      final app = mount(_Screen(table: i18n));
      expect(i18n.hasListeners, isTrue);

      app.app.unmount();

      expect(i18n.hasListeners, isFalse);
    });
  });
}
