@TestOn('browser')
/// Swipe-to-reveal, driven with real pointer events.
///
/// The gesture was only ever checked by eye before: a partial drag has to snap
/// the row open so an action can be clicked, and a long drag has to fire the
/// first action without one.
library;

import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/web_ui/web_renderer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

import 'support/dom.dart';

void main() {
  late web.HTMLElement root;
  late WebUIRenderer renderer;
  late List<String> fired;

  setUp(() async {
    root = mountRoot();
    root.style.setProperty('width', '400px');
    renderer = WebUIRenderer(root: root, animations: false);
    fired = [];
    renderer.onEvent('delete', (_) => fired.add('delete'));
    renderer.onEvent('archive', (_) => fired.add('archive'));
    // The node as a build would produce it; the callbacks a builder binds are
    // only available inside NativeUIApp.build().
    renderer.onEvent('mark', (_) => fired.add('mark'));
    await renderer.render(
      WidgetNode(
        type: 'SwipeActions',
        props: {
          'id': 'row',
          'actions': [
            {'label': 'Delete', 'color': '#d32f2f', 'eventId': 'delete'},
            {'label': 'Archive', 'color': '#1976d2', 'eventId': 'archive'},
          ],
          'leadingActions': [
            {'label': 'Mark read', 'color': '#1976d2', 'eventId': 'mark'},
          ],
        },
        children: [UIBuilder.text('A row', id: 'row_text')],
      ),
    );
  });
  tearDown(() => root.remove());

  web.HTMLElement foreground() =>
      root.querySelector('.dnn-swipe__fg') as web.HTMLElement;

  /// How far the row has been told to slide, in pixels.
  ///
  /// The inline style rather than the computed one: letting go starts a 200ms
  /// transition, and the computed matrix during it is wherever the animation
  /// has got to, not where the row is going.
  double offset() {
    final transform = foreground().style.getPropertyValue('transform');
    final match = RegExp(r'translateX\((-?[\d.]+)px\)').firstMatch(transform);
    return match == null ? 0 : double.parse(match.group(1)!);
  }

  void drag(double by, {bool release = true}) {
    final fg = foreground();
    fg.dispatchEvent(pointer('pointerdown', 300));
    fg.dispatchEvent(pointer('pointermove', 300 + by));
    if (release) fg.dispatchEvent(pointer('pointerup', 300 + by));
  }

  test('the actions are behind the row until it is dragged', () {
    // Two trailing and one leading, all built and all hidden behind the row.
    expect(root.querySelectorAll('.dnn-swipe__action').length, 3);
    expect(offset(), 0);
  });

  test('a partial drag snaps the row open, firing nothing', () {
    drag(-100);

    // Two actions of 88px: open is -176.
    expect(offset(), -176);
    expect(fired, isEmpty);
  });

  test('an action can be clicked once the row is open', () {
    drag(-100);

    (root.querySelectorAll('.dnn-swipe__action').item(0)! as web.HTMLElement)
        .click();

    expect(fired, ['delete']);
  });

  test('a short drag lets the row fall back, firing nothing', () {
    drag(-20);

    expect(offset(), 0);
    expect(fired, isEmpty);
  });

  test('a long drag fires the first action by itself', () {
    drag(-300);

    expect(fired, ['delete']);
    expect(offset(), 0);
  });

  test('a drag that is let go mid-way is still holding the row', () {
    drag(-60, release: false);

    expect(offset(), -60);
    expect(fired, isEmpty);
  });
  test('a drag the other way opens the leading actions', () {
    drag(60);

    // One leading action of 88px.
    expect(offset(), 88);
    expect(fired, isEmpty);
    expect(
      (root.querySelector('.dnn-swipe__actions--leading') as web.HTMLElement?)
          ?.textContent,
      'Mark read',
    );
  });

  test('a long drag the other way fires the first leading action', () {
    drag(200);

    expect(fired, ['mark']);
    expect(offset(), 0);
  });

  test('a leading action can be clicked once the row is open', () {
    drag(60);

    (root.querySelector('.dnn-swipe__actions--leading button')!
            as web.HTMLElement)
        .click();

    expect(fired, ['mark']);
  });

}

/// A pointer event at [x], of the kind the renderer listens for.
web.PointerEvent pointer(String type, double x) => web.PointerEvent(
      type,
      web.PointerEventInit(
        clientX: x.toInt(),
        pointerId: 1,
        bubbles: true,
        isPrimary: true,
      ),
    );