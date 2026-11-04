import 'dart:io';

import 'package:butlerly/core/data/raw_backup_archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  late Directory working;
  late File sqlite;
  late Directory evidence;
  late File archive;

  setUp(() async {
    working = await Directory.systemTemp.createTemp('butlerly-raw-archive-');
    sqlite = File(path.join(working.path, 'source.sqlite'));
    evidence = Directory(path.join(working.path, 'evidence'));
    await Directory(path.join(evidence.path, 'receipts')).create(recursive: true);
    await File(path.join(evidence.path, 'receipts', 'one.jpg'))
        .writeAsBytes([1, 2, 3, 4, 5]);
    archive = File(path.join(working.path, 'backup.package'));
    final db = await databaseFactoryFfi.openDatabase(sqlite.path);
    try {
      await db.execute('CREATE TABLE original_data (id TEXT PRIMARY KEY, value TEXT)');
      await db.insert('original_data', {
        'id': 'record-1',
        'value': 'uninterpreted original data',
      });
    } finally {
      await db.close();
    }
  });

  tearDown(() async {
    if (await working.exists()) await working.delete(recursive: true);
  });

  test('round-trips raw SQLite and available evidence without interpreting rows',
      () async {
    final backup = const RawBackupArchive();
    final created = await backup.write(
      sqliteSnapshot: sqlite,
      evidenceDirectory: evidence,
      referencedEvidencePaths: const [
        'receipts/one.jpg',
        'receipts/missing.jpg',
      ],
      destination: archive,
    );
    expect(created.attachmentCount, 1);
    expect(created.missingAttachmentCount, 1);
    expect(created.hasWarnings, isTrue);

    final staged = Directory(path.join(working.path, 'staged'));
    final inspected = await backup.extract(
      archive: archive,
      stagingDirectory: staged,
    );
    expect(inspected.sqliteBytes, await sqlite.length());
    expect(
      await File(path.join(staged.path, 'evidence', 'receipts', 'one.jpg'))
          .readAsBytes(),
      [1, 2, 3, 4, 5],
    );

    final restored = await databaseFactoryFfi.openDatabase(
      path.join(staged.path, 'butlerly.db'),
      options: OpenDatabaseOptions(readOnly: true),
    );
    try {
      final rows = await restored.query('original_data');
      expect(rows, hasLength(1));
      expect(rows.single['value'], 'uninterpreted original data');
    } finally {
      await restored.close();
    }
  });

  test('missing optional evidence does not fail backup', () async {
    final archiveManager = const RawBackupArchive();
    final result = await archiveManager.write(
      sqliteSnapshot: sqlite,
      evidenceDirectory: evidence,
      referencedEvidencePaths: const [
        'receipts/missing.jpg',
        '../unsafe-reference',
      ],
      destination: archive,
    );
    expect(result.missingAttachmentCount, 2);
    expect((await archiveManager.inspect(archive)).missingAttachmentCount, 2);
  });

  test('tampering with a saved archive is rejected', () async {
    final archiveManager = const RawBackupArchive();
    await archiveManager.write(
      sqliteSnapshot: sqlite,
      evidenceDirectory: evidence,
      referencedEvidencePaths: const [],
      destination: archive,
    );
    final file = await archive.open(mode: FileMode.append);
    try {
      await file.writeByte(0xAA);
    } finally {
      await file.close();
    }
    await expectLater(
      archiveManager.inspect(archive),
      throwsA(isA<FormatException>()),
    );
  });

  test('unsupported or legacy archive is rejected without changing files',
      () async {
    await archive.writeAsString('not a Butlerly raw backup');
    await expectLater(
      const RawBackupArchive().inspect(archive),
      throwsA(isA<FormatException>()),
    );
    expect(await archive.readAsString(), 'not a Butlerly raw backup');
  });
}
