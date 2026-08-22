import 'dart:io';

import 'package:butlerly/core/database/local_database.dart';
import 'package:butlerly/core/logging/app_logger.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory directory;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'butlerly_database_test_',
    );
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test('initializes a versioned local database', () async {
    final database = LocalDatabase(
      logger: AppLogger(),
      factory: databaseFactoryFfi,
      databaseDirectory: directory.path,
    );

    await database.initialize();
    final tables = await database.database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );

    expect(database.status, DatabaseStatus.ready);
    expect(await database.database.getVersion(), 12);
    expect(tables.map((row) => row['name']), contains('transactions'));

    await database.close();
  });
}
