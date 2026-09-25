/// Secure storage for the web target, encrypted with the browser's own crypto.
///
/// Values are encrypted with AES-GCM before they reach `localStorage`, under a
/// 256-bit key the browser generates and keeps in IndexedDB as a
/// **non-extractable** `CryptoKey`: script on the page can ask the browser to
/// encrypt and decrypt with it, but cannot read the key material out, so the
/// key cannot be copied off the machine.
///
/// ```dart
/// final storage = WebSecureStorage();
/// if (await storage.isEncryptionAvailable()) {
///   await storage.setString('token', token);
/// }
/// ```
///
/// **What this protects against, and what it does not.** An attacker with the
/// stored data but not the browser profile - a copied `localStorage` dump, a
/// backup, someone reading the file on disk - learns nothing. An attacker
/// running script on your origin, through XSS or a compromised dependency,
/// can ask the browser to decrypt exactly as your own code does. Browser-held
/// keys cannot solve that; keep secrets short-lived and scope them narrowly.
///
/// **It needs a secure context.** `crypto.subtle` is undefined on plain
/// `http://` (except `localhost`), so [isEncryptionAvailable] answers false
/// there and the writes refuse rather than silently storing plaintext.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../storage/storage_service.dart';

class WebSecureStorage extends SecureStorageService with StorageTypeConversion {
  /// Keys are stored under [prefix] so several apps on one origin do not
  /// clash, and [keyName] names this app's key inside the browser's key store.
  ///
  /// Two stores sharing a [keyName] share the *key* - the [prefix] only
  /// separates the values. That is usually what you want, and it is what makes
  /// [rotateKey] worth knowing about: rotating one of them re-encrypts only its
  /// own values and then removes the old key, which would leave the other
  /// store's values naming a key that is gone. Give stores that should rotate
  /// independently their own [keyName].
  WebSecureStorage({this.prefix = 'dnn.secure.', this.keyName = 'master'});

  final String prefix;
  final String keyName;

  static const _databaseName = 'dart_not_native_keys';
  static const _storeName = 'keys';

  /// The AES-GCM keys by version, fetched from IndexedDB or generated on first
  /// use. Older versions stay here so values written under them still read.
  final Map<int, Future<web.CryptoKey>> _keys = {};

  /// The version new writes use; null until read from the key store.
  Future<int>? _version;

  web.Storage get _storage => web.window.localStorage;

  /// Whether the browser will do the crypto: it exposes `crypto.subtle` only
  /// in a secure context (https, or localhost).
  @override
  Future<bool> isEncryptionAvailable() async =>
      web.window.has('crypto') && web.window.crypto.has('subtle');

  // ---------------------------------------------------------------------------
  // Reading and writing
  // ---------------------------------------------------------------------------

  @override
  Future<void> setString(String key, String value) async {
    if (!await isEncryptionAvailable()) {
      throw EncryptionException(
        'This browser will not encrypt: crypto.subtle needs a secure context '
        '(https, or localhost). Refusing to store a secret in the clear.',
      );
    }

    final version = await _currentVersion();
    final cryptoKey = await _keyOfVersion(version);
    // A fresh IV per write: reusing one with the same key destroys AES-GCM's
    // guarantees.
    final iv = _randomBytes(12);
    final params = _algorithm('AES-GCM')..['iv'] = iv.toJS;

    final encrypted = await web.window.crypto.subtle
        .encrypt(params, cryptoKey, Uint8List.fromList(utf8.encode(value)).toJS)
        .toDart;
    final cipher = (encrypted! as JSArrayBuffer).toDart.asUint8List();

    // Neither the IV nor the key version is a secret; both travel with the
    // value so a later read knows how it was written. Without the version a
    // rotated key would make every older value unreadable and undiagnosable -
    // the failure looks exactly like tampering.
    _storage.setItem(
      '$prefix$key',
      'k$version:${base64Encode(iv)}:${base64Encode(cipher)}',
    );
  }

  @override
  Future<String?> getString(String key) async {
    final stored = _storage.getItem('$prefix$key');
    if (stored == null) return null;

    final (version, iv, cipher) = _parse(key, stored);
    final cryptoKey = await _keyOfVersion(version);
    final params = _algorithm('AES-GCM')..['iv'] = iv.toJS;

    try {
      final decrypted = await web.window.crypto.subtle
          .decrypt(params, cryptoKey, cipher.toJS)
          .toDart;
      return utf8.decode((decrypted! as JSArrayBuffer).toDart.asUint8List());
    } catch (e) {
      // AES-GCM authenticates as well as encrypts, so a failure here means the
      // value was changed, or the key it names is gone. Both are worth
      // surfacing rather than returning null.
      throw EncryptionException(
        'Could not decrypt "$key": it was tampered with, or the key that wrote '
        'it (v$version) is no longer in the browser',
        error: e,
      );
    }
  }

  /// The key version, IV and ciphertext of a stored value.
  ///
  /// `k<version>:<iv>:<cipher>` is what [setString] writes. A two-part value is
  /// from before versions were recorded, and belongs to the first key - which
  /// is where that key still lives, so those values keep working untouched.
  (int, Uint8List, Uint8List) _parse(String key, String stored) {
    final parts = stored.split(':');
    if (parts.length == 2) {
      return (
        1,
        Uint8List.fromList(base64Decode(parts[0])),
        Uint8List.fromList(base64Decode(parts[1])),
      );
    }
    final version = parts.length == 3 && parts[0].startsWith('k')
        ? int.tryParse(parts[0].substring(1))
        : null;
    if (version == null) {
      throw EncryptionException('Stored value for "$key" is not readable');
    }
    return (
      version,
      Uint8List.fromList(base64Decode(parts[1])),
      Uint8List.fromList(base64Decode(parts[2])),
    );
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
      _ownKeys.map((key) => key.substring(prefix.length)).toSet();

  /// Every stored value, decrypted. Handy for debugging; not for logging.
  @override
  Future<Map<String, dynamic>> getAll() async {
    final all = <String, dynamic>{};
    for (final key in await getKeys()) {
      all[key] = await getString(key);
    }
    return all;
  }

  Iterable<String> get _ownKeys sync* {
    for (var i = 0; i < _storage.length; i++) {
      final key = _storage.key(i);
      if (key != null && key.startsWith(prefix)) yield key;
    }
  }

  // ---------------------------------------------------------------------------
  // The key
  // ---------------------------------------------------------------------------

  /// Where version [version]'s key lives in the browser's key store.
  ///
  /// The first version keeps the bare [keyName] it always had, so a store
  /// written before versions existed opens without migrating anything.
  String _slotOf(int version) => version == 1 ? keyName : '$keyName.v$version';

  /// The version new writes use.
  Future<int> _currentVersion() => _version ??= _readVersion();

  Future<int> _readVersion() async {
    final database = await _openDatabase();
    final stored = await _readEntry(database, '$keyName.version');
    final version = (stored as JSNumber?)?.toDartInt;
    return version ?? 1;
  }

  /// Version [version]'s key, generated on first use and kept for every use
  /// after. A version whose key is gone cannot be conjured back, so this
  /// generates only for the version that is current - anything older is a
  /// missing key, and [getString] says so.
  Future<web.CryptoKey> _keyOfVersion(int version) =>
      _keys[version] ??= _loadOrCreateKey(version);

  Future<web.CryptoKey> _loadOrCreateKey(int version) async {
    final database = await _openDatabase();
    final existing = await _readEntry(database, _slotOf(version));
    if (existing != null) return existing as web.CryptoKey;

    final current = await _currentVersion();
    if (version != current) {
      throw EncryptionException(
        'The key that wrote this value (v$version) is no longer in this '
        'browser; the value cannot be recovered',
      );
    }
    final key = await _generateKey();
    await _writeEntry(database, _slotOf(version), key);
    return key;
  }

  Future<web.CryptoKey> _generateKey() async {
    // Not extractable: the browser will use it, and will not hand it over.
    final generated = await web.window.crypto.subtle
        .generateKey(
          _algorithm('AES-GCM')..['length'] = 256.toJS,
          false,
          <JSString>['encrypt'.toJS, 'decrypt'.toJS].toJS,
        )
        .toDart;
    return generated! as web.CryptoKey;
  }

  /// Generates a new key and re-encrypts everything this store holds with it,
  /// answering the new version.
  ///
  /// For a secret that should stop being readable with the old key - a
  /// suspected leak, a scheduled rotation, a user signing out of a shared
  /// machine.
  ///
  /// Only *this* store's values move. Another store sharing this [keyName]
  /// keeps values naming the old key, which this removes - see the constructor.
  ///
  /// Ordered so that an interruption cannot lose data: the new key is written
  /// and made current first, then values are re-encrypted one at a time (each
  /// still naming the key that wrote it, so a half-finished run leaves every
  /// value readable), and only once they are all moved is the old key removed.
  /// Stop it anywhere and the store still opens; run it again and it finishes.
  Future<int> rotateKey() async {
    if (!await isEncryptionAvailable()) {
      throw EncryptionException(
        'This browser will not encrypt: crypto.subtle needs a secure context '
        '(https, or localhost). Refusing to rotate.',
      );
    }
    final database = await _openDatabase();
    final previous = await _currentVersion();
    final next = previous + 1;

    _keys[next] = Future.value(await _generateKey());
    await _writeEntry(database, _slotOf(next), await _keys[next]!);
    await _writeEntry(database, '$keyName.version', next.toJS);
    _version = Future.value(next);

    for (final key in await getKeys()) {
      final value = await getString(key);
      if (value != null) await setString(key, value);
    }

    // Nothing points at the old key any more.
    await _deleteEntry(database, _slotOf(previous));
    _keys.remove(previous);
    return next;
  }

  Future<web.IDBDatabase> _openDatabase() {
    final request = web.window.indexedDB.open(_databaseName, 1);
    final opened = Completer<web.IDBDatabase>();

    request.onupgradeneeded = ((web.Event _) {
      final database = request.result! as web.IDBDatabase;
      if (!database.objectStoreNames.contains(_storeName)) {
        database.createObjectStore(_storeName);
      }
    }).toJS;
    request.onsuccess = ((web.Event _) {
      opened.complete(request.result! as web.IDBDatabase);
    }).toJS;
    request.onerror = ((web.Event _) {
      opened.completeError(
        EncryptionException('Could not open the browser key store'),
      );
    }).toJS;

    return opened.future;
  }

  Future<JSAny?> _readEntry(web.IDBDatabase database, String slot) {
    final request = database
        .transaction(_storeName.toJS, 'readonly')
        .objectStore(_storeName)
        .get(slot.toJS);
    final read = Completer<JSAny?>();

    request.onsuccess = ((web.Event _) => read.complete(request.result)).toJS;
    request.onerror = ((web.Event _) => read.complete(null)).toJS;

    return read.future;
  }

  Future<void> _writeEntry(
    web.IDBDatabase database,
    String slot,
    JSAny value,
  ) {
    final request = database
        .transaction(_storeName.toJS, 'readwrite')
        .objectStore(_storeName)
        .put(value, slot.toJS);
    final written = Completer<void>();

    request.onsuccess = ((web.Event _) => written.complete()).toJS;
    request.onerror = ((web.Event _) {
      written.completeError(
        EncryptionException('Could not store the key in the browser'),
      );
    }).toJS;

    return written.future;
  }

  Future<void> _deleteEntry(web.IDBDatabase database, String slot) {
    final request = database
        .transaction(_storeName.toJS, 'readwrite')
        .objectStore(_storeName)
        .delete(slot.toJS);
    final deleted = Completer<void>();

    request.onsuccess = ((web.Event _) => deleted.complete()).toJS;
    // A key that will not delete is not worth failing a rotation over: the
    // values have already moved, and it is no longer named by any of them.
    request.onerror = ((web.Event _) => deleted.complete()).toJS;

    return deleted.future;
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// A JS `{name: ...}` for the Web Crypto calls to fill in.
  JSObject _algorithm(String name) => JSObject()..['name'] = name.toJS;

  Uint8List _randomBytes(int length) {
    final bytes = Uint8List(length);
    web.window.crypto.getRandomValues(bytes.toJS);
    return bytes;
  }
}
