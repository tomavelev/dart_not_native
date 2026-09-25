@TestOn('browser')
/// The camera preview in a real browser.
///
/// What a test runner can settle is the shape: a video element fed by
/// getUserMedia, a box for whatever the browser answers, and an element that
/// survives a re-render so the camera is not stopped and started.
///
/// What it cannot settle is the answer itself. Without a camera the runner's
/// getUserMedia does not reject - it waits for a permission prompt nobody is
/// there to click - so asserting on 'denied' or 'unavailable' here would hang
/// or, worse, pass by accident. Those paths are checked in a headless Chrome
/// run with a fake device and with prompts denied, by hand.
library;

import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/web_ui/web_renderer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

import 'support/dom.dart';

void main() {
  late web.HTMLElement root;
  late WebUIRenderer renderer;
  late List<Map<String, dynamic>> statuses;

  setUp(() {
    root = mountRoot();
    renderer = WebUIRenderer(root: root, animations: false);
    statuses = [];
    renderer.onEvent('cam_status', statuses.add);
  });
  tearDown(() => root.remove());

  web.Element frame() => root.querySelector('.dnn-camera')!;

  Future<void> show({bool active = true}) => renderer.render(
        UIBuilder.cameraPreview(eventId: 'cam', height: 200, active: active),
      );

  test('the video element is the browser own, sized as asked', () async {
    await show();

    final video = frame().querySelector('video') as web.HTMLVideoElement;
    expect(video.autoplay, isTrue);
    // Without playsinline, iOS Safari takes the video full screen.
    expect(video.hasAttribute('playsinline'), isTrue);
    expect(video.muted, isTrue);
    expect((frame() as web.HTMLElement).style.getPropertyValue('height'),
        '200px');
  });

  /// Waits for the browser to answer getUserMedia, which it does in its own
  /// time - a few hundred milliseconds in the test runner.
  Future<Map<String, dynamic>> firstStatus() async {
    for (var i = 0; i < 60 && statuses.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(statuses, isNotEmpty, reason: 'the browser never answered');
    return statuses.first;
  }

  test('says what happened when it cannot have the camera', () async {
    await show();

    final status = await firstStatus();

    // The test browser refuses rather than prompting, which is the path worth
    // having: an app hears 'denied' and the box says so on screen.
    expect(status['status'], anyOf('denied', 'unavailable'));
    expect(status['message'], isNotEmpty);
    final box = frame().querySelector('.dnn-camera__status')!;
    expect(box.textContent, isNotEmpty);
    expect((box as web.HTMLElement).hidden, isFalse);
  });

  test('the status box is there, and empty until there is news', () async {
    await show();

    // Hidden rather than absent: when getUserMedia answers - ready, denied or
    // no camera at all - the box is where the answer goes.
    final status = frame().querySelector('.dnn-camera__status')!;
    expect(status.textContent, isEmpty);
    expect((status as web.HTMLElement).hidden, isTrue);
  });

  test('active: false does not even ask', () async {
    await show(active: false);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(statuses.single['status'], 'stopped');
  });

  test('a re-render keeps the element, so the camera is not restarted',
      () async {
    await show();
    final before = frame();

    await show();

    expect(frame(), same(before));
  });
}
