import 'dart:convert';
import 'dart:io';

import 'package:butlerly/core/data/local_data_manager.dart';
import 'package:butlerly/core/database/local_database.dart';
import 'package:butlerly_database/butlerly_database.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common/sqlite_api.dart';

enum LocalRestoreMode { merge, replace }

final class BackupChangeSummary {
  const BackupChangeSummary({
    required this.transactionsAdded,
    required this.transactionsChanged,
    required this.masterDataChanged,
    required this.deletedEntities,
  });

  final int transactionsAdded;
  final int transactionsChanged;
  final int masterDataChanged;
  final int deletedEntities;

  bool get hasChanges =>
      transactionsAdded > 0 ||
      transactionsChanged > 0 ||
      masterDataChanged > 0 ||
      deletedEntities > 0;
}

final class BackupInspection {
  const BackupInspection({
    required this.createdAtUtc,
    required this.recordCount,
    required this.evidenceCount,
    required this.changes,
  });

  final DateTime createdAtUtc;
  final int recordCount;
  final int evidenceCount;
  final BackupChangeSummary changes;

  bool get hasNewerLocalData => changes.hasChanges;
}

final class LocalRestoreResult {
  const LocalRestoreResult({
    required this.mode,
    required this.restoredRows,
    required this.keptNewerLocalRows,
    required this.restoredEvidence,
  });

  final LocalRestoreMode mode;
  final int restoredRows;
  final int keptNewerLocalRows;
  final int restoredEvidence;
}

final class _TableSpec {
  const _TableSpec(
    this.name,
    this.keys, {
    this.updatedAt,
    this.createdAt,
    this.systemOwned = false,
    this.mergeUnion = false,
  });

  final String name;
  final List<String> keys;
  final String? updatedAt;
  final String? createdAt;
  final bool systemOwned;
  final bool mergeUnion;
}

final class _EvidenceDescriptor {
  const _EvidenceDescriptor({
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

final class _BackupPackage {
  const _BackupPackage({
    required this.file,
    required this.manifest,
    required this.tables,
    required this.evidence,
  });

  final File file;
  final Map<String, Object?> manifest;
  final Map<String, Object?> tables;
  final List<_EvidenceDescriptor> evidence;
}

final class _PreparedEvidence {
  const _PreparedEvidence({
    required this.directory,
    required this.addedCount,
    required this.pathRemaps,
  });

  final Directory directory;
  final int addedCount;
  final Map<String, String> pathRemaps;
}

final class LocalBackupManager {
  const LocalBackupManager(this.database, this.localDataManager);

  final LocalDatabase database;
  final LocalDataManager localDataManager;

  static const format = 'butlerly-backup';
  static const formatVersion = 2;
  static const schemaVersion = 8;
  static final _magic = utf8.encode('BUTLERLYBACKUP2');

  static const _tables = <_TableSpec>[
    _TableSpec('payment_sources', ['id'], updatedAt: 'updated_at', createdAt: 'created_at'),
    _TableSpec('categories', ['id'], updatedAt: 'updated_at', createdAt: 'created_at', systemOwned: true),
    _TableSpec('merchants', ['id'], updatedAt: 'updated_at', createdAt: 'created_at', systemOwned: true),
    _TableSpec('tags', ['id'], updatedAt: 'updated_at', createdAt: 'created_at', systemOwned: true),
    _TableSpec('provenances', ['id'], createdAt: 'captured_at'),
    _TableSpec('exchange_rates', ['id'], createdAt: 'effective_at'),
    _TableSpec('transactions', ['id'], updatedAt: 'updated_at', createdAt: 'created_at'),
    _TableSpec('normalized_money', ['transaction_id', 'exchange_rate_id'], updatedAt: 'updated_at'),
    _TableSpec('transaction_provenances', ['transaction_id', 'provenance_id'], mergeUnion: true),
    _TableSpec('transaction_tags', ['transaction_id', 'tag_id'], createdAt: 'created_at'),
    _TableSpec('evidence_items', ['id'], createdAt: 'created_at'),
    _TableSpec('financial_statements', ['id'], updatedAt: 'updated_at', createdAt: 'created_at'),
    _TableSpec('statement_rows', ['id'], updatedAt: 'updated_at', createdAt: 'created_at'),
    _TableSpec('extractions', ['id'], createdAt: 'created_at'),
    _TableSpec('attachment_links', ['id'], createdAt: 'created_at'),
    _TableSpec('suggestions', ['id'], updatedAt: 'decided_at', createdAt: 'created_at'),
    _TableSpec('review_issues', ['id'], updatedAt: 'closed_at', createdAt: 'created_at'),
    _TableSpec('reconciliation_candidates', ['id'], updatedAt: 'updated_at', createdAt: 'created_at'),
    _TableSpec('reconciliation_links', ['id'], createdAt: 'created_at'),
    _TableSpec('duplicate_candidate_groups', ['id'], updatedAt: 'updated_at', createdAt: 'created_at'),
    _TableSpec('duplicate_candidate_group_transactions', ['group_id', 'transaction_id']),
    _TableSpec('analysis_rule_activations', ['rule_id'], updatedAt: 'updated_at'),
    _TableSpec('analysis_rule_configurations', ['rule_id'], updatedAt: 'updated_at'),
    _TableSpec('user_preferences', ['id'], updatedAt: 'updated_at'),
  ];

  static final _specByName = <String, _TableSpec>{for (final spec in _tables) spec.name: spec};

  static const _derivedTables = <String>['analysis_findings', 'analysis_rule_results'];

  Future<File> createBackup(File destination) async {
    await database.persistenceDatabase.prepareForConsistentBackup();
    final createdAt = DateTime.now().toUtc();
    final tables = <String, Object?>{};
    var recordCount = 0;
    for (final spec in _tables) {
      final rows = await _portableRows(spec);
      tables[spec.name] = rows;
      recordCount += rows.length;
    }
    final tombstones = await database.database.query('entity_tombstones');
    tables['entity_tombstones'] = tombstones;
    recordCount += tombstones.length;

    final evidenceRoot = await localDataManager.evidenceDirectory();
    final evidence = <Map<String, Object?>>[];
    final sourceFiles = <File>[];
    if (await evidenceRoot.exists()) {
      await for (final entity in evidenceRoot.list(recursive: true)) {
        if (entity is! File) continue;
        final relative = path.normalize(path.relative(entity.path, from: evidenceRoot.path));
        final length = await entity.length();
        evidence.add({
          'path': relative,
          'length': length,
          'sha256': await sha256FileRange(entity),
        });
        sourceFiles.add(entity);
      }
    }

    final metadata = <String, Object?>{
      'manifest': {
        'format': format,
        'formatVersion': formatVersion,
        'schemaVersion': schemaVersion,
        'createdAtUtc': createdAt.toIso8601String(),
        'recordCount': recordCount,
        'evidenceCount': evidence.length,
        'derivedDataPolicy': 'rebuild',
      },
      'tables': tables,
      'evidence': evidence,
    };
    final metadataBytes = utf8.encode(jsonEncode(metadata));
    final metadataHash = ascii.encode(sha256Bytes(metadataBytes));
    final temporary = File('${destination.path}.tmp-${DateTime.now().microsecondsSinceEpoch}');
    await temporary.parent.create(recursive: true);
    final sink = temporary.openWrite();
    try {
      sink.add(_magic);
      sink.add(int64Bytes(metadataBytes.length));
      sink.add(metadataHash);
      sink.add(metadataBytes);
      for (final file in sourceFiles) {
        await sink.addStream(file.openRead());
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    if (await destination.exists()) await destination.delete();
    await temporary.rename(destination.path);
    return destination;
  }

  Future<BackupInspection> inspect(File file) async {
    final package = await _readPackage(file);
    final createdAt = DateTime.parse(package.manifest['createdAtUtc']! as String).toUtc();
    return BackupInspection(
      createdAtUtc: createdAt,
      recordCount: package.manifest['recordCount']! as int,
      evidenceCount: package.manifest['evidenceCount']! as int,
      changes: await _newerLocalSummary(createdAt),
    );
  }

  Future<void> recoverInterruptedRestore() async {
    final root = await localDataManager.evidenceDirectory();
    final journal = File('${root.path}.restore-journal.json');
    if (!await journal.exists()) return;
    Map<String, Object?> data;
    try {
      final decoded = jsonDecode(await journal.readAsString());
      if (decoded is! Map) throw const FormatException();
      data = decoded.cast<String, Object?>();
    } on Exception {
      return;
    }
    final operationId = data['operationId'] as String?;
    final previousPath = data['previousPath'] as String?;
    final stagingPath = data['stagingPath'] as String?;
    final phase = data['phase'] as String? ?? 'prepared';
    if (operationId == null) return;
    final committed = await database.database.query(
      'restore_commits',
      columns: ['operation_id'],
      where: 'operation_id = ?',
      whereArgs: [operationId],
      limit: 1,
    );
    if (committed.isNotEmpty) {
      if (previousPath != null) {
        final previous = Directory(previousPath);
        if (await previous.exists()) await previous.delete(recursive: true);
      }
      if (stagingPath != null) {
        final staging = Directory(stagingPath);
        if (await staging.exists()) await staging.delete(recursive: true);
      }
      await database.database.delete('restore_commits', where: 'operation_id = ?', whereArgs: [operationId]);
      await journal.delete();
      return;
    }
    if (phase == 'evidenceActivated' || phase == 'dbWriting') {
      if (previousPath != null) {
        final previous = Directory(previousPath);
        if (await previous.exists()) {
          if (await root.exists()) await root.delete(recursive: true);
          await previous.rename(root.path);
        }
      }
    }
    if (stagingPath != null) {
      final staging = Directory(stagingPath);
      if (await staging.exists()) await staging.delete(recursive: true);
    }
    if (await journal.exists()) await journal.delete();
  }

  Future<LocalRestoreResult> restore(File file, {required LocalRestoreMode mode}) async {
    await recoverInterruptedRestore();
    final package = await _readPackage(file);
    final backupTime = DateTime.parse(package.manifest['createdAtUtc']! as String).toUtc();
    final tablePayload = <String, Object?>{...package.tables};
    final protectedTransactions = mode == LocalRestoreMode.merge
        ? await _protectedTransactionIds(tablePayload, backupTime)
        : <String>{};
    final prepared = await _prepareEvidence(package, mode: mode);
    _applyEvidenceRemaps(tablePayload, prepared.pathRemaps);

    final root = await localDataManager.evidenceDirectory();
    final operationId = 'restore-${DateTime.now().microsecondsSinceEpoch}';
    final previous = Directory('${root.path}.restore-previous-$operationId');
    final journal = File('${root.path}.restore-journal.json');
    await _writeJournal(journal, operationId, previous.path, prepared.directory.path, 'prepared');

    var restoredRows = 0;
    var keptNewer = 0;
    var evidenceActivated = false;
    try {
      if (await root.exists()) await root.rename(previous.path);
      await prepared.directory.rename(root.path);
      evidenceActivated = true;
      await _writeJournal(journal, operationId, previous.path, prepared.directory.path, 'evidenceActivated');
      await database.database.transaction((tx) async {
        await _writeJournal(journal, operationId, previous.path, prepared.directory.path, 'dbWriting');
        if (mode == LocalRestoreMode.replace) {
          await _clearPortableState(tx);
        } else {
          keptNewer += await _applyBackupTombstones(tx, tablePayload, backupTime);
        }
        for (final spec in _tables) {
          final payload = (tablePayload[spec.name] as List? ?? const <Object?>[])
              .cast<Map>()
              .map((row) => row.cast<String, Object?>());
          for (final row in payload) {
            if (_isSystemOwned(spec, row)) continue;
            if (mode == LocalRestoreMode.merge) {
              if (_referencesProtectedTransaction(spec, row, protectedTransactions)) {
                keptNewer++;
                continue;
              }
              if (await _hasNewerLocalTombstone(tx, spec, row, backupTime)) {
                keptNewer++;
                continue;
              }
              final local = await _findRow(tx, spec, row);
              if (local != null && _rowChangedAfter(local, spec, backupTime)) {
                keptNewer++;
                continue;
              }
            }
            await _upsertRow(tx, spec, row);
            await _clearTombstoneForRestoredRow(tx, spec, row);
            restoredRows++;
          }
        }
        if (mode == LocalRestoreMode.replace) {
          final tombstones = (tablePayload['entity_tombstones'] as List? ?? const <Object?>[]).cast<Map>();
          for (final raw in tombstones) {
            final row = raw.cast<String, Object?>();
            if (_isSystemId(row['entity_type'] as String?, row['entity_id'])) continue;
            await tx.insert('entity_tombstones', row, conflictAlgorithm: ConflictAlgorithm.replace);
          }
        }
        for (final table in _derivedTables) {
          await tx.delete(table);
        }
        await tx.insert('restore_commits', {
          'operation_id': operationId,
          'committed_at': DateTime.now().toUtc().toIso8601String(),
        });
      });
      await _writeJournal(journal, operationId, previous.path, prepared.directory.path, 'dbCommitted');
    } catch (_) {
      if (evidenceActivated) {
        if (await root.exists()) await root.delete(recursive: true);
        if (await previous.exists()) await previous.rename(root.path);
      } else if (await prepared.directory.exists()) {
        await prepared.directory.delete(recursive: true);
      }
      if (await journal.exists()) await journal.delete();
      rethrow;
    }

    if (await previous.exists()) await previous.delete(recursive: true);
    await database.database.delete('restore_commits', where: 'operation_id = ?', whereArgs: [operationId]);
    if (await journal.exists()) await journal.delete();
    return LocalRestoreResult(
      mode: mode,
      restoredRows: restoredRows,
      keptNewerLocalRows: keptNewer,
      restoredEvidence: prepared.addedCount,
    );
  }

  Future<void> _writeJournal(File journal, String operationId, String previous, String staging, String phase) async {
    await journal.writeAsString(jsonEncode({
      'operationId': operationId,
      'previousPath': previous,
      'stagingPath': staging,
      'phase': phase,
    }), flush: true);
  }

  Future<_BackupPackage> _readPackage(File file) async {
    final raf = await file.open(mode: FileMode.read);
    try {
      final magic = await raf.read(_magic.length);
      if (!_listEquals(magic, _magic)) throw const FormatException('Unsupported Butlerly backup format.');
      final lengthBytes = await raf.read(8);
      if (lengthBytes.length != 8) throw const FormatException('Incomplete Butlerly backup header.');
      final metadataLength = int64FromBytes(lengthBytes);
      if (metadataLength <= 0 || metadataLength > 128 * 1024 * 1024) {
        throw const FormatException('Invalid Butlerly backup metadata length.');
      }
      final expectedHashBytes = await raf.read(64);
      if (expectedHashBytes.length != 64) throw const FormatException('Incomplete Butlerly backup checksum.');
      final metadataBytes = await raf.read(metadataLength);
      if (metadataBytes.length != metadataLength) throw const FormatException('Incomplete Butlerly backup metadata.');
      if (sha256Bytes(metadataBytes) != ascii.decode(expectedHashBytes)) {
        throw const FormatException('Backup metadata integrity validation failed.');
      }
      final decoded = jsonDecode(utf8.decode(metadataBytes));
      if (decoded is! Map) throw const FormatException('Invalid Butlerly backup metadata.');
      final metadata = decoded.cast<String, Object?>();
      final manifest = (metadata['manifest'] as Map?)?.cast<String, Object?>();
      final tables = (metadata['tables'] as Map?)?.cast<String, Object?>();
      final evidenceRaw = metadata['evidence'] as List?;
      if (manifest == null || tables == null || evidenceRaw == null) {
        throw const FormatException('Incomplete Butlerly backup metadata.');
      }
      if (manifest['format'] != format || manifest['formatVersion'] != formatVersion) {
        throw const FormatException('Unsupported Butlerly backup format.');
      }
      final sourceSchema = manifest['schemaVersion'] as int?;
      if (sourceSchema == null || sourceSchema > schemaVersion) {
        throw const FormatException('Backup was created by a newer Butlerly schema.');
      }
      var offset = _magic.length + 8 + 64 + metadataLength;
      final descriptors = <_EvidenceDescriptor>[];
      for (final raw in evidenceRaw.cast<Map>()) {
        final item = raw.cast<String, Object?>();
        final relative = item['path'] as String?;
        final length = item['length'] as int?;
        final hash = item['sha256'] as String?;
        if (relative == null || length == null || length < 0 || hash == null) {
          throw const FormatException('Invalid evidence descriptor.');
        }
        descriptors.add(_EvidenceDescriptor(relativePath: relative, length: length, sha256: hash, offset: offset));
        offset += length;
      }
      if (await file.length() != offset) throw const FormatException('Backup file length does not match its manifest.');
      return _BackupPackage(file: file, manifest: manifest, tables: tables, evidence: descriptors);
    } finally {
      await raf.close();
    }
  }

  Future<_PreparedEvidence> _prepareEvidence(_BackupPackage package, {required LocalRestoreMode mode}) async {
    final root = await localDataManager.evidenceDirectory();
    final staging = Directory('${root.path}.restore-${DateTime.now().microsecondsSinceEpoch}');
    if (await staging.exists()) await staging.delete(recursive: true);
    await staging.create(recursive: true);
    if (mode == LocalRestoreMode.merge && await root.exists()) await _copyDirectory(root, staging);
    var added = 0;
    final remaps = <String, String>{};
    try {
      for (final item in package.evidence) {
        final normalized = path.normalize(item.relativePath);
        if (path.isAbsolute(normalized) || normalized == '..' || normalized.startsWith('../')) {
          throw const FormatException('Unsafe evidence path.');
        }
        final actualHash = await sha256FileRange(
          package.file,
          start: item.offset,
          endExclusive: item.offset + item.length,
        );
        if (actualHash != item.sha256) throw const FormatException('Evidence integrity validation failed.');
        var relative = normalized;
        var destination = File(path.join(staging.path, relative));
        if (mode == LocalRestoreMode.merge && await destination.exists()) {
          final existingHash = await sha256FileRange(destination);
          if (existingHash == item.sha256) continue;
          final extension = path.extension(relative);
          final base = path.basenameWithoutExtension(relative);
          relative = path.join(path.dirname(relative), '$base.backup-${item.sha256.substring(0, 8)}$extension');
          destination = File(path.join(staging.path, relative));
          remaps[normalized] = relative;
        }
        await destination.parent.create(recursive: true);
        final sink = destination.openWrite();
        try {
          await sink.addStream(package.file.openRead(item.offset, item.offset + item.length));
          await sink.flush();
        } finally {
          await sink.close();
        }
        added++;
      }
      return _PreparedEvidence(directory: staging, addedCount: added, pathRemaps: remaps);
    } catch (_) {
      if (await staging.exists()) await staging.delete(recursive: true);
      rethrow;
    }
  }

  void _applyEvidenceRemaps(Map<String, Object?> tablePayload, Map<String, String> remaps) {
    if (remaps.isEmpty) return;
    final rows = (tablePayload['evidence_items'] as List? ?? const <Object?>[]).cast<Map>();
    for (final raw in rows) {
      final row = raw.cast<String, Object?>();
      final current = row['local_file_name'] as String?;
      if (current == null) continue;
      final normalized = path.normalize(current);
      final replacement = remaps[normalized] ?? remaps.entries
          .where((entry) => path.basename(entry.key) == path.basename(normalized))
          .map((entry) => entry.value)
          .firstOrNull;
      if (replacement != null) row['local_file_name'] = replacement;
    }
  }

  Future<Set<String>> _protectedTransactionIds(Map<String, Object?> tablePayload, DateTime backupTime) async {
    final protected = <String>{};
    final spec = _specByName['transactions']!;
    final rows = (tablePayload['transactions'] as List? ?? const <Object?>[]).cast<Map>();
    for (final raw in rows) {
      final row = raw.cast<String, Object?>();
      final id = row['id'] as String?;
      if (id == null) continue;
      if (await _hasNewerLocalTombstone(database.database, spec, row, backupTime)) {
        protected.add(id);
        continue;
      }
      final local = await database.database.query('transactions', where: 'id = ?', whereArgs: [id], limit: 1);
      if (local.isNotEmpty && _rowChangedAfter(local.single, spec, backupTime)) protected.add(id);
    }
    final newer = await database.database.query(
      'transactions',
      columns: ['id'],
      where: 'created_at > ?',
      whereArgs: [backupTime.toIso8601String()],
    );
    protected.addAll(newer.map((row) => row['id']! as String));
    return protected;
  }

  bool _referencesProtectedTransaction(_TableSpec spec, Map<String, Object?> row, Set<String> protected) {
    if (protected.isEmpty || spec.name == 'transactions') return false;
    for (final field in const ['transaction_id', 'receipt_transaction_id', 'payment_transaction_id']) {
      final value = row[field];
      if (value is String && protected.contains(value)) return true;
    }
    return false;
  }

  Future<BackupChangeSummary> _newerLocalSummary(DateTime backupTime) async {
    final cutoff = backupTime.toIso8601String();
    final added = Sqflite.firstIntValue(await database.database.rawQuery(
      'SELECT COUNT(*) FROM transactions WHERE created_at > ?', [cutoff],
    )) ?? 0;
    final changed = Sqflite.firstIntValue(await database.database.rawQuery(
      'SELECT COUNT(*) FROM transactions WHERE created_at <= ? AND updated_at > ?', [cutoff, cutoff],
    )) ?? 0;
    var master = 0;
    for (final query in <String>[
      "SELECT COUNT(*) FROM payment_sources WHERE COALESCE(updated_at, created_at) > '$cutoff'",
      "SELECT COUNT(*) FROM categories WHERE LOWER(origin) != 'system' AND COALESCE(updated_at, created_at) > '$cutoff'",
      "SELECT COUNT(*) FROM merchants WHERE is_built_in = 0 AND COALESCE(updated_at, created_at) > '$cutoff'",
      "SELECT COUNT(*) FROM tags WHERE id NOT LIKE 'tag.%' AND id NOT LIKE 'system-tag-%' AND COALESCE(updated_at, created_at) > '$cutoff'",
    ]) {
      master += Sqflite.firstIntValue(await database.database.rawQuery(query)) ?? 0;
    }
    final deleted = Sqflite.firstIntValue(await database.database.rawQuery(
      'SELECT COUNT(*) FROM entity_tombstones WHERE deleted_at > ?', [cutoff],
    )) ?? 0;
    return BackupChangeSummary(
      transactionsAdded: added,
      transactionsChanged: changed,
      masterDataChanged: master,
      deletedEntities: deleted,
    );
  }

  Future<List<Map<String, Object?>>> _portableRows(_TableSpec spec) async {
    if (!spec.systemOwned) return database.database.query(spec.name);
    switch (spec.name) {
      case 'categories':
        return database.database.query(spec.name, where: 'LOWER(origin) != ?', whereArgs: ['system'], orderBy: 'CASE WHEN parent_id IS NULL THEN 0 ELSE 1 END, id');
      case 'merchants':
        return database.database.query(spec.name, where: 'is_built_in = 0');
      case 'tags':
        return database.database.query(spec.name, where: "id NOT LIKE 'tag.%' AND id NOT LIKE 'system-tag-%'");
    }
    return database.database.query(spec.name);
  }

  Future<int> _applyBackupTombstones(Transaction tx, Map<String, Object?> tablePayload, DateTime backupTime) async {
    var kept = 0;
    final tombstones = (tablePayload['entity_tombstones'] as List? ?? const <Object?>[]).cast<Map>();
    for (final raw in tombstones) {
      final tombstone = raw.cast<String, Object?>();
      final entityType = tombstone['entity_type'] as String?;
      final entityId = tombstone['entity_id'];
      final spec = entityType == null ? null : _specByName[entityType];
      if (spec == null || entityId == null || _isSystemId(entityType, entityId)) continue;
      final values = _keyValuesFromTombstone(spec, '$entityId');
      if (values == null) continue;
      final localRows = await _queryByKeys(tx, spec, values);
      if (localRows.isNotEmpty && _rowChangedAfter(localRows.single, spec, backupTime)) {
        kept++;
        continue;
      }
      if (localRows.isNotEmpty) await _deleteByKeys(tx, spec, values);
      await tx.insert('entity_tombstones', tombstone, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    return kept;
  }

  Future<bool> _hasNewerLocalTombstone(DatabaseExecutor tx, _TableSpec spec, Map<String, Object?> row, DateTime backupTime) async {
    final id = _tombstoneId(spec, row);
    if (id == null) return false;
    final results = await tx.query(
      'entity_tombstones',
      where: 'entity_type = ? AND entity_id = ? AND deleted_at > ?',
      whereArgs: [spec.name, id, backupTime.toIso8601String()],
      limit: 1,
    );
    return results.isNotEmpty;
  }

  Future<void> _clearTombstoneForRestoredRow(Transaction tx, _TableSpec spec, Map<String, Object?> row) async {
    final id = _tombstoneId(spec, row);
    if (id == null) return;
    await tx.delete('entity_tombstones', where: 'entity_type = ? AND entity_id = ?', whereArgs: [spec.name, id]);
  }

  String? _tombstoneId(_TableSpec spec, Map<String, Object?> row) {
    final values = spec.keys.map((key) => row[key]).toList();
    if (values.any((value) => value == null)) return null;
    return values.map((value) => '$value').join('|');
  }

  List<Object?>? _keyValuesFromTombstone(_TableSpec spec, String id) {
    if (spec.keys.length == 1) return [id];
    final values = id.split('|');
    return values.length == spec.keys.length ? values : null;
  }

  Future<Map<String, Object?>?> _findRow(DatabaseExecutor tx, _TableSpec spec, Map<String, Object?> row) async {
    final values = spec.keys.map((key) => row[key]).toList(growable: false);
    final rows = await _queryByKeys(tx, spec, values);
    return rows.isEmpty ? null : rows.single;
  }

  Future<List<Map<String, Object?>>> _queryByKeys(DatabaseExecutor tx, _TableSpec spec, List<Object?> values) {
    final where = <String>[];
    final args = <Object?>[];
    for (var index = 0; index < spec.keys.length; index++) {
      final value = values[index];
      if (value == null) {
        where.add('${spec.keys[index]} IS NULL');
      } else {
        where.add('${spec.keys[index]} = ?');
        args.add(value);
      }
    }
    return tx.query(spec.name, where: where.join(' AND '), whereArgs: args, limit: 1);
  }

  Future<void> _deleteByKeys(DatabaseExecutor tx, _TableSpec spec, List<Object?> values) async {
    final where = <String>[];
    final args = <Object?>[];
    for (var index = 0; index < spec.keys.length; index++) {
      final value = values[index];
      if (value == null) {
        where.add('${spec.keys[index]} IS NULL');
      } else {
        where.add('${spec.keys[index]} = ?');
        args.add(value);
      }
    }
    await tx.delete(spec.name, where: where.join(' AND '), whereArgs: args);
  }

  Future<void> _upsertRow(Transaction tx, _TableSpec spec, Map<String, Object?> row) async {
    if (spec.mergeUnion) {
      await tx.insert(spec.name, row, conflictAlgorithm: ConflictAlgorithm.ignore);
      return;
    }
    final existing = await _findRow(tx, spec, row);
    if (existing == null) {
      await tx.insert(spec.name, row);
      return;
    }
    final values = spec.keys.map((key) => row[key]).toList(growable: false);
    final where = <String>[];
    final args = <Object?>[];
    for (var index = 0; index < spec.keys.length; index++) {
      final value = values[index];
      if (value == null) {
        where.add('${spec.keys[index]} IS NULL');
      } else {
        where.add('${spec.keys[index]} = ?');
        args.add(value);
      }
    }
    await tx.update(spec.name, row, where: where.join(' AND '), whereArgs: args);
  }

  bool _rowChangedAfter(Map<String, Object?> row, _TableSpec spec, DateTime cutoff) {
    for (final field in [spec.updatedAt, spec.createdAt]) {
      if (field == null) continue;
      final value = row[field];
      if (value is! String || value.isEmpty) continue;
      final parsed = DateTime.tryParse(value)?.toUtc();
      if (parsed != null && parsed.isAfter(cutoff)) return true;
    }
    return false;
  }

  bool _isSystemOwned(_TableSpec spec, Map<String, Object?> row) => switch (spec.name) {
    'categories' => '${row['origin']}'.toLowerCase() == 'system',
    'merchants' => row['is_built_in'] == 1,
    'tags' => _isSystemId('tags', row['id']),
    _ => false,
  };

  bool _isSystemId(String? entityType, Object? rawId) {
    final id = '$rawId';
    return switch (entityType) {
      'categories' => id.startsWith('category.'),
      'merchants' => id.startsWith('merchant.'),
      'tags' => id.startsWith('tag.') || id.startsWith('system-tag-'),
      _ => false,
    };
  }

  Future<void> _clearPortableState(Transaction tx) async {
    const childFirst = <String>[
      'duplicate_candidate_group_transactions',
      'duplicate_candidate_groups',
      'reconciliation_links',
      'reconciliation_candidates',
      'review_issues',
      'suggestions',
      'attachment_links',
      'extractions',
      'statement_rows',
      'financial_statements',
      'evidence_items',
      'transaction_tags',
      'transaction_provenances',
      'normalized_money',
      'transactions',
      'exchange_rates',
      'provenances',
      'analysis_rule_configurations',
      'analysis_rule_activations',
      'payment_sources',
      'user_preferences',
    ];
    for (final table in childFirst) await tx.delete(table);
    await tx.delete('merchants', where: 'is_built_in = 0');
    await tx.delete('categories', where: "LOWER(origin) != 'system'");
    await tx.delete('tags', where: "id NOT LIKE 'tag.%' AND id NOT LIKE 'system-tag-%'");
    await tx.delete('entity_tombstones');
  }

  Future<void> _copyDirectory(Directory source, Directory destination) async {
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

  bool _listEquals(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) return false;
    }
    return true;
  }
}
