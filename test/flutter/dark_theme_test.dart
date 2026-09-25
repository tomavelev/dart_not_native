/// Dark mode on the Flutter-hosted target.
///
/// The palette in force is the theme's own colours or its [AppTheme.dark]
/// counterpart, chosen by the theme's mode and - for `system` - by what the
/// device reports. What is pinned here is that the choice reaches the painted
/// widgets, since a renderer that resolved the palette and then painted a
/// hardcoded grey would look right in exactly one appearance.
library;

import 'package:dart_not_native/material.dart' show NativeUIAppHost;
import 'package:dart_not_native/widgets.dart';
import 'package:flutter/material.dart' as flutter;
import 'package:flutter_test/flutter_test.dart';

class _Screen extends StatelessWidget {
  const _Screen();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: const AppBar(title: Text('Settings')),
    body: Column(
      children: [
        const Text('Body copy'),
        const Card(child: Text('In a card')),
        const Alert.success(message: 'Saved'),
        const Alert.warning(message: 'Careful'),
        const Alert.info(message: 'By the way'),
        // Enabled, since a disabled control is greyed and would not show the
        // tint this is about.
        Checkbox(value: true, onChanged: (_) {}, label: 'Subscribe'),
        Radio<String>(
          value: 'free',
          groupValue: 'free',
          onChanged: (_) {},
          label: 'Free',
        ),
        Switch(value: true, onChanged: (_) {}, label: 'Dark mode'),
      ],
    ),
  );
}

void main() {
  Future<void> pump(WidgetTester tester, AppTheme theme) async {
    await tester.pumpWidget(
      flutter.MaterialApp(
        home: NativeUIAppHost(app: hostApp(const _Screen()), theme: theme),
      ),
    );
    await tester.pump();
  }

  flutter.Color textColour(WidgetTester tester, String data) =>
      tester.widget<flutter.Text>(find.text(data)).style!.color!;

  flutter.Color cardColour(WidgetTester tester) =>
      tester.widget<flutter.Card>(find.byType(flutter.Card)).color!;

  testWidgets('the default theme paints the light palette', (tester) async {
    await pump(tester, AppTheme.fallback);

    expect(textColour(tester, 'Body copy'), const flutter.Color(0xff212121));
    expect(cardColour(tester), const flutter.Color(0xfff5f5f5));
  });

  testWidgets('mode dark paints the dark palette without one being given', (
    tester,
  ) async {
    await pump(tester, const AppTheme(mode: AppThemeMode.dark));

    // The built-in dark palette: light text, a card raised off a dark surface.
    expect(textColour(tester, 'Body copy'), const flutter.Color(0xffececec));
    expect(cardColour(tester), const flutter.Color(0xff1e1e1e));
  });

  testWidgets('an app can supply its own dark palette', (tester) async {
    await pump(
      tester,
      const AppTheme(
        mode: AppThemeMode.dark,
        dark: AppTheme(text: '#00ff00', surfaceVariant: '#003300'),
      ),
    );

    expect(textColour(tester, 'Body copy'), const flutter.Color(0xff00ff00));
    expect(cardColour(tester), const flutter.Color(0xff003300));
  });

  group('mode system', () {
    testWidgets('follows the device into dark', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue =
          flutter.Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

      await pump(tester, const AppTheme(mode: AppThemeMode.system));

      expect(textColour(tester, 'Body copy'), const flutter.Color(0xffececec));
    });

    testWidgets('and stays light on a light device', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue =
          flutter.Brightness.light;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

      await pump(tester, const AppTheme(mode: AppThemeMode.system));

      expect(textColour(tester, 'Body copy'), const flutter.Color(0xff212121));
    });

    testWidgets('and repaints when the device changes its mind', (
      tester,
    ) async {
      tester.platformDispatcher.platformBrightnessTestValue =
          flutter.Brightness.light;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await pump(tester, const AppTheme(mode: AppThemeMode.system));
      expect(textColour(tester, 'Body copy'), const flutter.Color(0xff212121));

      tester.platformDispatcher.platformBrightnessTestValue =
          flutter.Brightness.dark;
      await tester.pumpAndSettle();

      expect(textColour(tester, 'Body copy'), const flutter.Color(0xffececec));
    });
  });

  group('the semantic colours', () {
    /// An alert paints its type's colour on the bar down its left edge.
    flutter.Color alertColour(WidgetTester tester, String message) {
      final container = tester.widget<flutter.Container>(
        find
            .ancestor(
              of: find.text(message),
              matching: find.byType(flutter.Container),
            )
            .first,
      );
      final decoration = container.decoration! as flutter.BoxDecoration;
      return (decoration.border! as flutter.Border).left.color;
    }

    testWidgets('are the light ones by default', (tester) async {
      await pump(tester, AppTheme.fallback);

      expect(alertColour(tester, 'Saved'), const flutter.Color(0xff388e3c));
      expect(alertColour(tester, 'Careful'), const flutter.Color(0xfffbc02d));
      expect(alertColour(tester, 'By the way'), const flutter.Color(0xff0288d1));
    });

    testWidgets('lighten in dark, where the deep ones go muddy', (tester) async {
      await pump(tester, const AppTheme(mode: AppThemeMode.dark));

      expect(alertColour(tester, 'Saved'), const flutter.Color(0xff66bb6a));
      expect(alertColour(tester, 'Careful'), const flutter.Color(0xffffca28));
      expect(alertColour(tester, 'By the way'), const flutter.Color(0xff4fc3f7));
    });

    testWidgets('an app can set its own, per appearance', (tester) async {
      await pump(
        tester,
        const AppTheme(
          success: '#004400',
          mode: AppThemeMode.system,
          dark: AppTheme(success: '#88ff88'),
        ),
      );
      expect(alertColour(tester, 'Saved'), const flutter.Color(0xff004400));

      tester.platformDispatcher.platformBrightnessTestValue =
          flutter.Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await tester.pumpAndSettle();

      expect(alertColour(tester, 'Saved'), const flutter.Color(0xff88ff88));
    });
  });

  group('the checkable controls', () {
    // A bare Checkbox or Switch draws itself in the platform's own accent -
    // UIKit's blue, Material's purple - which belongs to neither the app nor
    // its theme. All four renderers tint theirs from the palette instead.
    testWidgets('take the theme primary, not the platform accent', (
      tester,
    ) async {
      await pump(tester, const AppTheme(primary: '#00897b'));

      expect(
        tester.widget<flutter.Checkbox>(find.byType(flutter.Checkbox)).activeColor,
        const flutter.Color(0xff00897b),
      );
      expect(
        tester.widget<flutter.Switch>(find.byType(flutter.Switch)).activeThumbColor,
        const flutter.Color(0xff00897b),
      );
      expect(
        tester.widget<flutter.Icon>(find.byIcon(flutter.Icons.radio_button_checked)).color,
        const flutter.Color(0xff00897b),
      );
    });

    testWidgets('and follow the palette into dark', (tester) async {
      await pump(tester, const AppTheme(mode: AppThemeMode.dark));

      // The dark palette's lightened primary, not the light one.
      expect(
        tester.widget<flutter.Checkbox>(find.byType(flutter.Checkbox)).activeColor,
        const flutter.Color(0xff90caf9),
      );
      expect(
        tester.widget<flutter.Switch>(find.byType(flutter.Switch)).activeThumbColor,
        const flutter.Color(0xff90caf9),
      );
    });
  });

  testWidgets('mode light ignores a dark device', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue =
        flutter.Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await pump(tester, AppTheme.fallback);

    expect(textColour(tester, 'Body copy'), const flutter.Color(0xff212121));
  });
}
