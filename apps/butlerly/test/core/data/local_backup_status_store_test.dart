import 'dart:io';

import 'package:butlerly/core/data/local_backup_status_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late LocalBackupStatusStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'butlerly-backup-status-',
    );
    store = LocalBackupStatusStore(directoryOverride: directory);
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test(
    'unknown remains unknown when no successful backup was recorded',
    () async {
      expect(await store.read(), isNull);
    },
  );

  test('records successful completion and missing attachment status', () async {
    await store.recordCompleted(missingAttachments: true);
    final first = await store.read();
    expect(first, isNotNull);
    expect(first!.completedAtUtc.isUtc, isTrue);
    expect(first.missingAttachments, isTrue);
    expect(
      first.completedAtUtc.difference(DateTime.now().toUtc()).inMinutes.abs(),
      lessThan(2),
    );

    await store.recordCompleted(missingAttachments: false);
    final reopened = LocalBackupStatusStore(directoryOverride: directory);
    final second = await reopened.read();
    expect(second, isNotNull);
    expect(second!.missingAttachments, isFalse);
  });

  test('corrupt or mismatched status file never implies success', () async {
    final statusFile = File('${directory.path}/backup_status_v1.json');
    await statusFile.writeAsString('not valid json');
    expect(await store.read(), isNull);
    await statusFile.writeAsString(
      '{"version":2,"completedAtUtc":"2026-11-11T12:00:00Z","missingAttachments":false}',
    );
    expect(await store.read(), isNull);
  });
}
