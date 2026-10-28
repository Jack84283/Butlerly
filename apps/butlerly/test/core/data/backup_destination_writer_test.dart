import 'dart:convert';
import 'dart:io';

import 'package:butlerly/core/data/backup_destination_writer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  test(
    'recovery metadata cannot redirect private artifact operations',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'butlerly-backup-publication-metadata-',
      );
      addTearDown(() => root.delete(recursive: true));
      final privateDirectory = Directory(path.join(root.path, 'private'))
        ..createSync();
      final outside = File(path.join(root.path, 'outside.backup'))
        ..writeAsStringSync('must survive');
      final destination = File(path.join(root.path, 'destination.backup'));
      final marker = FileBackupPublicationRecoveryStore.markerFile(
        privateDirectory,
        'malicious',
      );
      await marker.writeAsString(
        jsonEncode({
          'operationId': 'malicious',
          'sourcePath': outside.path,
          'destinationPath': destination.path,
          'previousPath': outside.path,
          'hadExistingDestination': false,
          'previousReady': false,
        }),
        flush: true,
      );

      await expectLater(
        const BackupPublicationRecoveryManager().recover(privateDirectory),
        throwsA(isA<BackupPublicationRecoveryRequiredException>()),
      );
      expect(await outside.readAsString(), 'must survive');
      expect(await marker.exists(), isTrue);
    },
  );

  test('recovery metadata sidecar symlinks fail closed', () async {
    final root = await Directory.systemTemp.createTemp(
      'butlerly-backup-publication-sidecar-symlink-',
    );
    addTearDown(() => root.delete(recursive: true));
    final privateDirectory = Directory(path.join(root.path, 'private'))
      ..createSync();
    final target = File(path.join(root.path, 'target.json'))
      ..writeAsStringSync('{}');
    final marker = FileBackupPublicationRecoveryStore.markerFile(
      privateDirectory,
      'sidecar',
    );
    await Link(marker.path).create(target.path);

    await expectLater(
      const FileBackupPublicationRecoveryStore().read(privateDirectory),
      throwsA(isA<BackupPublicationRecoveryRequiredException>()),
    );
    expect(await target.readAsString(), '{}');
  });

  test(
    'migrates legacy publication markers before strict recovery validation',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'butlerly-backup-publication-legacy-marker-',
      );
      addTearDown(() => root.delete(recursive: true));
      final privateDirectory = Directory(path.join(root.path, 'private'))
        ..createSync();
      final source = File(
        path.join(
          privateDirectory.path,
          '.portable-backup-encrypted-legacy.butlerlybackup',
        ),
      )..writeAsStringSync('new backup');
      final previous = File(
        path.join(
          privateDirectory.path,
          '.portable-backup-previous-legacy.butlerlybackup',
        ),
      )..writeAsStringSync('previous backup');
      final destination = File(path.join(root.path, 'backup'))
        ..writeAsStringSync('partial replacement');
      final marker = FileBackupPublicationRecoveryStore.markerFile(
        privateDirectory,
        'legacy',
      );
      await marker.writeAsString(
        jsonEncode({
          'operationId': 'legacy',
          'sourcePath': source.path,
          'destinationPath': destination.path,
          'previousPath': previous.path,
          'hadExistingDestination': true,
          'previousReady': true,
        }),
        flush: true,
      );

      final recoveries = await const FileBackupPublicationRecoveryStore().read(
        privateDirectory,
      );
      expect(recoveries, hasLength(1));
      expect(recoveries.single.sourceSha256, isNotNull);
      expect(recoveries.single.previousSha256, isNotNull);
      final migrated = jsonDecode(await marker.readAsString()) as Map;
      expect(migrated['sourceSha256'], isNotNull);
      expect(migrated['previousSha256'], isNotNull);

      await BackupPublicationRecoveryManager().recover(
        privateDirectory,
        authorizedDestinationPath: destination.path,
      );

      expect(await destination.readAsString(), 'previous backup');
      expect(await source.exists(), isFalse);
      expect(await previous.exists(), isFalse);
      expect(await marker.exists(), isFalse);
    },
  );

  test(
    'failed replacement restores the existing selected destination',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'butlerly-backup-publication-',
      );
      addTearDown(() => root.delete(recursive: true));
      final privateDirectory = Directory(path.join(root.path, 'private'))
        ..createSync();
      final selectedDirectory = Directory(path.join(root.path, 'selected'))
        ..createSync();
      final source = File(path.join(privateDirectory.path, 'new.backup'))
        ..writeAsStringSync('new backup');
      final destination = File(path.join(selectedDirectory.path, 'backup'))
        ..writeAsStringSync('existing backup');
      var copyCount = 0;
      final writer = SandboxedBackupDestinationWriter(
        copy: (source, destinationPath) async {
          copyCount++;
          if (copyCount == 2) {
            await File(destinationPath).writeAsString('partial backup');
            throw const FileSystemException('simulated destination failure');
          }
          return source.copy(destinationPath);
        },
      );

      await expectLater(
        writer.publish(
          source: source,
          destination: destination,
          privateDirectory: privateDirectory,
          operationId: 'replace-failure',
        ),
        throwsA(isA<FileSystemException>()),
      );

      expect(await destination.readAsString(), 'existing backup');
      expect(await _namesStarting(selectedDirectory, 'backup.'), isEmpty);
      expect(
        await _namesStarting(privateDirectory, '.portable-backup-previous-'),
        isEmpty,
      );
    },
  );

  test(
    'failed new publication removes the partial selected destination',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'butlerly-backup-publication-new-',
      );
      addTearDown(() => root.delete(recursive: true));
      final privateDirectory = Directory(path.join(root.path, 'private'))
        ..createSync();
      final selectedDirectory = Directory(path.join(root.path, 'selected'))
        ..createSync();
      final source = File(path.join(privateDirectory.path, 'new.backup'))
        ..writeAsStringSync('new backup');
      final destination = File(path.join(selectedDirectory.path, 'backup'));
      final writer = SandboxedBackupDestinationWriter(
        copy: (source, destinationPath) async {
          await File(destinationPath).writeAsString('partial backup');
          throw const FileSystemException('simulated destination failure');
        },
      );

      await expectLater(
        writer.publish(
          source: source,
          destination: destination,
          privateDirectory: privateDirectory,
          operationId: 'new-failure',
        ),
        throwsA(isA<FileSystemException>()),
      );

      expect(await destination.exists(), isFalse);
      expect(
        await _namesStarting(privateDirectory, '.portable-backup-previous-'),
        isEmpty,
      );
    },
  );

  test(
    'failed previous-copy creation leaves the existing destination untouched',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'butlerly-backup-publication-previous-copy-failure-',
      );
      addTearDown(() => root.delete(recursive: true));
      final privateDirectory = Directory(path.join(root.path, 'private'))
        ..createSync();
      final selectedDirectory = Directory(path.join(root.path, 'selected'))
        ..createSync();
      final source = File(path.join(privateDirectory.path, 'new.backup'))
        ..writeAsStringSync('new backup');
      final destination = File(path.join(selectedDirectory.path, 'backup'))
        ..writeAsStringSync('existing backup');
      final writer = SandboxedBackupDestinationWriter(
        copy: (source, destinationPath) async {
          await File(destinationPath).writeAsString('partial previous');
          throw const FileSystemException('simulated previous-copy failure');
        },
      );

      await expectLater(
        writer.publish(
          source: source,
          destination: destination,
          privateDirectory: privateDirectory,
          operationId: 'previous-copy-failure',
        ),
        throwsA(isA<FileSystemException>()),
      );

      expect(await destination.readAsString(), 'existing backup');
      expect(
        await _namesStarting(privateDirectory, '.portable-backup-previous-'),
        isEmpty,
      );
    },
  );

  test(
    'failed rollback retains the private previous copy for recovery',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'butlerly-backup-publication-rollback-',
      );
      addTearDown(() => root.delete(recursive: true));
      final privateDirectory = Directory(path.join(root.path, 'private'))
        ..createSync();
      final selectedDirectory = Directory(path.join(root.path, 'selected'))
        ..createSync();
      final source = File(path.join(privateDirectory.path, 'new.backup'))
        ..writeAsStringSync('new backup');
      final destination = File(path.join(selectedDirectory.path, 'backup'))
        ..writeAsStringSync('existing backup');
      var copyCount = 0;
      final writer = SandboxedBackupDestinationWriter(
        copy: (source, destinationPath) async {
          copyCount++;
          if (copyCount == 2) {
            await File(destinationPath).writeAsString('partial backup');
            throw const FileSystemException('simulated destination failure');
          }
          if (copyCount == 3) {
            throw const FileSystemException('simulated rollback failure');
          }
          return source.copy(destinationPath);
        },
      );

      await expectLater(
        writer.publish(
          source: source,
          destination: destination,
          privateDirectory: privateDirectory,
          operationId: 'rollback-failure',
        ),
        throwsA(isA<BackupDestinationWriteException>()),
      );

      final previous = File(
        path.join(
          privateDirectory.path,
          '.portable-backup-previous-rollback-failure.butlerlybackup',
        ),
      );
      expect(await previous.readAsString(), 'existing backup');
      expect(await destination.readAsString(), 'existing backup');
      expect(await _namesStarting(selectedDirectory, 'backup.'), isEmpty);
    },
  );

  test(
    'startup recovery fails closed for an ambiguous interrupted replacement',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'butlerly-backup-publication-recovery-',
      );
      addTearDown(() => root.delete(recursive: true));
      final privateDirectory = Directory(path.join(root.path, 'private'))
        ..createSync();
      final selectedDirectory = Directory(path.join(root.path, 'selected'))
        ..createSync();
      final source = File(
        path.join(
          privateDirectory.path,
          '.portable-backup-encrypted-interrupted.butlerlybackup',
        ),
      )..writeAsStringSync('new backup');
      final previous = File(
        path.join(
          privateDirectory.path,
          '.portable-backup-previous-interrupted.butlerlybackup',
        ),
      )..writeAsStringSync('existing backup');
      final destination = File(path.join(selectedDirectory.path, 'backup'))
        ..writeAsStringSync('partial backup');
      final actualRecovery = BackupPublicationRecovery(
        operationId: 'interrupted',
        sourcePath: source.path,
        destinationPath: destination.path,
        previousPath: previous.path,
        hadExistingDestination: true,
        previousReady: true,
      );
      const store = FileBackupPublicationRecoveryStore();
      await store.write(privateDirectory, actualRecovery);

      await expectLater(
        BackupPublicationRecoveryManager().recover(privateDirectory),
        throwsA(isA<BackupPublicationRecoveryRequiredException>()),
      );

      expect(await destination.readAsString(), 'partial backup');
      expect(await previous.exists(), isTrue);
      expect(
        await FileBackupPublicationRecoveryStore.markerFile(
          privateDirectory,
          'interrupted',
        ).exists(),
        isTrue,
      );
    },
  );

  test(
    'startup recovery restores an absent destination after an interrupted replacement',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'butlerly-backup-publication-absent-destination-',
      );
      addTearDown(() => root.delete(recursive: true));
      final privateDirectory = Directory(path.join(root.path, 'private'))
        ..createSync();
      final source = File(
        path.join(
          privateDirectory.path,
          '.portable-backup-encrypted-absent.butlerlybackup',
        ),
      )..writeAsStringSync('new backup');
      final previous = File(
        path.join(
          privateDirectory.path,
          '.portable-backup-previous-absent.butlerlybackup',
        ),
      )..writeAsStringSync('existing backup');
      final destination = File(path.join(root.path, 'backup'));
      final recovery = BackupPublicationRecovery(
        operationId: 'absent',
        sourcePath: source.path,
        destinationPath: destination.path,
        previousPath: previous.path,
        hadExistingDestination: true,
        previousReady: true,
      );
      const store = FileBackupPublicationRecoveryStore();
      await store.write(privateDirectory, recovery);
      final staging = File(
        path.join(root.path, '.butlerly-backup-stage-absent.tmp'),
      );
      await source.copy(staging.path);

      await expectLater(
        BackupPublicationRecoveryManager().recover(privateDirectory),
        throwsA(isA<BackupPublicationRecoveryRequiredException>()),
      );

      expect(await destination.exists(), isFalse);
      expect(await previous.exists(), isTrue);

      await BackupPublicationRecoveryManager().recover(
        privateDirectory,
        authorizedDestinationPath: destination.path,
      );

      expect(await destination.readAsString(), 'existing backup');
      expect(await previous.exists(), isFalse);
      expect(await staging.exists(), isFalse);
      expect(await store.read(privateDirectory), isEmpty);
    },
  );

  test('recovery rejects a replaced private source artifact', () async {
    final root = await Directory.systemTemp.createTemp(
      'butlerly-backup-publication-source-fingerprint-',
    );
    addTearDown(() => root.delete(recursive: true));
    final privateDirectory = Directory(path.join(root.path, 'private'))
      ..createSync();
    final source = File(
      path.join(
        privateDirectory.path,
        '.portable-backup-encrypted-fingerprint.butlerlybackup',
      ),
    )..writeAsStringSync('new backup');
    final destination = File(path.join(root.path, 'backup'));
    final recovery = BackupPublicationRecovery(
      operationId: 'fingerprint',
      sourcePath: source.path,
      destinationPath: destination.path,
      previousPath: path.join(
        privateDirectory.path,
        '.portable-backup-previous-fingerprint.butlerlybackup',
      ),
      hadExistingDestination: false,
      previousReady: false,
    );
    const store = FileBackupPublicationRecoveryStore();
    await store.write(privateDirectory, recovery);
    await source.writeAsString('tampered source');

    await expectLater(
      BackupPublicationRecoveryManager().recover(
        privateDirectory,
        authorizedDestinationPath: destination.path,
      ),
      throwsA(isA<BackupPublicationRecoveryRequiredException>()),
    );
    expect(await destination.exists(), isFalse);
    expect(await source.readAsString(), 'tampered source');
    expect(await store.read(privateDirectory), hasLength(1));
  });

  test(
    'startup recovery preserves an unrelated replacement destination',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'butlerly-backup-publication-unrelated-replacement-',
      );
      addTearDown(() => root.delete(recursive: true));
      final privateDirectory = Directory(path.join(root.path, 'private'))
        ..createSync();
      final source = File(
        path.join(
          privateDirectory.path,
          '.portable-backup-encrypted-unrelated-replacement.butlerlybackup',
        ),
      )..writeAsStringSync('new backup');
      final destination = File(path.join(root.path, 'backup'))
        ..writeAsStringSync('unrelated file');
      final recovery = BackupPublicationRecovery(
        operationId: 'unrelated-replacement',
        sourcePath: source.path,
        destinationPath: destination.path,
        previousPath: path.join(
          privateDirectory.path,
          '.portable-backup-previous-unrelated-replacement.butlerlybackup',
        ),
        hadExistingDestination: false,
        previousReady: false,
      );
      const store = FileBackupPublicationRecoveryStore();
      await store.write(privateDirectory, recovery);

      await expectLater(
        BackupPublicationRecoveryManager().recover(privateDirectory),
        throwsA(isA<BackupPublicationRecoveryRequiredException>()),
      );

      expect(await destination.readAsString(), 'unrelated file');
      expect(await source.exists(), isTrue);
      expect(await store.read(privateDirectory), hasLength(1));
    },
  );

  test(
    'first-time recovery keeps the source until destination is authorized',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'butlerly-backup-publication-first-time-recovery-',
      );
      addTearDown(() => root.delete(recursive: true));
      final privateDirectory = Directory(path.join(root.path, 'private'))
        ..createSync();
      final source = File(
        path.join(
          privateDirectory.path,
          '.portable-backup-encrypted-first-time.butlerlybackup',
        ),
      )..writeAsStringSync('new backup');
      final destination = File(path.join(root.path, 'backup'));
      final recovery = BackupPublicationRecovery(
        operationId: 'first-time',
        sourcePath: source.path,
        destinationPath: destination.path,
        previousPath: path.join(
          privateDirectory.path,
          '.portable-backup-previous-first-time.butlerlybackup',
        ),
        hadExistingDestination: false,
        previousReady: false,
      );
      const store = FileBackupPublicationRecoveryStore();
      await store.write(privateDirectory, recovery);

      await expectLater(
        BackupPublicationRecoveryManager().recover(privateDirectory),
        throwsA(isA<BackupPublicationRecoveryRequiredException>()),
      );
      expect(await source.readAsString(), 'new backup');
      expect(await destination.exists(), isFalse);
      expect(await store.read(privateDirectory), hasLength(1));

      await BackupPublicationRecoveryManager().recover(
        privateDirectory,
        authorizedDestinationPath: destination.path,
      );

      expect(await destination.readAsString(), 'new backup');
      expect(await source.exists(), isFalse);
      expect(await store.read(privateDirectory), isEmpty);
    },
  );

  test(
    'destination symlinks are rejected without touching their targets',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'butlerly-backup-publication-destination-symlink-',
      );
      addTearDown(() => root.delete(recursive: true));
      final privateDirectory = Directory(path.join(root.path, 'private'))
        ..createSync();
      final selectedDirectory = Directory(path.join(root.path, 'selected'))
        ..createSync();
      final source = File(path.join(privateDirectory.path, 'new.backup'))
        ..writeAsStringSync('new backup');
      final target = File(path.join(root.path, 'unrelated.backup'))
        ..writeAsStringSync('must survive');
      final destination = File(path.join(selectedDirectory.path, 'backup'));
      await Link(destination.path).create(target.path);

      await expectLater(
        const SandboxedBackupDestinationWriter().publish(
          source: source,
          destination: destination,
          privateDirectory: privateDirectory,
          operationId: 'destination-symlink',
        ),
        throwsA(isA<FormatException>()),
      );

      expect(await target.readAsString(), 'must survive');
      expect(await source.readAsString(), 'new backup');
      expect(
        await FileBackupPublicationRecoveryStore.markerFile(
          privateDirectory,
          'destination-symlink',
        ).exists(),
        isFalse,
      );
    },
  );

  test(
    'destinations inside private storage are rejected before publication',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'butlerly-backup-publication-private-alias-',
      );
      addTearDown(() => root.delete(recursive: true));
      final privateDirectory = Directory(path.join(root.path, 'private'))
        ..createSync();
      final source = File(path.join(privateDirectory.path, 'new.backup'))
        ..writeAsStringSync('new backup');

      await expectLater(
        const SandboxedBackupDestinationWriter().publish(
          source: source,
          destination: source,
          privateDirectory: privateDirectory,
          operationId: 'private-alias',
        ),
        throwsA(isA<FormatException>()),
      );

      expect(await source.readAsString(), 'new backup');
      expect(
        await FileBackupPublicationRecoveryStore.markerFile(
          privateDirectory,
          'private-alias',
        ).exists(),
        isFalse,
      );
    },
  );

  test('hard-linked destinations are rejected before publication', () async {
    if (Platform.isWindows) return;
    final root = await Directory.systemTemp.createTemp(
      'butlerly-backup-publication-hard-link-',
    );
    addTearDown(() => root.delete(recursive: true));
    final privateDirectory = Directory(path.join(root.path, 'private'))
      ..createSync();
    final selectedDirectory = Directory(path.join(root.path, 'selected'))
      ..createSync();
    final source = File(path.join(privateDirectory.path, 'new.backup'))
      ..writeAsStringSync('new backup');
    final destination = File(path.join(selectedDirectory.path, 'backup'));
    final result = await Process.run('ln', [source.path, destination.path]);
    expect(result.exitCode, 0, reason: '$result');

    await expectLater(
      const SandboxedBackupDestinationWriter().publish(
        source: source,
        destination: destination,
        privateDirectory: privateDirectory,
        operationId: 'hard-link',
      ),
      throwsA(isA<FormatException>()),
    );

    expect(await source.readAsString(), 'new backup');
    expect(await destination.readAsString(), 'new backup');
  });

  test(
    'startup recovery preserves an unrelated replacement of an old destination',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'butlerly-backup-publication-unrelated-old-replacement-',
      );
      addTearDown(() => root.delete(recursive: true));
      final privateDirectory = Directory(path.join(root.path, 'private'))
        ..createSync();
      final source = File(
        path.join(
          privateDirectory.path,
          '.portable-backup-encrypted-unrelated-old-replacement.butlerlybackup',
        ),
      )..writeAsStringSync('new backup');
      final previous = File(
        path.join(
          privateDirectory.path,
          '.portable-backup-previous-unrelated-old-replacement.butlerlybackup',
        ),
      )..writeAsStringSync('old backup');
      final destination = File(path.join(root.path, 'backup'))
        ..writeAsStringSync('unrelated file');
      final recovery = BackupPublicationRecovery(
        operationId: 'unrelated-old-replacement',
        sourcePath: source.path,
        destinationPath: destination.path,
        previousPath: previous.path,
        hadExistingDestination: true,
        previousReady: true,
      );
      const store = FileBackupPublicationRecoveryStore();
      await store.write(privateDirectory, recovery);

      await expectLater(
        BackupPublicationRecoveryManager().recover(privateDirectory),
        throwsA(isA<BackupPublicationRecoveryRequiredException>()),
      );

      expect(await destination.readAsString(), 'unrelated file');
      expect(await previous.exists(), isTrue);
      expect(await store.read(privateDirectory), hasLength(1));
    },
  );

  test(
    'startup recovery resolves an interruption before the previous copy exists',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'butlerly-backup-publication-pre-copy-',
      );
      addTearDown(() => root.delete(recursive: true));
      final privateDirectory = Directory(path.join(root.path, 'private'))
        ..createSync();
      final destination = File(path.join(root.path, 'backup'))
        ..writeAsStringSync('existing backup');
      final source = File(
        path.join(
          privateDirectory.path,
          '.portable-backup-encrypted-pre-copy.butlerlybackup',
        ),
      )..writeAsStringSync('new backup');
      final recovery = BackupPublicationRecovery(
        operationId: 'pre-copy',
        sourcePath: source.path,
        destinationPath: destination.path,
        previousPath: path.join(
          privateDirectory.path,
          '.portable-backup-previous-pre-copy.butlerlybackup',
        ),
        hadExistingDestination: true,
        previousReady: false,
      );
      const store = FileBackupPublicationRecoveryStore();
      await store.write(privateDirectory, recovery);

      await BackupPublicationRecoveryManager().recover(privateDirectory);

      expect(await destination.readAsString(), 'existing backup');
      expect(await source.exists(), isFalse);
      expect(await store.read(privateDirectory), isEmpty);
    },
  );

  test(
    'startup recovery preserves a new source when the old destination disappears',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'butlerly-backup-publication-pre-copy-missing-destination-',
      );
      addTearDown(() => root.delete(recursive: true));
      final privateDirectory = Directory(path.join(root.path, 'private'))
        ..createSync();
      final source = File(
        path.join(
          privateDirectory.path,
          '.portable-backup-encrypted-pre-copy-missing.butlerlybackup',
        ),
      )..writeAsStringSync('new backup');
      final destination = File(path.join(root.path, 'backup'))
        ..writeAsStringSync('existing backup');
      final recovery = BackupPublicationRecovery(
        operationId: 'pre-copy-missing',
        sourcePath: source.path,
        destinationPath: destination.path,
        previousPath: path.join(
          privateDirectory.path,
          '.portable-backup-previous-pre-copy-missing.butlerlybackup',
        ),
        hadExistingDestination: true,
        previousReady: false,
      );
      const store = FileBackupPublicationRecoveryStore();
      await store.write(privateDirectory, recovery);
      await destination.delete();

      await expectLater(
        BackupPublicationRecoveryManager().recover(privateDirectory),
        throwsA(isA<BackupPublicationRecoveryRequiredException>()),
      );

      expect(await source.readAsString(), 'new backup');
      expect(await destination.exists(), isFalse);
      expect(await store.read(privateDirectory), hasLength(1));
    },
  );

  test(
    'startup recovery removes a partial previous copy before publication',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'butlerly-backup-publication-pre-copy-partial-',
      );
      addTearDown(() => root.delete(recursive: true));
      final privateDirectory = Directory(path.join(root.path, 'private'))
        ..createSync();
      final destination = File(path.join(root.path, 'backup'))
        ..writeAsStringSync('existing backup');
      final source = File(
        path.join(
          privateDirectory.path,
          '.portable-backup-encrypted-pre-copy-partial.butlerlybackup',
        ),
      )..writeAsStringSync('new backup');
      final previous = File(
        path.join(
          privateDirectory.path,
          '.portable-backup-previous-pre-copy-partial.butlerlybackup',
        ),
      )..writeAsStringSync('partial backup');
      final recovery = BackupPublicationRecovery(
        operationId: 'pre-copy-partial',
        sourcePath: source.path,
        destinationPath: destination.path,
        previousPath: previous.path,
        hadExistingDestination: true,
        previousReady: false,
      );
      const store = FileBackupPublicationRecoveryStore();
      await store.write(privateDirectory, recovery);

      await BackupPublicationRecoveryManager().recover(privateDirectory);

      expect(await destination.readAsString(), 'existing backup');
      expect(await previous.exists(), isFalse);
      expect(await source.exists(), isFalse);
      expect(await store.read(privateDirectory), isEmpty);
    },
  );

  test(
    'successful publication retains artifacts when marker finalization fails',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'butlerly-backup-publication-clear-failure-',
      );
      addTearDown(() => root.delete(recursive: true));
      final privateDirectory = Directory(path.join(root.path, 'private'))
        ..createSync();
      final source = File(
        path.join(
          privateDirectory.path,
          '.portable-backup-encrypted-clear-failure-publish.butlerlybackup',
        ),
      )..writeAsStringSync('new backup');
      final destination = File(path.join(root.path, 'backup'))
        ..writeAsStringSync('existing backup');
      final store = _FailOnceClearStore();
      final writer = SandboxedBackupDestinationWriter(recoveryStore: store);

      await expectLater(
        writer.publish(
          source: source,
          destination: destination,
          privateDirectory: privateDirectory,
          operationId: 'clear-failure-publish',
        ),
        throwsA(isA<BackupPublicationRecoveryRequiredException>()),
      );

      expect(await destination.readAsString(), 'new backup');
      expect(await source.exists(), isTrue);
      expect(
        await File(
          path.join(
            privateDirectory.path,
            '.portable-backup-previous-clear-failure-publish.butlerlybackup',
          ),
        ).exists(),
        isTrue,
      );

      await BackupPublicationRecoveryManager(
        store: store,
      ).recover(privateDirectory);

      expect(await source.exists(), isFalse);
      expect(await store.read(privateDirectory), isEmpty);
    },
  );

  test(
    'successful rollback retains artifacts when marker finalization fails',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'butlerly-backup-publication-rollback-clear-failure-',
      );
      addTearDown(() => root.delete(recursive: true));
      final privateDirectory = Directory(path.join(root.path, 'private'))
        ..createSync();
      final source = File(
        path.join(
          privateDirectory.path,
          '.portable-backup-encrypted-clear-failure-rollback.butlerlybackup',
        ),
      )..writeAsStringSync('new backup');
      final destination = File(path.join(root.path, 'backup'))
        ..writeAsStringSync('existing backup');
      var copyCount = 0;
      final store = _FailOnceClearStore();
      final writer = SandboxedBackupDestinationWriter(
        recoveryStore: store,
        copy: (source, destinationPath) async {
          copyCount++;
          if (copyCount == 2) {
            await File(destinationPath).writeAsString('partial backup');
            throw const FileSystemException('simulated destination failure');
          }
          return source.copy(destinationPath);
        },
      );

      await expectLater(
        writer.publish(
          source: source,
          destination: destination,
          privateDirectory: privateDirectory,
          operationId: 'clear-failure-rollback',
        ),
        throwsA(isA<BackupPublicationRecoveryRequiredException>()),
      );

      expect(await destination.readAsString(), 'existing backup');
      expect(await source.exists(), isTrue);

      await BackupPublicationRecoveryManager(
        store: store,
      ).recover(privateDirectory);

      expect(await source.exists(), isFalse);
      expect(await store.read(privateDirectory), isEmpty);
    },
  );
}

Future<List<String>> _namesStarting(Directory directory, String prefix) async {
  final names = <String>[];
  await for (final entity in directory.list(followLinks: false)) {
    final name = path.basename(entity.path);
    if (name.startsWith(prefix)) names.add(name);
  }
  return names;
}

final class _FailOnceClearStore implements BackupPublicationRecoveryStore {
  _FailOnceClearStore()
    : _delegate = const FileBackupPublicationRecoveryStore();

  final BackupPublicationRecoveryStore _delegate;
  bool _failed = false;

  @override
  Future<void> write(
    Directory privateDirectory,
    BackupPublicationRecovery recovery,
  ) => _delegate.write(privateDirectory, recovery);

  @override
  Future<void> clear(
    Directory privateDirectory,
    BackupPublicationRecovery recovery,
  ) {
    if (!_failed) {
      _failed = true;
      throw const FileSystemException('simulated recovery marker failure');
    }
    return _delegate.clear(privateDirectory, recovery);
  }

  @override
  Future<List<BackupPublicationRecovery>> read(Directory privateDirectory) =>
      _delegate.read(privateDirectory);
}
