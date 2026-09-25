/// Checks the documentation against the code, for the claims a machine can
/// check.
///
/// The docs drift. Twelve claims were corrected on 2026-09-24 alone - a
/// changelog describing CI lanes that had never run, a guide saying there were
/// no pixel goldens when there was one, a section listing four skipped tests
/// that had all been fixed, and paths pointing at files that had moved. Two of
/// those had been written earlier the same day.
///
/// Most of what a doc says is prose and stays a human's job. What is left is
/// small and worth pinning: a file a doc names should exist, an import it
/// shows should resolve, and the two places where a doc counts something the
/// suite can count for itself.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The markdown this checks: the repository's own docs, not its dependencies'.
List<File> docFiles() {
  final files = <File>[
    ...Directory(
      '.',
    ).listSync().whereType<File>().where((f) => f.path.endsWith('.md')),
    ...Directory(
      'packages/native_bridge',
    ).listSync().whereType<File>().where((f) => f.path.endsWith('.md')),
  ];
  for (final dir in ['maestro/native', 'maestro/web']) {
    final d = Directory(dir);
    if (d.existsSync()) {
      files.addAll(
        d.listSync().whereType<File>().where((f) => f.path.endsWith('.md')),
      );
    }
  }
  return files;
}

/// A backtick-quoted token in [text]: `like/this.dart`.
Iterable<String> quotedTokens(String text) =>
    RegExp(r'`([^`\s]+)`').allMatches(text).map((m) => m.group(1)!);

/// The directories a rooted path can start with - enough to tell a path from
/// a sentence, since prose says `setState` and never `lib/src/thing.dart`.
const roots = [
  'lib/',
  'test/',
  'packages/',
  'maestro/',
  'integration_test/',
  'tool/',
  'android/',
  'ios/',
  'web/',
  '.github/',
];

const fileExtensions = [
  '.dart',
  '.kt',
  '.swift',
  '.yaml',
  '.yml',
  '.json',
  '.sh',
  '.plist',
  '.md',
  '.gradle',
];

/// Whether [token] resolves to a real file from [doc]'s point of view.
///
/// Three ways, because the docs are written from three: the repository root,
/// the doc's own directory, and the package - a root-level doc discussing the
/// framework writes `lib/src/contrast.dart` and means the package's `lib`.
bool resolves(String token, File doc) =>
    File(token).existsSync() ||
    File('${doc.parent.path}/$token').existsSync() ||
    File('packages/native_bridge/$token').existsSync();

/// Imports a doc may show that do not exist yet, with the reason.
const plannedImports = {
  // INTEGRATION.md §"what would make this better" proposes a barrel that
  // conditionally exports the right set. It is a proposal, not a claim.
  'package:dart_not_native/dart_not_native.dart',
};

void main() {
  test('every repository path the docs name exists', () {
    final broken = <String>[];
    for (final doc in docFiles()) {
      for (final token in quotedTokens(doc.readAsStringSync())) {
        if (token.contains(RegExp(r'[*<>()]'))) continue;
        if (!roots.any(token.startsWith)) continue;
        if (!fileExtensions.any(token.endsWith)) continue;
        if (!resolves(token, doc)) broken.add('${doc.path}: `$token`');
      }
    }
    expect(
      broken,
      isEmpty,
      reason:
          'A doc names a file that is not there. Either the file moved and the '
          'doc did not, or it was deleted and the doc still describes it.',
    );
  });

  test('every package import the docs show resolves', () {
    final broken = <String>[];
    for (final doc in docFiles()) {
      for (final token in quotedTokens(doc.readAsStringSync())) {
        if (!token.startsWith('package:dart_not_native/')) continue;
        // Prose writes `package:dart_not_native/...` for "one of these", which
        // is an ellipsis rather than an import.
        if (!token.endsWith('.dart')) continue;
        if (plannedImports.contains(token)) continue;
        final path =
            'packages/native_bridge/lib/${token.split('/').skip(1).join('/')}';
        if (!File(path).existsSync()) broken.add('${doc.path}: `$token`');
      }
    }
    expect(
      broken,
      isEmpty,
      reason:
          'A doc shows an import that would not resolve. Add it to '
          '`plannedImports` with a reason if it is deliberately aspirational.',
    );
  });

  test('the suite has no skipped tests, which TESTING.md states', () {
    final skipped = <String>[];
    for (final dir in ['test', 'packages/native_bridge/test']) {
      for (final file in Directory(dir).listSync(recursive: true)) {
        if (file is! File || !file.path.endsWith('.dart')) continue;
        if (file.path.endsWith('docs_match_the_code_test.dart')) continue;
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (RegExp(r'\bskip:').hasMatch(lines[i])) {
            skipped.add('${file.path}:${i + 1}');
          }
        }
      }
    }
    expect(
      skipped,
      isEmpty,
      reason:
          'TESTING.md\'s "Skipped tests" section says there are none. A skip '
          'is fine - give it a `BUG:` reason and list it there, then this '
          'test needs updating too.',
    );
  });

  test('there is exactly one pixel golden, which TESTING.md states', () {
    final callers = <String>[];
    for (final dir in ['test', 'packages/native_bridge/test']) {
      for (final file in Directory(dir).listSync(recursive: true)) {
        if (file is! File || !file.path.endsWith('.dart')) continue;
        if (file.path.endsWith('docs_match_the_code_test.dart')) continue;
        if (file.readAsStringSync().contains('matchesGoldenFile(')) {
          callers.add(file.path);
        }
      }
    }
    expect(
      callers,
      ['test/gallery/counter_gallery_golden_test.dart'],
      reason:
          'TESTING.md says there is exactly one pixel golden and describes '
          'what it cannot see. A second one needs saying there, and needs to '
          'decide whether it too is compared with a tolerance.',
    );
  });
}
