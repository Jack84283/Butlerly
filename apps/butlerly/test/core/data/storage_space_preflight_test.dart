import 'dart:io';

import 'package:butlerly/core/data/storage_space_preflight.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('preflight blocks unsafe staging before any data mutation', () async {
    final root = await Directory.systemTemp.createTemp('butlerly-capacity-');
    addTearDown(() => root.delete(recursive: true));
    await expectLater(
      StorageSpacePreflight.requireAvailable(
        root,
        stagingBytes: 128 * 1024 * 1024,
        probe: (_) async => 100 * 1024 * 1024,
      ),
      throwsA(
        isA<FileSystemException>().having(
          (e) => e.osError?.errorCode,
          'ENOSPC error code',
          28,
        ),
      ),
    );
  });

  test('preflight accepts sufficiently available private space', () async {
    final root = await Directory.systemTemp.createTemp('butlerly-capacity-');
    addTearDown(() => root.delete(recursive: true));
    await StorageSpacePreflight.requireAvailable(
      root,
      stagingBytes: 128 * 1024 * 1024,
      probe: (_) async => 256 * 1024 * 1024,
    );
  });

  test('preflight treats unknown platform capacity as advisory', () async {
    final root = await Directory.systemTemp.createTemp('butlerly-capacity-');
    addTearDown(() => root.delete(recursive: true));
    await StorageSpacePreflight.requireAvailable(
      root,
      stagingBytes: 128 * 1024 * 1024,
      probe: (_) async => null,
    );
  });

  test('one filesystem must afford combined peak staging and export', () async {
    final root = await Directory.systemTemp.createTemp('shared-capacity-');
    addTearDown(() => root.delete(recursive: true));
    final internal = Directory('${root.path}/internal')..createSync();
    final external = Directory('${root.path}/external')..createSync();
    const mib = 1024 * 1024;
    await expectLater(
      StorageSpacePreflight.requireBackupCapacity(
        privateDirectory: internal,
        destinationDirectory: external,
        privateStagingBytes: 200 * mib,
        destinationStagingBytes: 100 * mib,
        identityProbe: (_) async => 'shared-device',
        probe: (_) async => 280 * mib,
      ),
      throwsA(isA<FileSystemException>()),
    );
    await StorageSpacePreflight.requireBackupCapacity(
      privateDirectory: internal,
      destinationDirectory: external,
      privateStagingBytes: 200 * mib,
      destinationStagingBytes: 100 * mib,
      identityProbe: (dir) async => dir.path,
      probe: (dir) async => dir.path == internal.path ? 280 * mib : 170 * mib,
    );
  });

  test('unknown filesystem identity must assume shared capacity', () async {
    final root = await Directory.systemTemp.createTemp('unknown-capacity-');
    addTearDown(() => root.delete(recursive: true));
    const mib = 1024 * 1024;
    await expectLater(
      StorageSpacePreflight.requireBackupCapacity(
        privateDirectory: root,
        destinationDirectory: root,
        privateStagingBytes: 200 * mib,
        destinationStagingBytes: 100 * mib,
        identityProbe: (_) async => null,
        probe: (_) async => 280 * mib,
      ),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('staging estimate includes copies and encryption verification', () {
    expect(
      StorageSpacePreflight.backupStagingBytes(
        databaseBytes: 100,
        evidenceBytes: 50,
      ),
      550,
    );
    expect(
      StorageSpacePreflight.restoreStagingBytes(
        archiveBytes: 200,
        databaseBytes: 100,
        evidenceBytes: 50,
      ),
      1200,
    );
  });
}
