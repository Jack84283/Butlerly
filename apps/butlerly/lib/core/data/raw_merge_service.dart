import 'dart:io';

import 'package:butlerly/core/data/atomic_evidence_publication.dart';
import 'package:butlerly/core/data/evidence_path_safety.dart';
import 'package:butlerly/core/data/raw_backup_archive.dart';
import 'package:butlerly/core/data/raw_backup_service.dart';
import 'package:butlerly/core/data/raw_restore_service.dart';
import 'package:butlerly/core/data/storage_space_preflight.dart';
import 'package:butlerly/core/database/local_database.dart';
import 'package:butlerly/core/evidence/evidence_mutation_lock.dart';
import 'package:butlerly_database/butlerly_database.dart' show sha256FileRange;
import 'package:path/path.dart' as path;
import 'package:sqflite_common/sqlite_api.dart';

typedef _DatabaseRevision = ({
  int totalChanges,
  int dataVersion,
  int schemaVersion,
});

/// Non-destructive, local-wins import from a raw SQLite backup.
///
/// A disposable staging database validates the local-wins union first.
/// Missing rows are then inserted through an exclusive transaction on the
/// existing live SQLite inode, not through physical database replacement.
/// Existing local rows win identity conflicts; tombstones protect intentional
/// deletions. Analysis rules are never evaluated.
final class RawMergeService {
  RawMergeService(this.database, this.backup, this.restores);

  final LocalDatabase database;
  final RawBackupService backup;
  final RawRestoreService restores;

  static final _safeName = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');
  static const _privateTables = <String>{
    'restore_context',
    'restore_commits',
    'sqlite_sequence',
    'entity_tombstones',
  };

  /// Merge imports rows transactionally into the existing SQLite file.
  /// Replacing the database pathname would strand idle external SQLite
  /// connections on an obsolete inode, allowing later writes to disappear.
  Future<RawBackupInspection> restoreMerge(
    File encryptedArchive, {
    required String password,
    Future<void> Function(String stage)? onStage,
  }) => EvidenceMutationLock.runExclusive(() async {
    final liveFile = File(database.persistenceDatabase.path);
    final parent = liveFile.parent;
    final liveEvidence = await backup.data.evidenceDirectory();
    await rejectSymlinkedPath(parent.path);
    await rejectSymlinkedPath(liveEvidence.path);
    for (final suffix in const ['', '.tmp']) {
      final marker = path.join(parent.path, '.raw-restore-journal.json$suffix');
      if (await FileSystemEntity.type(marker, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw StateError('Recover the interrupted Replace before Merge.');
      }
    }
    final operationId = DateTime.now().microsecondsSinceEpoch.toString();
    final working = Directory(
      path.join(parent.path, '.raw-merge-work-$operationId'),
    );
    final staging = Directory(path.join(working.path, 'staged'));
    final createdEvidence = <({File file, String hash})>[];
    var committed = false;
    await StorageSpacePreflight.requireAvailable(
      parent,
      stagingBytes: StorageSpacePreflight.restoreStagingBytes(
        archiveBytes: await encryptedArchive.length(),
        databaseBytes: await liveFile.length(),
        evidenceBytes: await StorageSpacePreflight.evidenceBytes(liveEvidence),
      ),
    );
    await working.create(recursive: true);
    try {
      await onStage?.call('archive extraction');
      final inspection = await backup.prepareRestore(
        encryptedArchive,
        password: password,
        stagingDirectory: staging,
      );
      await restores.upgradeStagedSqlite(
        File(path.join(staging.path, 'butlerly.db')),
      );
      final sourceRevision = await _liveDatabaseRevision();
      final merged = await _mergeIntoStaging(staging, inspection);
      await onStage?.call('attachment staging');
      // New attachment bytes must be durable before the SQLite transaction
      // commits any reference to them; never replace local attachment bytes.
      await _publishNewEvidence(
        Directory(path.join(staging.path, 'evidence')),
        liveEvidence,
        working,
        createdEvidence,
        onStage: onStage,
      );
      await onStage?.call('before transactional merge');
      final current = database.database;
      final stagedPath = path.join(staging.path, 'butlerly.db');
      final quoted = stagedPath.replaceAll("'", "''");
      await current.execute("ATTACH DATABASE '$quoted' AS merge_stage");
      try {
        await current.transaction((tx) async {
          // BEGIN EXCLUSIVE is enforced by SQLite itself even against idle,
          // independently opened connections which resume writing later.
          // Validate revision *inside* that transaction.
          if (sourceRevision != await _liveDatabaseRevision(tx)) {
            throw StateError(
              'Live database changed during Merge; retry with a new backup. '
              'No local data was replaced.',
            );
          }
          await onStage?.call('transactional merge write lock acquired');
          await _importStagedRows(tx);
          await onStage?.call('original SQLite preserved');
          final violations = await tx.rawQuery('PRAGMA foreign_key_check');
          if (violations.isNotEmpty) {
            throw const FormatException(
              'Merged SQLite contains unresolved foreign-key references.',
            );
          }
        }, exclusive: true);
        committed = true;
      } finally {
        // A failed post-commit DETACH must never report a committed Merge as
        // unsuccessful and encourage a second Restore.
        try {
          await current.execute('DETACH DATABASE merge_stage');
        } catch (_) {
          if (!committed) rethrow;
        }
      }
      return RawBackupInspection(
        createdAtUtc: merged.createdAtUtc,
        sqliteBytes: merged.sqliteBytes,
        recordCount: merged.recordCount,
        // Only newly published attachments count as restored by Merge.
        attachmentCount: createdEvidence.length,
        missingAttachmentCount: merged.missingAttachmentCount,
        keptLocalRowCount: merged.keptLocalRowCount,
      );
    } catch (error, stack) {
      // Files already published under their canonical evidence names are
      // immutable. Do not delete them after a failed DB transaction: an
      // independent SQLite writer could have referenced one meanwhile.
      // Unreferenced files are safer than deleting an externally referenced
      // receipt; a later Merge can reuse these exact verified bytes.
      Error.throwWithStackTrace(error, stack);
    } finally {
      try {
        await rejectEvidenceTree(working);
        if (await working.exists()) await working.delete(recursive: true);
      } catch (_) {
        // Crash or cleanup failure: later startup reclaims this stage.
      }
    }
  });

  Future<void> _publishNewEvidence(
    Directory staged,
    Directory live,
    Directory working,
    List<({File file, String hash})> created, {
    Future<void> Function(String stage)? onStage,
  }) async {
    await rejectEvidenceTree(staged);
    await rejectEvidenceTree(live);
    if (!await live.exists()) await live.create(recursive: true);
    await for (final entry in staged.list(
      recursive: true,
      followLinks: false,
    )) {
      await rejectEvidenceLink(entry);
      if (entry is! File) continue;
      final relative = path.relative(entry.path, from: staged.path);
      final safe = await validateEvidencePath(live, relative);
      final destination = File(path.join(live.path, safe));
      final digest = await sha256FileRange(entry);
      final existing = await FileSystemEntity.type(
        destination.path,
        followLinks: false,
      );
      if (existing != FileSystemEntityType.notFound) {
        if (existing != FileSystemEntityType.file ||
            await sha256FileRange(destination) != digest) {
          throw const FormatException(
            'Local evidence changed during Merge; no data was replaced.',
          );
        }
        continue;
      }
      await destination.parent.create(recursive: true);
      final temporary = File(
        path.join(working.path, '.new-evidence-${created.length}'),
      );
      await rejectSymlinkedPath(temporary.path);
      try {
        await entry.copy(temporary.path);
        if (await sha256FileRange(temporary) != digest) {
          throw StateError('New evidence copy failed verification.');
        }

        // The staged inode is fully written and hash-verified *before*
        // publication. Hard-link creation is atomic and fails if the name
        // exists; unlike exclusive-create-then-openWrite, a process kill can
        // never expose a partial final evidence file.
        await onStage?.call('before atomic evidence publish');
        try {
          await AtomicEvidencePublication.publishNoReplace(
            temporary,
            destination,
          );
        } on FileSystemException {
          // An identical competing publication is safe to reuse. A different
          // local file is a collision, not permission to overwrite it.
          final type = await FileSystemEntity.type(
            destination.path,
            followLinks: false,
          );
          if (type == FileSystemEntityType.file &&
              await sha256FileRange(destination) == digest) {
            continue;
          }
          if (type != FileSystemEntityType.notFound) {
            throw const FormatException(
              'Local evidence appeared during Merge; no file was replaced.',
            );
          }
          // Unsupported/cross-volume hard links fail safely rather than
          // exposing any partially written final attachment.
          rethrow;
        }
        if (await sha256FileRange(destination) != digest) {
          throw StateError('Published evidence failed verification.');
        }
        created.add((file: destination, hash: digest));
      } finally {
        try {
          if (await temporary.exists()) await temporary.delete();
        } catch (_) {}
      }
    }
  }

  /// Staged rows are a verified local-wins union. Import only identities
  /// absent from the live database; never modify existing local rows.
  Future<void> _importStagedRows(DatabaseExecutor tx) async {
    final mainTables = await _tablesFrom(tx, 'main');
    final stageTables = await _tablesFrom(tx, 'merge_stage');
    if (mainTables.length != stageTables.length ||
        !mainTables.containsAll(stageTables)) {
      throw const FormatException(
        'Staged Merge schema differs from live data.',
      );
    }
    final tables = mainTables.difference(_privateTables);
    final ordered = await _orderTables(tx, tables);
    await tx.execute('PRAGMA defer_foreign_keys = ON');
    for (final table in ordered) {
      final columns = await _tableColumns(tx, 'main', table);
      final incoming = await _tableColumns(tx, 'merge_stage', table);
      if (columns.length != incoming.length ||
          !columns.every(incoming.contains)) {
        throw FormatException('Incompatible staged columns for $table.');
      }
      final keys = await _primaryKey(tx, table);
      if (keys.isEmpty) {
        throw FormatException('Cannot merge $table without an identity key.');
      }
      final names = columns.map(_quote).join(', ');
      final values = columns.map((c) => 's.${_quote(c)}').join(', ');
      final same = keys
          .map((k) => 'l.${_quote(k)} IS s.${_quote(k)}')
          .join(' AND ');
      await tx.execute(
        'INSERT INTO main.${_quote(table)} ($names) '
        'SELECT $values FROM merge_stage.${_quote(table)} s '
        'WHERE NOT EXISTS (SELECT 1 FROM main.${_quote(table)} l '
        'WHERE $same)',
      );
    }
    if (mainTables.contains('entity_tombstones')) {
      await tx.execute(
        'INSERT OR IGNORE INTO main.entity_tombstones '
        '(entity_type, entity_id, deleted_at) '
        'SELECT entity_type, entity_id, deleted_at '
        'FROM merge_stage.entity_tombstones',
      );
    }
  }

  Future<Set<String>> _tablesFrom(DatabaseExecutor tx, String schema) async {
    final rows = await tx.rawQuery(
      'SELECT name FROM $schema.sqlite_master '
      "WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
    );
    final tables = <String>{};
    for (final row in rows) {
      final name = row['name'];
      if (name is! String || !_safeName.hasMatch(name)) {
        throw const FormatException('Unsafe staged SQLite table identifier.');
      }
      tables.add(name);
    }
    return tables;
  }

  /// Detect commits on the application's existing connection (total_changes)
  /// and on other SQLite connections (data_version), including schema edits.
  /// The application consistency gate blocks normal use-case writes; this is
  /// an additional fail-closed guard for uncoordinated writers during staging.
  Future<_DatabaseRevision> _liveDatabaseRevision([
    DatabaseExecutor? activeConnection,
  ]) async {
    final live = activeConnection ?? database.database;
    final changes = await live.rawQuery('SELECT total_changes() AS total');
    final version = await live.rawQuery('PRAGMA data_version');
    final schema = await live.rawQuery('PRAGMA schema_version');
    return (
      totalChanges: changes.single['total'] as int,
      dataVersion: version.single.values.single as int,
      schemaVersion: schema.single.values.single as int,
    );
  }

  Future<RawBackupInspection> _mergeIntoStaging(
    Directory staging,
    RawBackupInspection inspection,
  ) async {
    final archived = File(path.join(staging.path, 'butlerly.db'));
    final working = File(path.join(staging.path, 'local-merge.db'));
    final quoted = working.path.replaceAll("'", "''");
    await database.database.execute("VACUUM INTO '$quoted'");

    final connection = await database.persistenceDatabase.factory.openDatabase(
      working.path,
      options: OpenDatabaseOptions(
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      ),
    );
    var importedRows = 0;
    var keptLocalRows = 0;
    final importedEvidenceNames = <String>{};
    try {
      final escaped = archived.path.replaceAll("'", "''");
      await connection.execute("ATTACH DATABASE '$escaped' AS archived");

      final sourceVersion = await connection.rawQuery(
        'PRAGMA archived.user_version',
      );
      final localVersion = await connection.rawQuery('PRAGMA user_version');
      if (sourceVersion.single.values.single !=
          localVersion.single.values.single) {
        throw const FormatException(
          'Cannot merge databases with different schema versions.',
        );
      }

      final tables = await _loadTables(connection);
      // The backup must satisfy its own declared relationships. Otherwise an
      // orphaned source child could silently attach to an unrelated local
      // parent that happens to reuse the same ID. Checking only the merged
      // target would miss this semantic corruption.
      final sourceOrphans = await connection.rawQuery(
        'PRAGMA archived.foreign_key_check',
      );
      if (sourceOrphans.isNotEmpty) {
        throw const FormatException(
          'Cannot merge: backup has unresolved foreign-key references.',
        );
      }
      final ordered = await _orderTables(connection, tables);
      // All current local domain rows survive Merge, including overlapping
      // identities where the local value wins. Count them before importing.
      for (final table in ordered) {
        final count = await connection.rawQuery(
          'SELECT COUNT(*) AS total FROM main.${_quote(table)}',
        );
        keptLocalRows += count.single['total'] as int;
      }
      final sourceTombstones = await _hasTable(
        connection,
        'archived',
        'entity_tombstones',
      );
      final localTombstones = await _hasTable(
        connection,
        'main',
        'entity_tombstones',
      );
      if (sourceTombstones != localTombstones) {
        throw const FormatException('Incompatible deletion tracking.');
      }

      // Determine which original evidence files belong to newly imported
      // evidence identities. A different local file at that same path is a
      // conflict, not permission to overwrite its bytes.
      if (tables.contains('evidence_items')) {
        final rows = await connection.rawQuery(
          'SELECT b.local_file_name FROM archived.evidence_items b '
          'WHERE NOT EXISTS (SELECT 1 FROM main.evidence_items l '
          'WHERE l.id = b.id)',
        );
        for (final row in rows) {
          final value = row['local_file_name'];
          if (value is String && value.trim().isNotEmpty) {
            importedEvidenceNames.add(
              evidencePathKey(normalizeEvidencePath(value)),
            );
          }
        }
      }

      // Local-wins on primary keys is not sufficient for imported children:
      // their backup foreign keys may now point to a different local entity.
      // Reject those ambiguous joins rather than silently reassigning receipts,
      // transactions, or statements to a changed merchant/category/source.
      await _rejectConflictingReferencedIdentities(connection, tables);

      await connection.transaction((tx) async {
        // Defer physical foreign keys until all parent/child tables have been
        // imported. Unlike the previous engine, there is no rule validation.
        await tx.execute('PRAGMA defer_foreign_keys = ON');
        for (final table in ordered) {
          final columns = await _tableColumns(tx, 'main', table);
          final backupColumns = await _tableColumns(tx, 'archived', table);
          if (columns.length != backupColumns.length ||
              !columns.every(backupColumns.contains)) {
            throw FormatException('Incompatible columns for table $table.');
          }
          final keys = await _primaryKey(tx, table);
          if (keys.isEmpty) {
            throw FormatException(
              'Cannot safely merge table $table without a key.',
            );
          }
          final quotedColumns = columns.map(_quote).join(', ');
          final sourceColumns = columns
              .map((column) => 'b.${_quote(column)}')
              .join(', ');
          final sameIdentity = keys
              .map((column) => 'l.${_quote(column)} IS b.${_quote(column)}')
              .join(' AND ');
          var where =
              'NOT EXISTS (SELECT 1 FROM main.${_quote(table)} l '
              'WHERE $sameIdentity)';
          if (localTombstones) {
            final entityId = keys.length == 1
                ? 'b.${_quote(keys.single)}'
                : keys.map((key) => 'b.${_quote(key)}').join(" || '|' || ");
            where +=
                ' AND NOT EXISTS (SELECT 1 FROM main.entity_tombstones t '
                "WHERE t.entity_type = '$table' AND t.entity_id = $entityId)";
          }
          await tx.execute(
            'INSERT INTO main.${_quote(table)} ($quotedColumns) '
            'SELECT $sourceColumns FROM archived.${_quote(table)} b '
            'WHERE $where',
          );
          final changes = await tx.rawQuery('SELECT changes() AS count');
          importedRows += (changes.single['count'] as int? ?? 0);
        }
        if (sourceTombstones) {
          // Import source deletion markers only when the corresponding entity
          // is absent locally. Never delete current local rows to apply them.
          final known = await _knownTombstoneTables(tx, tables);
          for (final entry in known.entries) {
            final table = entry.key;
            final keys = entry.value;
            final idExpr = keys.length == 1
                ? 'l.${_quote(keys.single)}'
                : keys.map((key) => 'l.${_quote(key)}').join(" || '|' || ");
            await tx.execute(
              'INSERT OR IGNORE INTO main.entity_tombstones '
              '(entity_type, entity_id, deleted_at) '
              'SELECT s.entity_type, s.entity_id, s.deleted_at '
              'FROM archived.entity_tombstones s '
              "WHERE s.entity_type = '$table' "
              'AND NOT EXISTS (SELECT 1 FROM main.${_quote(table)} l '
              'WHERE $idExpr = s.entity_id)',
            );
          }
        }
      });
      await connection.execute('DETACH DATABASE archived');
    } finally {
      await connection.close();
    }

    final stagedEvidence = Directory(path.join(staging.path, 'evidence'));
    final liveEvidence = await backup.data.evidenceDirectory();
    await rejectEvidenceTree(stagedEvidence);
    await rejectEvidenceTree(liveEvidence);
    var newFiles = 0;
    final files = <String>{};
    if (await stagedEvidence.exists()) {
      await for (final entry in stagedEvidence.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entry is! File) continue;
        final relative = await validateEvidencePath(
          stagedEvidence,
          path.relative(entry.path, from: stagedEvidence.path),
        );
        files.add(evidencePathKey(relative));
        newFiles++;
      }
    }
    if (await liveEvidence.exists()) {
      await for (final entry in liveEvidence.list(
        recursive: true,
        followLinks: false,
      )) {
        await rejectEvidenceLink(entry);
        if (entry is! File) continue;
        final relative = await validateEvidencePath(
          liveEvidence,
          path.relative(entry.path, from: liveEvidence.path),
        );
        final key = evidencePathKey(relative);
        // No case-aliasing: same bytes must have exactly the same path.
        final target = File(path.join(stagedEvidence.path, relative));
        if (await target.exists()) {
          if (await sha256FileRange(target) != await sha256FileRange(entry)) {
            if (importedEvidenceNames.contains(key)) {
              throw const FormatException(
                'Conflicting receipt filenames: merge cannot safely preserve both.',
              );
            }
            await entry.copy(target.path); // local identity wins
          }
        } else {
          if (files.contains(key)) {
            throw const FormatException('Ambiguous attachment name collision.');
          }
          await target.parent.create(recursive: true);
          await entry.copy(target.path);
          files.add(key);
        }
      }
    }
    // Replace the extracted backup with the complete merged local snapshot.
    if (await archived.exists()) await archived.delete();
    await working.rename(archived.path);
    return RawBackupInspection(
      createdAtUtc: inspection.createdAtUtc,
      sqliteBytes: await archived.length(),
      recordCount: importedRows,
      attachmentCount: newFiles,
      missingAttachmentCount: inspection.missingAttachmentCount,
      keptLocalRowCount: keptLocalRows,
    );
  }

  /// Check references of rows that will be imported, before any merge writes.
  /// Comparing all parent columns is intentionally conservative: even a
  /// changed timestamp forces the user to resolve an ambiguous identity
  /// instead of silently attaching an imported row to different local data.
  Future<void> _rejectConflictingReferencedIdentities(
    Database db,
    Set<String> tables,
  ) async {
    for (final table in tables) {
      final childKeys = await _primaryKey(db, table);
      if (childKeys.isEmpty) continue; // the merge loop rejects this table
      final sameChild = childKeys
          .map((key) => 'localChild.${_quote(key)} IS b.${_quote(key)}')
          .join(' AND ');
      final foreignKeys = await db.rawQuery(
        'PRAGMA main.foreign_key_list(${_quote(table)})',
      );
      final byConstraint = <int, List<Map<String, Object?>>>{};
      for (final reference in foreignKeys) {
        final id = reference['id'] as int;
        byConstraint.putIfAbsent(id, () => []).add(reference);
      }
      for (final references in byConstraint.values) {
        if (references.length != 1) {
          throw FormatException(
            'Cannot merge $table with an unverified composite reference.',
          );
        }
        final reference = references.single;
        final parent = reference['table'] as String;
        final from = reference['from'] as String;
        if (!tables.contains(parent)) continue;
        final specified = reference['to'] as String?;
        final parentKeys = await _primaryKey(db, parent);
        final to = specified != null && specified.isNotEmpty
            ? specified
            : (parentKeys.length == 1 ? parentKeys.single : null);
        if (to == null) {
          throw FormatException(
            'Cannot merge $table: the referenced parent key is ambiguous.',
          );
        }
        final localColumns = await _tableColumns(db, 'main', parent);
        final sourceColumns = await _tableColumns(db, 'archived', parent);
        if (localColumns.length != sourceColumns.length ||
            !localColumns.every(sourceColumns.contains)) {
          throw FormatException(
            'Cannot merge $table: referenced parent columns differ.',
          );
        }
        final changedParent = localColumns
            .map(
              (column) =>
                  'NOT (localParent.${_quote(column)} IS '
                  'backupParent.${_quote(column)})',
            )
            .join(' OR ');
        final conflicting = await db.rawQuery(
          'SELECT 1 FROM archived.${_quote(table)} b '
          'JOIN archived.${_quote(parent)} backupParent '
          'ON backupParent.${_quote(to)} IS b.${_quote(from)} '
          'JOIN main.${_quote(parent)} localParent '
          'ON localParent.${_quote(to)} IS backupParent.${_quote(to)} '
          'WHERE NOT EXISTS (SELECT 1 FROM main.${_quote(table)} localChild '
          'WHERE $sameChild) AND ($changedParent) LIMIT 1',
        );
        if (conflicting.isNotEmpty) {
          throw FormatException(
            'Cannot merge $table: a referenced $parent identity differs '
            'between the backup and local data.',
          );
        }
      }
    }
  }

  Future<Set<String>> _loadTables(Database db) async {
    final mainTables = await _tables(db, 'main');
    final archivedTables = await _tables(db, 'archived');
    for (final name in archivedTables) {
      if (!mainTables.contains(name)) {
        throw FormatException('Backup includes unknown SQLite table $name.');
      }
    }
    for (final name in mainTables) {
      if (!archivedTables.contains(name)) {
        throw FormatException('Backup is missing SQLite table $name.');
      }
    }
    return mainTables.difference(_privateTables);
  }

  Future<Set<String>> _tables(Database db, String schema) async {
    final rows = await db.rawQuery(
      'SELECT name FROM $schema.sqlite_master '
      "WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
    );
    final result = <String>{};
    for (final row in rows) {
      final name = row['name'];
      if (name is! String || !_safeName.hasMatch(name)) {
        throw const FormatException('Unsafe SQLite table identifier.');
      }
      result.add(name);
    }
    return result;
  }

  Future<bool> _hasTable(Database db, String schema, String table) async =>
      (await _tables(db, schema)).contains(table);

  Future<List<String>> _tableColumns(
    DatabaseExecutor db,
    String schema,
    String table,
  ) async {
    final rows = await db.rawQuery(
      'PRAGMA $schema.table_info(${_quote(table)})',
    );
    return rows.map((row) => row['name']! as String).toList();
  }

  Future<List<String>> _primaryKey(DatabaseExecutor db, String table) async {
    final rows = await db.rawQuery('PRAGMA main.table_info(${_quote(table)})');
    final sorted = rows.where((row) => (row['pk'] as int? ?? 0) > 0).toList()
      ..sort((a, b) => (a['pk'] as int).compareTo(b['pk'] as int));
    return sorted.map((row) => row['name']! as String).toList();
  }

  Future<Map<String, List<String>>> _knownTombstoneTables(
    DatabaseExecutor db,
    Set<String> tables,
  ) async {
    final result = <String, List<String>>{};
    for (final table in tables) {
      final keys = await _primaryKey(db, table);
      // Tombstone identifiers for other composite keys might use different
      // encodings. Import only the known format, never guess.
      if (keys.length == 1 || table == 'transaction_tags') {
        result[table] = keys;
      }
    }
    return result;
  }

  Future<List<String>> _orderTables(
    DatabaseExecutor db,
    Set<String> tables,
  ) async {
    final dependencies = <String, Set<String>>{};
    for (final table in tables) {
      final references = await db.rawQuery(
        'PRAGMA main.foreign_key_list(${_quote(table)})',
      );
      dependencies[table] = references
          .map((ref) => ref['table'] as String)
          .where((dep) => dep != table && tables.contains(dep))
          .toSet();
    }
    final pending = {...tables};
    final result = <String>[];
    while (pending.isNotEmpty) {
      final ready =
          pending
              .where(
                (table) => dependencies[table]!.intersection(pending).isEmpty,
              )
              .toList()
            ..sort();
      // Cycles are handled with deferred foreign keys in the transaction.
      if (ready.isEmpty) {
        result.addAll(pending.toList()..sort());
        break;
      }
      result.addAll(ready);
      pending.removeAll(ready);
    }
    return result;
  }

  static String _quote(String name) {
    if (!_safeName.hasMatch(name)) {
      throw const FormatException('Unsafe SQLite identifier.');
    }
    return '"$name"';
  }
}
