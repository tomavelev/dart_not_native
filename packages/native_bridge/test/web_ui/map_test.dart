@TestOn('browser')
/// The web map: tiles from arithmetic, markers where they belong, and an
/// attribution the tiles are given in exchange for.
library;

import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/web_ui/web_renderer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

import 'support/dom.dart';

void main() {
  late web.HTMLElement root;
  late WebUIRenderer renderer;

  setUp(() {
    root = mountRoot();
    renderer = WebUIRenderer(root: root, animations: false);
  });
  tearDown(() => root.remove());

  web.Element map() => root.querySelector('.dnn-map')!;
  List<web.Element> tiles() {
    final found = map().querySelectorAll('.dnn-map__tile');
    return [for (var i = 0; i < found.length; i++) found.item(i)! as web.Element];
  }

  Future<void> show({
    double latitude = 51.5007,
    double longitude = -0.1246,
    double zoom = 13,
    List<({double latitude, double longitude, String? label})> markers =
        const [],
    String? tileUrl,
  }) =>
      renderer.render(UIBuilder.map(
        latitude: latitude,
        longitude: longitude,
        zoom: zoom,
        markers: markers,
        tileUrl: tileUrl,
      ));

  test('lays out tiles around the centre it was given', () async {
    await show();

    expect(tiles(), isNotEmpty);
    // Every tile is a real image the browser fetches and caches - no canvas,
    // no library.
    expect(tiles().every((t) => t.tagName.toLowerCase() == 'img'), isTrue);
  });

  test('the tile the centre falls in is the one Mercator says', () async {
    // Big Ben at zoom 13 is x=4093, y=2723 in the standard tile scheme - the
    // same numbers any slippy map would ask for.
    await show(latitude: 51.5007, longitude: -0.1246, zoom: 13);

    final sources = tiles().map((t) => t.getAttribute('src')).toList();
    expect(sources, contains(contains('/13/4093/2723.png')));
  });

  test('a different tile source is used when one is given', () async {
    await show(tileUrl: 'https://tiles.example.com/{z}/{x}/{y}.png');

    expect(
      tiles().first.getAttribute('src'),
      startsWith('https://tiles.example.com/13/'),
    );
  });

  test('markers land on the map, with their labels', () async {
    await show(markers: [
      (latitude: 51.5007, longitude: -0.1246, label: 'Big Ben'),
    ]);

    final marker = map().querySelector('.dnn-map__marker');
    expect(marker, isNotNull);
    expect(marker!.getAttribute('title'), 'Big Ben');
  });

  test('the tiles are attributed, which is what they cost', () async {
    await show();

    expect(
      map().querySelector('.dnn-map__attribution')?.textContent,
      contains('OpenStreetMap'),
    );
  });

  test('a re-render keeps the map element, so tiles are not refetched',
      () async {
    await show();
    final before = map();

    await show(zoom: 14);

    expect(map(), same(before));
  });
}
