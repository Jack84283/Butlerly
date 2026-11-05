import 'dart:io';

import 'package:butlerly/core/data/backup_destination_writer.dart';
import 'package:butlerly/core/data/backup_encryption.dart';
import 'package:butlerly/core/data/evidence_path_safety.dart';
import 'package:butlerly/core/data/local_data_manager.dart';
import 'package:butlerly/core/data/raw_backup_archive.dart';
import 'package:butlerly/core/data/storage_space_preflight.dart';
import 'package:butlerly/core/database/local_database.dart';
import 'package:butlerly/core/evidence/evidence_mutation_lock.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart'
    show
        BackupCreationException,
        BackupCreationStage,
        BackupPasswordTooShortException,
        NewerBackupSchemaException,
        UnsupportedBackupSchemaException;
import 'package:path/path.dart' as path;
import 'package:sqflite_common/sqlite_api.dart';

/// Business-agnostic backup workflow.
///
/// SQLite's VACUUM INTO produces a coherent database file without interpreting
/// Butlerly tables. The package contains that file and original attachments.
/// Neither this class nor RawBackupArchive runs analysis/business validation.
final class RawBackupService {
  RawBackupService(
    this.database,
    this.data, {
    BackupDestinationWriter? destinationWriter,
  }) : _destinationWriter =
           destinationWriter ?? const SandboxedBackupDestinationWriter();

  final LocalDatabase database;
  final LocalDataManager data;
  final BackupDestinationWriter _destinationWriter;
  final RawBackupArchive _archive = const RawBackupArchive();
  final BackupEncryption _encryption = const BackupEncryption();
  static const _rawInnerFormat = 'butlerly-raw-backup';

  /// Creates and verifies an encrypted archive, then safely publishes it.
  /// Missing evidence is a warning, never a reason to repair SQLite records.
  Future<RawBackupInspection> createBackup(
    File destination, {
    required String password,
  }) => EvidenceMutationLock.runExclusive(() async {
    final root = Directory(path.dirname(database.persistenceDatabase.path));
    await rejectSymlinkedPath(root.path);
    final id = DateTime.now().microsecondsSinceEpoch;
    final working = Directory(path.join(root.path, '.raw-backup-work-$id'));
    final encrypted = File(path.join(root.path, '.raw-backup-$id.butlerly'));
    var preserveEncrypted = false;
    var stage = BackupCreationStage.snapshot;
    final databaseBytes = await File(
      database.persistenceDatabase.path,
    ).length();
    final evidenceBytes = await StorageSpacePreflight.evidenceBytes(
      await data.evidenceDirectory(),
    );
    await StorageSpacePreflight.requireAvailable(
      root,
      stagingBytes: StorageSpacePreflight.backupStagingBytes(
        databaseBytes: databaseBytes,
        evidenceBytes: evidenceBytes,
      ),
    );
    await StorageSpacePreflight.requireAvailable(
      destination.parent,
      stagingBytes: databaseBytes + evidenceBytes,
    );
    await working.create();
    try {
      final snapshot = File(path.join(working.path, 'butlerly.db'));
      // Never run VACUUM INTO inside a SQLite transaction. SQLite itself
      // provides a consistent point-in-time snapshot, including WAL content.
      final quoted = snapshot.path.replaceAll("'", "''");
      await database.database.execute("VACUUM INTO '$quoted'");
      final snapshotDatabase = await database.persistenceDatabase.factory
          .openDatabase(
            snapshot.path,
            options: OpenDatabaseOptions(readOnly: true),
          );
      stage = BackupCreationStage.inventory;
      final references = <String>[];
      var recordCount = 0;
      try {
        // Preview metadata only; never validate or change financial rows.
        final count = await snapshotDatabase.rawQuery(
          'SELECT COUNT(*) AS total FROM transactions',
        );
        recordCount = count.single['total'] as int;
        final rows = await snapshotDatabase.query(
          'evidence_items',
          columns: ['local_file_name'],
        );
        for (final row in rows) {
          final value = row['local_file_name'];
          if (value is String && value.isNotEmpty) references.add(value);
        }
      } finally {
        await snapshotDatabase.close();
      }
      stage = BackupCreationStage.packaging;
      final plain = File(path.join(working.path, 'payload'));
      final inspection = await _archive.write(
        sqliteSnapshot: snapshot,
        evidenceDirectory: await data.evidenceDirectory(),
        referencedEvidencePaths: references,
        destination: plain,
        recordCount: recordCount,
      );
      stage = BackupCreationStage.encryption;
      await _encryption.encrypt(
        plain,
        encrypted,
        password: password,
        innerFormat: _rawInnerFormat,
      );
      stage = BackupCreationStage.verification;
      final verification = File(path.join(working.path, 'verification'));
      await _encryption.decrypt(
        encrypted,
        verification,
        password: password,
        acceptedInnerFormats: const {_rawInnerFormat},
      );
      final verified = await _archive.inspect(verification);
      if (verified.sqliteBytes != inspection.sqliteBytes ||
          verified.attachmentCount != inspection.attachmentCount ||
          verified.missingAttachmentCount !=
              inspection.missingAttachmentCount) {
        throw const FormatException('Encrypted backup verification failed.');
      }
      stage = BackupCreationStage.publication;
      await _destinationWriter.publish(
        source: encrypted,
        destination: destination,
        privateDirectory: root,
        operationId: '$id',
      );
      return verified;
    } on BackupPublicationRecoveryRequiredException {
      preserveEncrypted = true;
      rethrow;
    } on BackupDestinationWriteException {
      // The publisher may need the private encrypted source to recover the
      // original external destination; never delete that recovery artifact.
      preserveEncrypted = true;
      rethrow;
    } on BackupPasswordTooShortException {
      rethrow;
    } catch (error, stack) {
      Error.throwWithStackTrace(
        BackupCreationException(stage: stage, cause: error),
        stack,
      );
    } finally {
      // Publication has already completed (or the original error is in
      // flight). Cleanup failures must never make a saved backup look failed.
      // A crash/unremovable work directory is handled by startup maintenance.
      try {
        if (await working.exists()) await working.delete(recursive: true);
      } catch (_) {
        // Best effort; never mask successful publication.
      }
      if (!preserveEncrypted) {
        try {
          if (await encrypted.exists()) await encrypted.delete();
        } catch (_) {
          // Preserve the original result; the encrypted private candidate
          // remains recoverable rather than risking deletion of a user file.
        }
      }
    }
  });

  /// Authenticates then inspects the new raw archive without touching live data.
  Future<RawBackupInspection> inspect(
    File encryptedFile, {
    required String password,
  }) async {
    final temporary = await _privateTemporaryDirectory();
    try {
      final plain = File(path.join(temporary.path, 'payload'));
      await _encryption.decrypt(
        encryptedFile,
        plain,
        password: password,
        acceptedInnerFormats: const {_rawInnerFormat},
      );
      // Read-only preview authenticates every archived byte, but only
      // materializes SQLite. Extracting all attachments here would duplicate
      // disk writes that the actual Restore performs after confirmation.
      final sqlite = File(path.join(temporary.path, 'inspection.sqlite'));
      final summary = await _archive.inspectAndStageSqlite(
        archive: plain,
        sqliteDestination: sqlite,
      );
      await requireSupportedSchema(sqlite);
      return summary;
    } finally {
      if (await temporary.exists()) await temporary.delete(recursive: true);
    }
  }

  /// Read-only preflight shared by preview and the actual restore path.
  /// An older valid schema may be migrated in staging. A newer schema requires
  /// updating the installed app, never a live-database downgrade.
  Future<void> requireSupportedSchema(File sqlite) async {
    final current = database.persistenceDatabase;
    final reader = await current.factory.openDatabase(
      sqlite.path,
      options: OpenDatabaseOptions(readOnly: true),
    );
    try {
      final result = await reader.rawQuery('PRAGMA user_version');
      if (result.length != 1 || result.single.values.single is! int) {
        throw const UnsupportedBackupSchemaException();
      }
      final sourceVersion = result.single.values.single as int;
      if (sourceVersion < 1) {
        throw const UnsupportedBackupSchemaException();
      }
      if (sourceVersion > current.targetVersion) {
        throw NewerBackupSchemaException(
          backupVersion: sourceVersion,
          supportedVersion: current.targetVersion,
        );
      }
    } finally {
      await reader.close();
    }
  }

  /// Authenticates and extracts into a caller-chosen *new* staging directory.
  /// This method deliberately cannot activate or modify the live database.
  Future<RawBackupInspection> prepareRestore(
    File encryptedFile, {
    required String password,
    required Directory stagingDirectory,
  }) async {
    final temporary = await _privateTemporaryDirectory();
    try {
      final plain = File(path.join(temporary.path, 'payload'));
      await _encryption.decrypt(
        encryptedFile,
        plain,
        password: password,
        acceptedInnerFormats: const {_rawInnerFormat},
      );
      return await _archive.extract(
        archive: plain,
        stagingDirectory: stagingDirectory,
      );
    } finally {
      if (await temporary.exists()) await temporary.delete(recursive: true);
    }
  }

  Future<Directory> _privateTemporaryDirectory() async {
    final root = Directory(path.dirname(database.persistenceDatabase.path));
    await rejectSymlinkedPath(root.path);
    return Directory(
      path.join(
        root.path,
        '.raw-backup-read-${DateTime.now().microsecondsSinceEpoch}',
      ),
    )..createSync();
  }
}
