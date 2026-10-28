import 'dart:convert';
import 'dart:io';

import 'package:butlerly/core/data/local_backup_manager.dart';
import 'package:butlerly/core/data/local_data_manager.dart';
import 'package:butlerly/core/database/local_database.dart';
import 'package:butlerly/core/logging/app_logger.dart';
import 'package:butlerly_database/butlerly_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  test('replace restore preserves normalized money', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final now = DateTime.utc(2026, 9, 1);
    await fixture.insertTransaction('tx-fx', now);
    await fixture.database.database.insert('exchange_rates', {
      'id': 'rate-1',
      'from_currency': 'EUR',
      'to_currency': 'USD',
      'rate_coefficient': '110',
      'rate_scale': 2,
      'effective_at': now.toIso8601String(),
      'source': 'test',
    });
    await fixture.database.database.insert('normalized_money', {
      'transaction_id': 'tx-fx',
      'exchange_rate_id': 'rate-1',
      'amount_coefficient': '1100',
      'amount_scale': 2,
      'currency': 'USD',
      'normalization_source': 'exchangeRate',
      'base_currency': 'USD',
      'effective_date': '2026-09-01',
      'updated_at': now.toIso8601String(),
    });
    final backup = File(path.join(fixture.root.path, 'fx.butlerlybackup'));
    await fixture.manager.createBackup(backup);
    await fixture.database.database.update(
      'normalized_money',
      {'amount_coefficient': '9999'},
      where: 'transaction_id = ?',
      whereArgs: ['tx-fx'],
    );

    await fixture.manager.restore(backup, mode: LocalRestoreMode.replace);

    final restored = await fixture.database.database.query(
      'normalized_money',
      where: 'transaction_id = ?',
      whereArgs: ['tx-fx'],
    );
    expect(restored, hasLength(1));
    expect(restored.single['amount_coefficient'], '1100');
  });

  test(
    'backup and restore preserve user-entered normalized money without an exchange rate',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final now = DateTime.utc(2026, 9, 2);
      await fixture.insertTransaction('tx-manual-normalization', now);
      await fixture.database.database.insert('normalized_money', {
        'transaction_id': 'tx-manual-normalization',
        'exchange_rate_id': null,
        'amount_coefficient': '1234',
        'amount_scale': 2,
        'currency': 'USD',
        'normalization_source': 'manual',
        'base_currency': 'USD',
        'effective_date': '2026-09-02',
        'updated_at': now.toIso8601String(),
      });
      final backup = File(
        path.join(fixture.root.path, 'manual-normalization.butlerlybackup'),
      );

      await fixture.manager.createBackup(backup);
      final inspection = await fixture.manager.inspect(backup);
      expect(inspection.hasNewerLocalData, isFalse);

      await fixture.database.database.update(
        'normalized_money',
        {'amount_coefficient': '9999'},
        where: 'transaction_id = ? AND exchange_rate_id IS NULL',
        whereArgs: ['tx-manual-normalization'],
      );
      await fixture.manager.restore(backup, mode: LocalRestoreMode.replace);

      final restored = await fixture.database.database.query(
        'normalized_money',
        where: 'transaction_id = ? AND exchange_rate_id IS NULL',
        whereArgs: ['tx-manual-normalization'],
      );
      expect(restored, hasLength(1));
      expect(restored.single['amount_coefficient'], '1234');
    },
  );

  test(
    'normalized money rejects a missing exchange-rate identity key',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final now = DateTime.utc(2026, 9, 3);
      await fixture.insertTransaction('tx-missing-normalization-key', now);
      await fixture.database.database.insert('normalized_money', {
        'transaction_id': 'tx-missing-normalization-key',
        'exchange_rate_id': null,
        'amount_coefficient': '1234',
        'amount_scale': 2,
        'currency': 'USD',
        'normalization_source': 'manual',
        'base_currency': 'USD',
        'effective_date': '2026-09-03',
        'updated_at': now.toIso8601String(),
      });
      final backup = File(
        path.join(fixture.root.path, 'missing-normalization-key.butlerly'),
      );
      await fixture.manager.createBackup(backup);
      await _rewriteBackupMetadata(backup, (metadata) {
        final tables = (metadata['tables']! as Map).cast<String, Object?>();
        final rows = (tables['normalized_money']! as List).cast<Map>();
        rows.single.remove('exchange_rate_id');
      });

      await expectLater(
        fixture.manager.restore(backup, mode: LocalRestoreMode.replace),
        throwsA(isA<FormatException>()),
      );
      expect(
        await fixture.database.database.query(
          'normalized_money',
          where: 'transaction_id = ? AND exchange_rate_id IS NULL',
          whereArgs: ['tx-missing-normalization-key'],
        ),
        hasLength(1),
      );
    },
  );

  test(
    'duplicate tombstone identities are rejected before restore mutation',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final original = DateTime.utc(2026, 9, 4, 12);
      await fixture.insertTransaction('tx-tombstone-duplicate', original);
      await fixture.database.database.insert('entity_tombstones', {
        'entity_type': 'transactions',
        'entity_id': 'tx-tombstone-duplicate',
        'deleted_at': original.toIso8601String(),
      });
      final backup = File(
        path.join(fixture.root.path, 'duplicate-tombstone.butlerlybackup'),
      );
      await fixture.manager.createBackup(backup);
      await fixture.database.database.update(
        'transactions',
        {'amount_coefficient': '9999'},
        where: 'id = ?',
        whereArgs: ['tx-tombstone-duplicate'],
      );
      await _rewriteBackupMetadata(backup, (metadata) {
        final tables = (metadata['tables']! as Map).cast<String, Object?>();
        final rows = (tables['entity_tombstones']! as List).cast<Map>();
        final duplicate =
            Map<String, Object?>.from(rows.single.cast<String, Object?>())
              ..['deleted_at'] = original
                  .add(const Duration(seconds: 1))
                  .toIso8601String();
        rows.add(duplicate);
      });

      await expectLater(
        fixture.manager.restore(backup, mode: LocalRestoreMode.replace),
        throwsA(isA<FormatException>()),
      );
      final transaction = await fixture.database.database.query(
        'transactions',
        where: 'id = ?',
        whereArgs: ['tx-tombstone-duplicate'],
      );
      expect(transaction.single['amount_coefficient'], '9999');
      expect(
        await fixture.database.database.query(
          'entity_tombstones',
          where: 'entity_type = ? AND entity_id = ?',
          whereArgs: ['transactions', 'tx-tombstone-duplicate'],
        ),
        hasLength(1),
      );
    },
  );

  test('startup recovery rolls evidence back when DB did not commit', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final evidence = fixture.evidence;
    final current = File(path.join(evidence.path, 'receipt.bin'));
    await current.writeAsString('new');
    final operation = 'restore-test-uncommitted';
    final previous = Directory('${evidence.path}.restore-previous-$operation')
      ..createSync(recursive: true);
    await File(path.join(previous.path, 'receipt.bin')).writeAsString('old');
    final journal = File('${evidence.path}.restore-journal.json');
    await journal.writeAsString(
      jsonEncode({
        'operationId': operation,
        'previousPath': previous.path,
        'stagingPath': '${evidence.path}.missing-staging',
        'phase': 'evidenceActivated',
      }),
    );

    await fixture.manager.recoverInterruptedRestore();

    expect(
      await File(path.join(evidence.path, 'receipt.bin')).readAsString(),
      'old',
    );
    expect(await journal.exists(), isFalse);
  });

  test('failed staging construction removes its partial workspace', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await fixture.insertTransaction(
      'tx-staging-construction',
      DateTime.utc(2026, 9, 5),
    );
    final backup = File(
      path.join(fixture.root.path, 'staging-construction.butlerlybackup'),
    );
    await fixture.manager.createBackup(backup);
    final failingManager = LocalBackupManager(
      fixture.database,
      LocalDataManager(
        fixture.database,
        documentsDirectory: Directory(
          path.join(fixture.root.path, 'documents'),
        ),
        localEvidenceDirectory: fixture.evidence,
      ),
      afterStagingRootCreated: (_) async {
        throw StateError('simulated staging construction failure');
      },
    );

    await expectLater(
      failingManager.restore(backup, mode: LocalRestoreMode.replace),
      throwsA(isA<StateError>()),
    );
    final stageDirectories = await fixture.root
        .list(followLinks: false)
        .where((entity) => entity is Directory)
        .cast<Directory>()
        .where(
          (directory) => path
              .basename(directory.path)
              .startsWith('.butlerly-restore-stage-'),
        )
        .toList();
    expect(stageDirectories, isEmpty);
  });

  test(
    'startup recovery keeps evidence when DB commit marker exists',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final evidence = fixture.evidence;
      await File(path.join(evidence.path, 'receipt.bin')).writeAsString('new');
      final operation = 'restore-test-committed';
      final previous = Directory('${evidence.path}.restore-previous-$operation')
        ..createSync(recursive: true);
      await File(path.join(previous.path, 'receipt.bin')).writeAsString('old');
      await fixture.database.database.insert('restore_commits', {
        'operation_id': operation,
        'committed_at': DateTime.now().toUtc().toIso8601String(),
      });
      final journal = File('${evidence.path}.restore-journal.json');
      await journal.writeAsString(
        jsonEncode({
          'operationId': operation,
          'previousPath': previous.path,
          'stagingPath': '${evidence.path}.missing-staging',
          'phase': 'evidenceActivated',
        }),
      );

      await fixture.manager.recoverInterruptedRestore();

      expect(
        await File(path.join(evidence.path, 'receipt.bin')).readAsString(),
        'new',
      );
      expect(await previous.exists(), isFalse);
      expect(await journal.exists(), isFalse);
    },
  );

  test(
    'torn committed journal keeps live evidence by matching recovery path',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final evidence = fixture.evidence;
      await File(path.join(evidence.path, 'receipt.bin')).writeAsString('new');
      final operation = 'restore-test-torn-committed';
      final previous = Directory('${evidence.path}.restore-previous-$operation')
        ..createSync(recursive: true);
      await File(path.join(previous.path, 'receipt.bin')).writeAsString('old');
      await fixture.database.database.insert('restore_commits', {
        'operation_id': operation,
        'committed_at': DateTime.now().toUtc().toIso8601String(),
      });
      final journal = File('${evidence.path}.restore-journal.json');
      await journal.writeAsString('{"operationId":');

      await fixture.manager.recoverInterruptedRestore();

      expect(
        await File(path.join(evidence.path, 'receipt.bin')).readAsString(),
        'new',
      );
      expect(await previous.exists(), isFalse);
      expect(await fixture.database.database.query('restore_commits'), isEmpty);
      expect(await journal.exists(), isFalse);
    },
  );

  test(
    'unrelated stale commit marker cannot bless an uncommitted restore',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final evidence = fixture.evidence;
      await File(path.join(evidence.path, 'receipt.bin')).writeAsString('new');
      final operation = 'restore-current-uncommitted';
      final previous = Directory('${evidence.path}.restore-previous-$operation')
        ..createSync(recursive: true);
      await File(path.join(previous.path, 'receipt.bin')).writeAsString('old');
      await fixture.database.database.insert('restore_commits', {
        'operation_id': 'restore-unrelated-stale',
        'committed_at': DateTime.now().toUtc().toIso8601String(),
      });
      final journal = File('${evidence.path}.restore-journal.json');
      await journal.writeAsString(
        jsonEncode({
          'operationId': operation,
          'previousPath': previous.path,
          'stagingPath': '${evidence.path}.missing-staging',
          'phase': 'dbWriting',
        }),
      );

      await fixture.manager.recoverInterruptedRestore();

      expect(
        await File(path.join(evidence.path, 'receipt.bin')).readAsString(),
        'old',
      );
      expect(await fixture.database.database.query('restore_commits'), isEmpty);
    },
  );

  test(
    'evidence path collision preserves both binaries and remaps backup row',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final now = DateTime.utc(2026, 9, 1);
      await fixture.database.database.insert('provenances', {
        'id': 'prov-1',
        'source_type': 'manual',
        'captured_at': now.toIso8601String(),
      });
      await fixture.database.database.insert('evidence_items', {
        'id': 'evidence-1',
        'type': 'receipt',
        'original_name': 'receipt.bin',
        'media_type': 'application/octet-stream',
        'provenance_id': 'prov-1',
        'created_at': now.toIso8601String(),
        'local_file_name': 'receipt.bin',
      });
      final evidence = File(path.join(fixture.evidence.path, 'receipt.bin'));
      await evidence.writeAsString('backup-version');
      final backup = File(
        path.join(fixture.root.path, 'collision.butlerlybackup'),
      );
      await fixture.manager.createBackup(backup);
      await evidence.writeAsString('newer-local-version');
      await fixture.database.database.delete(
        'evidence_items',
        where: 'id = ?',
        whereArgs: ['evidence-1'],
      );
      await fixture.database.database.delete(
        'entity_tombstones',
        where: 'entity_type = ?',
        whereArgs: ['evidence_items'],
      );

      await fixture.manager.restore(backup, mode: LocalRestoreMode.merge);

      expect(await evidence.readAsString(), 'newer-local-version');
      final restored = await fixture.database.database.query(
        'evidence_items',
        where: 'id = ?',
        whereArgs: ['evidence-1'],
      );
      expect(restored, hasLength(1));
      final restoredName = restored.single['local_file_name']! as String;
      expect(restoredName, isNot('receipt.bin'));
      expect(
        await File(
          path.join(fixture.evidence.path, restoredName),
        ).readAsString(),
        'backup-version',
      );
    },
  );

  test(
    'collision remap never changes another row with the same basename',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final now = DateTime.utc(2026, 9, 1).toIso8601String();
      await fixture.database.database.insert('provenances', {
        'id': 'prov-paths',
        'source_type': 'manual',
        'captured_at': now,
      });
      final firstPath = path.join('receipts', 'receipt.bin');
      final secondPath = path.join('statements', 'receipt.bin');
      for (final entry in <(String, String)>[
        ('evidence-receipt', firstPath),
        ('evidence-statement', secondPath),
      ]) {
        await fixture.database.database.insert('evidence_items', {
          'id': entry.$1,
          'type': 'receipt',
          'original_name': 'receipt.bin',
          'media_type': 'application/octet-stream',
          'provenance_id': 'prov-paths',
          'created_at': now,
          'local_file_name': entry.$2,
        });
      }
      final first = File(path.join(fixture.evidence.path, firstPath));
      final second = File(path.join(fixture.evidence.path, secondPath));
      await first.parent.create(recursive: true);
      await second.parent.create(recursive: true);
      await first.writeAsString('backup-first');
      await second.writeAsString('backup-second');
      final backup = File(
        path.join(fixture.root.path, 'same-name.butlerlybackup'),
      );
      await fixture.manager.createBackup(backup);

      await first.writeAsString('newer-local-first');
      await fixture.database.database.delete('evidence_items');
      await fixture.database.database.delete(
        'entity_tombstones',
        where: 'entity_type = ?',
        whereArgs: ['evidence_items'],
      );

      await fixture.manager.restore(backup, mode: LocalRestoreMode.merge);

      final rows = await fixture.database.database.query(
        'evidence_items',
        orderBy: 'id',
      );
      final byId = <String, Map<String, Object?>>{
        for (final row in rows) row['id']! as String: row,
      };
      expect(byId['evidence-statement']!['local_file_name'], secondPath);
      final remapped = byId['evidence-receipt']!['local_file_name']! as String;
      expect(remapped, isNot(firstPath));
      expect(await first.readAsString(), 'newer-local-first');
      expect(
        await File(path.join(fixture.evidence.path, remapped)).readAsString(),
        'backup-first',
      );
      expect(await second.readAsString(), 'backup-second');
    },
  );

  test('case-folded evidence remap preserves the backup bytes', () async {
    // The collision only exists on the case-insensitive filesystems used by
    // macOS and Windows. The Linux path is still covered by the ordinary
    // collision tests above.
    if (!Platform.isMacOS && !Platform.isWindows) return;

    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final now = DateTime.utc(2026, 9, 1).toIso8601String();
    await fixture.database.database.insert('provenances', {
      'id': 'prov-case-path',
      'source_type': 'manual',
      'captured_at': now,
    });
    await fixture.database.database.insert('evidence_items', {
      'id': 'evidence-case-path',
      'type': 'receipt',
      'original_name': 'receipt.bin',
      'media_type': 'application/octet-stream',
      'provenance_id': 'prov-case-path',
      'created_at': now,
      'local_file_name': 'Receipt.bin',
    });
    final evidence = File(path.join(fixture.evidence.path, 'Receipt.bin'));
    await evidence.writeAsString('backup-case-version');
    final backup = File(
      path.join(fixture.root.path, 'case-folded.butlerlybackup'),
    );
    await fixture.manager.createBackup(backup);
    await _rewriteBackupMetadata(backup, (metadata) {
      final evidenceRows = (metadata['evidence']! as List).cast<Map>();
      evidenceRows.single['path'] = 'RECEIPT.BIN';
      final tables = (metadata['tables']! as Map).cast<String, Object?>();
      final rows = (tables['evidence_items']! as List).cast<Map>();
      rows.single['local_file_name'] = 'receipt.bin';
    });
    await evidence.writeAsString('newer-local-case-version');
    await fixture.database.database.delete('evidence_items');
    await fixture.database.database.delete(
      'entity_tombstones',
      where: 'entity_type = ?',
      whereArgs: ['evidence_items'],
    );

    await fixture.manager.restore(backup, mode: LocalRestoreMode.merge);

    final restored = await fixture.database.database.query(
      'evidence_items',
      where: 'id = ?',
      whereArgs: ['evidence-case-path'],
    );
    final restoredName = restored.single['local_file_name']! as String;
    expect(restoredName.toLowerCase(), contains('receipt.backup-'));
    expect(
      await File(path.join(fixture.evidence.path, restoredName)).readAsString(),
      'backup-case-version',
    );
    expect(await evidence.readAsString(), 'newer-local-case-version');
  });

  test('inspection reports concrete newer local transaction counts', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final old = DateTime.utc(2026, 1, 1);
    await fixture.insertTransaction('existing', old);
    final backup = File(path.join(fixture.root.path, 'summary.butlerlybackup'));
    await fixture.manager.createBackup(backup);
    final future = DateTime.now().toUtc().add(const Duration(minutes: 1));
    await fixture.database.database.update(
      'transactions',
      {'updated_at': future.toIso8601String()},
      where: 'id = ?',
      whereArgs: ['existing'],
    );
    await fixture.insertTransaction('added', future);
    await fixture.database.database.insert('recurring_pattern_decisions', {
      'id': 'recurring-decision-newer',
      'pattern_key': 'newer|expense|EUR||',
      'status': 'confirmed',
      'cadence': 'monthly',
      'interval_days': 30,
      'expected_amount_coefficient': '10000',
      'expected_amount_scale': 2,
      'created_at': old.toIso8601String(),
      'updated_at': future.toIso8601String(),
    });

    final inspection = await fixture.manager.inspect(backup);

    expect(inspection.changes.transactionsAdded, 1);
    expect(inspection.changes.transactionsChanged, 1);
    expect(inspection.changes.masterDataChanged, greaterThanOrEqualTo(1));
    expect(inspection.hasNewerLocalData, isTrue);
  });
}

final class _Fixture {
  _Fixture(this.root, this.evidence, this.database, this.manager);

  final Directory root;
  final Directory evidence;
  final LocalDatabase database;
  final LocalBackupManager manager;

  static Future<_Fixture> create() async {
    final root = await Directory.systemTemp.createTemp(
      'butlerly-backup-hardening-',
    );
    final documents = Directory(path.join(root.path, 'documents'))
      ..createSync();
    final evidence = Directory(path.join(root.path, 'evidence'))..createSync();
    final database = LocalDatabase(
      logger: AppLogger(),
      factory: databaseFactoryFfi,
      databaseDirectory: root.path,
    );
    await database.initialize();
    final data = LocalDataManager(
      database,
      documentsDirectory: documents,
      localEvidenceDirectory: evidence,
    );
    return _Fixture(
      root,
      evidence,
      database,
      LocalBackupManager(database, data),
    );
  }

  Future<void> insertTransaction(String id, DateTime timestamp) async {
    await database.database.insert('transactions', {
      'id': id,
      'unknown_time_reason': 'unknown',
      'amount_coefficient': '100',
      'amount_scale': 2,
      'currency': 'EUR',
      'direction': 'expense',
      'source_type': 'manual',
      'status': 'active',
      'created_at': timestamp.toIso8601String(),
      'updated_at': timestamp.toIso8601String(),
    });
  }

  Future<void> dispose() async {
    await database.close();
    if (await root.exists()) await root.delete(recursive: true);
  }
}

Future<void> _rewriteBackupMetadata(
  File backup,
  void Function(Map<String, Object?> metadata) mutate,
) async {
  final bytes = await backup.readAsBytes();
  final magic = utf8.encode('BUTLERLYBACKUP2');
  final metadataLength = int64FromBytes(
    bytes.sublist(magic.length, magic.length + 8),
  );
  final metadataStart = magic.length + 8 + 64;
  final metadataEnd = metadataStart + metadataLength;
  final metadata =
      jsonDecode(utf8.decode(bytes.sublist(metadataStart, metadataEnd)))
          as Map<String, Object?>;
  mutate(metadata);
  final encoded = utf8.encode(jsonEncode(metadata));
  await backup.writeAsBytes([
    ...magic,
    ...int64Bytes(encoded.length),
    ...ascii.encode(sha256Bytes(encoded)),
    ...encoded,
    ...bytes.sublist(metadataEnd),
  ], flush: true);
}
