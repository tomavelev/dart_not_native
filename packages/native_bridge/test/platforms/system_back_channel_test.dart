/// Tests for the channel the Android and iOS hosts call when the user goes
/// back, driven by simulated platform messages.
library;

import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/platforms/system_back_channel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const codec = StandardMethodCodec();

  /// Delivers a call from the native host and returns what it is told.
  Future<Object?> callFromPlatform([String method = 'systemBack']) async {
    final reply = await TestDefaultBinaryMessengerBinding
        .instance
        .defaultBinaryMessenger
        .handlePlatformMessage(
          SystemBackChannel.channel.name,
          codec.encodeMethodCall(MethodCall(method)),
          null,
        );
    return reply == null ? null : codec.decodeEnvelope(reply);
  }

  setUp(() {
    SystemBack.clearHandlers();
    SystemBackChannel.bind();
  });

  tearDown(() {
    SystemBackChannel.unbind();
    SystemBack.clearHandlers();
  });

  test('binding is idempotent and reported', () {
    SystemBackChannel.bind();

    expect(SystemBackChannel.isBound, isTrue);
  });

  test('the host is told false when the app has nowhere to go', () async {
    expect(await callFromPlatform(), isFalse);
  });

  test('the host is told true when the app consumed the gesture', () async {
    SystemBack.addHandler(() => true);

    expect(await callFromPlatform(), isTrue);
  });

  test('the gesture reaches the app handlers', () async {
    var calls = 0;
    SystemBack.addHandler(() {
      calls++;
      return true;
    });

    await callFromPlatform();
    await callFromPlatform();

    expect(calls, 2);
  });

  test('an unknown method reaches the host as not-implemented, so it keeps '
      'its default behaviour', () async {
    expect(await callFromPlatform('somethingElse'), isNull);
  });

  test(
    'after unbind the host gets no answer and falls back to its default',
    () async {
      SystemBack.addHandler(() => true);

      SystemBackChannel.unbind();

      expect(await callFromPlatform(), isNull);
      expect(SystemBackChannel.isBound, isFalse);
    },
  );

  test('handleCall can be driven directly', () async {
    SystemBack.addHandler(() => true);

    expect(
      await SystemBackChannel.handleCall(const MethodCall('systemBack')),
      isTrue,
    );
    expect(
      () => SystemBackChannel.handleCall(const MethodCall('nope')),
      throwsA(isA<MissingPluginException>()),
    );
  });
}
