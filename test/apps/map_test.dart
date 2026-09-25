/// A map, through the widget layer.
library;

import 'package:dart_not_native/core.dart' show WidgetNode;
import 'package:dart_not_native/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/app_tester.dart';

class _Screen extends StatefulWidget {
  const _Screen();

  @override
  State<_Screen> createState() => _ScreenState();
}

class _ScreenState extends State<_Screen> {
  double latitude = 51.5007;
  double longitude = -0.1246;
  double zoom = 13;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Column(
          children: [
            MapView(
              key: const ValueKey('map'),
              latitude: latitude,
              longitude: longitude,
              zoom: zoom,
              markers: const [
                MapMarker(
                  latitude: 51.5007,
                  longitude: -0.1246,
                  label: 'Big Ben',
                ),
              ],
              onCameraIdle: (lat, lng, level) => setState(() {
                latitude = lat;
                longitude = lng;
                zoom = level;
              }),
            ),
            Text(
              '${latitude.toStringAsFixed(3)}, ${longitude.toStringAsFixed(3)}'
              ' @ ${zoom.toStringAsFixed(0)}',
              key: const ValueKey('where'),
            ),
          ],
        ),
      );
}

void main() {
  late AppTester tester;

  setUp(() => tester = AppTester.mount(hostApp(const _Screen())));

  WidgetNode map() => tester.get('map');

  test('carries where it is looking and what is pinned', () {
    expect(map().props['latitude'], 51.5007);
    expect(map().props['longitude'], -0.1246);
    expect(map().props['zoom'], 13.0);
    expect(map().props['interactive'], isTrue);
    expect((map().props['markers'] as List).single, {
      'latitude': 51.5007,
      'longitude': -0.1246,
      'label': 'Big Ben',
    });
  });

  test('a map that came to rest tells the app where, once', () async {
    await tester.emit('${tester.eventIdOf('map')}_idle', {
      'latitude': 48.8584,
      'longitude': 2.2945,
      'zoom': 15.0,
    });

    expect(tester.text('where'), '48.858, 2.295 @ 15');
    // And the tree follows the app, not the other way round.
    expect(map().props['latitude'], 48.8584);
  });

  test('a map with no callback still draws, and stays where it was put', () {
    final still = AppTester.mount(
      hostApp(
        const _StillMap(),
      ),
    );

    expect(still.get('still').props.containsKey('eventId'), isFalse);
    expect(still.get('still').props['interactive'], isFalse);
  });
}

class _StillMap extends StatelessWidget {
  const _StillMap();

  @override
  Widget build(BuildContext context) => Scaffold(
        body: const MapView(
          key: ValueKey('still'),
          latitude: 0,
          longitude: 0,
          interactive: false,
        ),
      );
}
