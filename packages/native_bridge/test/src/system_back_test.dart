/// Unit tests for the platform back registry.
library;

import 'package:dart_not_native/core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(SystemBack.clearHandlers);
  tearDown(SystemBack.clearHandlers);

  test('with nothing listening the platform keeps the gesture', () {
    expect(SystemBack.hasHandlers, isFalse);
    expect(SystemBack.dispatch(), isFalse);
  });

  test('a handler that consumes the gesture stops the dispatch', () {
    SystemBack.addHandler(() => true);

    expect(SystemBack.dispatch(), isTrue);
  });

  test('handlers run newest first, so a modal beats the router beneath it', () {
    final calls = <String>[];
    SystemBack.addHandler(() {
      calls.add('router');
      return true;
    });
    SystemBack.addHandler(() {
      calls.add('modal');
      return true;
    });

    expect(SystemBack.dispatch(), isTrue);

    expect(calls, ['modal']);
  });

  test('a declining handler passes the gesture down', () {
    final calls = <String>[];
    SystemBack.addHandler(() {
      calls.add('router');
      return true;
    });
    SystemBack.addHandler(() {
      calls.add('modal');
      return false;
    });

    expect(SystemBack.dispatch(), isTrue);

    expect(calls, ['modal', 'router']);
  });

  test('when every handler declines the platform takes the gesture back', () {
    SystemBack.addHandler(() => false);
    SystemBack.addHandler(() => false);

    expect(SystemBack.dispatch(), isFalse);
  });

  test('a throwing handler does not wedge the gesture for the rest', () {
    SystemBack.addHandler(() => true);
    SystemBack.addHandler(() => throw StateError('broken screen'));

    expect(
      SystemBack.dispatch,
      throwsStateError,
      reason: 'the failure is surfaced, not swallowed',
    );
    SystemBack.clearHandlers();

    SystemBack.addHandler(() => true);
    expect(SystemBack.dispatch(), isTrue);
  });

  test('removeHandler reports whether it was registered', () {
    bool handler() => true;
    SystemBack.addHandler(handler);

    expect(SystemBack.removeHandler(handler), isTrue);
    expect(SystemBack.removeHandler(handler), isFalse);
    expect(SystemBack.dispatch(), isFalse);
  });

  test('a handler removed during a dispatch does not break the walk', () {
    final calls = <String>[];
    late bool Function() second;
    bool first() {
      calls.add('first');
      return true;
    }

    second = () {
      calls.add('second');
      SystemBack.removeHandler(second);
      return false;
    };
    SystemBack.addHandler(first);
    SystemBack.addHandler(second);

    expect(SystemBack.dispatch(), isTrue);

    expect(calls, ['second', 'first']);
    expect(SystemBack.handlerCount, 1);
  });

  test('clearHandlers empties the registry', () {
    SystemBack.addHandler(() => true);

    SystemBack.clearHandlers();

    expect(SystemBack.hasHandlers, isFalse);
    expect(SystemBack.handlerCount, 0);
  });
}
