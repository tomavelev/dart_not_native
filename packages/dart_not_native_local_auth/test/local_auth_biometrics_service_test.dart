/// Tests for [LocalAuthBiometricsService] against a fake `local_auth` platform.
///
/// The fake replaces `LocalAuthPlatform.instance`, so these run the real
/// `LocalAuthentication` and pin how the dart_not_native contract maps onto
/// it: which options reach the platform, and how its answers and exceptions
/// come back.
library;

import 'package:dart_not_native_local_auth/dart_not_native_local_auth.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth_platform_interface/local_auth_platform_interface.dart'
    as la;
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePlatform extends la.LocalAuthPlatform
    with MockPlatformInterfaceMixin {
  bool hardware = true;
  List<la.BiometricType> enrolled = const [];
  Object? authenticateAnswer = true;
  Object? queryError;
  la.AuthenticationOptions? lastOptions;
  String? lastReason;
  int stops = 0;

  Future<T> _query<T>(T value) async {
    if (queryError != null) throw queryError!;
    return value;
  }

  @override
  Future<bool> authenticate({
    required String localizedReason,
    required Iterable<la.AuthMessages> authMessages,
    la.AuthenticationOptions options = const la.AuthenticationOptions(),
  }) async {
    lastReason = localizedReason;
    lastOptions = options;
    final answer = authenticateAnswer;
    if (answer is bool) return answer;
    throw answer!;
  }

  @override
  Future<bool> deviceSupportsBiometrics() => _query(hardware);

  @override
  Future<List<la.BiometricType>> getEnrolledBiometrics() => _query(enrolled);

  @override
  Future<bool> isDeviceSupported() => _query(true);

  @override
  Future<bool> stopAuthentication() async {
    stops++;
    return true;
  }
}

void main() {
  late _FakePlatform platform;
  late BiometricsService service;

  setUp(() {
    platform = _FakePlatform();
    la.LocalAuthPlatform.instance = platform;
    service = LocalAuthBiometricsService();
  });

  group('queries', () {
    test('iOS modalities map to the contract types', () async {
      platform.enrolled = [la.BiometricType.face, la.BiometricType.fingerprint];
      expect(await service.getAvailableBiometrics(), [
        BiometricType.faceRecognition,
        BiometricType.fingerprint,
      ]);
    });

    test('Android strength classes collapse to one unknown', () async {
      platform.enrolled = [la.BiometricType.strong, la.BiometricType.weak];
      expect(await service.getAvailableBiometrics(), [BiometricType.unknown]);
    });

    test('hardware without enrolment supports but cannot check', () async {
      platform.hardware = true;
      platform.enrolled = const [];
      expect(await service.deviceSupportsBiometrics(), isTrue);
      expect(await service.areBiometricsEnrolled(), isFalse);
      expect(await service.canCheckBiometrics(), isFalse);
    });

    test('hardware with enrolment can check', () async {
      platform.enrolled = [la.BiometricType.fingerprint];
      expect(await service.areBiometricsEnrolled(), isTrue);
      expect(await service.canCheckBiometrics(), isTrue);
    });

    test('no hardware cannot check', () async {
      platform.hardware = false;
      platform.enrolled = [la.BiometricType.fingerprint];
      expect(await service.canCheckBiometrics(), isFalse);
    });

    test('platform errors answer no instead of throwing', () async {
      platform.queryError = PlatformException(code: 'boom');
      expect(await service.getAvailableBiometrics(), isEmpty);
      expect(await service.deviceSupportsBiometrics(), isFalse);
      expect(await service.canCheckBiometrics(), isFalse);
    });

    test('a missing plugin still throws', () async {
      platform.queryError = MissingPluginException();
      expect(
        service.deviceSupportsBiometrics(),
        throwsA(isA<MissingPluginException>()),
      );
    });
  });

  group('authenticate', () {
    test('passes the options through, biometrics only', () async {
      final result = await service.authenticate(
        BiometricOptions(
          reason: 'Unlock',
          stickyAuth: true,
          sensitiveTransaction: false,
        ),
      );

      expect(result.authenticated, isTrue);
      expect(platform.lastReason, 'Unlock');
      expect(platform.lastOptions!.biometricOnly, isTrue);
      expect(platform.lastOptions!.stickyAuth, isTrue);
      expect(platform.lastOptions!.sensitiveTransaction, isFalse);
    });

    test('a false answer is a failure', () async {
      platform.authenticateAnswer = false;
      final result = await service.authenticate(
        BiometricOptions(reason: 'Unlock'),
      );
      expect(result.authenticated, isFalse);
      expect(result.errorMessage, 'Authentication failed');
    });

    test('a local_auth exception carries its code', () async {
      platform.authenticateAnswer = const la.LocalAuthException(
        code: la.LocalAuthExceptionCode.userCanceled,
        description: 'Cancelled by the user',
      );
      final result = await service.authenticate(
        BiometricOptions(reason: 'Unlock'),
      );
      expect(result.authenticated, isFalse);
      expect(result.errorCode, 'userCanceled');
      expect(result.errorMessage, 'Cancelled by the user');
    });

    test('an exception without a description falls back to the code', () async {
      platform.authenticateAnswer = const la.LocalAuthException(
        code: la.LocalAuthExceptionCode.biometricLockout,
      );
      final result = await service.authenticate(
        BiometricOptions(reason: 'Unlock'),
      );
      expect(result.errorCode, 'biometricLockout');
      expect(result.errorMessage, 'biometricLockout');
    });

    test('a platform exception is a failure too', () async {
      platform.authenticateAnswer = PlatformException(
        code: 'NotAvailable',
        message: 'No activity',
      );
      final result = await service.authenticate(
        BiometricOptions(reason: 'Unlock'),
      );
      expect(result.errorCode, 'NotAvailable');
      expect(result.errorMessage, 'No activity');
    });
  });

  test('stopAuthentication reaches the platform', () async {
    await service.stopAuthentication();
    expect(platform.stops, 1);
  });
}
