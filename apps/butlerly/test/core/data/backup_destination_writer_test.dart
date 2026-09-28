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
}

Future<List<String>> _namesStarting(Directory directory, String prefix) async {
  final names = <String>[];
  await for (final entity in directory.list(followLinks: false)) {
    final name = path.basename(entity.path);
    if (name.startsWith(prefix)) names.add(name);
  }
  return names;
}
