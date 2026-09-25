/// Local Storage Service Interface
///
/// Abstraction for key-value storage with platform-specific implementations.

library;

import 'dart:async';
import 'dart:convert';

/// Storage exception
class StorageException implements Exception {
  final String message;
  final dynamic originalError;
  final StackTrace? stackTrace;

  StorageException(this.message, {this.originalError, this.stackTrace});

  @override
  String toString() => 'StorageException: $message';
}

/// Thrown when encrypting or decrypting fails.
///
/// Lives here rather than beside one implementation because every secure
/// backend - the Keychain, EncryptedSharedPreferences, the browser's Web
/// Crypto - reports failures through it.
class EncryptionException extends StorageException {
  EncryptionException(super.message, {dynamic error, super.stackTrace})
    : super(originalError: error);
}

/// Base storage service interface
abstract class StorageService {
  /// Set a string value
  Future<void> setString(String key, String value);

  /// Get a string value
  Future<String?> getString(String key);

  /// Set an integer value
  Future<void> setInt(String key, int value);

  /// Get an integer value
  Future<int?> getInt(String key);

  /// Set a double value
  Future<void> setDouble(String key, double value);

  /// Get a double value
  Future<double?> getDouble(String key);

  /// Set a boolean value
  Future<void> setBool(String key, bool value);

  /// Get a boolean value
  Future<bool?> getBool(String key);

  /// Set a list of strings
  Future<void> setStringList(String key, List<String> value);

  /// Get a list of strings
  Future<List<String>?> getStringList(String key);

  /// Remove a key
  Future<void> remove(String key);

  /// Remove all keys
  Future<void> clear();

  /// Check if key exists
  Future<bool> containsKey(String key);

  /// Get all keys
  Future<Set<String>> getKeys();

  /// Get all entries (for debugging/export)
  Future<Map<String, dynamic>> getAll();
}

/// Secure storage service (for sensitive data)
/// Data is encrypted at rest
abstract class SecureStorageService implements StorageService {
  /// Indicates if encryption is available
  Future<bool> isEncryptionAvailable();
}

/// Storage implementation metadata
class StorageImplementation {
  final String name; // 'shared_preferences', 'keychain', etc.
  final String version; // Implementation version
  final String platform; // 'android', 'ios', 'web'
  final bool supportsEncryption;
  final String? encryptionMethod; // 'AES-256', 'RSA', 'none', etc.

  StorageImplementation({
    required this.name,
    required this.version,
    required this.platform,
    this.supportsEncryption = false,
    this.encryptionMethod,
  });

  @override
  String toString() =>
      '$name v$version ($platform${supportsEncryption ? ', encrypted' : ''})';
}

/// Mixin for default implementations of compound types
mixin StorageTypeConversion implements StorageService {
  /// Convert int to string and store
  @override
  Future<void> setInt(String key, int value) async {
    await setString(key, value.toString());
  }

  /// Get string and convert to int
  @override
  Future<int?> getInt(String key) async {
    final value = await getString(key);
    if (value == null) return null;
    try {
      return int.parse(value);
    } catch (e) {
      return null;
    }
  }

  /// Convert double to string and store
  @override
  Future<void> setDouble(String key, double value) async {
    await setString(key, value.toString());
  }

  /// Get string and convert to double
  @override
  Future<double?> getDouble(String key) async {
    final value = await getString(key);
    if (value == null) return null;
    try {
      return double.parse(value);
    } catch (e) {
      return null;
    }
  }

  /// Convert bool to string and store
  @override
  Future<void> setBool(String key, bool value) async {
    await setString(key, value ? 'true' : 'false');
  }

  /// Get string and convert to bool
  @override
  Future<bool?> getBool(String key) async {
    final value = await getString(key);
    if (value == null) return null;
    return value.toLowerCase() == 'true';
  }

  /// Convert list to JSON string and store
  @override
  Future<void> setStringList(String key, List<String> value) async {
    await setString(key, jsonEncode(value));
  }

  /// Get JSON string and convert to list
  @override
  Future<List<String>?> getStringList(String key) async {
    final value = await getString(key);
    if (value == null) return null;
    try {
      return List<String>.from(jsonDecode(value) as List);
    } catch (e) {
      return null;
    }
  }
}
