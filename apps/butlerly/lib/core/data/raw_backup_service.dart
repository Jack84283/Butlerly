import 'dart:io';

import 'package:butlerly/core/data/backup_destination_writer.dart';
import 'package:butlerly/core/data/backup_encryption.dart';
import 'package:butlerly/core/data/evidence_path_safety.dart';
import 'package:butlerly/core/data/local_data_manager.dart';
import 'package:butlerly/core/data/raw_backup_archive.dart';
import 'package:butlerly/core/database/local_database.dart';
import 'package:butlerly/core/evidence/evidence_mutation_lock.dart';
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
      final references = <String>[];
      try {
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
      final plain = File(path.join(working.path, 'payload'));
      final inspection = await _archive.write(
        sqliteSnapshot: snapshot,
        evidenceDirectory: await data.evidenceDirectory(),
        referencedEvidencePaths: references,
        destination: plain,
      );
      await _encryption.encrypt(
        plain,
        encrypted,
        password: password,
        innerFormat: _rawInnerFormat,
      );
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
    } finally {
      // Do not retain a plaintext backup, even after a publication failure.
      if (await working.exists()) await working.delete(recursive: true);
      if (!preserveEncrypted && await encrypted.exists()) {
        await encrypted.delete();
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
      return await _archive.inspect(plain);
    } finally {
      if (await temporary.exists()) await temporary.delete(recursive: true);
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
