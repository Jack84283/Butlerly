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
  });

  final String name;
  final List<String> keys;
  final String? updatedAt;
  final String? createdAt;
  final bool systemOwned;
}

/// Portable Butlerly backup package.
///
/// The public backup format is a versioned JSON container rather than a copy
/// of the live SQLite file. Evidence bytes are embedded as base64 so one file
/// can be moved between supported devices. Derived Review/Analysis results are
/// deliberately omitted and rebuilt from restored authoritative state.
final class LocalBackupManager {
  const LocalBackupManager(this.database, this.localDataManager);

  final LocalDatabase database;
  final LocalDataManager localDataManager;

  static const format = 'butlerly-backup';
  static const formatVersion = 1;
  static const schemaVersion = 8;

  static const _tables = <_TableSpec>[
    _TableSpec('payment_sources', ['id'], updatedAt: 'updated_at', createdAt: 'created_at'),
    _TableSpec('merchants', ['id'], updatedAt: 'updated_at', createdAt: 'created_at'),
    _TableSpec('categories', ['id'], updatedAt: 'updated_at', createdAt: 'created_at', systemOwned: true),
    _TableSpec('tags', ['id'], updatedAt: 'updated_at', createdAt: 'created_at'),
    _TableSpec('provenances', ['id'], createdAt: 'captured_at'),
    _TableSpec('exchange_rates', ['id'], createdAt: 'effective_at'),
    _TableSpec('transactions', ['id'], updatedAt: 'updated_at', createdAt: 'created_at'),
    _TableSpec('transaction_provenances', ['transaction_id', 'provenance_id']),
    _TableSpec('transaction_tags', ['transaction_id', 'tag_id']),
    _TableSpec('evidence_items', ['id'], createdAt: 'created_at'),
    _TableSpec('financial_statements', ['id'], updatedAt: 'updated_at', createdAt: 'created_at'),
    _TableSpec('statement_rows', ['id'], updatedAt: 'updated_at', createdAt: 'created_at'),
    _TableSpec('extractions', ['id'], createdAt: 'created_at'),
    _TableSpec('attachment_links', ['id'], createdAt: 'created_at'),
    _TableSpec('suggestions', ['id'], updatedAt: 'decided_at', createdAt: 'created_at'),
    // Persist review decisions/history. Active/generated queue membership is
    // rebuilt by feature services after restore rather than treated as a
    // portable cache.
    _TableSpec('review_issues', ['id'], updatedAt: 'closed_at', createdAt: 'created_at'),
    _TableSpec('reconciliation_candidates', ['id'], updatedAt: 'updated_at', createdAt: 'created_at'),
    _TableSpec('reconciliation_links', ['id'], createdAt: 'created_at'),
    _TableSpec('duplicate_candidate_groups', ['id'], updatedAt: 'updated_at', createdAt: 'created_at'),
    _TableSpec('duplicate_candidate_group_transactions', ['group_id', 'transaction_id']),
    _TableSpec('analysis_rule_activations', ['rule_id'], updatedAt: 'updated_at'),
    _TableSpec('analysis_rule_configurations', ['rule_id'], updatedAt: 'updated_at'),
    _TableSpec('user_preferences', ['id'], updatedAt: 'updated_at'),
    _TableSpec('entity_tombstones', ['entity_type', 'entity_id'], updatedAt: 'deleted_at'),
  ];

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
      final rows = await database.database.query(spec.name);
      tables[spec.name] = rows;
      recordCount += rows.length;
    }

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
    final createdAt = DateTime.parse(manifest['createdAtUtc']! as String).toUtc();
    final tablePayload = (package['tables']! as Map).cast<String, Object?>();

    var restoredRows = 0;
    var keptNewer = 0;
    await database.database.transaction((tx) async {
      if (mode == LocalRestoreMode.replace) {
        await _clearPortableState(tx);
      }
      for (final spec in _tables) {
        final payload = (tablePayload[spec.name] as List? ?? const <Object?>[])
            .cast<Map>()
            .map((row) => row.cast<String, Object?>());
        for (final row in payload) {
          if (spec.systemOwned && _isSystemOwned(row)) continue;
          if (mode == LocalRestoreMode.merge) {
            final local = await _findRow(tx, spec, row);
            if (local != null && _rowChangedAfter(local, spec, createdAt)) {
              keptNewer++;
              continue;
            }
          }
          await tx.insert(spec.name, row, conflictAlgorithm: ConflictAlgorithm.replace);
          restoredRows++;
        }
      }
      // Derived data can always be reproduced and must not carry stale results
      // across devices or restore boundaries.
      for (final table in _derivedTables) {
        await tx.delete(table);
      }
    });

    final evidence = (package['evidence'] as List? ?? const <Object?>[]).cast<Map>();
    final restoredEvidence = await _restoreEvidence(evidence, mode: mode);
    return LocalRestoreResult(
      mode: mode,
      restoredRows: restoredRows,
      keptNewerLocalRows: keptNewer,
      restoredEvidence: restoredEvidence,
    );
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
    return package;
  }

  Future<bool> _hasNewerLocalData(DateTime backupTime) async {
    for (final spec in _tables) {
      final field = spec.updatedAt ?? spec.createdAt;
      if (field == null) continue;
      final rows = await database.database.rawQuery(
        'SELECT 1 FROM ${spec.name} WHERE $field > ? LIMIT 1',
        [backupTime.toIso8601String()],
      );
      if (rows.isNotEmpty) return true;
    }
    return false;
  }

  Future<Map<String, Object?>?> _findRow(
    Transaction tx,
    _TableSpec spec,
    Map<String, Object?> row,
  ) async {
    final where = spec.keys.map((key) => '$key = ?').join(' AND ');
    final values = spec.keys.map((key) => row[key]).toList(growable: false);
    final matches = await tx.query(spec.name, where: where, whereArgs: values, limit: 1);
    return matches.isEmpty ? null : matches.single;
  }

  bool _rowChangedAfter(
    Map<String, Object?> row,
    _TableSpec spec,
    DateTime cutoff,
  ) {
    final candidates = <Object?>[
      if (spec.updatedAt != null) row[spec.updatedAt],
      if (spec.createdAt != null) row[spec.createdAt],
    ];
    for (final value in candidates) {
      if (value is! String || value.isEmpty) continue;
      final parsed = DateTime.tryParse(value)?.toUtc();
      if (parsed != null && parsed.isAfter(cutoff)) return true;
    }
    return false;
  }

  bool _isSystemOwned(Map<String, Object?> row) =>
      row['origin'] == 'system' || row['origin'] == 'SYSTEM';

  Future<void> _clearPortableState(Transaction tx) async {
    // Child-first order; system/reference catalog tables are intentionally not
    // cleared because the receiving Butlerly version owns them.
    const tables = <String>[
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
      'merchants',
      'categories',
      'tags',
      'user_preferences',
      'entity_tombstones',
    ];
    for (final table in tables) {
      await tx.delete(table);
    }
  }

  Future<int> _restoreEvidence(
    Iterable<Map> payload, {
    required LocalRestoreMode mode,
  }) async {
    final root = await localDataManager.evidenceDirectory();
    if (mode == LocalRestoreMode.replace && await root.exists()) {
      await root.delete(recursive: true);
    }
    await root.create(recursive: true);
    var count = 0;
    for (final item in payload) {
      final relative = item['path'] as String?;
      final encoded = item['bytes'] as String?;
      final expectedHash = item['sha256'] as String?;
      if (relative == null || encoded == null || expectedHash == null) {
        throw const FormatException('Invalid evidence entry.');
      }
      final normalized = path.normalize(relative);
      if (path.isAbsolute(normalized) || normalized.startsWith('..')) {
        throw const FormatException('Unsafe evidence path.');
      }
      final bytes = base64Decode(encoded);
      if (sha256.convert(bytes).toString() != expectedHash) {
        throw const FormatException('Evidence integrity validation failed.');
      }
      final destination = File(path.join(root.path, normalized));
      if (mode == LocalRestoreMode.merge && await destination.exists()) {
        // Evidence is immutable; an existing file with the same bytes is kept.
        final existing = await destination.readAsBytes();
        if (sha256.convert(existing).toString() == expectedHash) continue;
        // Stable evidence path conflict: preserve newer/local bytes rather than
        // overwriting an unknown local artifact.
        continue;
      }
      await destination.parent.create(recursive: true);
      await destination.writeAsBytes(bytes, flush: true);
      count++;
    }
    return count;
  }
}
