/// What a renderer reports, read as parts rather than prose.
///
/// A host used to get a string and had to parse it to learn anything; the
/// wire format still carries strings from older native halves, so both shapes
/// have to arrive as the same type.
library;

import 'package:dart_not_native/core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RenderError', () {
    test('unknown types are listed, and read back in the message', () {
      final error = RenderError.unknownNodeTypes({'Sparkline', 'Hologram'});

      expect(error.kind, RenderErrorKind.unknownNodeType);
      expect(error.nodeTypes, {'Sparkline', 'Hologram'});
      // Sorted, so the same two types always read the same way.
      expect(error.message, 'Unknown node type(s): Hologram, Sparkline');
    });

    test('a failure keeps the thrown object and its trace', () {
      final cause = StateError('no container');
      final trace = StackTrace.current;
      final error = RenderError.failed('boom', cause: cause, stackTrace: trace);

      expect(error.kind, RenderErrorKind.renderFailed);
      expect(error.nodeTypes, isEmpty);
      expect(error.cause, same(cause));
      expect(error.stackTrace, same(trace));
    });
  });

  group('reading what a native renderer sent', () {
    test('a structured reply becomes the types it names', () {
      final error = RenderError.fromChannel({
        'unknownTypes': ['MapView', 'WebView'],
      });

      expect(error!.kind, RenderErrorKind.unknownNodeType);
      expect(error.nodeTypes, {'MapView', 'WebView'});
    });

    test('a structured failure becomes a failure', () {
      final error = RenderError.fromChannel({'error': 'container missing'});

      expect(error!.kind, RenderErrorKind.renderFailed);
      expect(error.message, 'container missing');
    });

    test('nothing to report is null, not an empty error', () {
      expect(RenderError.fromChannel(null), isNull);
      expect(RenderError.fromChannel(''), isNull);
      expect(RenderError.fromChannel(<String, Object?>{}), isNull);
      expect(RenderError.fromChannel({'error': ''}), isNull);
    });

    test('the sentence older native halves returned still parses', () {
      // A plugin built before the structured reply lands should still say
      // something useful rather than nothing.
      final error = RenderError.fromChannel(
        'Unknown node type(s): Hologram, Sparkline',
      );

      expect(error!.kind, RenderErrorKind.unknownNodeType);
      expect(error.nodeTypes, {'Hologram', 'Sparkline'});
    });

    test('any other string is a failure, message intact', () {
      final error = RenderError.fromChannel('Error: container not initialized');

      expect(error!.kind, RenderErrorKind.renderFailed);
      expect(error.message, 'Error: container not initialized');
    });
  });
}
