/// StorageService backed by the browser's localStorage.
library;

import 'dart:convert';

import 'package:web/web.dart' as web;

import '../storage/storage_service.dart';

/// Stores values in `window.localStorage` under [prefix] so several apps on
/// one origin do not clash. Values are kept as strings, like on mobile.
class LocalStorageService implements StorageService {
  final String prefix;

  LocalStorageService({this.prefix = 'dnn.'});

  web.Storage get _storage => web.window.localStorage;

  Iterable<String> get _ownKeys sync* {
    for (var i = 0; i < _storage.length; i++) {
      final key = _storage.key(i);
      if (key != null && key.startsWith(prefix)) yield key;
    }
  }

  @override
  Future<void> setString(String key, String value) async =>
      _storage.setItem('$prefix$key', value);

  @override
  Future<String?> getString(String key) async =>
      _storage.getItem('$prefix$key');

  @override
  Future<void> setInt(String key, int value) => setString(key, '$value');

  @override
  Future<int?> getInt(String key) async =>
      int.tryParse(await getString(key) ?? '');

  @override
  Future<void> setDouble(String key, double value) => setString(key, '$value');

  @override
  Future<double?> getDouble(String key) async =>
      double.tryParse(await getString(key) ?? '');

  @override
  Future<void> setBool(String key, bool value) => setString(key, '$value');

  @override
  Future<bool?> getBool(String key) async {
    final value = await getString(key);
    return value == null ? null : value == 'true';
  }

  @override
  Future<void> setStringList(String key, List<String> value) =>
      setString(key, jsonEncode(value));

  @override
  Future<List<String>?> getStringList(String key) async {
    final value = await getString(key);
    if (value == null) return null;
    try {
      return List<String>.from(jsonDecode(value) as List);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> remove(String key) async => _storage.removeItem('$prefix$key');

  @override
  Future<void> clear() async {
    for (final key in _ownKeys.toList()) {
      _storage.removeItem(key);
    }
  }

  @override
  Future<bool> containsKey(String key) async =>
      _storage.getItem('$prefix$key') != null;

  @override
  Future<Set<String>> getKeys() async =>
      _ownKeys.map((k) => k.substring(prefix.length)).toSet();

  @override
  Future<Map<String, dynamic>> getAll() async => {
    for (final key in _ownKeys)
      key.substring(prefix.length): _storage.getItem(key),
  };
}

/// localStorage-backed "secure" storage. Browsers offer no at-rest
/// encryption for localStorage, so [isEncryptionAvailable] is false.
/// A [SecureStorageService] that does not encrypt, and says so.
///
/// Prefer [WebSecureStorage], which encrypts with the browser's Web Crypto.
/// This one is for the cases that cannot: a page served over plain http, where
/// `crypto.subtle` does not exist, or a test that wants to read what was
/// written.
class LocalSecureStorageService extends LocalStorageService
    implements SecureStorageService {
  LocalSecureStorageService({super.prefix = 'dnn.secure.'});

  @override
  Future<bool> isEncryptionAvailable() async => false;
}
