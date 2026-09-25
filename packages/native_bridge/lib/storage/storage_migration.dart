/// Bringing stored data forward when an app's shape changes.
///
/// A key an app renamed, a value whose format changed, a setting that split in
/// two: the data on a user's device was written by the version they had before,
/// and nothing in [StorageService] said what to do about it. This is the small
/// piece that does - a list of steps, each numbered, each run at most once.
///
/// ```dart
/// await storage.migrate([
///   StorageMigration(1, (s) async {
///     final old = await s.getString('user_name');
///     if (old != null) {
///       await s.setString('profile.name', old);
///       await s.remove('user_name');
///     }
///   }),
/// ]);
/// ```
///
/// It works on any store, including the encrypted one, because it only uses
/// the contract every store implements.
library;

import 'storage_service.dart';

/// One step that brings stored data up to [version].
///
/// [version]s are the app's own numbering, starting at 1 and rising. A store
/// that has never been migrated is at 0, so every step runs on a fresh install
/// too - which is what makes a migration the only place a key's shape is
/// decided, rather than the same logic living in both a migration and the
/// first-run path.
class StorageMigration {
  const StorageMigration(this.version, this.run);

  final int version;
  final Future<void> Function(StorageService storage) run;
}

/// Where the schema version is kept. An app that already uses this key can
/// pass another to [StorageMigrations.migrate].
const String defaultSchemaVersionKey = 'dnn.schema_version';

extension StorageMigrations on StorageService {
  /// Runs the migrations this store has not run yet, oldest first, and answers
  /// the version it is now at.
  ///
  /// The version is recorded after *each* step, not at the end: a run that is
  /// interrupted - the app is killed, the tab closes, a step throws - resumes
  /// at the step it failed on rather than replaying the ones that succeeded. A
  /// step that throws stops the run, with the store left at the last version
  /// that completed, and the error reaches the caller: an app that cannot
  /// migrate its data should hear about it rather than carry on against data it
  /// does not understand.
  ///
  /// Running it again when nothing is pending does nothing and touches nothing.
  Future<int> migrate(
    List<StorageMigration> migrations, {
    String versionKey = defaultSchemaVersionKey,
  }) async {
    final ordered = [...migrations]..sort((a, b) => a.version.compareTo(b.version));
    final versions = ordered.map((m) => m.version).toList();
    if (versions.toSet().length != versions.length) {
      throw ArgumentError.value(
        versions,
        'migrations',
        'two migrations share a version; each one must be numbered uniquely',
      );
    }
    if (versions.any((version) => version < 1)) {
      throw ArgumentError.value(
        versions,
        'migrations',
        'migration versions start at 1; 0 means "never migrated"',
      );
    }

    var current = await schemaVersion(versionKey: versionKey);
    for (final migration in ordered) {
      if (migration.version <= current) continue;
      await migration.run(this);
      await setInt(versionKey, migration.version);
      current = migration.version;
    }
    return current;
  }

  /// The version this store's data is at; 0 when it has never been migrated.
  Future<int> schemaVersion({
    String versionKey = defaultSchemaVersionKey,
  }) async =>
      await getInt(versionKey) ?? 0;
}
