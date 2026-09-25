/// Unit tests for the storage contract: the type-conversion mixin every
/// platform implementation inherits.
library;

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

  group('strings', () {
    test('round trip', () async {
      await storage.setString('name', 'Ada');

      expect(await storage.getString('name'), 'Ada');
    });

    test('a missing key reads as null', () async {
      expect(await storage.getString('nope'), isNull);
    });

    test('writing twice keeps the last value', () async {
      await storage.setString('k', 'first');
      await storage.setString('k', 'second');

      expect(await storage.getString('k'), 'second');
    });
  });

  group('typed values are stored as strings', () {
    test('int', () async {
      await storage.setInt('count', 42);

      expect(await storage.getInt('count'), 42);
      expect(storage.entries['count'], '42');
    });

    test('negative and zero ints', () async {
      await storage.setInt('a', -7);
      await storage.setInt('b', 0);

      expect(await storage.getInt('a'), -7);
      expect(await storage.getInt('b'), 0);
    });

    test('double', () async {
      await storage.setDouble('ratio', 0.5);

      expect(await storage.getDouble('ratio'), 0.5);
    });

    test('bool', () async {
      await storage.setBool('on', true);
      await storage.setBool('off', false);

      expect(await storage.getBool('on'), isTrue);
      expect(await storage.getBool('off'), isFalse);
      expect(storage.entries['on'], 'true');
    });

    test('string list', () async {
      await storage.setStringList('tags', ['a', 'b']);

      expect(await storage.getStringList('tags'), ['a', 'b']);
    });

    test('an empty list round trips', () async {
      await storage.setStringList('tags', []);

      expect(await storage.getStringList('tags'), isEmpty);
    });
  });

  group('type mismatches read as null instead of throwing', () {
    test('a non-numeric string is not an int or a double', () async {
      await storage.setString('k', 'not a number');

      expect(await storage.getInt('k'), isNull);
      expect(await storage.getDouble('k'), isNull);
    });

    test('a non-JSON string is not a list', () async {
      await storage.setString('k', 'plain');

      expect(await storage.getStringList('k'), isNull);
    });

    test('missing keys read as null for every type', () async {
      expect(await storage.getInt('nope'), isNull);
      expect(await storage.getDouble('nope'), isNull);
      expect(await storage.getBool('nope'), isNull);
      expect(await storage.getStringList('nope'), isNull);
    });

    test('anything other than "true" reads as false', () async {
      await storage.setString('k', 'yes');

      expect(await storage.getBool('k'), isFalse);
    });
  });

  group('key management', () {
    test('containsKey and getKeys reflect what was written', () async {
      await storage.setString('a', '1');
      await storage.setInt('b', 2);

      expect(await storage.containsKey('a'), isTrue);
      expect(await storage.containsKey('c'), isFalse);
      expect(await storage.getKeys(), {'a', 'b'});
    });

    test('remove deletes one key, clear deletes them all', () async {
      await storage.setString('a', '1');
      await storage.setString('b', '2');

      await storage.remove('a');
      expect(await storage.getKeys(), {'b'});

      await storage.clear();
      expect(await storage.getKeys(), isEmpty);
    });

    test('removing a missing key is a no-op', () async {
      await storage.remove('nope');

      expect(await storage.getKeys(), isEmpty);
    });

    test('getAll exports a detached copy', () async {
      await storage.setString('a', '1');

      final export = await storage.getAll();
      export['b'] = '2';

      expect(await storage.getKeys(), {'a'});
    });
  });

  group('StorageException', () {
    test('keeps the original error and reads clearly', () {
      final error = StateError('disk full');
      final exception = StorageException(
        'Failed to write',
        originalError: error,
      );

      expect(exception.toString(), 'StorageException: Failed to write');
      expect(exception.originalError, same(error));
    });
  });

  group('StorageImplementation', () {
    test('describes the backend', () {
      expect(
        StorageImplementation(
          name: 'keychain',
          version: '1.0',
          platform: 'ios',
          supportsEncryption: true,
        ).toString(),
        'keychain v1.0 (ios, encrypted)',
      );

      expect(
        StorageImplementation(
          name: 'shared_preferences',
          version: '1.0',
          platform: 'android',
        ).toString(),
        'shared_preferences v1.0 (android)',
      );
    });
  });
}
