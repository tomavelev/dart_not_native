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

  test('the vocabulary is not empty and has no duplicates by case', () {
    expect(nodeTypes, isNotEmpty);
    expect(
      nodeTypes.map((type) => type.toLowerCase()).toSet(),
      hasLength(nodeTypes.length),
    );
  });
}
