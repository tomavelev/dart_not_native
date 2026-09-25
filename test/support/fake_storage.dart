/// In-memory stand-ins for the storage back ends the examples inject.
library;

import 'package:dart_not_native/core.dart';
import 'package:dart_not_native/storage/storage_service.dart';

class FakeStorage extends StorageService with StorageTypeConversion {
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

class FakeSecureStorage extends FakeStorage implements SecureStorageService {
  FakeSecureStorage({this.encryptionAvailable = true});

  final bool encryptionAvailable;

  @override
  Future<bool> isEncryptionAvailable() async => encryptionAvailable;
}
