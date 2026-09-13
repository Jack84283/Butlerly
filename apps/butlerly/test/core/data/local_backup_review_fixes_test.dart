import 'dart:convert';
import 'dart:io';

import 'package:butlerly/core/data/local_backup_manager.dart';
import 'package:butlerly/core/data/local_data_manager.dart';
import 'package:butlerly/core/database/local_database.dart';
import 'package:butlerly/core/logging/app_logger.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  test('merge restore preserves historical master-data updatedAt', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final old = DateTime.utc(2025, 1, 1).toIso8601String();
    await fixture.database.database.insert('merchants', {
      'id': 'merchant-user-review',
      'name': 'Review Merchant',
      'status': 'active',
      'normalized_name': 'review merchant',
      'is_built_in': 0,
      'created_at': old,
      'updated_at': old,
    });
    final backup = File(path.join(fixture.root.path, 'timestamps.butlerlybackup'));
    await fixture.manager.createBackup(backup);

    await fixture.manager.restore(backup, mode: LocalRestoreMode.merge);

    final rows = await fixture.database.database.query(
      'merchants',
      columns: ['updated_at'],
      where: 'id = ?',
      whereArgs: ['merchant-user-review'],
    );
    expect(rows, hasLength(1));
    expect(rows.single['updated_at'], old);
  });

  test('post-commit cleanup ambiguity never deletes live evidence', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final live = File(path.join(fixture.evidence.path, 'committed.bin'));
    await live.writeAsString('committed-evidence', flush: true);
    final journal = File('${fixture.evidence.path}.restore-journal.json');
    await journal.writeAsString(
      jsonEncode({
        'operationId': 'restore-cleanup-window',
        'previousPath': '${fixture.evidence.path}.restore-previous-missing',
        'stagingPath': '${fixture.evidence.path}.restore-missing',
        'phase': 'dbCommitted',
      }),
      flush: true,
    );

    await fixture.manager.recoverInterruptedRestore();

    expect(await live.exists(), isTrue);
    expect(await live.readAsString(), 'committed-evidence');
    expect(await journal.exists(), isFalse);
  });

  test('backup package keeps pre-write database state', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final old = DateTime.utc(2025, 1, 1).toIso8601String();
    await fixture.database.database.insert('merchants', {
      'id': 'merchant-snapshot-review',
      'name': 'Before backup',
      'status': 'active',
      'normalized_name': 'before backup',
      'is_built_in': 0,
      'created_at': old,
      'updated_at': old,
    });

    // Keep serialization active long enough for the competing write to be
    // submitted while the manager owns its independent SQLite snapshot lock.
    final slowEvidence = File(path.join(fixture.evidence.path, 'slow.bin'));
    await slowEvidence.writeAsBytes(List<int>.filled(2 * 1024 * 1024, 7));
    final backup = File(path.join(fixture.root.path, 'snapshot.butlerlybackup'));
    final backupFuture = fixture.manager.createBackup(backup);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final writeFuture = fixture.database.database.update(
      'merchants',
      {'name': 'After backup', 'normalized_name': 'after backup'},
      where: 'id = ?',
      whereArgs: ['merchant-snapshot-review'],
    );

    await backupFuture;
    await writeFuture;
    await fixture.manager.restore(backup, mode: LocalRestoreMode.replace);

    final rows = await fixture.database.database.query(
      'merchants',
      columns: ['name'],
      where: 'id = ?',
      whereArgs: ['merchant-snapshot-review'],
    );
    expect(rows, hasLength(1));
    expect(rows.single['name'], 'Before backup');
  });
}

final class _Fixture {
  _Fixture(this.root, this.evidence, this.database, this.manager);

  final Directory root;
  final Directory evidence;
  final LocalDatabase database;
  final LocalBackupManager manager;

  static Future<_Fixture> create() async {
    final root = await Directory.systemTemp.createTemp('butlerly-review-fixes-');
    final documents = Directory(path.join(root.path, 'documents'))..createSync();
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
    return _Fixture(root, evidence, database, LocalBackupManager(database, data));
  }

  Future<void> dispose() async {
    await database.close();
    if (await root.exists()) await root.delete(recursive: true);
  }
}
