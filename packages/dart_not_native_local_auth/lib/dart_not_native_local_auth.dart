/// [BiometricsService] for Android and iOS, backed by the `local_auth` plugin.
///
/// ```dart
/// import 'package:dart_not_native_local_auth/dart_not_native_local_auth.dart';
///
/// final BiometricsService biometrics = LocalAuthBiometricsService();
/// final result = await biometrics.authenticate(
///   BiometricOptions(reason: 'Unlock your account'),
/// );
/// ```
///
/// Host requirements come from `local_auth`: on Android the activity must be a
/// `FlutterFragmentActivity`, and on iOS `Info.plist` needs
/// `NSFaceIDUsageDescription`.
library;

import 'package:dart_not_native/biometrics/biometrics_service.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:local_auth/local_auth.dart' as la;

export 'package:dart_not_native/biometrics/biometrics_service.dart';

/// Implements the dart_not_native biometrics contract on `local_auth`.
///
/// Platform errors from the queries answer "no" rather than throw, as the
/// contract promises; a missing plugin still throws, since that is a build
/// mistake and not a device state.
class LocalAuthBiometricsService implements BiometricsService {
  LocalAuthBiometricsService({la.LocalAuthentication? localAuth})
    : _auth = localAuth ?? la.LocalAuthentication();

  final la.LocalAuthentication _auth;

  /// The enrolled biometrics.
  ///
  /// Android reports only a strength class, not a modality, so there every
  /// enrolled biometric comes back as [BiometricType.unknown]; iOS names face
  /// or fingerprint.
  @override
  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      final enrolled = await _auth.getAvailableBiometrics();
      return enrolled.map(_toBiometricType).toSet().toList();
    } on PlatformException {
      return const [];
    } on la.LocalAuthException {
      return const [];
    }
  }

  /// Whether a biometric check can happen now: hardware present and something
  /// enrolled.
  @override
  Future<bool> canCheckBiometrics() async =>
      await deviceSupportsBiometrics() && await areBiometricsEnrolled();

  /// Whether the device has biometric hardware, enrolled or not.
  @override
  Future<bool> deviceSupportsBiometrics() =>
      _answer(() => _auth.canCheckBiometrics);

  @override
  Future<bool> areBiometricsEnrolled() async =>
      (await getAvailableBiometrics()).isNotEmpty;

  /// Biometrics only - the device PIN is not offered as a fallback, since
  /// this is the biometrics service.
  ///
  /// `local_auth` shows no error dialogs of its own since 3.0, so
  /// [BiometricOptions.useErrorDialogs] has no effect; every failure comes
  /// back in the result, with [BiometricResult.errorCode] set to the
  /// [la.LocalAuthExceptionCode] name (`userCanceled`, `biometricLockout`...).
  @override
  Future<BiometricResult> authenticate(BiometricOptions options) async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: options.reason,
        biometricOnly: true,
        sensitiveTransaction: options.sensitiveTransaction,
        persistAcrossBackgrounding: options.stickyAuth,
      );
      return ok
          ? BiometricResult.success()
          : BiometricResult.failure('Authentication failed');
    } on la.LocalAuthException catch (e) {
      return BiometricResult.failure(
        e.description ?? e.code.name,
        code: e.code.name,
      );
    } on PlatformException catch (e) {
      return BiometricResult.failure(e.message ?? e.code, code: e.code);
    }
  }

  @override
  Future<void> stopAuthentication() async {
    await _auth.stopAuthentication();
  }

  Future<bool> _answer(Future<bool> Function() query) async {
    try {
      return await query();
    } on PlatformException {
      return false;
    } on la.LocalAuthException {
      return false;
    }
  }

  static BiometricType _toBiometricType(la.BiometricType type) =>
      switch (type) {
        la.BiometricType.face => BiometricType.faceRecognition,
        la.BiometricType.fingerprint => BiometricType.fingerprint,
        la.BiometricType.iris => BiometricType.iris,
        la.BiometricType.strong ||
        la.BiometricType.weak => BiometricType.unknown,
      };
}
