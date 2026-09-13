import 'dart:convert';
import 'dart:io';

import 'package:butlerly/core/data/local_backup_engine.dart' as engine;
import 'package:butlerly/core/data/local_backup_snapshot_writer.dart';
import 'package:butlerly/core/data/local_data_manager.dart';
import 'package:butlerly/core/data/local_restore_recovery.dart';
import 'package:butlerly/core/database/local_database.dart';
import 'package:butlerly_database/butlerly_database.dart'
    show Sqflite, int64FromBytes, sha256Bytes, sha256FileRange;
import 'package:path/path.dart' as path;
import 'package:sqflite_common/sqlite_api.dart';

export 'local_backup_engine.dart'
    show
        BackupChangeSummary,
        BackupInspection,
        LocalRestoreMode,
        LocalRestoreResult;
export 'local_restore_recovery.dart';

/// Public backup/restore boundary for Butlerly.
///
/// [local_backup_engine.dart] owns package validation and restore mechanics.
/// [LocalBackupSnapshotWriter] owns creation from one SQLite read snapshot.
final class LocalBackupManager {
  LocalBackupManager(this.database, this.localDataManager)
    : _engine = engine.LocalBackupManager(database, localDataManager),
      _snapshotWriter = LocalBackupSnapshotWriter(localDataManager);

  final LocalDatabase database;
  final LocalDataManager localDataManager;
  final engine.LocalBackupManager _engine;
  final LocalBackupSnapshotWriter _snapshotWriter;

  static final _backupMagic = utf8.encode('BUTLERLYBACKUP2');

  /// Creates one logical database snapshot without rejecting concurrent app
  /// writes. WAL lets a dedicated reader keep its established snapshot while
  /// the primary application connection commits newer changes independently.
  Future<File> createBackup(File destination) async {
    final persistence = database.persistenceDatabase;
    await persistence.prepareForConsistentBackup();

    // WAL is persistent for the database file. It is selected before the
    // snapshot connection opens so readers and writers can overlap safely.
    await database.database.rawQuery('PRAGMA journal_mode = WAL');
    await database.database.execute('PRAGMA busy_timeout = 30000');
    final snapshot = await persistence.factory.openDatabase(
      persistence.path,
      options: OpenDatabaseOptions(
        singleInstance: false,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
          await db.execute('PRAGMA busy_timeout = 30000');
        },
      ),
    );
    var transactionOpen = false;
    try {
      await snapshot.execute('BEGIN');
      transactionOpen = true;
      // The timestamp is deliberately taken no later than the first read. If a
      // writer races this tiny boundary, Merge becomes conservatively biased
      // toward preserving the newer local row rather than overwriting it.
      final createdAtUtc = DateTime.now().toUtc();
      await snapshot.rawQuery('SELECT COUNT(*) FROM sqlite_master');
      final result = await _snapshotWriter.write(
        destination,
        source: snapshot,
        createdAtUtc: createdAtUtc,
      );
      await snapshot.execute('COMMIT');
      transactionOpen = false;
      return result;
    } catch (_) {
      if (transactionOpen) {
        try {
          await snapshot.execute('ROLLBACK');
        } on Exception {
          // Preserve the original backup failure.
        }
      }
      rethrow;
    } finally {
      await snapshot.close();
    }
  }

  Future<engine.BackupInspection> inspect(File file) async {
    final base = await _engine.inspect(file);
    final cutoff = base.createdAtUtc.toIso8601String();
    final additional = await _countOtherNewerData(cutoff);
    if (additional == 0) return base;
    return engine.BackupInspection(
      createdAtUtc: base.createdAtUtc,
      recordCount: base.recordCount,
      evidenceCount: base.evidenceCount,
      changes: engine.BackupChangeSummary(
        transactionsAdded: base.changes.transactionsAdded,
        transactionsChanged: base.changes.transactionsChanged,
        masterDataChanged: base.changes.masterDataChanged + additional,
        deletedEntities: base.changes.deletedEntities,
      ),
    );
  }

  Future<void> recoverInterruptedRestore() =>
      recoverInterruptedLocalRestore(database, localDataManager);

  Future<engine.LocalRestoreResult> restore(
    File file, {
    required engine.LocalRestoreMode mode,
  }) async {
    await recoverInterruptedLocalRestore(database, localDataManager);

    if (mode == engine.LocalRestoreMode.replace) {
      // Replace is destructive after it commits. Always preserve the current
      // local workspace in a Butlerly-managed package before mutation starts.
      await _createPreRestoreSafetyBackup();
      final result = await _engine.restore(file, mode: mode);
      await _purgeGeneratedWorkflowState();
      return result;
    }

    // Validate every evidence byte and prove the filesystem staging operation
    // can complete before changing any local workflow state. This makes a
    // corrupt/truncated package or a dangerous remap collision a no-op locally.
    await _preflightMergeRestore(file);

    // Generated rows are not authoritative. Purge them before restore_context
    // is installed so the preserve-newer relationship triggers cannot protect
    // a newly generated unresolved duplicate membership from this cleanup.
    await _purgeGeneratedWorkflowState();

    final inspection = await _engine.inspect(file);
    await database.database.insert(
      'restore_context',
      {
        'id': 1,
        'backup_time': inspection.createdAtUtc.toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    late final engine.LocalRestoreResult result;
    try {
      result = await _engine.restore(file, mode: mode);
    } finally {
      await database.database.delete('restore_context', where: 'id = 1');
    }

    // Older format-v2 packages may still contain generated workflow rows.
    // Purge them only after restore_context is gone for the same reason as the
    // pre-restore purge above.
    await _purgeGeneratedWorkflowState();
    return result;
  }

  Future<File> _createPreRestoreSafetyBackup() async {
    final directory = await localDataManager.safetyBackupDirectory();
    final timestamp = DateTime.now().toUtc().toIso8601String().replaceAll(
      ':',
      '-',
    );
    return createBackup(
      File(path.join(directory.path, 'Before Restore $timestamp.butlerlybackup')),
    );
  }

  /// Performs the expensive validation/staging phase without touching the live
  /// database or evidence root. The actual restore intentionally repeats this
  /// work so the engine remains the sole owner of activation and crash recovery.
  Future<void> _preflightMergeRestore(File file) async {
    final package = await _readPreflightPackage(file);
    final root = await localDataManager.evidenceDirectory();
    final staging = Directory(
      '${root.path}.restore-preflight-${DateTime.now().microsecondsSinceEpoch}',
    );
    if (await staging.exists()) await staging.delete(recursive: true);
    await staging.create(recursive: true);
    try {
      if (await root.exists()) await _copyDirectory(root, staging);
      for (final item in package.evidence) {
        final normalized = path.normalize(item.relativePath);
        if (_unsafeRelativePath(normalized)) {
          throw const FormatException('Unsafe evidence path.');
        }
        final actualHash = await sha256FileRange(
          file,
          start: item.offset,
          endExclusive: item.offset + item.length,
        );
        if (actualHash != item.sha256) {
          throw const FormatException('Evidence integrity validation failed.');
        }

        var destination = File(path.join(staging.path, normalized));
        if (await destination.exists()) {
          final existingHash = await sha256FileRange(destination);
          if (existingHash == item.sha256) continue;

          // Mirror the engine's current deterministic remap. The preflight must
          // prove that target is either unused or already contains the exact
          // backup bytes; otherwise the engine's later openWrite would truncate
          // unrelated local evidence.
          final extension = path.extension(normalized);
          final base = path.basenameWithoutExtension(normalized);
          final remapped = path.join(
            path.dirname(normalized),
            '$base.backup-${item.sha256.substring(0, 8)}$extension',
          );
          destination = File(path.join(staging.path, remapped));
          if (await destination.exists()) {
            final remapHash = await sha256FileRange(destination);
            if (remapHash != item.sha256) {
              throw StateError(
                'Evidence collision remap target already contains different bytes.',
              );
            }
            continue;
          }
        }

        await destination.parent.create(recursive: true);
        final sink = destination.openWrite();
        try {
          await sink.addStream(
            file.openRead(item.offset, item.offset + item.length),
          );
          await sink.flush();
        } finally {
          await sink.close();
        }
      }
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
    }
  }

  Future<_PreflightPackage> _readPreflightPackage(File file) async {
    final raf = await file.open(mode: FileMode.read);
    try {
      final magic = await raf.read(_backupMagic.length);
      if (!_listEquals(magic, _backupMagic)) {
        throw const FormatException('Unsupported Butlerly backup format.');
      }
      final lengthBytes = await raf.read(8);
      if (lengthBytes.length != 8) {
        throw const FormatException('Incomplete Butlerly backup header.');
      }
      final metadataLength = int64FromBytes(lengthBytes);
      if (metadataLength <= 0 || metadataLength > 128 * 1024 * 1024) {
        throw const FormatException('Invalid Butlerly backup metadata length.');
      }
      final expectedHashBytes = await raf.read(64);
      if (expectedHashBytes.length != 64) {
        throw const FormatException('Incomplete Butlerly backup checksum.');
      }
      final metadataBytes = await raf.read(metadataLength);
      if (metadataBytes.length != metadataLength) {
        throw const FormatException('Incomplete Butlerly backup metadata.');
      }
      if (sha256Bytes(metadataBytes) != ascii.decode(expectedHashBytes)) {
        throw const FormatException(
          'Backup metadata integrity validation failed.',
        );
      }
      final decoded = jsonDecode(utf8.decode(metadataBytes));
      if (decoded is! Map) {
        throw const FormatException('Invalid Butlerly backup metadata.');
      }
      final metadata = decoded.cast<String, Object?>();
      final manifest = (metadata['manifest'] as Map?)?.cast<String, Object?>();
      final evidenceRaw = metadata['evidence'] as List?;
      if (manifest == null || evidenceRaw == null) {
        throw const FormatException('Incomplete Butlerly backup metadata.');
      }
      if (manifest['format'] != 'butlerly-backup' ||
          manifest['formatVersion'] != 2) {
        throw const FormatException('Unsupported Butlerly backup format.');
      }
      final sourceSchema = manifest['schemaVersion'] as int?;
      if (sourceSchema == null || sourceSchema > 8) {
        throw const FormatException(
          'Backup was created by a newer Butlerly schema.',
        );
      }

      var offset = _backupMagic.length + 8 + 64 + metadataLength;
      final evidence = <_PreflightEvidence>[];
      for (final raw in evidenceRaw.cast<Map>()) {
        final item = raw.cast<String, Object?>();
        final relative = item['path'] as String?;
        final length = item['length'] as int?;
        final hash = item['sha256'] as String?;
        if (relative == null || length == null || length < 0 || hash == null) {
          throw const FormatException('Invalid evidence descriptor.');
        }
        evidence.add(
          _PreflightEvidence(
            relativePath: relative,
            length: length,
            sha256: hash,
            offset: offset,
          ),
        );
        offset += length;
      }
      if (await file.length() != offset) {
        throw const FormatException(
          'Backup file length does not match its manifest.',
        );
      }
      return _PreflightPackage(evidence);
    } finally {
      await raf.close();
    }
  }

  /// Generated workflow candidates are rebuilt from the restored authoritative
  /// records. Closed/resolved decisions remain because they represent explicit
  /// user intent rather than recomputable recommendations.
  Future<void> _purgeGeneratedWorkflowState() async {
    await database.database.transaction((tx) async {
      await tx.delete('review_issues', where: 'closed_at IS NULL');
      await tx.delete('suggestions', where: 'decided_at IS NULL');
      // `proposed` is the generated reconciliation state. Confirmed, rejected,
      // and undone candidates encode explicit user workflow decisions.
      await tx.delete(
        'reconciliation_candidates',
        where: "status = 'proposed'",
      );
      // Delete membership rows explicitly before unresolved groups. Historical
      // fixtures and partially migrated databases must not rely on FK cascades.
      await tx.rawDelete(
        'DELETE FROM duplicate_candidate_group_transactions '
        'WHERE group_id IN ('
        "SELECT id FROM duplicate_candidate_groups WHERE status = 'unresolved'"
        ')',
      );
      await tx.delete(
        'duplicate_candidate_groups',
        where: "status = 'unresolved'",
      );
      await tx.delete(
        'entity_tombstones',
        where:
            "entity_type IN ('review_issues', 'suggestions', "
            "'reconciliation_candidates', 'duplicate_candidate_groups', "
            "'duplicate_candidate_group_transactions')",
      );
    });
  }

  Future<int> _countOtherNewerData(String cutoff) async {
    var count = 0;
    for (final query in <String>[
      'SELECT COUNT(*) FROM evidence_items WHERE created_at > ?',
      'SELECT COUNT(*) FROM financial_statements WHERE updated_at > ?',
      'SELECT COUNT(*) FROM statement_rows WHERE updated_at > ?',
      'SELECT COUNT(*) FROM review_issues '
          'WHERE closed_at IS NOT NULL AND closed_at > ?',
      'SELECT COUNT(*) FROM suggestions '
          'WHERE decided_at IS NOT NULL AND decided_at > ?',
      "SELECT COUNT(*) FROM reconciliation_candidates "
          "WHERE status != 'proposed' AND updated_at > ?",
      "SELECT COUNT(*) FROM duplicate_candidate_groups "
          "WHERE status != 'unresolved' AND updated_at > ?",
      'SELECT COUNT(*) FROM analysis_rule_activations WHERE updated_at > ?',
      'SELECT COUNT(*) FROM analysis_rule_configurations WHERE updated_at > ?',
      'SELECT COUNT(*) FROM user_preferences WHERE updated_at > ?',
    ]) {
      final rows = await database.database.rawQuery(query, [cutoff]);
      count += Sqflite.firstIntValue(rows) ?? 0;
    }
    return count;
  }

  Future<void> _copyDirectory(
    Directory source,
    Directory destination,
  ) async {
    await for (final entity in source.list(recursive: true)) {
      final relative = path.relative(entity.path, from: source.path);
      final target = path.join(destination.path, relative);
      if (entity is Directory) {
        await Directory(target).create(recursive: true);
      } else if (entity is File) {
        final file = File(target);
        await file.parent.create(recursive: true);
        await entity.copy(file.path);
      }
    }
  }

  bool _unsafeRelativePath(String value) =>
      path.isAbsolute(value) || value == '..' || value.startsWith('../');

  bool _listEquals(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }
}

final class _PreflightPackage {
  const _PreflightPackage(this.evidence);

  final List<_PreflightEvidence> evidence;
}

final class _PreflightEvidence {
  const _PreflightEvidence({
    required this.relativePath,
    required this.length,
    required this.sha256,
    required this.offset,
  });

  final String relativePath;
  final int length;
  final String sha256;
  final int offset;
}
