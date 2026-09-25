/// The native renderers, on the device, drawing the whole protocol.
///
/// Everything else about the Kotlin and Swift renderers is checked by reading
/// their source (`renderer_coverage_test.dart` matches their dispatch against
/// [nodeTypes]) or by compiling them. Neither notices a renderer that compiles,
/// dispatches on every type, and then throws when it is handed one - which is
/// exactly what a wrong `LayoutParams` or an un-themed context does.
///
/// A native render answers with what it could not draw, so this asks for one of
/// everything and expects silence.
///
///   flutter test integration_test/native_renderer_test.dart -d <android|ios>
library;

import 'dart:io';

import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/platforms/android_renderer.dart';
import 'package:dart_not_native/platforms/ios_renderer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/example_apps.dart';

/// One of every node type the protocol defines, in a place it belongs.
///
/// Two trees rather than one: `NavigationStack` is a screen's root on iOS, not
/// something to nest inside a Column, and the natives are entitled to expect
/// that.
class _EveryNodeApp extends NativeUIApp {
  _EveryNodeApp(this.tree);

  final WidgetNode Function() tree;

  @override
  WidgetNode build() => tree();
}

WidgetNode _screenTree() => UIBuilder.overlay(
      child: UIBuilder.scaffold(
        appBar: UIBuilder.appBar(title: 'Every node'),
        body: UIBuilder.column(
          crossAxisAlignment: 'stretch',
          children: [
            UIBuilder.padding(
              all: 8,
              child: UIBuilder.row(
                spacing: 8,
                children: [
                  UIBuilder.expanded(child: UIBuilder.text('Row text')),
                  UIBuilder.iconButton(
                    icon: 'add',
                    eventId: 'icon',
                    tooltip: 'Add',
                  ),
                  iOSUIBuilder.spacer(),
                ],
              ),
            ),
            UIBuilder.center(child: DSText.h2('Heading')),
            // Padding that differs per edge: one number would not say which
            // edges the app meant.
            UIBuilder.padding(
              left: 32,
              top: 4,
              right: 0,
              bottom: 16,
              child: UIBuilder.text('Unevenly padded'),
            ),
            UIBuilder.wrap(
              spacing: 4,
              children: [
                DSBadge.solid(label: 'Badge'),
                DSBadge.dot(),
                DSLoading.spinner(),
                DSLoading.progressLinear(value: 0.4),
              ],
            ),
            DSDivider.horizontal(),
            DSAlert.info(message: 'Alert', title: 'Info', dismissible: true),
            DSCard.elevated(
              title: 'Card',
              content: UIBuilder.text('Card body'),
            ),
            UIBuilder.image(
              src: 'https://example.invalid/image.png',
              alt: 'An image',
              width: 48,
              height: 48,
            ),
            UIBuilder.button(label: 'Button', eventId: 'button'),
            AndroidUIBuilder.materialButton(
              label: 'Material',
              eventId: 'material',
            ),
            UIBuilder.textField(
              hint: 'Hint',
              eventId: 'field',
              label: 'Label',
            ),
            DSCheckbox.input(eventId: 'check', checked: true, label: 'Check'),
            DSRadio.input(eventId: 'radio', value: 'a', label: 'Radio'),
            DSToggle.input(eventId: 'toggle', enabled: true, label: 'Toggle'),
            UIBuilder.slider(
              eventId: 'slider',
              value: 3,
              min: 0,
              max: 10,
              divisions: 10,
            ),
            AndroidUIBuilder.listView(
              children: [
                AndroidUIBuilder.listItem(text: 'Item', subtitle: 'Subtitle'),
              ],
            ),
            UIBuilder.animatedOpacity(
              opacity: 0.5,
              child: UIBuilder.text('Half faded'),
            ),
            UIBuilder.animatedContainer(
              width: 160,
              height: 48,
              color: '#2196f3',
              child: UIBuilder.text('Animated box'),
            ),
            UIBuilder.tabs(
              eventId: 'tabs',
              tabs: const ['One', 'Two', 'Three'],
              selectedIndex: 1,
            ),
            UIBuilder.grid(
              crossAxisCount: 3,
              spacing: 4,
              runSpacing: 4,
              childAspectRatio: 1.5,
              children: [
                for (var i = 0; i < 5; i++)
                  DSCard.filled(content: UIBuilder.text('Cell $i')),
              ],
            ),
            UIBuilder.swipeActions(
              child: AndroidUIBuilder.listItem(text: 'Swipe me'),
              actions: [
                (label: 'Delete', color: '#f44336', onPressed: () {}),
              ],
            ),
            UIBuilder.lazyList(
              id: 'lazy',
              itemCount: 200,
              itemExtent: 48,
              itemBuilder: (index) =>
                  AndroidUIBuilder.listItem(text: 'Row $index'),
            ),
            // A list whose rows are not all the same height, which is a
            // different placement path in both natives.
            UIBuilder.lazyList(
              id: 'varied',
              itemCount: 50,
              itemExtentBuilder: (index) => index % 5 == 0 ? 72 : 40,
              itemBuilder: (index) =>
                  AndroidUIBuilder.listItem(text: 'Varied $index'),
            ),
            UIBuilder.webView(url: 'about:blank', height: 80),
            // No CameraPreview here on purpose: it would put a permission
            // dialog in front of an automated run, and a lane that needs
            // someone to tap Allow is not a lane. Its paths are checked in
            // camera_test.dart and by hand on a device.
            UIBuilder.map(
              latitude: 51.5007,
              longitude: -0.1246,
              zoom: 13,
              height: 120,
              markers: const [
                (latitude: 51.5007, longitude: -0.1246, label: 'Big Ben'),
              ],
            ),
            UIBuilder.sizedBox(height: 8),
          ],
        ),
        floatingActionButton:
            UIBuilder.floatingActionButton(tooltip: 'Add', eventId: 'fab'),
      ),
      overlays: [
        UIBuilder.dialog(
          title: 'Dialog',
          content: [UIBuilder.text('Body')],
          actions: [UIBuilder.button(label: 'OK', eventId: 'ok')],
          dismissEventId: 'dialog_dismiss',
        ),
        UIBuilder.bottomSheet(
          title: 'Sheet',
          content: [UIBuilder.text('Sheet body')],
          dismissEventId: 'sheet_dismiss',
        ),
        UIBuilder.snackbar(message: 'Snackbar', id: 'snack'),
      ],
    );

/// The iOS-flavoured half of the vocabulary, in its own screen.
WidgetNode _navigationTree() => iOSUIBuilder.navigationStack(
      content: iOSUIBuilder.vStack(
        spacing: 8,
        children: [
          iOSUIBuilder.navigationBar(title: 'Navigation'),
          iOSUIBuilder.hStack(
            children: [
              UIBuilder.text('Left'),
              iOSUIBuilder.spacer(),
              UIBuilder.text('Right'),
            ],
          ),
          iOSUIBuilder.list(
            children: [
              iOSUIBuilder.listRow(text: 'Row', subtitle: 'Subtitle'),
            ],
          ),
          iOSUIBuilder.button(label: 'Button', eventId: 'ios_button'),
        ],
      ),
    );

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final native = Platform.isAndroid || Platform.isIOS;
  late NativeUIRenderer renderer;
  Future<bool> available(NativeUIRenderer platform) async =>
      platform is AndroidNativeRenderer
          ? platform.isAvailable()
          : (platform as iOSNativeRenderer).isAvailable();

  /// Mounts [app], gives the platform a moment to answer, and returns what it
  /// said it could not draw.
  Future<List<RenderError>> drawErrors(NativeUIApp app) async {
    final errors = <RenderError>[];
    final subscription = app.renderErrors.listen(errors.add);
    app.mount(renderer);
    // The render crosses a platform channel; the answer comes back after it.
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await subscription.cancel();
    app.unmount();
    return errors;
  }

  String describe(List<RenderError> errors) =>
      errors.map((e) => '${e.kind.name}: ${e.message}').join('\n');

  setUpAll(() async {
    if (!native) return;
    final NativeUIRenderer platform = Platform.isAndroid
        ? AndroidNativeRenderer()
        : iOSNativeRenderer();
    // Not a skip: on a phone the plugin is expected to be there, and its
    // absence is the failure this lane exists to catch.
    expect(
      await available(platform),
      isTrue,
      reason: 'the native renderer plugin did not register',
    );
    renderer = platform;
  });

  testWidgets('draws one of every node type', (tester) async {
    final errors = await drawErrors(_EveryNodeApp(_screenTree));

    expect(errors, isEmpty, reason: describe(errors));
  }, skip: !native);

  testWidgets('draws the navigation vocabulary too', (tester) async {
    final errors = await drawErrors(_EveryNodeApp(_navigationTree));

    expect(errors, isEmpty, reason: describe(errors));
  }, skip: !native);

  group('every example app', () {
    for (final entry in exampleApps.entries) {
      testWidgets('${entry.key} draws natively', (tester) async {
        final errors = await drawErrors(entry.value());

        expect(errors, isEmpty, reason: describe(errors));
      }, skip: !native);
    }
  });
}
