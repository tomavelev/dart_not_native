@TestOn('browser')
/// Tests for web secure storage, run in a real browser against the real Web
/// Crypto implementation - no fakes.
///
/// Run with: flutter test --platform chrome
library;

import 'dart:convert';

import 'package:dart_not_native/storage/storage_service.dart';
import 'package:dart_not_native/web_ui/secure_local_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

void main() {
  late WebSecureStorage storage;

  setUp(() async {
    // A prefix per test, so one test cannot read another's values - and a key
    // name per test, since the key is shared by name across stores and a
    // rotation in one test would otherwise reach the next.
    final unique = 'test.${DateTime.now().microsecondsSinceEpoch}';
    storage = WebSecureStorage(prefix: '$unique.', keyName: unique);
  });

  tearDown(() async => storage.clear());

  test('the browser will encrypt here', () async {
    // The test server serves localhost, which is a secure context.
    expect(await storage.isEncryptionAvailable(), isTrue);
  });

  group('round trips', () {
    test('a value comes back as it went in', () async {
      await storage.setString('token', 'secret-value');

      expect(await storage.getString('token'), 'secret-value');
    });

    test('so do unicode and empty strings', () async {
      await storage.setString('unicode', 'naïve 🔐 日本語');
      await storage.setString('empty', '');

      expect(await storage.getString('unicode'), 'naïve 🔐 日本語');
      expect(await storage.getString('empty'), '');
    });

    test('and the typed values built on top of strings', () async {
      await storage.setInt('attempts', 3);
      await storage.setBool('biometrics', true);
      await storage.setStringList('scopes', ['read', 'write']);

      expect(await storage.getInt('attempts'), 3);
      expect(await storage.getBool('biometrics'), isTrue);
      expect(await storage.getStringList('scopes'), ['read', 'write']);
    });

    test('a key that was never written reads as null', () async {
      expect(await storage.getString('missing'), isNull);
    });

    test('a value written twice keeps the second', () async {
      await storage.setString('k', 'first');
      await storage.setString('k', 'second');

      expect(await storage.getString('k'), 'second');
    });
  });

  group('what is actually stored', () {
    test('is not the plaintext', () async {
      await storage.setString('token', 'secret-value');

      final raw = web.window.localStorage.getItem('${storage.prefix}token')!;
      expect(raw, isNot(contains('secret-value')));
      expect(raw, isNot(contains(base64Encode(utf8.encode('secret-value')))),
          reason: 'nor merely encoded');
    });

    test('carries a fresh IV per write, so equal values differ', () async {
      await storage.setString('a', 'same value');
      await storage.setString('b', 'same value');

      final first = web.window.localStorage.getItem('${storage.prefix}a')!;
      final second = web.window.localStorage.getItem('${storage.prefix}b')!;
      expect(first, isNot(second),
          reason: 'an IV reused with one key would break AES-GCM');
      expect(await storage.getString('a'), await storage.getString('b'));
    });
  });

  group('tampering', () {
    test('a changed ciphertext is refused, not returned', () async {
      await storage.setString('token', 'secret-value');
      final raw = web.window.localStorage.getItem('${storage.prefix}token')!;
      // The ciphertext is the last field whatever the stored shape - the key
      // version and IV come before it.
      final parts = raw.split(':');
      final bytes = base64Decode(parts.last);
      bytes[0] = bytes[0] ^ 0xff;
      parts[parts.length - 1] = base64Encode(bytes);
      web.window.localStorage
          .setItem('${storage.prefix}token', parts.join(':'));

      expect(
        storage.getString('token'),
        throwsA(isA<EncryptionException>()),
        reason: 'AES-GCM authenticates as well as encrypts',
      );
    });

    test('a value that is not in the stored shape is refused', () async {
      web.window.localStorage.setItem('${storage.prefix}token', 'nonsense');

      expect(storage.getString('token'), throwsA(isA<EncryptionException>()));
    });
  });

  group('key management', () {
    test('keys and containsKey see only this store', () async {
      await storage.setString('a', '1');
      await storage.setString('b', '2');

      expect(await storage.getKeys(), {'a', 'b'});
      expect(await storage.containsKey('a'), isTrue);
      expect(await storage.containsKey('nope'), isFalse);
    });

    test('remove takes one, clear takes the rest', () async {
      await storage.setString('a', '1');
      await storage.setString('b', '2');

      await storage.remove('a');
      expect(await storage.getKeys(), {'b'});

      await storage.clear();
      expect(await storage.getKeys(), isEmpty);
    });

    test('getAll decrypts everything it holds', () async {
      await storage.setString('a', 'one');
      await storage.setString('b', 'two');

      expect(await storage.getAll(), {'a': 'one', 'b': 'two'});
    });

    test('a second instance reads what the first wrote', () async {
      // The key is generated once and kept in the browser, so a later page
      // load - a new instance here - can still read the values.
      await storage.setString('token', 'secret-value');

      final reopened =
          WebSecureStorage(prefix: storage.prefix, keyName: storage.keyName);

      expect(await reopened.getString('token'), 'secret-value');
    });

    test('a stored value records which key wrote it', () async {
      await storage.setString('token', 'secret-value');

      // Without this a rotated key would make every older value unreadable
      // *and* undiagnosable: the failure looks exactly like tampering.
      final raw = web.window.localStorage.getItem('${storage.prefix}token')!;
      expect(raw.split(':').first, 'k1');
    });

    test('a value from before versions were recorded still reads', () async {
      // The two-field shape the store used to write. Its key is the first one,
      // which is where it still lives, so nothing has to be migrated.
      await storage.setString('token', 'secret-value');
      final raw = web.window.localStorage.getItem('${storage.prefix}token')!;
      final parts = raw.split(':');
      web.window.localStorage.setItem(
        '${storage.prefix}token',
        '${parts[1]}:${parts[2]}',
      );

      expect(await storage.getString('token'), 'secret-value');
    });
  });

  group('rotating the key', () {
    test('values survive, and are re-encrypted under the new key', () async {
      await storage.setString('token', 'secret-value');
      await storage.setString('other', 'also secret');
      final before = web.window.localStorage.getItem('${storage.prefix}token')!;

      final version = await storage.rotateKey();

      expect(version, 2);
      expect(await storage.getString('token'), 'secret-value');
      expect(await storage.getString('other'), 'also secret');
      final after = web.window.localStorage.getItem('${storage.prefix}token')!;
      expect(after.split(':').first, 'k2');
      expect(after, isNot(before), reason: 'encrypted again, under the new key');
    });

    test('a later instance reads what a rotation left behind', () async {
      await storage.setString('token', 'secret-value');
      await storage.rotateKey();

      // The new version is recorded in the browser, not just in this object.
      final reopened =
          WebSecureStorage(prefix: storage.prefix, keyName: storage.keyName);

      expect(await reopened.getString('token'), 'secret-value');
    });

    test('rotating twice keeps working', () async {
      await storage.setString('token', 'secret-value');

      expect(await storage.rotateKey(), 2);
      expect(await storage.rotateKey(), 3);
      expect(await storage.getString('token'), 'secret-value');
    });

    test('a value left on the old key after a rotation says so', () async {
      await storage.setString('token', 'secret-value');
      final stale = web.window.localStorage.getItem('${storage.prefix}token')!;
      await storage.rotateKey();
      // As if the re-encryption had been interrupted before reaching this one
      // *and* the old key were already gone - the worst case the ordering in
      // rotateKey exists to avoid.
      web.window.localStorage.setItem('${storage.prefix}token', stale);

      // Not "tampered with": the value names a key, and the message says which.
      await expectLater(
        storage.getString('token'),
        throwsA(
          isA<EncryptionException>().having(
            (e) => e.toString(),
            'message',
            contains('v1'),
          ),
        ),
      );
    });

    test('an empty store rotates without complaint', () async {
      expect(await storage.rotateKey(), 2);
      await storage.setString('token', 'after');
      expect(await storage.getString('token'), 'after');
    });
  });

  group('more key management', () {
    test('two stores with different prefixes do not collide', () async {
      // Same key, different namespace - which is the point of the prefix.
      final other = WebSecureStorage(
        prefix: '${storage.prefix}other.',
        keyName: storage.keyName,
      );
      await storage.setString('token', 'mine');
      await other.setString('token', 'theirs');

      expect(await storage.getString('token'), 'mine');
      expect(await other.getString('token'), 'theirs');
      await other.clear();
    });
  });
}
