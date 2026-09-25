/// A camera preview, through the widget layer.
library;

import 'package:dart_not_native/core.dart' show WidgetNode;
import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/app_tester.dart';

class _Scanner extends StatefulWidget {
  const _Scanner();

  @override
  State<_Scanner> createState() => _ScannerState();
}

class _ScannerState extends State<_Scanner> {
  bool live = true;
  String status = 'starting';

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Column(
          children: [
            CameraPreview(
              key: const ValueKey('camera'),
              height: 240,
              facing: CameraFacing.front,
              active: live,
              onStatus: (state, message) => setState(() => status = state),
            ),
            Text(status, key: const ValueKey('status')),
            ElevatedButton(
              key: const ValueKey('toggle'),
              onPressed: () => setState(() => live = !live),
              child: const Text('Toggle'),
            ),
          ],
        ),
      );
}

void main() {
  late AppTester tester;

  setUp(() => tester = AppTester.mount(hostApp(const _Scanner())));

  WidgetNode camera() => tester.get('camera');

  test('carries which camera, how tall, and whether it is running', () {
    expect(camera().props['facing'], 'front');
    expect(camera().props['height'], 240.0);
    expect(camera().props['active'], isTrue);
  });

  test('the app hears what happened, without hearing frames', () async {
    await tester.emit('${tester.eventIdOf('camera')}_status', {
      'status': 'denied',
      'message': 'The camera permission was refused.',
    });

    expect(tester.text('status'), 'denied');
  });

  test('a screen can stop the camera without losing its place', () async {
    await tester.tap('toggle');

    // Still in the tree - the renderers stop the stream and keep the view, so
    // turning it back on does not ask for the permission again.
    expect(camera().props['active'], isFalse);
    expect(tester.find('camera'), isNotNull);
  });
}
