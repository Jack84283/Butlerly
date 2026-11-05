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
