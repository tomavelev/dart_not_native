/// Storage Example - rendered through the platform's own views.
///
/// The screen takes a `StorageService` and a `SecureStorageService`. The
/// framework ships only the browser implementations; here, on a Flutter host,
/// the values live in memory. A real app passes a few lines over
/// `shared_preferences` and `flutter_secure_storage` instead.
///
/// The app is a plain Flutter `StatefulWidget` in apps/storage_example_app.dart;
/// only the import (`widgets.dart`) renders it natively rather than through the
/// Flutter engine.
library;

import 'package:dart_not_native/storage/storage_service.dart';
import 'package:dart_not_native/widgets.dart';

import 'apps/storage_example_app.dart';

void main() {
  runApp(
    StorageExampleApp(
      storage: _FallbackStorage(),
      secureStorage: _FallbackSecureStorage(),
    ),
    title: 'Storage',
  );
}

class _FallbackStorage implements StorageService {
  final Map<String, String> _data = {};

  @override
  Future<void> setString(String key, String value) async => _data[key] = value;

  @override
  Future<String?> getString(String key) async => _data[key];

  @override
  Future<void> setInt(String key, int value) async =>
      _data[key] = value.toString();

  @override
  Future<int?> getInt(String key) async =>
      _data[key] != null ? int.parse(_data[key]!) : null;

  @override
  Future<void> setDouble(String key, double value) async =>
      _data[key] = value.toString();

  @override
  Future<double?> getDouble(String key) async =>
      _data[key] != null ? double.parse(_data[key]!) : null;

  @override
  Future<void> setBool(String key, bool value) async =>
      _data[key] = value ? 'true' : 'false';

  @override
  Future<bool?> getBool(String key) async =>
      _data[key]?.toLowerCase() == 'true';

  @override
  Future<void> setStringList(String key, List<String> value) async =>
      _data[key] = value.join(',');

  @override
  Future<List<String>?> getStringList(String key) async =>
      _data[key]?.split(',');

  @override
  Future<void> remove(String key) async => _data.remove(key);

  @override
  Future<void> clear() async => _data.clear();

  @override
  Future<bool> containsKey(String key) async => _data.containsKey(key);

  @override
  Future<Set<String>> getKeys() async => _data.keys.toSet();

  @override
  Future<Map<String, dynamic>> getAll() async => _data.cast<String, dynamic>();
}

class _FallbackSecureStorage extends _FallbackStorage
    implements SecureStorageService {
  @override
  Future<bool> isEncryptionAvailable() async => false;
}
