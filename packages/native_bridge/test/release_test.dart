/// The version, in the three places a consumer reads it from.
///
/// A pub consumer reads the pubspec, a CocoaPods consumer the podspec, a Gradle
/// consumer the build file - so a version that moves in one and not the others
/// ships a package whose platform halves claim to be something else. Nothing
/// generates one from another, so this is what keeps them together.
///
/// The convention itself is in RELEASING.md.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `major.minor.patch`, optionally with a pre-release or build suffix.
final _semver = RegExp(r'^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$');

String _match(String path, RegExp pattern) {
  final source = File(path).readAsStringSync();
  final match = pattern.firstMatch(source);
  if (match == null) throw StateError('no version found in $path');
  return match.group(1)!;
}

void main() {
  final pubspec = _match('pubspec.yaml', RegExp(r'^version:\s*(\S+)', multiLine: true));

  test('the pubspec version is a library version, not an app one', () {
    // pub refuses an unparseable version before a test can run, so what is
    // worth asserting is the part it allows and a library should not have: the
    // `+1` build suffix the example app at the repository root carries. It
    // means nothing to a consumer and is not part of the tag.
    expect(pubspec, matches(_semver));
    expect(pubspec, isNot(contains('+')), reason: 'a build suffix is app-style');
  });

  test('the podspec agrees with it', () {
    final podspec = _match(
      'ios/dart_not_native.podspec',
      RegExp(r"s\.version\s*=\s*'([^']+)'"),
    );

    expect(podspec, pubspec, reason: 'a CocoaPods consumer reads this one');
  });

  test('the Android build file agrees with it', () {
    final gradle = _match(
      'android/build.gradle',
      RegExp(r'^version\s*=\s*"([^"]+)"', multiLine: true),
    );

    expect(gradle, pubspec, reason: 'a Gradle consumer reads this one');
  });

  group('the changelog', () {
    final headings = RegExp(r'^## (.+)$', multiLine: true)
        .allMatches(File('CHANGELOG.md').readAsStringSync())
        .map((m) => m.group(1)!.trim())
        .toList();

    test('has a section per release, newest first', () {
      expect(headings, isNotEmpty);
      final versions = headings.where((h) => h != 'Unreleased').toList();
      expect(versions, isNotEmpty);
      for (final version in versions) {
        expect(version, matches(_semver), reason: 'not a version heading');
      }

      // Descending, so the top of the file is the newest thing released.
      final sorted = [...versions]..sort(_compareVersions);
      expect(versions, sorted.reversed.toList());
    });

    test('documents the version being shipped', () {
      // Either this version is released and written up, or the work since the
      // last release is gathered under Unreleased - never a version in the
      // pubspec that the changelog has never heard of.
      expect(
        headings.first == 'Unreleased' || headings.first == pubspec,
        isTrue,
        reason: 'CHANGELOG.md starts with "${headings.first}", '
            'but the pubspec says $pubspec',
      );
    });
  });
}

int _compareVersions(String a, String b) {
  final left = a.split(RegExp(r'[.+-]')).map(int.tryParse).toList();
  final right = b.split(RegExp(r'[.+-]')).map(int.tryParse).toList();
  for (var i = 0; i < 3; i++) {
    final compared = (left[i] ?? 0).compareTo(right[i] ?? 0);
    if (compared != 0) return compared;
  }
  return 0;
}
