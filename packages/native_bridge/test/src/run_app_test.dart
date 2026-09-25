/// Tests for the one-call bootstrap.
library;

import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/platforms/system_back_channel.dart';
import 'package:dart_not_native/run_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _rendererChannel = MethodChannel(
  'com.programtom.dart_not_native/renderer',
);

class _CounterApp extends NativeUIApp {
  int count = 0;

  @override
  WidgetNode build() => UIBuilder.scaffold(
    appBar: UIBuilder.appBar(title: 'Counter'),
    body: UIBuilder.column(
      children: [
        UIBuilder.text('$count', id: 'count'),
        UIBuilder.button(
          label: 'Increment',
          onPressed: () => setState(() => count++),
        ),
      ],
    ),
  );
}

/// An app that routes, so the bootstrap can wire its back gesture.
class _RoutedApp extends NativeUIApp with NavigationHost {
  @override
  late final NavigationApp nav =
      (NavigationAppBuilder()
            ..setInitialPath('/')
            ..addRoute(
              path: '/',
              name: 'home',
              builder: (_) => UIBuilder.text('Home', id: 'screen'),
            )
            ..addRoute(
              path: '/next',
              name: 'next',
              builder: (_) => UIBuilder.text('Next', id: 'screen'),
            ))
          .build();

  @override
  WidgetNode build() => nav.router.buildCurrentRoute();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Answers the renderer channel, recording what it was asked.
  List<String> installRenderer({required bool available}) {
    final methods = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_rendererChannel, (call) async {
          methods.add(call.method);
          if (!available) throw MissingPluginException('no native renderer');
          return null;
        });
    return methods;
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_rendererChannel, null);
    SystemBackChannel.unbind();
    SystemBack.clearHandlers();
  });

  group('default (Flutter widgets)', () {
    testWidgets('mounts the app and paints it', (tester) async {
      await runNativeApp(_CounterApp(), systemBack: false);
      await tester.pumpAndSettle();

      expect(find.widgetWithText(AppBar, 'Counter'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);
    });

    testWidgets('the app is interactive', (tester) async {
      await runNativeApp(_CounterApp(), systemBack: false);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Increment'));
      await tester.pumpAndSettle();

      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('does not speak to the native renderer', (tester) async {
      final methods = installRenderer(available: true);

      await runNativeApp(_CounterApp(), systemBack: false);
      await tester.pumpAndSettle();

      expect(methods, isEmpty);
    });

    testWidgets('passes the title and theme through', (tester) async {
      await runNativeApp(
        _CounterApp(),
        systemBack: false,
        title: 'My App',
        theme: ThemeData(useMaterial3: false),
      );
      await tester.pumpAndSettle();

      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.title, 'My App');
      expect(app.theme?.useMaterial3, isFalse);
    });
  });

  group('native views', () {
    testWidgets('renders through the platform when it is available', (
      tester,
    ) async {
      final methods = installRenderer(available: true);

      await runNativeApp(_CounterApp(), nativeViews: true, systemBack: false);
      await tester.pumpAndSettle();

      expect(methods, ['initialize', 'render']);
      expect(
        find.text('0'),
        findsNothing,
        reason: 'the platform draws the app, not Flutter',
      );
    });

    testWidgets('falls back to Flutter when the platform cannot render', (
      tester,
    ) async {
      installRenderer(available: false);

      await runNativeApp(_CounterApp(), nativeViews: true, systemBack: false);
      await tester.pumpAndSettle();

      expect(find.widgetWithText(AppBar, 'Counter'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);
    });

    testWidgets('the fallback app is still interactive', (tester) async {
      installRenderer(available: false);

      await runNativeApp(_CounterApp(), nativeViews: true, systemBack: false);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Increment'));
      await tester.pumpAndSettle();

      expect(find.text('1'), findsOneWidget);
    });
  });

  group('system back', () {
    testWidgets('is wired by default', (tester) async {
      await runNativeApp(_CounterApp());
      await tester.pumpAndSettle();

      expect(SystemBackChannel.isBound, isTrue);
    });

    testWidgets('can be left alone', (tester) async {
      await runNativeApp(_CounterApp(), systemBack: false);
      await tester.pumpAndSettle();

      expect(SystemBackChannel.isBound, isFalse);
    });

    testWidgets('a routing app pops a route on the platform gesture', (
      tester,
    ) async {
      final app = _RoutedApp();
      await runNativeApp(app);
      await tester.pumpAndSettle();
      await app.nav.navigate('/next');
      await tester.pumpAndSettle();
      expect(find.text('Next'), findsOneWidget);

      expect(SystemBack.dispatch(), isTrue);
      await tester.pumpAndSettle();

      expect(find.text('Home'), findsOneWidget);
    });

    testWidgets('and declines once it is at its first screen', (tester) async {
      await runNativeApp(_RoutedApp());
      await tester.pumpAndSettle();

      expect(
        SystemBack.dispatch(),
        isFalse,
        reason: 'nothing to pop, so the platform closes the app',
      );
    });
  });
}
