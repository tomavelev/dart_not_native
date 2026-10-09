@TestOn('browser')
/// The canvas: a list of commands replayed into a real `<canvas>`.
///
/// What matters is asserted on the pixels - a command that is accepted and
/// draws nothing is the bug worth catching - and on the element, which must
/// be the same one from frame to frame.
library;

import 'dart:js_interop';

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

  web.HTMLCanvasElement surface() =>
      root.querySelector('canvas')! as web.HTMLCanvasElement;
  double ratio() => web.window.devicePixelRatio.toDouble();

  /// The colour at a logical point, as `[r, g, b, a]`.
  List<int> pixel(num x, num y) {
    final context = surface().getContext('2d')! as web.CanvasRenderingContext2D;
    final data = context
        .getImageData((x * ratio()).round(), (y * ratio()).round(), 1, 1)
        .data
        .toDart;
    return [data[0], data[1], data[2], data[3]];
  }

  WidgetNode picture(
    List<List<Object?>> commands, {
    List<Map<String, dynamic>> paints = const [
      {'color': '#ff0000'},
      {'color': '#0000ff', 'style': 'stroke', 'strokeWidth': 4},
      {'color': '#8000ff00'},
    ],
    double? width = 100,
    double? height = 80,
  }) => UIBuilder.canvas(
    commands: commands,
    paints: paints,
    width: width,
    height: height,
  );

  test('the backing store is the logical size times the pixel ratio',
      () async {
    await renderer.render(picture(const []));

    expect(surface().width, (100 * ratio()).round());
    expect(surface().height, (80 * ratio()).round());
  });

  test('a filled rectangle is where it was put, and nowhere else', () async {
    await renderer.render(
      picture([
        ['rect', 10, 10, 30, 20, 0],
      ]),
    );

    expect(pixel(20, 20), [255, 0, 0, 255]);
    expect(pixel(60, 60), [0, 0, 0, 0]);
  });

  test('a new list of commands repaints the same canvas', () async {
    await renderer.render(
      picture([
        ['rect', 0, 0, 50, 80, 0],
      ]),
    );
    final before = surface();
    final frame = root.querySelector('[data-type="Canvas"]');
    expect(pixel(25, 40), [255, 0, 0, 255]);

    await renderer.render(
      picture([
        ['rect', 50, 0, 50, 80, 0],
      ]),
    );

    expect(surface(), same(before));
    expect(root.querySelector('[data-type="Canvas"]'), same(frame));
    // The frame before is gone, not drawn over.
    expect(pixel(25, 40), [0, 0, 0, 0]);
    expect(pixel(75, 40), [255, 0, 0, 255]);
  });

  test('a frame per tick makes no elements', () async {
    await renderer.render(picture(const []));
    renderer.debugCreateCount = 0;

    for (var i = 0; i < 20; i++) {
      await renderer.render(
        picture([
          ['circle', 10 + i, 40, 5, 0],
        ]),
      );
    }

    expect(renderer.debugCreateCount, 0);
  });

  test('a translucent paint is alpha first', () async {
    await renderer.render(
      picture([
        ['rect', 0, 0, 100, 80, 2],
      ]),
    );

    final colour = pixel(50, 40);
    expect(colour[1], 255);
    expect(colour[0], 0);
    expect(colour[3], closeTo(128, 2));
  });

  test('shapes: circle, oval, rounded rectangle, stroked line, arc', () async {
    await renderer.render(
      picture([
        ['circle', 20, 20, 10, 0],
        ['oval', 40, 10, 30, 20, 0],
        ['rrect', 0, 50, 40, 30, 10, 0],
        ['line', 50, 60, 100, 60, 1],
        ['arc', 70, 0, 30, 30, 0, 3.14159, true, 0],
      ]),
    );

    expect(pixel(20, 20), [255, 0, 0, 255], reason: 'circle');
    expect(pixel(55, 20), [255, 0, 0, 255], reason: 'oval');
    expect(pixel(41, 11), [0, 0, 0, 0], reason: 'outside the oval\'s corner');
    expect(pixel(20, 65), [255, 0, 0, 255], reason: 'rounded rectangle');
    expect(pixel(1, 51), [0, 0, 0, 0], reason: 'its corner is rounded off');
    expect(pixel(75, 60), [0, 0, 255, 255], reason: 'line');
    // Half a turn clockwise from three o'clock is the lower half.
    expect(pixel(85, 22), [255, 0, 0, 255], reason: 'arc, lower half');
    expect(pixel(85, 8), [0, 0, 0, 0], reason: 'arc, upper half');
  });

  test('a path, filled', () async {
    await renderer.render(
      picture([
        [
          'path',
          [
            ['M', 10, 10],
            ['L', 90, 10],
            ['L', 90, 70],
            ['Z'],
          ],
          0,
        ],
      ]),
    );

    expect(pixel(80, 20), [255, 0, 0, 255]);
    expect(pixel(20, 60), [0, 0, 0, 0]);
  });

  test('transforms and clips apply, and do not leak into the next frame',
      () async {
    await renderer.render(
      picture([
        ['save'],
        ['translate', 50, 0],
        ['clipRect', 0, 0, 10, 80],
        ['rect', 0, 0, 50, 80, 0],
        // No restore: the frame has to clean up after itself.
      ]),
    );
    expect(pixel(55, 40), [255, 0, 0, 255]);
    expect(pixel(70, 40), [0, 0, 0, 0], reason: 'clipped');

    await renderer.render(
      picture([
        ['rect', 0, 0, 20, 20, 0],
      ]),
    );
    expect(pixel(10, 10), [255, 0, 0, 255], reason: 'no translate left over');
  });

  test('text is drawn from its top-left corner', () async {
    await renderer.render(
      picture([
        [
          'text',
          '████',
          10,
          20,
          {'size': 20, 'color': '#0000ff'},
        ],
      ]),
    );

    expect(pixel(20, 32)[2], 255);
    expect(pixel(20, 32)[3], 255);
    expect(pixel(20, 10)[3], 0, reason: 'nothing above y');
  });

  test('a bad command is skipped and the rest still draw', () async {
    final error = await renderer.render(
      picture([
        ['nonsense', 1, 2],
        ['rect'],
        [],
        ['rect', 0, 0, 10, 10, 0],
      ]),
    );

    expect(error, isNull);
    expect(pixel(5, 5), [255, 0, 0, 255]);
  });

  test('a canvas sized by its parent draws once it knows its size', () async {
    var reported = <String, dynamic>{};
    renderer.onEvent('size', (data) => reported = data);
    await renderer.render(
      UIBuilder.box(
        width: 120,
        height: 90,
        child: node('Canvas', {
          'sizeEventId': 'size',
          'paints': [
            {'color': '#ff0000'},
          ],
          'commands': [
            ['rect', 0, 0, 1000, 1000, 0],
          ],
        }),
      ),
    );
    final frame =
        root.querySelector('[data-type="Canvas"]')! as web.HTMLElement;
    // What the stylesheet's grid would have done for it.
    frame.style
      ..width = '120px'
      ..height = '90px';
    await settle();

    expect(reported, {'width': 120.0, 'height': 90.0});
    expect(surface().width, (120 * ratio()).round());
    expect(pixel(110, 80), [255, 0, 0, 255]);
  });

  test('a child sits in the frame, beside the surface', () async {
    await renderer.render(
      UIBuilder.canvas(
        commands: const [],
        width: 50,
        height: 50,
        child: UIBuilder.text('over'),
      ),
    );

    final host = root.querySelector('.dnn-canvas__child')!;
    expect(childTypes(host), ['Text']);
    expect(root.querySelectorAll('canvas').length, 1);
  });

  test('a tap on a canvas reports the point', () async {
    Map<String, dynamic>? tapped;
    renderer.onEvent('tap', (data) => tapped = data);
    await renderer.render(
      node('Canvas', {
        'width': 100.0,
        'height': 80.0,
        'tapEventId': 'tap',
        'paints': const [],
        'commands': const [],
      }),
    );
    final frame = root.querySelector('[data-type="Canvas"]')!;
    final rect = frame.getBoundingClientRect();

    frame.dispatchEvent(clickAt(rect.left + 12, rect.top + 34));

    expect(tapped!['x'], closeTo(12, 1));
    expect(tapped!['y'], closeTo(34, 1));
  });
}
