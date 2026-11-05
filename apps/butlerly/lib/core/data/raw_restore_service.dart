import 'dart:convert';
import 'dart:io';

import 'package:butlerly/core/data/evidence_path_safety.dart';
import 'package:butlerly/core/data/raw_backup_archive.dart';
import 'package:butlerly/core/data/raw_backup_service.dart';
import 'package:butlerly/core/database/local_database.dart';
import 'package:butlerly/core/evidence/evidence_mutation_lock.dart';
import 'package:butlerly_database/butlerly_database.dart'
    show ButlerlyDatabase, sha256FileRange, sha256OpenFile;
import 'package:butlerly_finance_application/butlerly_finance_application.dart'
    show RestoreRecoveryRequiredException;
import 'package:path/path.dart' as path;
import 'package:sqflite_common/sqlite_api.dart';

/// Physical Replace restore for an encrypted raw Butlerly archive.
///
/// Source data is never interpreted or repaired. A durable journal and
/// same-filesystem previous copies make interrupted file activation reversible.
/// The SQLite persistence object is reopened in place so existing repositories
/// retain the same object after a successful restore.
final class RawRestoreService {
  RawRestoreService(this.database, this.backup);

  final LocalDatabase database;
  final RawBackupService backup;

  static const _journalName = '.raw-restore-journal.json';
  static final _operationIdPattern = RegExp(r'^[0-9]{13,20}$');

  /// Reverses an interrupted activation. The normal app startup must call this
  /// BEFORE opening SQLite. It does not accept arbitrary paths from the journal.
  static Future<void> recoverInterruptedReplace({
    required File liveDatabase,
    required Directory evidenceDirectory,
  }) async {
    final journal = File(path.join(liveDatabase.parent.path, _journalName));
    await rejectSymlinkedPath(journal.path);
    if (!await journal.exists()) return;
    final decoded = jsonDecode(await journal.readAsString());
    if (decoded is! Map<String, dynamic> ||
        decoded['format'] != 'butlerly-raw-restore' ||
        decoded['operationId'] is! String ||
        !_operationIdPattern.hasMatch(decoded['operationId'] as String) ||
        decoded['hadEvidence'] is! bool) {
      throw StateError('A previous restore requires manual recovery.');
    }
    final operationId = decoded['operationId'] as String;
    final hadEvidence = decoded['hadEvidence'] as bool;
    final oldDb = _oldDatabase(liveDatabase, operationId);
    final oldEvidence = _oldEvidence(evidenceDirectory, operationId);
    final incomingEvidence = _incomingEvidence(evidenceDirectory, operationId);
    final working = _working(liveDatabase, operationId);

    await rejectSymlinkedPath(liveDatabase.path);
    await rejectSymlinkedPath(evidenceDirectory.path);
    await rejectSymlinkedPath(oldDb.path);
    await rejectSymlinkedPath(oldEvidence.path);
    await rejectSymlinkedPath(incomingEvidence.path);
    await rejectSymlinkedPath(working.path);

    final databaseMoved = await oldDb.exists();
    if (!databaseMoved && await oldEvidence.exists()) {
      throw StateError('Incomplete restore recovery state; no data changed.');
    }

    // Preserve original WAL companions even if the process terminated between
    // moving a sidecar and moving the main SQLite file.
    if (databaseMoved) {
      if (await oldEvidence.exists()) {
        await rejectEvidenceTree(evidenceDirectory);
        if (await evidenceDirectory.exists()) {
          await evidenceDirectory.delete(recursive: true);
        }
        await oldEvidence.rename(evidenceDirectory.path);
      } else if (!hadEvidence) {
        await rejectEvidenceTree(evidenceDirectory);
        if (await evidenceDirectory.exists()) {
          await evidenceDirectory.delete(recursive: true);
        }
      } else if (!await evidenceDirectory.exists()) {
        throw StateError('Original attachment directory is unavailable.');
      }
      // Restored DB sidecars may have been created by a failed reopen.
      for (final extension in const ['-wal', '-shm', '-journal']) {
        final sidecar = File('${liveDatabase.path}$extension');
        await rejectSymlinkedPath(sidecar.path);
        if (await sidecar.exists()) await sidecar.delete();
      }
      if (await liveDatabase.exists()) await liveDatabase.delete();
      await oldDb.rename(liveDatabase.path);
    } else if (!await liveDatabase.exists()) {
      throw StateError('Original SQLite database is unavailable.');
    }

    for (final extension in const ['-wal', '-shm']) {
      final previous = _oldSidecar(liveDatabase, extension, operationId);
      final current = File('${liveDatabase.path}$extension');
      await rejectSymlinkedPath(previous.path);
      if (!await previous.exists()) continue;
      if (await current.exists()) {
        throw StateError('Conflicting SQLite sidecar during restore recovery.');
      }
      await previous.rename(current.path);
    }

    // Delete the marker only after original DB and evidence are back.
    await journal.delete();
    await _cleanupAfterRestore(
      working: working,
      incomingEvidence: incomingEvidence,
    );
  }

  /// Restores the saved SQLite rows and available attachments, applying only
  /// the established SQLite schema migrations to a temporary staged database.
  /// No financial/analysis rule validation or automatic data repair.
  ///
  /// [onStage] is a test/diagnostic hook. Errors before journal deletion trigger
  /// rollback to the exact pre-activation files, not a best-effort merge.
  Future<RawBackupInspection> restoreReplace(
    File encryptedArchive, {
    required String password,
    Future<void> Function(String stage)? onStage,
    // A disposable Merge snapshot must be revalidated before live activation.
    // A failed guard leaves original files, journal and connections untouched.
    Future<void> Function(Database liveConnection)? beforeActivation,
    Future<RawBackupInspection> Function(
      Directory staging,
      RawBackupInspection inspection,
    )?
    prepareStaging,
  }) => EvidenceMutationLock.runExclusive(() async {
    final liveDatabase = File(database.persistenceDatabase.path);
    final evidenceDirectory = await backup.data.evidenceDirectory();
    final parent = liveDatabase.parent;
    await rejectSymlinkedPath(parent.path);
    await rejectSymlinkedPath(evidenceDirectory.path);
    await recoverInterruptedReplace(
      liveDatabase: liveDatabase,
      evidenceDirectory: evidenceDirectory,
    );
    final operationId = DateTime.now().microsecondsSinceEpoch.toString();
    final working = _working(liveDatabase, operationId);
    final staging = Directory(path.join(working.path, 'staged'));
    final incomingEvidence = _incomingEvidence(evidenceDirectory, operationId);
    final oldDatabase = _oldDatabase(liveDatabase, operationId);
    final oldEvidence = _oldEvidence(evidenceDirectory, operationId);
    final journal = File(path.join(parent.path, _journalName));
    var journalWritten = false;
    var committed = false;
    var activationFenced = false;
    var uncertainRecovery = false;
    RandomAccessFile? exclusiveMergeLock;
    await working.create(recursive: true);
    try {
      // On Windows, a locked file cannot be atomically renamed with the
      // POSIX activation protocol. Fail closed instead of running an unsafe
      // physical Merge while a second SQLite writer could be active.
      if (prepareStaging != null && Platform.isWindows) {
        throw StateError(
          'Merge activation requires an exclusive SQLite workspace lock '
          'that is not supported by this Windows restore path.',
        );
      }
      await onStage?.call('archive extraction');
      final inspection = await backup.prepareRestore(
        encryptedArchive,
        password: password,
        stagingDirectory: staging,
      );
      // Upgrade only the extracted, disposable database. The encrypted source
      // archive and the active local database remain untouched until activation.
      await _upgradeStagedSqlite(File(path.join(staging.path, 'butlerly.db')));
      final result = prepareStaging == null
          ? inspection
          : await prepareStaging(staging, inspection);
      final snapshot = File(path.join(staging.path, 'butlerly.db'));
      await _validatePhysicalSqlite(snapshot);

      await onStage?.call('attachment staging');
      await _stageEvidence(
        Directory(path.join(staging.path, 'evidence')),
        incomingEvidence,
      );
      // Fail cleanly if another restore left an unresolved conflict.
      if (await oldDatabase.exists() || await oldEvidence.exists()) {
        throw StateError('A previous restore copy must be reconciled.');
      }
      for (final extension in const ['-wal', '-shm']) {
        if (await _oldSidecar(liveDatabase, extension, operationId).exists()) {
          throw StateError('A previous SQLite sidecar must be reconciled.');
        }
      }

      // Ensure committed WAL pages are in the primary SQLite file before
      // moving it. Never confuse WAL from the old DB with a replacement file.
      final checkpoint = await database.database.rawQuery(
        'PRAGMA wal_checkpoint(TRUNCATE)',
      );
      if (checkpoint.isNotEmpty &&
          checkpoint.first['busy'] is int &&
          checkpoint.first['busy'] != 0) {
        throw StateError('SQLite still has active readers; restore deferred.');
      }

      // All cooperative application writes are serialized by the workspace
      // consistency gate. Fence every other normal persistence connection
      // accessor *before* the final revision check and keep the fence through
      // activation or successful rollback. Captured direct SQLite handles
      // remain a reason to use the consistency gate for every writer.
      await onStage?.call('database connection close');
      database.persistenceDatabase.beginRestoreActivation();
      activationFenced = true;
      await onStage?.call('restore write barrier entered');
      await beforeActivation?.call(
        database.persistenceDatabase.restoreActivationConnection,
      );
      // A retained raw SQLite connection can bypass the repository accessor
      // fence. For Merge, fingerprint the checkpointed source before closing
      // it, then compare after close has drained queued SQLite operations.
      // Any late commit forces rollback instead of discarding that write.
      final preCloseFingerprint = prepareStaging == null
          ? null
          : await sha256FileRange(liveDatabase);
      if (preCloseFingerprint != null) {
        // A direct handle could have committed while hashing. Recheck the
        // recorded live revision after hashing to catch such writes before
        // the durable activation journal is written.
        await beforeActivation?.call(
          database.persistenceDatabase.restoreActivationConnection,
        );
      }

      final markerTemp = File('${journal.path}.tmp');
      await rejectSymlinkedPath(markerTemp.path);
      await markerTemp.writeAsString(
        jsonEncode({
          'format': 'butlerly-raw-restore',
          'operationId': operationId,
          'hadEvidence': await evidenceDirectory.exists(),
        }),
        flush: true,
      );
      await markerTemp.rename(journal.path);
      journalWritten = true;
      await onStage?.call('restore journal written');
      // Do not replace a file while any Butlerly connection holds it open.
      await database.persistenceDatabase.close();
      if (preCloseFingerprint != null) {
        // POSIX SQLite uses advisory byte-range locks on the DB file. Take
        // a nonblocking whole-file exclusive lock after the app connection
        // closes; if another process still owns the SQLite workspace, abort
        // without replacing its database. Keep this handle open through the
        // file swap and never reopen/close another descriptor of the same DB
        // while the lock is held (POSIX close() can release all such locks).
        exclusiveMergeLock = await liveDatabase.open(mode: FileMode.append);
        await exclusiveMergeLock.lock(FileLock.exclusive);
        await onStage?.call('exclusive merge activation lock acquired');
        // A second SQLite connection may retain committed pages in its WAL,
        // leaving the primary DB bytes unchanged. Never activate a Merge
        // while such a write journal remains unresolved.
        for (final suffix in const ['-wal', '-journal']) {
          final pending = File('${liveDatabase.path}$suffix');
          if (await pending.exists() && await pending.length() > 0) {
            throw StateError(
              'SQLite has an outstanding write journal; '
              'Merge activation was canceled.',
            );
          }
        }
        if (preCloseFingerprint != await sha256OpenFile(exclusiveMergeLock)) {
          throw StateError(
            'Live database changed during final Merge activation; '
            'the original database was preserved.',
          );
        }
        // Preserve the *locked* original through a verified, fully written
        // temporary copy. Publishing it to oldDatabase only after the hash
        // matches makes interrupted-copy recovery unambiguous. This permits
        // the staged database to atomically replace the still-present path,
        // avoiding a window where another process might create a new DB.
        await _preserveLockedPrevious(
          exclusiveMergeLock,
          File(path.join(working.path, 'original-db-copy')),
          oldDatabase,
          preCloseFingerprint,
        );
      }

      for (final extension in const ['-wal', '-shm']) {
        final current = File('${liveDatabase.path}$extension');
        if (await current.exists()) {
          await current.rename(
            _oldSidecar(liveDatabase, extension, operationId).path,
          );
        }
      }
      if (preCloseFingerprint == null) {
        // Replace keeps its original journaled move behavior. Merge instead
        // has an already-verified oldDatabase copy and keeps the live path
        // occupied until one atomic POSIX rename installs the merged snapshot.
        await liveDatabase.rename(oldDatabase.path);
      }
      await onStage?.call('original SQLite preserved');
      await rejectEvidenceRoot(evidenceDirectory);
      if (await evidenceDirectory.exists()) {
        await evidenceDirectory.rename(oldEvidence.path);
      }
      await incomingEvidence.rename(evidenceDirectory.path);
      await snapshot.rename(liveDatabase.path);
      await onStage?.call('replacement files activated');

      // Reuse the same ButlerlyDatabase object held by app repositories.
      // On open SQLite applies its normal schema setup, not semantic checks.
      await database.reopenActiveConnection();
      final check = await database
          .persistenceDatabase
          .restoreActivationConnection
          .rawQuery('PRAGMA integrity_check');
      if (check.length != 1 || check.single.values.single != 'ok') {
        throw StateError('Restored SQLite file failed physical integrity.');
      }
      await onStage?.call('restored database reopened');
      await journal
          .delete(); // durable success: rollback copies remain until then
      journalWritten = false;
      committed = true;
      return result;
    } catch (error, stack) {
      if (journalWritten) {
        try {
          // If reopen partially succeeded, close it before file rollback.
          await database.persistenceDatabase.close();
          await recoverInterruptedReplace(
            liveDatabase: liveDatabase,
            evidenceDirectory: evidenceDirectory,
          );
          await database.reopenActiveConnection();
          journalWritten = false;
        } catch (_) {
          // Keep the restore journal and the write fence until recovery.
          // Gateway persists a recovery-only UI marker separately.
          uncertainRecovery = true;
          throw const RestoreRecoveryRequiredException();
        }
      }
      Error.throwWithStackTrace(error, stack);
    } finally {
      if (exclusiveMergeLock != null) {
        // Releasing the activation handle is best effort. In particular,
        // cleanup must not report a committed restore as failed or hide the
        // original error just because OS lock release reports a close error.
        try {
          await exclusiveMergeLock.unlock();
        } catch (_) {}
        try {
          await exclusiveMergeLock.close();
        } catch (_) {}
      }
      if (activationFenced && !uncertainRecovery) {
        database.persistenceDatabase.finishRestoreActivation();
      }
      if (!journalWritten) {
        await _cleanupAfterRestore(
          working: working,
          incomingEvidence: incomingEvidence,
        );
      }
      if (committed) {
        // Cleanup of committed previous copies is best effort, and must never
        // change the result or prematurely erase rollback state.
        try {
          if (await oldDatabase.exists()) await oldDatabase.delete();
          for (final extension in const ['-wal', '-shm']) {
            final previous = _oldSidecar(liveDatabase, extension, operationId);
            if (await previous.exists()) await previous.delete();
          }
          if (await oldEvidence.exists()) {
            await rejectEvidenceTree(oldEvidence);
            await oldEvidence.delete(recursive: true);
          }
        } catch (_) {
          // The journal was already deleted: Restore committed successfully.
          // Retain anything not safely removable for a later cleanup pass.
          // In particular rejectEvidenceTree may throw FormatException.
        }
      }
    }
  });

  /// Copy the locked, checkpointed original to a temporary file on the same
  /// filesystem without opening an additional descriptor of the source DB.
  /// POSIX releases process-wide SQLite advisory locks when *any* descriptor
  /// for that inode is closed, hence File.copy() is unsafe while locked.
  static Future<void> _preserveLockedPrevious(
    RandomAccessFile lockedSource,
    File stagingCopy,
    File previous,
    String expectedHash,
  ) async {
    final output = await stagingCopy.open(mode: FileMode.write);
    try {
      await lockedSource.setPosition(0);
      while (true) {
        final chunk = await lockedSource.read(64 * 1024);
        if (chunk.isEmpty) break;
        await output.writeFrom(chunk);
      }
      await output.flush();
    } finally {
      await output.close();
    }
    if (await sha256FileRange(stagingCopy) != expectedHash) {
      throw StateError('Locked original SQLite copy did not verify.');
    }
    await stagingCopy.rename(previous.path);
  }

  /// Upgrade a staged SQLite file using exactly the same ordered migration
  /// assets as normal Butlerly startup. Never seed catalogs or run analysis
  /// validation: this step changes schema shape, not financial business rules.
  ///
  /// The archive stays encrypted and untouched; any migration failure occurs
  /// before activation and therefore leaves the live SQLite files unchanged.
  Future<void> _upgradeStagedSqlite(File snapshot) async {
    // The same read-only check is performed during the user-facing preview,
    // but recheck here in case the supplied archive changed between actions.
    await backup.requireSupportedSchema(snapshot);
    final template = database.persistenceDatabase;
    final factory = template.factory;
    final reader = await factory.openDatabase(
      snapshot.path,
      options: OpenDatabaseOptions(readOnly: true),
    );
    int sourceVersion;
    try {
      final result = await reader.rawQuery('PRAGMA user_version');
      if (result.length != 1 || result.single.values.single is! int) {
        throw const FormatException('Backup has an invalid SQLite schema.');
      }
      sourceVersion = result.single.values.single as int;
      final integrity = await reader.rawQuery('PRAGMA integrity_check');
      if (integrity.length != 1 || integrity.single.values.single != 'ok') {
        throw const FormatException('Backup SQLite snapshot is damaged.');
      }
    } finally {
      await reader.close();
    }
    if (sourceVersion == template.targetVersion) return;

    // A missing intermediate migration must fail closed; do not let the SQLite
    // opening API create or silently recreate a partial database.
    for (
      var version = sourceVersion + 1;
      version <= template.targetVersion;
      version++
    ) {
      if (!template.migrations.containsKey(version)) {
        throw FormatException('Missing SQLite migration for schema $version.');
      }
    }

    final migrator = ButlerlyDatabase(
      factory: factory,
      path: snapshot.path,
      schemaSql: template.schemaSql,
      migrations: template.migrations,
      targetVersion: template.targetVersion,
    );
    try {
      await migrator.open(seedSystemDataOnOpen: false);
      final integrity = await migrator.connection.rawQuery(
        'PRAGMA integrity_check',
      );
      final version = await migrator.connection.rawQuery('PRAGMA user_version');
      if (integrity.length != 1 ||
          integrity.single.values.single != 'ok' ||
          version.length != 1 ||
          version.single.values.single != template.targetVersion) {
        throw const FormatException('Migrated SQLite snapshot is damaged.');
      }
    } finally {
      await migrator.close();
    }
  }

  Future<void> _validatePhysicalSqlite(File snapshot) async {
    final template = database.persistenceDatabase;
    final factory = template.factory;
    final open = await factory.openDatabase(
      snapshot.path,
      options: OpenDatabaseOptions(readOnly: true),
    );
    try {
      final version = await open.rawQuery('PRAGMA user_version');
      if (version.isEmpty ||
          version.first.values.single != template.targetVersion) {
        throw const FormatException(
          'Backup database schema is not supported by this app.',
        );
      }
      final integrity = await open.rawQuery('PRAGMA integrity_check');
      if (integrity.length != 1 || integrity.single.values.single != 'ok') {
        throw const FormatException('Backup SQLite snapshot is damaged.');
      }
    } finally {
      await open.close();
    }
  }

  Future<void> _stageEvidence(Directory source, Directory destination) async {
    await rejectEvidenceTree(source);
    await rejectSymlinkedPath(destination.path);
    if (await destination.exists()) {
      throw const FileSystemException('Evidence restore staging exists.');
    }
    await destination.create(recursive: true);
    await for (final entity in source.list(
      recursive: true,
      followLinks: false,
    )) {
      await rejectEvidenceLink(entity);
      if (entity is! File) continue;
      final relative = await validateEvidencePath(
        source,
        path.relative(entity.path, from: source.path),
      );
      final target = File(path.join(destination.path, relative));
      await target.parent.create(recursive: true);
      await entity.copy(target.path);
      if (await sha256FileRange(entity) != await sha256FileRange(target)) {
        throw StateError('Attachment staging checksum mismatch.');
      }
    }
  }

  static File _oldDatabase(File live, String id) =>
      File('${live.path}.raw-restore-previous-$id');

  static File _oldSidecar(File live, String extension, String id) =>
      File('${live.path}$extension.raw-restore-previous-$id');

  static Directory _oldEvidence(Directory live, String id) =>
      Directory('${live.path}.raw-restore-previous-$id');

  static Directory _incomingEvidence(Directory live, String id) =>
      Directory('${live.path}.raw-restore-incoming-$id');

  static Directory _working(File live, String id) =>
      Directory(path.join(live.parent.path, '.raw-restore-work-$id'));

  static Future<void> _cleanupAfterRestore({
    required Directory working,
    required Directory incomingEvidence,
  }) async {
    try {
      if (await working.exists()) await working.delete(recursive: true);
      if (await incomingEvidence.exists()) {
        await rejectEvidenceTree(incomingEvidence);
        await incomingEvidence.delete(recursive: true);
      }
    } catch (_) {
      // Working-file cleanup must never mask a successful restore or rollback.
      // A symlink/invalid tree stays in place for recovery-aware maintenance.
    }
  }
}
