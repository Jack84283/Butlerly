import 'dart:convert';
import 'dart:io';

import 'package:butlerly/core/data/local_data_manager.dart';
import 'package:butlerly/core/database/local_database.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common/sqlite_api.dart';

enum LocalRestoreMode { merge, replace }

final class BackupInspection {
  const BackupInspection({
    required this.createdAtUtc,
    required this.recordCount,
    required this.evidenceCount,
    required this.hasNewerLocalData,
  });

  final DateTime createdAtUtc;
  final int recordCount;
  final int evidenceCount;
  final bool hasNewerLocalData;
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

final class _PreparedEvidence {
  const _PreparedEvidence({required this.directory, required this.addedCount});

  final Directory directory;
  final int addedCount;
}

/// Versioned, portable Butlerly backup and restore service.
///
/// The backup contract is independent of the live SQLite file. Authoritative
/// rows are serialized by stable ID, receipt/evidence bytes are checksum
/// protected, current application-owned master data is retained on restore,
/// and Analysis/Insights materializations are rebuilt rather than restored.
final class LocalBackupManager {
  const LocalBackupManager(this.database, this.localDataManager);

  final LocalDatabase database;
  final LocalDataManager localDataManager;

  static const format = 'butlerly-backup';
  static const formatVersion = 1;
  static const schemaVersion = 8;

  static const _tables = <_TableSpec>[
    _TableSpec(
      'payment_sources',
      ['id'],
      updatedAt: 'updated_at',
      createdAt: 'created_at',
    ),
    // Categories precede Merchants because a user Merchant may reference a
    // user Category through its default classification.
    _TableSpec(
      'categories',
      ['id'],
      updatedAt: 'updated_at',
      createdAt: 'created_at',
      systemOwned: true,
    ),
    _TableSpec(
      'merchants',
      ['id'],
      updatedAt: 'updated_at',
      createdAt: 'created_at',
      systemOwned: true,
    ),
    _TableSpec(
      'tags',
      ['id'],
      updatedAt: 'updated_at',
      createdAt: 'created_at',
      systemOwned: true,
    ),
    _TableSpec('provenances', ['id'], createdAt: 'captured_at'),
    _TableSpec('exchange_rates', ['id'], createdAt: 'effective_at'),
    _TableSpec(
      'transactions',
      ['id'],
      updatedAt: 'updated_at',
      createdAt: 'created_at',
    ),
    _TableSpec(
      'transaction_provenances',
      ['transaction_id', 'provenance_id'],
      mergeUnion: true,
    ),
    _TableSpec(
      'transaction_tags',
      ['transaction_id', 'tag_id'],
      createdAt: 'created_at',
    ),
    _TableSpec('evidence_items', ['id'], createdAt: 'created_at'),
    _TableSpec(
      'financial_statements',
      ['id'],
      updatedAt: 'updated_at',
      createdAt: 'created_at',
    ),
    _TableSpec(
      'statement_rows',
      ['id'],
      updatedAt: 'updated_at',
      createdAt: 'created_at',
    ),
    _TableSpec('extractions', ['id'], createdAt: 'created_at'),
    _TableSpec('attachment_links', ['id'], createdAt: 'created_at'),
    _TableSpec(
      'suggestions',
      ['id'],
      updatedAt: 'decided_at',
      createdAt: 'created_at',
    ),
    _TableSpec(
      'review_issues',
      ['id'],
      updatedAt: 'closed_at',
      createdAt: 'created_at',
    ),
    _TableSpec(
      'reconciliation_candidates',
      ['id'],
      updatedAt: 'updated_at',
      createdAt: 'created_at',
    ),
    _TableSpec('reconciliation_links', ['id'], createdAt: 'created_at'),
    _TableSpec(
      'duplicate_candidate_groups',
      ['id'],
      updatedAt: 'updated_at',
      createdAt: 'created_at',
    ),
    _TableSpec(
      'duplicate_candidate_group_transactions',
      ['group_id', 'transaction_id'],
      mergeUnion: true,
    ),
    _TableSpec(
      'analysis_rule_activations',
      ['rule_id'],
      updatedAt: 'updated_at',
    ),
    _TableSpec(
      'analysis_rule_configurations',
      ['rule_id'],
      updatedAt: 'updated_at',
    ),
    _TableSpec('user_preferences', ['id'], updatedAt: 'updated_at'),
  ];

  static final _specByName = <String, _TableSpec>{
    for (final spec in _tables) spec.name: spec,
  };

  static const _derivedTables = <String>[
    'analysis_findings',
    'analysis_rule_results',
  ];

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

    final evidencePayload = <Map<String, Object?>>[];
    final evidenceDirectory = await localDataManager.evidenceDirectory();
    if (await evidenceDirectory.exists()) {
      await for (final entity in evidenceDirectory.list(recursive: true)) {
        if (entity is! File) continue;
        final bytes = await entity.readAsBytes();
        evidencePayload.add({
          'path': path.relative(entity.path, from: evidenceDirectory.path),
          'length': bytes.length,
          'sha256': sha256.convert(bytes).toString(),
          'bytes': base64Encode(bytes),
        });
      }
    }

    final package = <String, Object?>{
      'manifest': {
        'format': format,
        'formatVersion': formatVersion,
        'schemaVersion': schemaVersion,
        'createdAtUtc': createdAt.toIso8601String(),
        'recordCount': recordCount,
        'evidenceCount': evidencePayload.length,
        'derivedDataPolicy': 'rebuild',
      },
      'tables': tables,
      'evidence': evidencePayload,
    };
    final encoded = utf8.encode(jsonEncode(package));
    final wrapper = <String, Object?>{
      'format': format,
      'formatVersion': formatVersion,
      'payloadSha256': sha256.convert(encoded).toString(),
      'payload': base64Encode(encoded),
    };
    await destination.parent.create(recursive: true);
    await destination.writeAsString(jsonEncode(wrapper), flush: true);
    return destination;
  }

  Future<BackupInspection> inspect(File file) async {
    final package = await _readPackage(file);
    final manifest = package['manifest']! as Map<String, Object?>;
    final createdAt = DateTime.parse(manifest['createdAtUtc']! as String).toUtc();
    return BackupInspection(
      createdAtUtc: createdAt,
      recordCount: manifest['recordCount']! as int,
      evidenceCount: manifest['evidenceCount']! as int,
      hasNewerLocalData: await _hasNewerLocalData(createdAt),
    );
  }

  Future<LocalRestoreResult> restore(
    File file, {
    required LocalRestoreMode mode,
  }) async {
    final package = await _readPackage(file);
    final manifest = package['manifest']! as Map<String, Object?>;
    final backupTime = DateTime.parse(
      manifest['createdAtUtc']! as String,
    ).toUtc();
    final tablePayload = (package['tables']! as Map).cast<String, Object?>();
    final evidencePayload = (package['evidence'] as List? ?? const <Object?>[])
        .cast<Map>();

    // Validate and stage every evidence file before modifying live state.
    final prepared = await _prepareEvidence(evidencePayload, mode: mode);
    Directory? previousEvidence;
    var activated = false;
    var restoredRows = 0;
    var keptNewer = 0;
    try {
      previousEvidence = await _activatePreparedEvidence(prepared.directory);
      activated = true;
      try {
        await database.database.transaction((tx) async {
          if (mode == LocalRestoreMode.replace) {
            await _clearPortableState(tx);
          } else {
            keptNewer += await _applyBackupTombstones(
              tx,
              tablePayload,
              backupTime,
            );
          }

          for (final spec in _tables) {
            final payload =
                (tablePayload[spec.name] as List? ?? const <Object?>[])
                    .cast<Map>()
                    .map((row) => row.cast<String, Object?>());
            for (final row in payload) {
              if (_isSystemOwned(spec, row)) continue;
              if (mode == LocalRestoreMode.merge) {
                if (await _hasNewerLocalTombstone(tx, spec, row, backupTime)) {
                  keptNewer++;
                  continue;
                }
                final local = await _findRow(tx, spec, row);
                if (local != null &&
                    _rowChangedAfter(local, spec, backupTime)) {
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
            final tombstones =
                (tablePayload['entity_tombstones'] as List? ??
                        const <Object?>[])
                    .cast<Map>();
            for (final raw in tombstones) {
              final row = raw.cast<String, Object?>();
              if (_isSystemId(
                row['entity_type'] as String?,
                row['entity_id'],
              )) {
                continue;
              }
              await tx.insert(
                'entity_tombstones',
                row,
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
            }
          }

          for (final table in _derivedTables) {
            await tx.delete(table);
          }
        });
      } catch (_) {
        await _rollbackEvidence(previousEvidence);
        activated = false;
        rethrow;
      }
    } catch (_) {
      if (!activated && await prepared.directory.exists()) {
        await prepared.directory.delete(recursive: true);
      }
      rethrow;
    }

    // The old evidence tree is only a recovery snapshot at this point. Its
    // cleanup must not turn an already committed restore into a reported
    // failure or attempt to roll the database back after commit.
    if (previousEvidence != null && await previousEvidence.exists()) {
      try {
        await previousEvidence.delete(recursive: true);
      } on FileSystemException {
        // Safe to leave the recovery copy for later cleanup.
      }
    }
    return LocalRestoreResult(
      mode: mode,
      restoredRows: restoredRows,
      keptNewerLocalRows: keptNewer,
      restoredEvidence: prepared.addedCount,
    );
  }

  Future<List<Map<String, Object?>>> _portableRows(_TableSpec spec) async {
    if (!spec.systemOwned) return database.database.query(spec.name);
    switch (spec.name) {
      case 'categories':
        return database.database.query(
          spec.name,
          where: 'LOWER(origin) != ?',
          whereArgs: ['system'],
          orderBy: 'CASE WHEN parent_id IS NULL THEN 0 ELSE 1 END, id',
        );
      case 'merchants':
        return database.database.query(spec.name, where: 'is_built_in = 0');
      case 'tags':
        return database.database.query(
          spec.name,
          where: "id NOT LIKE 'tag.%' AND id NOT LIKE 'system-tag-%'",
        );
    }
    return database.database.query(spec.name);
  }

  Future<Map<String, Object?>> _readPackage(File file) async {
    final raw = jsonDecode(await file.readAsString());
    if (raw is! Map) throw const FormatException('Invalid Butlerly backup.');
    final wrapper = raw.cast<String, Object?>();
    if (wrapper['format'] != format || wrapper['formatVersion'] != formatVersion) {
      throw const FormatException('Unsupported Butlerly backup format.');
    }
    final payloadBytes = base64Decode(wrapper['payload']! as String);
    if (sha256.convert(payloadBytes).toString() != wrapper['payloadSha256']) {
      throw const FormatException('Backup integrity validation failed.');
    }
    final decoded = jsonDecode(utf8.decode(payloadBytes));
    if (decoded is! Map) throw const FormatException('Invalid backup payload.');
    final package = decoded.cast<String, Object?>();
    final manifest = (package['manifest'] as Map?)?.cast<String, Object?>();
    if (manifest == null ||
        manifest['format'] != format ||
        manifest['formatVersion'] != formatVersion) {
      throw const FormatException('Invalid backup manifest.');
    }
    final sourceSchema = manifest['schemaVersion'] as int?;
    if (sourceSchema == null || sourceSchema > schemaVersion) {
      throw const FormatException('Backup was created by a newer Butlerly schema.');
    }
    if (package['tables'] is! Map || package['evidence'] is! List) {
      throw const FormatException('Incomplete Butlerly backup payload.');
    }
    return package;
  }

  Future<bool> _hasNewerLocalData(DateTime backupTime) async {
    for (final spec in _tables) {
      final field = spec.updatedAt ?? spec.createdAt;
      if (field == null) continue;
      final systemFilter = switch (spec.name) {
        'categories' => " AND LOWER(origin) != 'system'",
        'merchants' => ' AND is_built_in = 0',
        'tags' => " AND id NOT LIKE 'tag.%' AND id NOT LIKE 'system-tag-%'",
        _ => '',
      };
      final rows = await database.database.rawQuery(
        'SELECT 1 FROM ${spec.name} WHERE $field > ?$systemFilter LIMIT 1',
        [backupTime.toIso8601String()],
      );
      if (rows.isNotEmpty) return true;
    }
    final deleted = await database.database.rawQuery(
      'SELECT 1 FROM entity_tombstones WHERE deleted_at > ? LIMIT 1',
      [backupTime.toIso8601String()],
    );
    return deleted.isNotEmpty;
  }

  Future<int> _applyBackupTombstones(
    Transaction tx,
    Map<String, Object?> tablePayload,
    DateTime backupTime,
  ) async {
    var keptNewer = 0;
    final tombstones =
        (tablePayload['entity_tombstones'] as List? ?? const <Object?>[])
            .cast<Map>();
    for (final raw in tombstones) {
      final tombstone = raw.cast<String, Object?>();
      final entityType = tombstone['entity_type'] as String?;
      final entityId = tombstone['entity_id'];
      final spec = entityType == null ? null : _specByName[entityType];
      if (spec == null || entityId == null) continue;
      if (_isSystemId(entityType, entityId)) continue;
      final values = _keyValuesFromTombstone(spec, '$entityId');
      if (values == null) continue;
      final localRows = await tx.query(
        entityType!,
        where: _keyWhere(spec),
        whereArgs: values,
        limit: 1,
      );
      if (localRows.isNotEmpty &&
          _rowChangedAfter(localRows.single, spec, backupTime)) {
        keptNewer++;
        continue;
      }
      if (localRows.isNotEmpty) {
        await tx.delete(entityType, where: _keyWhere(spec), whereArgs: values);
      }
      await tx.insert(
        'entity_tombstones',
        tombstone,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    return keptNewer;
  }

  Future<bool> _hasNewerLocalTombstone(
    Transaction tx,
    _TableSpec spec,
    Map<String, Object?> row,
    DateTime backupTime,
  ) async {
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

  Future<void> _clearTombstoneForRestoredRow(
    Transaction tx,
    _TableSpec spec,
    Map<String, Object?> row,
  ) async {
    final id = _tombstoneId(spec, row);
    if (id == null) return;
    await tx.delete(
      'entity_tombstones',
      where: 'entity_type = ? AND entity_id = ?',
      whereArgs: [spec.name, id],
    );
  }

  String? _tombstoneId(_TableSpec spec, Map<String, Object?> row) {
    if (spec.name == 'transaction_tags') {
      final transactionId = row['transaction_id'];
      final tagId = row['tag_id'];
      if (transactionId == null || tagId == null) return null;
      return '$transactionId|$tagId';
    }
    if (spec.keys.length != 1) return null;
    final id = row[spec.keys.single];
    return id == null ? null : '$id';
  }

  List<Object?>? _keyValuesFromTombstone(_TableSpec spec, String id) {
    if (spec.name == 'transaction_tags') {
      final separator = id.indexOf('|');
      if (separator <= 0 || separator == id.length - 1) return null;
      return [id.substring(0, separator), id.substring(separator + 1)];
    }
    return spec.keys.length == 1 ? [id] : null;
  }

  String _keyWhere(_TableSpec spec) =>
      spec.keys.map((key) => '$key = ?').join(' AND ');

  Future<Map<String, Object?>?> _findRow(
    Transaction tx,
    _TableSpec spec,
    Map<String, Object?> row,
  ) async {
    final values = spec.keys.map((key) => row[key]).toList(growable: false);
    final matches = await tx.query(
      spec.name,
      where: _keyWhere(spec),
      whereArgs: values,
      limit: 1,
    );
    return matches.isEmpty ? null : matches.single;
  }

  Future<void> _upsertRow(
    Transaction tx,
    _TableSpec spec,
    Map<String, Object?> row,
  ) async {
    if (spec.mergeUnion) {
      await tx.insert(
        spec.name,
        row,
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      return;
    }
    final existing = await _findRow(tx, spec, row);
    if (existing == null) {
      await tx.insert(spec.name, row);
      return;
    }
    final values = spec.keys.map((key) => row[key]).toList(growable: false);
    await tx.update(
      spec.name,
      row,
      where: _keyWhere(spec),
      whereArgs: values,
    );
  }

  bool _rowChangedAfter(
    Map<String, Object?> row,
    _TableSpec spec,
    DateTime cutoff,
  ) {
    for (final field in [spec.updatedAt, spec.createdAt]) {
      if (field == null) continue;
      final value = row[field];
      if (value is! String || value.isEmpty) continue;
      final parsed = DateTime.tryParse(value)?.toUtc();
      if (parsed != null && parsed.isAfter(cutoff)) return true;
    }
    return false;
  }

  bool _isSystemOwned(_TableSpec spec, Map<String, Object?> row) =>
      switch (spec.name) {
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
      'transactions',
      'exchange_rates',
      'provenances',
      'analysis_rule_configurations',
      'analysis_rule_activations',
      'payment_sources',
      'user_preferences',
    ];
    for (final table in childFirst) {
      await tx.delete(table);
    }
    await tx.delete('merchants', where: 'is_built_in = 0');
    await tx.delete('categories', where: "LOWER(origin) != 'system'");
    await tx.delete(
      'tags',
      where: "id NOT LIKE 'tag.%' AND id NOT LIKE 'system-tag-%'",
    );
    await tx.delete('entity_tombstones');
  }

  Future<_PreparedEvidence> _prepareEvidence(
    Iterable<Map> payload, {
    required LocalRestoreMode mode,
  }) async {
    final root = await localDataManager.evidenceDirectory();
    final staging = Directory(
      '${root.path}.restore-${DateTime.now().microsecondsSinceEpoch}',
    );
    if (await staging.exists()) await staging.delete(recursive: true);
    await staging.create(recursive: true);
    if (mode == LocalRestoreMode.merge && await root.exists()) {
      await _copyDirectory(root, staging);
    }

    var added = 0;
    try {
      for (final item in payload) {
        final relative = item['path'] as String?;
        final encoded = item['bytes'] as String?;
        final expectedHash = item['sha256'] as String?;
        if (relative == null || encoded == null || expectedHash == null) {
          throw const FormatException('Invalid evidence entry.');
        }
        final normalized = path.normalize(relative);
        if (path.isAbsolute(normalized) ||
            normalized == '..' ||
            normalized.startsWith('../')) {
          throw const FormatException('Unsafe evidence path.');
        }
        final bytes = base64Decode(encoded);
        if (sha256.convert(bytes).toString() != expectedHash) {
          throw const FormatException('Evidence integrity validation failed.');
        }
        final destination = File(path.join(staging.path, normalized));
        if (mode == LocalRestoreMode.merge && await destination.exists()) {
          final existing = await destination.readAsBytes();
          if (sha256.convert(existing).toString() == expectedHash) continue;
          // Evidence originals are immutable. A same-path local conflict is
          // preserved rather than silently overwritten.
          continue;
        }
        await destination.parent.create(recursive: true);
        await destination.writeAsBytes(bytes, flush: true);
        added++;
      }
      return _PreparedEvidence(directory: staging, addedCount: added);
    } catch (_) {
      if (await staging.exists()) await staging.delete(recursive: true);
      rethrow;
    }
  }

  Future<Directory?> _activatePreparedEvidence(Directory staging) async {
    final root = await localDataManager.evidenceDirectory();
    final previous = Directory(
      '${root.path}.restore-previous-${DateTime.now().microsecondsSinceEpoch}',
    );
    Directory? retained;
    if (await root.exists()) {
      await root.rename(previous.path);
      retained = previous;
    }
    try {
      await staging.rename(root.path);
      return retained;
    } catch (_) {
      if (retained != null && await retained.exists()) {
        await retained.rename(root.path);
      }
      rethrow;
    }
  }

  Future<void> _rollbackEvidence(Directory? previous) async {
    final root = await localDataManager.evidenceDirectory();
    if (await root.exists()) await root.delete(recursive: true);
    if (previous != null && await previous.exists()) {
      await previous.rename(root.path);
    }
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
}
