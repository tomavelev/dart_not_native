/// Bringing stored data forward across app versions.
///
/// The interesting cases are the ones that are not the happy path: a run that
/// is interrupted, a step that throws, a store that is already up to date.
library;

import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/storage/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// String-only storage, exactly what a platform backend has to provide.
class _MemoryStorage extends StorageService with StorageTypeConversion {
  final Map<String, String> entries = {};

  @override
  Future<void> setString(String key, String value) async =>
      entries[key] = value;

  @override
  Future<String?> getString(String key) async => entries[key];

  @override
  Future<void> remove(String key) async => entries.remove(key);

  @override
  Future<void> clear() async => entries.clear();

  @override
  Future<bool> containsKey(String key) async => entries.containsKey(key);

  @override
  Future<Set<String>> getKeys() async => entries.keys.toSet();

  @override
  Future<Map<String, dynamic>> getAll() async => Map.of(entries);
}

void main() {
  late _MemoryStorage storage;

  setUp(() => storage = _MemoryStorage());

  /// A step that records that it ran.
  StorageMigration step(int version, List<int> ran) =>
      StorageMigration(version, (_) async => ran.add(version));

  test('a fresh store is at version 0', () async {
    expect(await storage.schemaVersion(), 0);
  });

  test('every step runs on a fresh store, oldest first', () async {
    final ran = <int>[];

    final version = await storage.migrate([step(2, ran), step(1, ran), step(3, ran)]);

    // Declared out of order; run in order, which is what a migration list
    // means whatever order it is written in.
    expect(ran, [1, 2, 3]);
    expect(version, 3);
    expect(await storage.schemaVersion(), 3);
  });

  test('a step that already ran does not run again', () async {
    final first = <int>[];
    await storage.migrate([step(1, first), step(2, first)]);

    final second = <int>[];
    final version = await storage.migrate([step(1, second), step(2, second)]);

    expect(second, isEmpty);
    expect(version, 2);
  });

  test('only the new steps run when the app adds one', () async {
    final ran = <int>[];
    await storage.migrate([step(1, ran)]);
    ran.clear();

    await storage.migrate([step(1, ran), step(2, ran)]);

    expect(ran, [2]);
  });

  test('a step actually sees the data, and its changes stick', () async {
    await storage.setString('user_name', 'Ada');

    await storage.migrate([
      StorageMigration(1, (s) async {
        final old = await s.getString('user_name');
        if (old != null) {
          await s.setString('profile.name', old);
          await s.remove('user_name');
        }
      }),
    ]);

    expect(await storage.getString('profile.name'), 'Ada');
    expect(await storage.containsKey('user_name'), isFalse);
  });

  group('when a step fails', () {
    test('the error reaches the caller', () async {
      expect(
        storage.migrate([
          StorageMigration(1, (_) async => throw StateError('bad data')),
        ]),
        throwsStateError,
      );
    });

    test('the steps before it are not replayed on the next run', () async {
      final ran = <int>[];
      var shouldFail = true;

      Future<int> attempt() => storage.migrate([
            step(1, ran),
            StorageMigration(2, (_) async {
              if (shouldFail) throw StateError('not yet');
              ran.add(2);
            }),
            step(3, ran),
          ]);

      await expectLater(attempt(), throwsStateError);
      // Step 1 completed and was recorded; 3 never ran.
      expect(ran, [1]);
      expect(await storage.schemaVersion(), 1);

      shouldFail = false;
      ran.clear();
      expect(await attempt(), 3);
      expect(ran, [2, 3], reason: 'resumed, rather than starting over');
    });
  });

  group('a list that cannot be right', () {
    test('two steps sharing a version are refused', () {
      final ran = <int>[];

      expect(
        () => storage.migrate([step(1, ran), step(1, ran)]),
        throwsArgumentError,
      );
    });

    test('a version below 1 is refused, since 0 means never migrated', () {
      final ran = <int>[];

      expect(() => storage.migrate([step(0, ran)]), throwsArgumentError);
    });
  });

  test('an app can keep its version under its own key', () async {
    final ran = <int>[];

    await storage.migrate([step(1, ran)], versionKey: 'my.version');

    expect(await storage.getInt('my.version'), 1);
    expect(await storage.containsKey(defaultSchemaVersionKey), isFalse);
    expect(await storage.schemaVersion(versionKey: 'my.version'), 1);
  });

  test('no migrations leaves the store untouched', () async {
    final version = await storage.migrate([]);

    expect(version, 0);
    expect(storage.entries, isEmpty);
  });
}
