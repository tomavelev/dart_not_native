/// The app theme reaches the Flutter renderer: a primary button with no
/// explicit colour paints in the theme's primary.
library;

import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/platforms/flutter_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _ButtonApp extends NativeUIApp {
  @override
  void init() {}

  @override
  WidgetNode build() => UIBuilder.button(label: 'Go', eventId: 'go');
}

Color? _buttonBackground(WidgetTester tester) {
  final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
  return button.style?.backgroundColor?.resolve(<WidgetState>{});
}

void main() {
  testWidgets('a primary button paints in the theme primary', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NativeUIAppHost(
          app: _ButtonApp(),
          theme: const AppTheme(primary: '#e91e63'),
        ),
      ),
    );
    await tester.pump();

    expect(_buttonBackground(tester), const Color(0xffe91e63));
  });

  testWidgets('without a theme it stays Material blue', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: NativeUIAppHost(app: _ButtonApp())),
    );
    await tester.pump();

    expect(_buttonBackground(tester), const Color(0xff1976d2));
  });

  testWidgets('a badge with no colour follows the theme primary',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NativeUIAppHost(
          app: _BadgeApp(),
          theme: const AppTheme(primary: '#e91e63'),
        ),
      ),
    );
    await tester.pump();

    final container = tester.widget<Container>(
      find
          .ancestor(of: find.text('New'), matching: find.byType(Container))
          .first,
    );
    expect((container.decoration as BoxDecoration).color,
        const Color(0xffe91e63));
  });

  testWidgets('secondary and error button variants use the theme palette',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NativeUIAppHost(
          app: _VariantButtonsApp(),
          theme: const AppTheme(secondary: '#00bcd4', error: '#b00020'),
        ),
      ),
    );
    await tester.pump();

    // Secondary renders as an outlined button (its colour is the foreground);
    // error as an elevated button (its colour is the background).
    final secondary = tester.widget<OutlinedButton>(
      find.ancestor(of: find.text('Second'), matching: find.byType(OutlinedButton)),
    );
    expect(secondary.style?.foregroundColor?.resolve(<WidgetState>{}),
        const Color(0xff00bcd4));

    final error = tester.widget<ElevatedButton>(
      find.ancestor(of: find.text('Wrong'), matching: find.byType(ElevatedButton)),
    );
    expect(error.style?.backgroundColor?.resolve(<WidgetState>{}),
        const Color(0xffb00020));
  });
}

class _BadgeApp extends NativeUIApp {
  @override
  void init() {}

  @override
  WidgetNode build() => DSBadge.solid(label: 'New');
}

class _VariantButtonsApp extends NativeUIApp {
  @override
  void init() {}

  @override
  WidgetNode build() => UIBuilder.column(children: [
        UIBuilder.button(label: 'Second', eventId: 's', variant: 'secondary'),
        UIBuilder.button(label: 'Wrong', eventId: 'e', variant: 'error'),
      ]);
}

