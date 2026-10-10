/// A value dragged along a track, through the widget layer.
library;

import 'package:dart_not_native/core.dart' show WidgetNode;
import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dart_not_native/testing.dart';

class _VolumeScreen extends StatefulWidget {
  const _VolumeScreen();

  @override
  State<_VolumeScreen> createState() => _VolumeScreenState();
}

class _VolumeScreenState extends State<_VolumeScreen> {
  double volume = 0.5;
  double saved = 0.5;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Column(
          children: [
            Slider(
              key: const ValueKey('volume'),
              value: volume,
              divisions: 10,
              onChanged: (value) => setState(() => volume = value),
              onChangeEnd: (value) => setState(() => saved = value),
            ),
            Text('${volume.toStringAsFixed(2)}',
                key: const ValueKey('live')),
            Text('${saved.toStringAsFixed(2)}', key: const ValueKey('saved')),
            const Slider(
              key: ValueKey('locked'),
              value: 0.25,
              onChanged: null,
            ),
          ],
        ),
      );
}

void main() {
  late AppTester tester;

  setUp(() => tester = AppTester.mount(hostApp(const _VolumeScreen())));

  WidgetNode slider(String id) => tester.get(id);

  test('carries where the thumb is and what it may say', () {
    final props = slider('volume').props;

    expect(props['value'], 0.5);
    expect(props['min'], 0.0);
    expect(props['max'], 1.0);
    expect(props['divisions'], 10);
    expect(props['disabled'], isFalse);
  });

  test('dragging reports as it moves, without waiting for the release', () async {
    await tester.emit('${tester.eventIdOf('volume')}_change', {'value': 0.8});

    expect(tester.text('live'), '0.80');
    // Not saved yet: the thumb is still moving.
    expect(tester.text('saved'), '0.50');
    expect(slider('volume').props['value'], 0.8);
  });

  test('letting go is the decision', () async {
    await tester.emit('${tester.eventIdOf('volume')}_end', {'value': 0.3});

    expect(tester.text('saved'), '0.30');
  });

  test('no onChanged is a disabled slider, as in Flutter', () {
    expect(slider('locked').props['disabled'], isTrue);
  });
}
