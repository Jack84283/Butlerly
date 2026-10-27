import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:butlerly/core/data/backup_container_format.dart';
import 'package:butlerly/core/data/duplicate_group_backup_policy.dart';
import 'package:butlerly/core/data/local_data_manager.dart';
import 'package:butlerly_database/butlerly_database.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common/sqlite_api.dart';

/// Serializes one logical SQLite snapshot into Butlerly's portable backup
/// container. The caller owns the read transaction that provides [source].
final class LocalBackupSnapshotWriter {
  const LocalBackupSnapshotWriter(this.localDataManager);

  final LocalDataManager localDataManager;

  static const format = BackupContainerFormat.name;
  static const formatVersion = BackupContainerFormat.version;
  static const schemaVersion = BackupContainerFormat.schemaVersion;
  static const appVersion = BackupContainerFormat.appVersion;
  static const appBuild = BackupContainerFormat.appBuild;
  static final _magic = BackupContainerFormat.magic;

  static const _plainTables = <String>[
    'payment_sources',
    'payment_settlements',
    'merchant_aliases',
    'merchant_normalization_patterns',
    'transaction_rules',
    'provenances',
    'exchange_rates',
    'transactions',
    'normalized_money',
    'transaction_provenances',
    'transaction_tags',
    'evidence_items',
    'financial_statements',
    'statement_rows',
    'extractions',
    'attachment_links',
    'analysis_rule_activations',
    'analysis_rule_configurations',
    'recurring_pattern_decisions',
    'user_preferences',
    'budgets',
  ];

  static const _generatedTombstoneTypes = <String>{
    'review_issues',
    'suggestions',
    'reconciliation_candidates',
    'duplicate_candidate_groups',
    'duplicate_candidate_group_transactions',
  };

  Future<File> write(
    File destination, {
    required DatabaseExecutor source,
    required DateTime createdAtUtc,
  }) async {
    final tables = <String, Object?>{};
    var recordCount = 0;

    for (final table in _plainTables) {
      final rows = await source.query(table);
      tables[table] = rows;
      recordCount += rows.length;
    }

    final categories = _orderCategoriesForBackup(
      await source.query(
        'categories',
        where: 'LOWER(origin) != ?',
        whereArgs: ['system'],
        orderBy: 'id',
      ),
    );
    tables['categories'] = categories;
    recordCount += categories.length;
    final categoryTranslations = await _rowsForIds(
      source,
      table: 'category_translations',
      field: 'category_id',
      ids: categories.map((row) => row['id']! as String).toSet(),
    );
    tables['category_translations'] = categoryTranslations;
    recordCount += categoryTranslations.length;

    final merchants = await source.query('merchants', where: 'is_built_in = 0');
    tables['merchants'] = merchants;
    recordCount += merchants.length;

    final tags = await source.query(
      'tags',
      where:
          "id NOT IN ("
          "'tag.business','tag.personal','tag.reimbursable',"
          "'tag.tax_related','tag.travel','tag.recurring','tag.subscription'"
          ')',
    );
    tables['tags'] = tags;
    recordCount += tags.length;
    final tagTranslations = await _rowsForIds(
      source,
      table: 'tag_translations',
      field: 'tag_id',
      ids: tags.map((row) => row['id']! as String).toSet(),
    );
    tables['tag_translations'] = tagTranslations;
    recordCount += tagTranslations.length;

    final referenceData = await source.query(
      'reference_data',
      where: 'LOWER(origin) != ?',
      whereArgs: ['system'],
      orderBy: 'id',
    );
    tables['reference_data'] = referenceData;
    recordCount += referenceData.length;
    final referenceDataTranslations = await _rowsForIds(
      source,
      table: 'reference_data_translations',
      field: 'reference_data_id',
      ids: referenceData.map((row) => row['id']! as String).toSet(),
    );
    tables['reference_data_translations'] = referenceDataTranslations;
    recordCount += referenceDataTranslations.length;

    // Open Review issues are generated from current records. A closed issue is
    // durable evidence of a user's decision and therefore remains portable.
    final reviewIssues = await source.query(
      'review_issues',
      where: 'closed_at IS NOT NULL',
    );
    tables['review_issues'] = reviewIssues;
    recordCount += reviewIssues.length;

    // Suggestions are generated proposals; only explicitly decided proposals
    // carry durable user intent across devices.
    final suggestions = await source.query(
      'suggestions',
      where: 'decided_at IS NOT NULL',
    );
    tables['suggestions'] = suggestions;
    recordCount += suggestions.length;

    // Only proposed reconciliation candidates are generated. Confirmed,
    // rejected, and undone statuses all encode a user workflow decision.
    final reconciliationCandidates = await source.query(
      'reconciliation_candidates',
      where: "status != 'proposed'",
    );
    tables['reconciliation_candidates'] = reconciliationCandidates;
    recordCount += reconciliationCandidates.length;
    final reconciliationIds = reconciliationCandidates
        .map((row) => row['id'] as String)
        .toSet();
    final reconciliationLinks = await _rowsForIds(
      source,
      table: 'reconciliation_links',
      field: 'candidate_id',
      ids: reconciliationIds,
    );
    tables['reconciliation_links'] = reconciliationLinks;
    recordCount += reconciliationLinks.length;

    // Transaction-only unresolved groups are generated from active
    // transactions. Preserve a group when it carries repair context (a stale
    // member, an incomplete membership, or a newly matching record), because
    // dropping it would make a saved decision inaccessible after restore.
    // Statement-row candidates are durable review work and always survive.
    final allDuplicateGroups = await source.query('duplicate_candidate_groups');
    final allDuplicateMembers = await source.query(
      'duplicate_candidate_group_transactions',
    );
    final duplicateTransactions = await source.query(
      'transactions',
      columns: [
        'id',
        'transaction_date',
        'amount_coefficient',
        'amount_scale',
        'currency',
        'direction',
        'status',
      ],
    );
    final durableUnresolvedDuplicateIds =
        DuplicateGroupBackupPolicy.durableUnresolvedGroupIds(
          groups: allDuplicateGroups,
          memberships: allDuplicateMembers,
          transactions: duplicateTransactions,
        );
    final duplicateGroups = allDuplicateGroups
        .where(
          (row) =>
              row['status'] != 'unresolved' ||
              DuplicateGroupBackupPolicy.hasStatementEvidence(
                row['statement_rows'],
              ) ||
              durableUnresolvedDuplicateIds.contains(row['id']),
        )
        .toList(growable: false);
    tables['duplicate_candidate_groups'] = duplicateGroups;
    recordCount += duplicateGroups.length;
    final duplicateIds = duplicateGroups
        .map((row) => row['id'] as String)
        .toSet();
    final duplicateMembers = await _rowsForIds(
      source,
      table: 'duplicate_candidate_group_transactions',
      field: 'group_id',
      ids: duplicateIds,
    );
    tables['duplicate_candidate_group_transactions'] = duplicateMembers;
    recordCount += duplicateMembers.length;

    final tombstones = await source.query('entity_tombstones');
    final portableTombstones = tombstones
        .where((row) => !_generatedTombstoneTypes.contains(row['entity_type']))
        .toList(growable: false);
    tables['entity_tombstones'] = portableTombstones;
    recordCount += portableTombstones.length;

    final evidenceRows =
        tables['evidence_items']! as List<Map<String, Object?>>;
    final evidenceRoot = await localDataManager.evidenceDirectory();

    // Every DB-referenced binary must exist. In addition, preserve unreferenced
    // files conservatively: a partially completed metadata operation must never
    // cause Backup to silently discard a user's receipt or statement.
    for (final row in evidenceRows) {
      final localName = row['local_file_name'] as String?;
      if (localName == null || localName.trim().isEmpty) continue;
      final normalized = path.normalize(localName);
      if (path.isAbsolute(normalized) ||
          normalized == '..' ||
          normalized.startsWith('../')) {
        throw const FormatException('Unsafe local evidence path.');
      }
      if (!await File(path.join(evidenceRoot.path, normalized)).exists()) {
        throw StateError('Referenced evidence file is missing.');
      }
    }

    final allEvidenceFiles = <File>[];
    if (await evidenceRoot.exists()) {
      await for (final entity in evidenceRoot.list(recursive: true)) {
        if (entity is File) allEvidenceFiles.add(entity);
      }
    }
    allEvidenceFiles.sort((left, right) {
      final leftRelative = path.relative(left.path, from: evidenceRoot.path);
      final rightRelative = path.relative(right.path, from: evidenceRoot.path);
      return leftRelative.compareTo(rightRelative);
    });

    final evidence = <Map<String, Object?>>[];
    final sourceFiles = <File>[];
    for (final file in allEvidenceFiles) {
      final relative = path.normalize(
        path.relative(file.path, from: evidenceRoot.path),
      );
      if (path.isAbsolute(relative) ||
          relative == '..' ||
          relative.startsWith('../')) {
        throw const FormatException('Unsafe local evidence path.');
      }
      final length = await file.length();
      evidence.add({
        'path': relative,
        'length': length,
        'sha256': await sha256FileRange(file),
      });
      sourceFiles.add(file);
    }

    final metadata = <String, Object?>{
      'manifest': {
        'format': format,
        'formatVersion': formatVersion,
        'schemaVersion': schemaVersion,
        'backupId': _newBackupId(),
        'appVersion': appVersion,
        'appBuild': appBuild,
        'createdAtUtc': createdAtUtc.toUtc().toIso8601String(),
        'recordCount': recordCount,
        'evidenceCount': evidence.length,
        'derivedDataPolicy': 'rebuild',
      },
      'tables': tables,
      'evidence': evidence,
    };
    final metadataBytes = utf8.encode(jsonEncode(metadata));
    final metadataHash = ascii.encode(sha256Bytes(metadataBytes));
    final temporary = File(
      '${destination.path}.tmp-${DateTime.now().microsecondsSinceEpoch}',
    );
    await temporary.parent.create(recursive: true);
    final sink = temporary.openWrite();
    try {
      sink.add(_magic);
      sink.add(int64Bytes(metadataBytes.length));
      sink.add(metadataHash);
      sink.add(metadataBytes);
      for (var index = 0; index < sourceFiles.length; index++) {
        final file = sourceFiles[index];
        final expectedHash = evidence[index]['sha256']! as String;
        final expectedLength = evidence[index]['length']! as int;
        await sink.addStream(file.openRead());
        if (await file.length() != expectedLength ||
            await sha256FileRange(file) != expectedHash) {
          throw StateError('Evidence changed while the backup was created.');
        }
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    if (await destination.exists()) await destination.delete();
    await temporary.rename(destination.path);
    return destination;
  }

  List<Map<String, Object?>> _orderCategoriesForBackup(
    List<Map<String, Object?>> rows,
  ) {
    final pending = [...rows];
    final knownIds = rows.map((row) => row['id']).whereType<String>().toSet();
    final emitted = <String>{};
    final ordered = <Map<String, Object?>>[];
    while (pending.isNotEmpty) {
      final ready = pending.where((row) {
        final parentId = row['parent_id'] as String?;
        return parentId == null ||
            !knownIds.contains(parentId) ||
            emitted.contains(parentId);
      }).toList();
      if (ready.isEmpty) {
        throw StateError('Category hierarchy contains a cycle.');
      }
      for (final row in ready) {
        pending.remove(row);
        ordered.add(row);
        final id = row['id'];
        if (id is String) emitted.add(id);
      }
    }
    return ordered;
  }

  Future<List<Map<String, Object?>>> _rowsForIds(
    DatabaseExecutor source, {
    required String table,
    required String field,
    required Set<String> ids,
  }) async {
    if (ids.isEmpty) return <Map<String, Object?>>[];
    final placeholders = List.filled(ids.length, '?').join(', ');
    return source.query(
      table,
      where: '$field IN ($placeholders)',
      whereArgs: ids.toList(growable: false),
    );
  }

  String _newBackupId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String hex(int value) => value.toRadixString(16).padLeft(2, '0');
    final text = bytes.map(hex).join();
    return '${text.substring(0, 8)}-'
        '${text.substring(8, 12)}-'
        '${text.substring(12, 16)}-'
        '${text.substring(16, 20)}-'
        '${text.substring(20)}';
  }
}
