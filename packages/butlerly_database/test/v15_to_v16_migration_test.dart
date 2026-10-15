import 'dart:io';

import 'package:butlerly_database/butlerly_database.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

import 'support/deployment_sql.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('v15 to v16 retains existing cards and saves network metadata', () async {
    final directory = await Directory.systemTemp.createTemp('butlerly-v16-');
    final path = '${directory.path}/legacy.db';
    final schema = await File('database/schema/v1.sql').readAsString();
    final legacy = schema.replaceFirst('      network TEXT,\n', '');
    try {
      final old = ButlerlyDatabase(
        factory: databaseFactoryFfi,
        path: path,
        schemaSql: legacy,
        targetVersion: 15,
      );
      await old.open();
      await old.connection.insert('payment_sources', {
        'id': 'legacy-card',
        'name': 'Chase Sapphire',
        'type': 'card',
        'status': 'active',
        'issuer': 'Chase',
        'last_four': '8421',
      });
      await old.close();

      final upgraded = ButlerlyDatabase(
        factory: databaseFactoryFfi,
        path: path,
        schemaSql: schema,
        targetVersion: 16,
        migrations: {16: await migrationSqlForVersion(16)},
      );
      await upgraded.open();
      addTearDown(upgraded.close);
      expect(await upgraded.connection.getVersion(), 16);
      final repository = SqlitePaymentSourceRepository(upgraded);
      final legacySource = await repository.findById(
        PaymentSourceId('legacy-card'),
      );
      expect(legacySource?.name, 'Chase Sapphire');
      expect(legacySource?.network, isNull);
      expect(legacySource?.lastFour, '8421');

      await repository.save(
        PaymentSource(
          id: PaymentSourceId('legacy-card'),
          name: 'Chase Sapphire',
          type: PaymentSourceType.card,
          issuer: 'Chase',
          lastFour: '8421',
          network: 'visa',
        ),
      );
      expect(
        (await repository.findById(PaymentSourceId('legacy-card')))?.network,
        'visa',
      );
    } finally {
      await Directory(directory.path).delete(recursive: true);
    }
  });
}
