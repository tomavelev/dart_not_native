/// Checks that every renderer draws the whole node vocabulary.
///
/// A screen is written once and rendered by whichever renderer the target
/// provides, so a node type one renderer is missing is a screen that silently
/// shows a placeholder there. The renderers mark their dispatch with
/// `node-types:begin`/`end`; this reads the types out of each and compares
/// them against [nodeTypes], the protocol's own list.
///
/// The Kotlin and Swift renderers cannot be run here - no device, and no Xcode
/// on Linux - so this source-level check is what keeps them honest.
library;

import 'dart:io';

import 'package:dart_not_native/core.dart';
import 'package:flutter_test/flutter_test.dart';

/// The source between the braces of the function [opening] starts.
///
/// Reading a whole file would let a line somewhere else stand in for the one
/// that matters - a change event sent by a slider passing for a text field's,
/// say - so every check that asks "does *this* function still do that?" reads
/// only the function's own body.
String handlerBody(String path, String opening) {
  final source = File(path).readAsStringSync();
  final start = source.indexOf(opening);
  if (start < 0) throw StateError('$path has no "$opening"');
  var depth = 0;
  for (var i = start + opening.length - 1; i < source.length; i++) {
    if (source[i] == '{') depth++;
    if (source[i] == '}') {
      depth--;
      if (depth == 0) return source.substring(start, i);
    }
  }
  throw StateError('$path: "$opening" is never closed');
}

/// The node types [file] dispatches on, read from between its markers.
///
/// [marker] names which pair of markers to read between: the render dispatch
/// (`node-types`) or the list of nodes whose children can be walked one to one
/// (`child-views`).
Set<String> handledTypes(
  String path, {
  required RegExp pattern,
  String marker = 'node-types',
}) {
  final source = File(path).readAsStringSync();
  final start = source.indexOf('$marker:begin');
  final end = source.indexOf('$marker:end');
  if (start < 0 || end <= start) {
    throw StateError('$path is missing its $marker markers');
  }

  final dispatch = source.substring(start, end);
  return pattern
      .allMatches(dispatch)
      .expand(
        (match) => RegExp(
          "['\"]([A-Za-z]+)['\"]",
        ).allMatches(match.group(0)!).map((m) => m.group(1)!),
      )
      .toSet();
}

void main() {
  final renderers = <String, Set<String>>{
    'web (DOM)': handledTypes(
      'lib/web_ui/web_renderer.dart',
      pattern: RegExp(r"case '[A-Za-z]+':"),
    ),
    'Flutter': handledTypes(
      'lib/platforms/flutter_renderer.dart',
      pattern: RegExp(r"case '[A-Za-z]+':"),
    ),
    'Android (Kotlin)': handledTypes(
      'android/src/main/kotlin/com/programtom/dart_not_native/NativeUIRenderer.kt',
      pattern: RegExp(r'"[A-Za-z]+"(, "[A-Za-z]+")* ->'),
    ),
    'iOS (Swift)': handledTypes(
      'ios/Classes/NativeUIRenderer.swift',
      pattern: RegExp(r'case "[A-Za-z]+"(, "[A-Za-z]+")*:'),
    ),
  };

  renderers.forEach((name, handled) {
    group(name, () {
      test('draws every node type the protocol defines', () {
        final missing = nodeTypes.difference(handled);

        expect(
          missing,
          isEmpty,
          reason: '$name cannot draw: ${missing.join(', ')}',
        );
      });

      test('draws nothing the protocol does not define', () {
        final extra = handled.difference(nodeTypes);

        expect(
          extra,
          isEmpty,
          reason:
              '$name handles types no app can build: '
              '${extra.join(', ')} - add them to nodeTypes or remove them',
        );
      });
    });
  });

  // The Dart side sends WidgetNode.toJson() - props nested under `props` - and
  // the native renderers read props straight off each node. Until they
  // flattened the tree, no title, label or event id reached a native view.
  // This pins the flattening in place.
  group('the native renderers read the wire format', () {
    final sources = {
      'Android (Kotlin)':
          'android/src/main/kotlin/com/programtom/dart_not_native/NativeUIRenderer.kt',
      'iOS (Swift)': 'ios/Classes/NativeUIRenderer.swift',
    };

    sources.forEach((name, path) {
      test('$name flattens props before rendering', () {
        final source = File(path).readAsStringSync();
        // The tree is normalised (props lifted onto each node) before it is
        // rendered or diffed - the render path hoists it into a local now.
        expect(source, contains('normalized(tree)'));
        expect(source, contains('"props"'));
      });
    });

    test('and the Dart side still nests them', () {
      final json = UIBuilder.appBar(title: 'Inbox').toJson();
      expect(json['props'], {'title': 'Inbox'});
      expect(json.containsKey('title'), isFalse);
    });
  });

  // A node that animates has to be patched in place: a rebuilt view starts at
  // the new opacity, size and colour, with nothing left to move from. On the
  // natives that means appearing in `childViews`, and nothing fails when it
  // does not - the screen is correct, it just jumps. That is how the first
  // fade behaved, and only looking at it showed why, so it is pinned here.
  group('a node that animates can be patched', () {
    const motion = {'AnimatedOpacity', 'AnimatedContainer'};

    final walkable = <String, Set<String>>{
      'Android (Kotlin)': handledTypes(
        'android/src/main/kotlin/com/programtom/dart_not_native/NativeUIRenderer.kt',
        pattern: RegExp(r'"[A-Za-z]+"(,\s*"[A-Za-z]+")* ->'),
        marker: 'child-views',
      ),
      'iOS (Swift)': handledTypes(
        'ios/Classes/NativeUIRenderer.swift',
        pattern: RegExp(r'case "[A-Za-z]+"(,\s*"[A-Za-z]+")*:'),
        marker: 'child-views',
      ),
    };

    walkable.forEach((name, types) {
      test('$name walks the children of every motion node', () {
        final missing = motion.difference(types);

        expect(
          missing,
          isEmpty,
          reason:
              '$name rebuilds instead of patching: ${missing.join(', ')} - '
              'add them to childViews, or the animation jumps',
        );
      });
    });
  });

  // A bound field that never tells Dart what was typed looks completely
  // right: it draws, it takes the keyboard, it keeps its caret - and the app
  // behind it sees nothing. The floating-label work deleted the one line that
  // sends it on Android (cc26696) and nothing noticed for two days, because
  // the device lane checks what a renderer *draws*, not what it reports.
  group('a bound text field reports what is typed into it', () {
    test('Android (Kotlin) sends a change event as the text changes', () {
      expect(
        handlerBody(
          'android/src/main/kotlin/com/programtom/dart_not_native/NativeUIRenderer.kt',
          'override fun afterTextChanged(s: Editable?) {',
        ),
        contains('_change'),
        reason: 'Android stopped reporting what the user typed',
      );
    });

    test('iOS (Swift) sends a change event as the text changes', () {
      expect(
        handlerBody(
          'ios/Classes/NativeUIRenderer.swift',
          '@objc private func textChanged(_ sender: UITextField) {',
        ),
        contains('"change"'),
        reason: 'iOS stopped reporting what the user typed',
      );
    });
  });

  // A field only takes the keyboard when it is asked, and the ask arrives on
  // whichever path the reconciler took: a field built fresh (the screen just
  // opened) or one patched in place (a failed submit on a form that is already
  // on screen). Answering it in only one of the two leaves the common case -
  // pressing submit twice - doing nothing at all.
  group('a field takes the keyboard when the app asks for it', () {
    const kotlin =
        'android/src/main/kotlin/com/programtom/dart_not_native/'
        'NativeUIRenderer.kt';
    const swift = 'ios/Classes/NativeUIRenderer.swift';

    final paths = {
      'Android (Kotlin)': (
        kotlin,
        [
          // Every shape of Android field is built through this one.
          'private fun configureEditText(node: Map<*, *>, field: EditText, '
              'hint: String?): EditText {',
          'private fun patchTextField(view: View, oldNode: Map<*, *>, '
              'newNode: Map<*, *>): Boolean {',
        ],
      ),
      'iOS (Swift)': (
        swift,
        [
          'private func renderTextField(_ node: [String: Any]) -> UIView {',
          'private func patchTextField(',
        ],
      ),
    };

    paths.forEach((name, where) {
      final (path, openings) = where;
      for (final opening in openings) {
        final built = !opening.contains('patch');
        test(
          '$name answers a focus ask on a field it ${built ? 'builds' : 'patches'}',
          () {
            expect(
              handlerBody(path, opening),
              contains('applyFocusRequest'),
              reason: '$name ignores focusVersion on this path',
            );
          },
        );
      }
    });
  });

  // A window has been edge-to-edge since Android 15, so a bar drawn at the top
  // of one sits *under* the clock and the status icons unless it says
  // otherwise. Three device flows failed on exactly that, each asserting a
  // title that was drawn and could not be read.
  group('a bar at the top of the window clears the status icons', () {
    const kotlin =
        'android/src/main/kotlin/com/programtom/dart_not_native/'
        'NativeUIRenderer.kt';
    const opening =
        'private fun renderAppBar(node: Map<*, *>): View = '
        'MaterialToolbar(materialContext).apply {';

    test('Android (Kotlin) pads the app bar past the system bars', () {
      expect(
        handlerBody(kotlin, opening),
        contains('onSystemBars'),
        reason: 'the app bar never reads the status bar inset',
      );
    });

    const swift = 'ios/Classes/NativeUIRenderer.swift';

    test('iOS (Swift) lets a scaffold with a bar start at the very top', () {
      expect(
        handlerBody(
          swift,
          'private func renderScaffold(_ node: [String: Any]) -> UIView {',
        ),
        contains('hasBar ? container.topAnchor'),
        reason: 'the bar stops at the safe area and leaves a band above it',
      );
    });

    test('iOS (Swift) insets the app bar title by the safe area', () {
      expect(
        handlerBody(
          swift,
          'private func renderAppBar(_ node: [String: Any]) -> UIView {',
        ),
        contains('host.safeAreaLayoutGuide.topAnchor'),
        reason: 'the title is drawn behind the clock and the status icons',
      );
    });

    test('iOS (Swift) ends a scaffold body above the home indicator', () {
      expect(
        handlerBody(
          swift,
          'private func renderScaffold(_ node: [String: Any]) -> UIView {',
        ),
        contains(
          'column.bottomAnchor.constraint('
          'equalTo: container.safeAreaLayoutGuide.bottomAnchor)',
        ),
        reason: 'the body runs under the home indicator, unlike Android',
      );
    });

    test('Android (Kotlin) keeps a full title row under that inset', () {
      expect(
        handlerBody(kotlin, opening),
        contains('minimumHeight'),
        reason:
            'the bar wraps to its padding plus the title, which leaves the '
            'title nowhere to sit but flat against the bottom edge',
      );
    });
  });

  // The bottom edge clears the navigation bar because `avoidKeyboard` measures
  // against the visible display frame, which excludes that bar as well as the
  // keyboard. Nothing else insets the bottom, so a rewrite in terms of the IME
  // inset - which the function's name invites - would put the content back
  // under the bar with no test to say so.
  test('Android (Kotlin) measures the bottom inset from the visible frame', () {
    const kotlin =
        'android/src/main/kotlin/com/programtom/dart_not_native/'
        'NativeUIRenderer.kt';
    expect(
      handlerBody(kotlin, 'private fun avoidKeyboard(container: View) {'),
      contains('getWindowVisibleDisplayFrame'),
      reason: 'the bottom edge stops clearing the navigation bar',
    );
  });

  // The four things below were added to both native renderers together and
  // none of them can be run here, so each is pinned to the function that does
  // it. A right-to-left screen, a disabled control and an image's fallback
  // all fail the same quiet way when the line goes missing: the screen still
  // draws, just not what the tree said.
  group('the native renderers answer for', () {
    const kotlin =
        'android/src/main/kotlin/com/programtom/dart_not_native/'
        'NativeUIRenderer.kt';
    const swift = 'ios/Classes/NativeUIRenderer.swift';

    /// What each renderer's function must still contain: a name for the
    /// test, the file, the function's opening, and the lines that do the job.
    const pinned = <(String, String, String, List<String>)>[
      (
        'Android (Kotlin) turns the root container for an rtl tree',
        kotlin,
        'private fun applyDirection(root: View, tree: Map<*, *>): Boolean {',
        ['"textDirection"', 'LAYOUT_DIRECTION_RTL'],
      ),
      (
        'Android (Kotlin) reads the direction on every render',
        kotlin,
        'private fun renderTree(tree: Map<*, *>?): Map<String, Any>? {',
        ['applyDirection(root, next)'],
      ),
      (
        'iOS (Swift) reads the direction on every render',
        swift,
        'private func renderTree(_ tree: [String: Any]) -> [String: Any]? {',
        ['next["textDirection"]', 'applyDirection('],
      ),
      (
        'iOS (Swift) turns every view for an rtl tree',
        swift,
        'private func applyDirection(_ view: UIView) {',
        ['.forceRightToLeft'],
      ),
      (
        'Android (Kotlin) disables a checkable control the tree disabled',
        kotlin,
        'private fun applyDisabled(button: CompoundButton, node: Map<*, *>) {',
        ['node["disabled"] == true', 'isEnabled'],
      ),
      (
        'Android (Kotlin) does so again when it patches one',
        kotlin,
        'private fun patchControl(view: View, node: Map<*, *>, '
            'checkedKey: String): Boolean {',
        ['applyDisabled'],
      ),
      (
        'iOS (Swift) dims a disabled checkbox or radio',
        swift,
        'private func styleControlLabel(_ button: UIButton, '
            '_ node: [String: Any]) {',
        ['node["disabled"]', 'button.alpha'],
      ),
      (
        'iOS (Swift) disables a switch the tree disabled',
        swift,
        'private func renderToggle(_ node: [String: Any]) -> UIView {',
        ['node["disabled"]'],
      ),
      (
        'Android (Kotlin) owns an HTTP cache on disk',
        kotlin,
        'private fun installHttpCache() {',
        ['HttpResponseCache.getInstalled()', 'HttpResponseCache.install('],
      ),
      (
        'Android (Kotlin) looks in memory before it fetches or shows a '
            'fallback',
        kotlin,
        'private fun loadImage(src: String?, into: ImageView, hiding: View, '
            'limit: Int) {',
        ['imageCache.get(key)', 'imageWaiters[key]'],
      ),
      (
        'iOS (Swift) looks in memory before it fetches or shows a fallback',
        swift,
        'private func load(_ src: String?, into view: UIImageView, '
            'hiding fallback: UIView) {',
        ['imageCache.object(forKey:', 'imageWaiters'],
      ),
      (
        'Android (Kotlin) draws an image\'s child as its fallback',
        kotlin,
        'private fun renderImage(node: Map<*, *>): View {',
        ['imageFallback(node)'],
      ),
      (
        'iOS (Swift) draws an image\'s child as its fallback',
        swift,
        'private func renderImage(_ node: [String: Any]) -> UIView {',
        ['ImageFallbackHost()', 'firstChild(node)'],
      ),
      // An event is answered by the build it was raised against (see
      // EventBindings): each native half has to keep the number its tree
      // came with and hand it back from the one place events leave by.
      (
        'Android (Kotlin) keeps the build number of the tree it shows',
        kotlin,
        'private fun renderTree(tree: Map<*, *>?): Map<String, Any>? {',
        ['treeBuild = (tree["build"] as? Number)?.toInt()'],
      ),
      (
        'Android (Kotlin) names the build with every event',
        kotlin,
        'private fun sendEvent(eventId: String, data: Map<String, Any?>) {',
        ['"build" to treeBuild'],
      ),
      (
        'iOS (Swift) keeps the build number of the tree it shows',
        swift,
        'private func renderTree(_ tree: [String: Any]) -> [String: Any]? {',
        ['treeBuild = (tree["build"] as? NSNumber)?.intValue'],
      ),
      (
        'iOS (Swift) names the build with every event',
        swift,
        'private func send(eventId: String, data: [String: Any]) {',
        ['arguments["build"] = treeBuild', 'arguments: arguments'],
      ),
    ];

    for (final (name, path, opening, lines) in pinned) {
      test(name, () {
        final body = handlerBody(path, opening);
        for (final line in lines) {
          expect(body, contains(line), reason: '$opening lost "$line"');
        }
      });
    }

    for (final control in const {
      'renderCheckbox(node: Map<*, *>): View = '
          'MaterialCheckBox(materialContext).apply {',
      'renderRadio(node: Map<*, *>): View = '
          'MaterialRadioButton(materialContext).apply {',
      'renderToggle(node: Map<*, *>): View = '
          'SwitchCompat(materialContext).apply {',
    }) {
      test(
        'Android (Kotlin) applies disabled in ${control.split('(').first}',
        () {
          expect(
            handlerBody(kotlin, 'private fun $control'),
            contains('applyDisabled'),
          );
        },
      );
    }
  });

  // A device test - Maestro, agent-device - and a screen reader both go
  // through the platform's accessibility tree, and two things have to be in
  // it for either to work on a screen composed from boxes: the node's `id`,
  // or nothing can be found whatever the language, and an activate action on
  // a box that takes a tap, or it can be found and not pressed. Neither shows
  // on screen, so a renderer that loses one looks exactly as it did.
  group('what a device test finds a view by', () {
    const kotlin =
        'android/src/main/kotlin/com/programtom/dart_not_native/'
        'NativeUIRenderer.kt';
    const kotlinViews =
        'android/src/main/kotlin/com/programtom/dart_not_native/'
        'NativeUIViews.kt';
    const swift = 'ios/Classes/NativeUIRenderer.swift';
    const swiftViews = 'ios/Classes/NativeUIViews.swift';

    test('Android (Kotlin) reports a node id as the resource name', () {
      final identify = handlerBody(
        kotlin,
        'private fun identify(view: View, node: Map<*, *>) {',
      );
      expect(identify, contains('node["id"]'));
      expect(identify, contains('access.resourceName = id'));
      // The delegate is what puts it where uiautomator reads `resource-id`.
      expect(
        handlerBody(
          kotlinViews,
          'override fun onInitializeAccessibilityNodeInfo('
          'host: View, info: AccessibilityNodeInfoCompat) {',
        ),
        contains('info.viewIdResourceName = it'),
      );
    });

    test('Android (Kotlin) identifies a view when built and when patched', () {
      final source = File(kotlin).readAsStringSync();
      expect(source, contains('drawWidget(node)?.also { identify(it, node) }'));
      expect(
        handlerBody(
          kotlin,
          'private fun patchNode(view: View, oldNode: Map<*, *>, '
          'newNode: Map<*, *>): Boolean {',
        ),
        contains('identify(view, newNode)'),
      );
    });

    test('iOS (Swift) reports a node id as the accessibility identifier', () {
      final identify = handlerBody(
        swift,
        'private func identify(_ view: UIView, _ node: [String: Any]) {',
      );
      expect(identify, contains('node["id"]'));
      expect(identify, contains('target.accessibilityIdentifier = id'));
    });

    test('iOS (Swift) identifies a view when built and when patched', () {
      final source = File(swift).readAsStringSync();
      // Once from the build wrapper, and from the patch path for the node
      // itself and for a lazy list that was reconciled.
      expect(
        'identify(view, '.allMatches(source).length,
        greaterThanOrEqualTo(3),
      );
      expect(source, contains('identify(view, newNode)'));
    });

    test('Android (Kotlin) lets a tappable box be activated', () {
      final views = File(kotlinViews).readAsStringSync();
      // Clickable is what offers the action; performClick is what it does.
      expect(views, contains('isClickable = value.tap != null'));
      expect(views, contains('isLongClickable = value.longPress != null'));
      expect(
        handlerBody(kotlinViews, 'override fun performClick(): Boolean {'),
        contains('activate(events.tap)'),
      );
      expect(
        views,
        contains(
          'override fun performLongClick(): Boolean = '
          'activate(events.longPress)',
        ),
      );
      // Nothing is activated through a box that lets no touch through.
      expect(
        handlerBody(
          kotlinViews,
          'private fun activate(eventId: String?): Boolean {',
        ),
        allOf(contains('pointerIgnored(this)'), contains('host.send(')),
      );
    });

    test('iOS (Swift) lets a tappable box be activated', () {
      final activate = handlerBody(
        swiftViews,
        'override func accessibilityActivate() -> Bool {',
      );
      expect(activate, contains('style.tapEventId'));
      expect(activate, contains('!pointerIgnored'));
      expect(activate, contains('onEvent?(eventId'));
    });
  });

  test('each native renderer sends its events from one place', () {
    const kotlin =
        'android/src/main/kotlin/com/programtom/dart_not_native/'
        'NativeUIRenderer.kt';
    const swift = 'ios/Classes/NativeUIRenderer.swift';
    // The build number is added where an event leaves; a second call to the
    // channel would be a way round it.
    expect(
      'methodChannel?.invokeMethod('.allMatches(File(swift).readAsStringSync()),
      hasLength(1),
    );
    expect(
      'channel?.invokeMethod('.allMatches(File(kotlin).readAsStringSync()),
      hasLength(1),
    );
  });

  for (final path in const [
    'lib/platforms/android_renderer.dart',
    'lib/platforms/ios_renderer.dart',
  ]) {
    test('$path sends the build number and reads it back', () {
      final source = File(path).readAsStringSync();
      expect(source, contains("json['build'] = build"));
      expect(
        source,
        contains("EventBindings.eventBuild = (arguments['build']"),
      );
    });
  }

  test('the vocabulary is not empty and has no duplicates by case', () {
    expect(nodeTypes, isNotEmpty);
    expect(
      nodeTypes.map((type) => type.toLowerCase()).toSet(),
      hasLength(nodeTypes.length),
    );
  });
}
