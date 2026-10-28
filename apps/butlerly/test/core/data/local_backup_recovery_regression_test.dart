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

  test('backup creation recovers an interrupted destination swap', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final destination = File(
      path.join(fixture.root.path, 'recoverable.butlerlybackup'),
    );

    await fixture.manager.createBackup(destination);
    final originalLength = await destination.length();
    final previous = File('${destination.path}.previous-interrupted');
    await destination.rename(previous.path);
    expect(await destination.exists(), isFalse);
    expect(await previous.exists(), isTrue);

    await fixture.manager.createBackup(destination);

    expect(await destination.exists(), isTrue);
    expect(await destination.length(), greaterThan(0));
    expect(originalLength, greaterThan(0));
    expect(await previous.exists(), isFalse);
    final leftovers = await destination.parent
        .list(followLinks: false)
        .where(
          (entity) =>
              entity is File &&
              path
                  .basename(entity.path)
                  .startsWith('${path.basename(destination.path)}.previous-'),
        )
        .toList();
    expect(leftovers, isEmpty);
  });

  test(
    'ambiguous torn restore fails closed and preserves every tree',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final live = File(path.join(fixture.evidence.path, 'receipt.bin'));
      await live.writeAsString('live');

      final previousA = Directory(
        '${fixture.evidence.path}.restore-previous-restore-a',
      )..createSync(recursive: true);
      final previousB = Directory(
        '${fixture.evidence.path}.restore-previous-restore-b',
      )..createSync(recursive: true);
      await File(
        path.join(previousA.path, 'receipt.bin'),
      ).writeAsString('old-a');
      await File(
        path.join(previousB.path, 'receipt.bin'),
      ).writeAsString('old-b');
      final safetyDirectory = await fixture.manager.localDataManager
          .safetyBackupDirectory();
      final safety = File(
        path.join(safetyDirectory.path, 'safety.butlerlybackup'),
      );
      await fixture.manager.createBackup(safety);
      await _writeOrigin(
        fixture.evidence,
        operationId: 'wrapper-ambiguous',
        rootExisted: true,
        safetyBackupPath: safety.path,
      );
      final journal = File('${fixture.evidence.path}.restore-journal.json');
      await journal.writeAsString('{"operationId":');

      await expectLater(
        fixture.manager.recoverInterruptedRestore(),
        throwsA(isA<RestoreRecoveryRequiredException>()),
      );

      expect(await live.readAsString(), 'live');
      expect(await previousA.exists(), isTrue);
      expect(await previousB.exists(), isTrue);
      expect(await journal.exists(), isTrue);
      expect(fixture.manager.recoveryState.isRecoveryRequired, isTrue);
      expect(
        fixture.manager.recoveryState.incident?.reason,
        'ambiguous-restore-recovery',
      );
      expect(
        fixture.manager.recoveryState.incident?.safetyBackupPath,
        safety.path,
      );
    },
  );

  test('valid restore journal ignores unrelated stale previous tree', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final live = File(path.join(fixture.evidence.path, 'receipt.bin'));
    await live.writeAsString('new');

    const operation = 'restore-current';
    final currentPrevious = Directory(
      '${fixture.evidence.path}.restore-previous-$operation',
    )..createSync(recursive: true);
    await File(
      path.join(currentPrevious.path, 'receipt.bin'),
    ).writeAsString('expected-old');
    final unrelated = Directory(
      '${fixture.evidence.path}.restore-previous-restore-stale',
    )..createSync(recursive: true);
    await File(
      path.join(unrelated.path, 'receipt.bin'),
    ).writeAsString('stale-old');

    final journal = File('${fixture.evidence.path}.restore-journal.json');
    await journal.writeAsString(
      '{"operationId":"$operation",'
      '"previousPath":"${currentPrevious.path}",'
      '"stagingPath":"${fixture.evidence.path}.restore-$operation",'
      '"phase":"dbWriting"}',
    );

    await fixture.manager.recoverInterruptedRestore();

    expect(await live.readAsString(), 'expected-old');
    expect(await unrelated.exists(), isTrue);
    expect(await journal.exists(), isFalse);
  });

  test(
    'external journal paths fail closed without touching their targets',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final outside = Directory(path.join(fixture.root.path, 'outside'))
        ..createSync(recursive: true);
      final protectedFile = File(path.join(outside.path, 'must-survive.txt'))
        ..writeAsStringSync('protected');
      final journal = File('${fixture.evidence.path}.restore-journal.json');
      await journal.writeAsString(
        '{"operationId":"restore-external",'
        '"previousPath":"${outside.path}",'
        '"stagingPath":"${outside.path}",'
        '"phase":"evidenceActivated"}',
      );

      await expectLater(
        fixture.manager.recoverInterruptedRestore(),
        throwsA(isA<RestoreRecoveryRequiredException>()),
      );

      expect(await protectedFile.readAsString(), 'protected');
      expect(await outside.exists(), isTrue);
      expect(await journal.exists(), isTrue);
      expect(
        fixture.manager.recoveryState.incident?.reason,
        'unsafe-restore-journal-path',
      );
    },
  );

  for (final controlFile in <({String label, String suffix})>[
    (label: 'journal', suffix: '.restore-journal.json'),
    (label: 'journal temp', suffix: '.restore-journal.json.tmp'),
    (label: 'journal previous', suffix: '.restore-journal.json.previous'),
    (label: 'origin', suffix: '.restore-origin.json'),
    (label: 'origin temp', suffix: '.restore-origin.json.tmp'),
    (label: 'origin previous', suffix: '.restore-origin.json.previous'),
  ]) {
    test('symlinked ${controlFile.label} control file fails closed', () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final live = File(path.join(fixture.evidence.path, 'receipt.bin'))
        ..writeAsStringSync('must-survive');
      final target = File(
        path.join(fixture.root.path, '${controlFile.label}-target.json'),
      )..writeAsStringSync('{}');
      final link = File('${fixture.evidence.path}${controlFile.suffix}');
      await Link(link.path).create(target.path);

      await expectLater(
        fixture.manager.recoverInterruptedRestore(),
        throwsA(isA<RestoreRecoveryRequiredException>()),
      );

      expect(await live.readAsString(), 'must-survive');
      expect(await target.readAsString(), '{}');
      expect(
        await FileSystemEntity.type(link.path, followLinks: false),
        FileSystemEntityType.link,
      );
      expect(
        fixture.manager.recoveryState.incident?.reason,
        'unsafe-restore-control-path',
      );
    });
  }

  test('symlinked live evidence root fails closed', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final realEvidence = Directory('${fixture.evidence.path}-real')
      ..createSync(recursive: true);
    final live = File(path.join(realEvidence.path, 'receipt.bin'))
      ..writeAsStringSync('must-survive');
    await fixture.evidence.delete();
    await Link(fixture.evidence.path).create(realEvidence.path);

    try {
      await expectLater(
        fixture.manager.recoverInterruptedRestore(),
        throwsA(isA<RestoreRecoveryRequiredException>()),
      );

      expect(await live.readAsString(), 'must-survive');
      expect(
        fixture.manager.recoveryState.incident?.reason,
        'unsafe-restore-evidence-root',
      );
      expect(
        await FileSystemEntity.type(fixture.evidence.path, followLinks: false),
        FileSystemEntityType.link,
      );
    } finally {
      await Link(fixture.evidence.path).delete();
      await realEvidence.rename(fixture.evidence.path);
    }
  });

  test(
    'pre-commit recovery returns to an originally absent evidence root',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.evidence.delete(recursive: true);

      const operation = 'restore-empty-origin';
      final safetyDirectory = await fixture.manager.localDataManager
          .safetyBackupDirectory();
      await fixture.evidence.create(recursive: true);
      await File(
        path.join(fixture.evidence.path, 'restored.bin'),
      ).writeAsString('new');
      await _writeOrigin(
        fixture.evidence,
        operationId: 'wrapper-empty-origin',
        rootExisted: false,
        safetyBackupPath: path.join(
          safetyDirectory.path,
          'safety.butlerlybackup',
        ),
      );
      final originState = File('${fixture.evidence.path}.restore-origin.json');
      final journal = File('${fixture.evidence.path}.restore-journal.json');
      await journal.writeAsString(
        '{"operationId":"$operation",'
        '"previousPath":"${fixture.evidence.path}.restore-previous-$operation",'
        '"stagingPath":"${fixture.evidence.path}.restore-$operation",'
        '"phase":"dbWriting"}',
      );

      await fixture.manager.recoverInterruptedRestore();

      expect(await fixture.evidence.exists(), isFalse);
      expect(await journal.exists(), isFalse);
      expect(await originState.exists(), isFalse);
      expect(fixture.manager.recoveryState.isRecoveryRequired, isFalse);
    },
  );

  test('missing previous tree for an existing origin fails closed', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final live = File(path.join(fixture.evidence.path, 'receipt.bin'));
    await live.writeAsString('uncommitted-live');

    const operation = 'restore-missing-previous';
    final safetyDirectory = await fixture.manager.localDataManager
        .safetyBackupDirectory();
    final safety = File(
      path.join(safetyDirectory.path, 'safety.butlerlybackup'),
    );
    await fixture.manager.createBackup(safety);
    await _writeOrigin(
      fixture.evidence,
      operationId: 'wrapper-missing-previous',
      rootExisted: true,
      safetyBackupPath: safety.path,
    );
    final originState = File('${fixture.evidence.path}.restore-origin.json');
    final journal = File('${fixture.evidence.path}.restore-journal.json');
    await journal.writeAsString(
      '{"operationId":"$operation",'
      '"previousPath":"${fixture.evidence.path}.restore-previous-$operation",'
      '"stagingPath":"${fixture.evidence.path}.restore-$operation",'
      '"phase":"dbWriting"}',
    );

    await expectLater(
      fixture.manager.recoverInterruptedRestore(),
      throwsA(isA<RestoreRecoveryRequiredException>()),
    );

    expect(await live.readAsString(), 'uncommitted-live');
    expect(await journal.exists(), isTrue);
    expect(await originState.exists(), isTrue);
    expect(
      fixture.manager.recoveryState.incident?.reason,
      'missing-previous-evidence-recovery',
    );
    expect(
      fixture.manager.recoveryState.incident?.safetyBackupPath,
      safety.path,
    );
  });

  test(
    'activated legacy journal without origin never deletes live evidence',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final live = File(path.join(fixture.evidence.path, 'receipt.bin'));
      await live.writeAsString('only-live-copy');
      const operation = 'restore-no-origin';
      final journal = File('${fixture.evidence.path}.restore-journal.json');
      await journal.writeAsString(
        '{"operationId":"$operation",'
        '"previousPath":"${fixture.evidence.path}.restore-previous-$operation",'
        '"stagingPath":"${fixture.evidence.path}.restore-$operation",'
        '"phase":"evidenceActivated"}',
      );

      await expectLater(
        fixture.manager.recoverInterruptedRestore(),
        throwsA(isA<RestoreRecoveryRequiredException>()),
      );

      expect(await live.readAsString(), 'only-live-copy');
      expect(await journal.exists(), isTrue);
      expect(
        fixture.manager.recoveryState.incident?.reason,
        'indeterminate-restore-recovery',
      );
    },
  );

  test(
    'completed engine activation with pending wrapper validation fails closed',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final safetyDirectory = await fixture.manager.localDataManager
          .safetyBackupDirectory();
      final safety = File(
        path.join(safetyDirectory.path, 'safety.butlerlybackup'),
      );
      await fixture.manager.createBackup(safety);
      await _writeOrigin(
        fixture.evidence,
        operationId: 'wrapper-validation-pending',
        rootExisted: true,
        safetyBackupPath: safety.path,
      );

      await expectLater(
        fixture.manager.recoverInterruptedRestore(),
        throwsA(isA<RestoreRecoveryRequiredException>()),
      );

      final incident = fixture.manager.recoveryState.incident;
      expect(incident?.reason, 'post-activation-validation-pending');
      expect(incident?.retryCurrentState, isTrue);
      expect(incident?.safetyBackupPath, safety.path);
    },
  );

  test('outside safety path records a generic recovery gate', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await _writeOrigin(
      fixture.evidence,
      operationId: 'unsafe-safety-path',
      rootExisted: true,
      safetyBackupPath: path.join(fixture.root.path, 'outside.butlerlybackup'),
    );

    await expectLater(
      fixture.manager.recoverInterruptedRestore(),
      throwsA(isA<RestoreRecoveryRequiredException>()),
    );

    final incident = fixture.manager.recoveryState.incident;
    expect(incident?.reason, 'unsafe-restore-safety-path');
    expect(incident?.safetyBackupPath, isEmpty);
  });

  test(
    'interrupted origin replacement never trusts the older main intent',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final safetyDirectory = await fixture.manager.localDataManager
          .safetyBackupDirectory();
      final oldSafety = File(
        path.join(safetyDirectory.path, 'old-safety.butlerlybackup'),
      );
      final newSafety = File(
        path.join(safetyDirectory.path, 'new-safety.butlerlybackup'),
      );
      await fixture.manager.createBackup(oldSafety);
      await fixture.manager.createBackup(newSafety);

      await _writeOrigin(
        fixture.evidence,
        operationId: 'old-operation',
        rootExisted: true,
        safetyBackupPath: oldSafety.path,
      );
      final origin = File('${fixture.evidence.path}.restore-origin.json');
      await File('${origin.path}.tmp').writeAsString(
        jsonEncode({
          'operationId': 'new-operation',
          'rootExisted': true,
          'safetyBackupPath': newSafety.path,
          'activationPending': true,
        }),
        flush: true,
      );

      await expectLater(
        fixture.manager.recoverInterruptedRestore(),
        throwsA(isA<RestoreRecoveryRequiredException>()),
      );

      final incident = fixture.manager.recoveryState.incident;
      expect(incident?.reason, 'unreadable-restore-origin-state');
      expect(incident?.safetyBackupPath, isEmpty);
      expect(await origin.exists(), isTrue);
      expect(await File('${origin.path}.tmp').exists(), isTrue);
    },
  );
}

Future<void> _writeOrigin(
  Directory evidence, {
  required String operationId,
  required bool rootExisted,
  required String safetyBackupPath,
}) async {
  final file = File('${evidence.path}.restore-origin.json');
  await file.writeAsString(
    jsonEncode({
      'operationId': operationId,
      'rootExisted': rootExisted,
      'safetyBackupPath': safetyBackupPath,
      'activationPending': true,
    }),
    flush: true,
  );
}

final class _Fixture {
  _Fixture(this.root, this.evidence, this.database, this.manager);

  final Directory root;
  final Directory evidence;
  final LocalDatabase database;
  final LocalBackupManager manager;

  static Future<_Fixture> create() async {
    final root = await Directory.systemTemp.createTemp(
      'butlerly-backup-recovery-regression-',
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

  Future<void> dispose() async {
    await database.close();
    if (await root.exists()) await root.delete(recursive: true);
  }
}
