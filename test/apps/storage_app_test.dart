/// Tests for the storage example, driven against in-memory back ends.
library;

import 'package:dart_not_native/widgets.dart' show hostApp;
import 'package:dart_not_native_example/examples/apps/storage_example_app.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/app_tester.dart';
import '../support/fake_storage.dart';

void main() {
  late FakeStorage storage;
  late FakeSecureStorage secure;
  late AppTester tester;

  /// The app loads asynchronously; let its futures settle.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  setUp(() async {
    storage = FakeStorage();
    secure = FakeSecureStorage();
    tester = AppTester.mount(
      hostApp(StorageExampleApp(storage: storage, secureStorage: secure)),
    );
    await settle();
  });

  test('reports the encryption capability of the back end', () async {
    expect(tester.text('encryption_status'), 'Encryption: Enabled');

    final plainTester = AppTester.mount(
      hostApp(
        StorageExampleApp(
          storage: FakeStorage(),
          secureStorage: FakeSecureStorage(encryptionAvailable: false),
        ),
      ),
    );
    await settle();

    expect(
      plainTester.text('encryption_status'),
      'Encryption: Disabled (web fallback)',
    );
  });

  test('starts empty', () {
    expect(tester.text('regular_count'), '0 keys');
    expect(tester.text('secure_count'), '0 keys');
    expect(tester.text('status'), 'Status: Ready');
  });

  test('saving regular data writes through and lists the keys', () async {
    await tester.tap('save_regular');
    await settle();

    expect(storage.entries['app_name'], 'MyApp');
    expect(storage.entries['app_launches'], '42');
    expect(tester.text('status'), 'Status: Regular data saved');
    expect(tester.text('regular_count'), '6 keys');
    expect(tester.text('regular_app_name'), 'app_name: MyApp');
    expect(
      tester.text('regular_recent_searches'),
      'recent_searches: ["flutter","dart","storage"]',
    );
  });

  test('saving secure data masks the values on screen', () async {
    await tester.tap('save_secure');
    await settle();

    expect(secure.entries['api_key'], 'sk_live_abc123xyz789');
    expect(tester.text('secure_count'), '4 keys');
    expect(tester.text('secure_api_key'), 'api_key: sk_live_ab...');
    expect(
      tester.texts.any((t) => t.contains('super_secret_password_123')),
      isFalse,
      reason: 'secrets must not be rendered in full',
    );
  });

  test('the type round trip reports what came back', () async {
    await tester.tap('test_types');
    await settle();

    expect(
      tester.text('status'),
      'Status: Types OK: Hello World / 12345 / 3.14159 / true / item1, item2, item3',
    );
  });

  test('reload refreshes from the back end', () async {
    await storage.setString('written_behind_the_app', 'yes');

    await tester.tap('load_all');
    await settle();

    expect(
      tester.text('regular_written_behind_the_app'),
      'written_behind_the_app: yes',
    );
  });

  test('clear empties both stores', () async {
    await tester.tap('save_regular');
    await tester.tap('save_secure');
    await settle();

    await tester.tap('clear_all');
    await settle();

    expect(storage.entries, isEmpty);
    expect(secure.entries, isEmpty);
    expect(tester.text('status'), 'Status: All data cleared');
    expect(tester.text('regular_count'), '0 keys');
  });

  test('a failing back end is reported instead of crashing the app', () async {
    final failing = _FailingStorage();
    final failTester = AppTester.mount(
      hostApp(
        StorageExampleApp(storage: failing, secureStorage: FakeSecureStorage()),
      ),
    );
    await settle();

    await failTester.tap('save_regular');
    await settle();

    expect(failTester.text('status'), startsWith('Status: Failed to save'));
  });

  test('every button is wired', () async {
    for (final eventId in tester.eventIds) {
      final result = await tester.emit(eventId);
      expect(result['success'], isTrue, reason: '$eventId has no handler');
    }
  });
}

class _FailingStorage extends FakeStorage {
  @override
  Future<void> setString(String key, String value) async =>
      throw StateError('disk full');
}
