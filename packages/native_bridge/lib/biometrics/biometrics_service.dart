/// Biometrics Service
///
/// Fingerprint, face recognition, and other biometric authentication.
///
/// This file is only the contract, in pure Dart. The implementation comes from
/// an adapter package, so an app that never authenticates does not ship a
/// biometrics plugin:
///
/// - Android and iOS: `LocalAuthBiometricsService` from
///   `package:dart_not_native_local_auth`, backed by the `local_auth` plugin.
library;

import 'dart:async';

/// Biometric type available on device
enum BiometricType { fingerprint, faceRecognition, iris, unknown }

/// Biometric authentication result
class BiometricResult {
  final bool authenticated;
  final String? errorMessage;
  final String? errorCode;

  BiometricResult({
    required this.authenticated,
    this.errorMessage,
    this.errorCode,
  });

  factory BiometricResult.success() => BiometricResult(authenticated: true);

  factory BiometricResult.failure(String message, {String? code}) =>
      BiometricResult(
        authenticated: false,
        errorMessage: message,
        errorCode: code,
      );
}

/// Biometric authentication options
class BiometricOptions {
  final String reason;
  final bool stickyAuth;
  final bool useErrorDialogs;
  final bool sensitiveTransaction;

  BiometricOptions({
    required this.reason,
    this.stickyAuth = false,
    this.useErrorDialogs = true,
    this.sensitiveTransaction = false,
  });
}

/// Biometric service interface
abstract class BiometricsService {
  /// Get available biometric types on device
  Future<List<BiometricType>> getAvailableBiometrics();

  /// Check if device has any biometrics enrolled
  Future<bool> canCheckBiometrics();

  /// Check if device supports biometrics
  Future<bool> deviceSupportsBiometrics();

  /// Authenticate user with biometrics
  Future<BiometricResult> authenticate(BiometricOptions options);

  /// Stop ongoing authentication
  Future<void> stopAuthentication();

  /// Check if biometrics are enrolled
  Future<bool> areBiometricsEnrolled();
}

/// Biometric service with caching
class CachedBiometricsService implements BiometricsService {
  final BiometricsService _delegate;
  late List<BiometricType> _cachedBiometrics;
  late bool _cachedCanCheck;
  late bool _cachedSupports;
  bool _initialized = false;

  CachedBiometricsService(this._delegate);

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    _cachedBiometrics = await _delegate.getAvailableBiometrics();
    _cachedCanCheck = await _delegate.canCheckBiometrics();
    _cachedSupports = await _delegate.deviceSupportsBiometrics();
    _initialized = true;
  }

  @override
  Future<List<BiometricType>> getAvailableBiometrics() async {
    await _ensureInitialized();
    return _cachedBiometrics;
  }

  @override
  Future<bool> canCheckBiometrics() async {
    await _ensureInitialized();
    return _cachedCanCheck;
  }

  @override
  Future<bool> deviceSupportsBiometrics() async {
    await _ensureInitialized();
    return _cachedSupports;
  }

  @override
  Future<BiometricResult> authenticate(BiometricOptions options) =>
      _delegate.authenticate(options);

  @override
  Future<void> stopAuthentication() => _delegate.stopAuthentication();

  @override
  Future<bool> areBiometricsEnrolled() => _delegate.areBiometricsEnrolled();
}
