import 'dart:io';

import 'package:butlerly/core/data/backup_destination_writer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
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
      expect(await destination.readAsString(), 'partial backup');
      expect(await _namesStarting(selectedDirectory, 'backup.'), isEmpty);
    },
  );

  test(
    'startup recovery restores a destination after an interrupted replacement',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'butlerly-backup-publication-recovery-',
      );
      addTearDown(() => root.delete(recursive: true));
      final privateDirectory = Directory(path.join(root.path, 'private'))
        ..createSync();
      final selectedDirectory = Directory(path.join(root.path, 'selected'))
        ..createSync();
      final source = File(path.join(privateDirectory.path, 'new.backup'))
        ..writeAsStringSync('new backup');
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

      await BackupPublicationRecoveryManager().recover(privateDirectory);

      expect(await destination.readAsString(), 'existing backup');
      expect(await previous.exists(), isFalse);
      expect(
        await FileBackupPublicationRecoveryStore.markerFile(
          privateDirectory,
          'interrupted',
        ).exists(),
        isFalse,
      );
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
      final source = File(path.join(privateDirectory.path, 'source.backup'))
        ..writeAsStringSync('new backup');
      final recovery = BackupPublicationRecovery(
        operationId: 'pre-copy',
        sourcePath: source.path,
        destinationPath: destination.path,
        previousPath: path.join(privateDirectory.path, 'previous.backup'),
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
      final source = File(path.join(privateDirectory.path, 'source.backup'))
        ..writeAsStringSync('new backup');
      final previous = File(path.join(privateDirectory.path, 'previous.backup'))
        ..writeAsStringSync('partial backup');
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
      final source = File(path.join(privateDirectory.path, 'new.backup'))
        ..writeAsStringSync('new backup');
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
      final source = File(path.join(privateDirectory.path, 'new.backup'))
        ..writeAsStringSync('new backup');
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
