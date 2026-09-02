import 'dart:io';

import 'package:butlerly/core/config/app_configuration.dart';
import 'package:butlerly/core/data/local_data_manager.dart';
import 'package:butlerly/core/database/initial_master_data.dart';
import 'package:butlerly/core/database/local_database.dart';
import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/core/logging/app_logger.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Real local application boundary used by V1 integration tests.
///
/// Each restart closes the SQLite connection, rebuilds the repositories and
/// service graph, then reloads the same database directory. This keeps tests
/// close to the production bootstrap while making persistence boundaries
/// explicit and isolated from a developer's application data.
final class V1IntegrationHarness {
  V1IntegrationHarness._(this.root);

  final Directory root;
  late LocalDatabase database;
  late FinanceServices finance;
  late LocalDataManager data;

  Directory get documents => Directory(path.join(root.path, 'documents'));
  Directory get evidence => Directory(path.join(root.path, 'evidence'));

  static Future<V1IntegrationHarness> create() async {
    sqfliteFfiInit();
    final root = await Directory.systemTemp.createTemp('butlerly-v1-e2e-');
    final harness = V1IntegrationHarness._(root);
    await harness._open();
    return harness;
  }

  Future<void> _open() async {
    await documents.create(recursive: true);
    await evidence.create(recursive: true);
    database = LocalDatabase(
      logger: AppLogger(),
      factory: databaseFactoryFfi,
      databaseDirectory: root.path,
    );
    await database.initialize();
    configureDependencies(
      configuration: const AppConfiguration(),
      database: database,
      logger: AppLogger(),
    );
    finance = services<FinanceServices>();
    data = LocalDataManager(
      database,
      documentsDirectory: documents,
      localEvidenceDirectory: evidence,
    );
    await finance.seedInitialMasterData(buildInitialMasterData());
  }

  Future<void> restart() async {
    await database.close();
    await services.reset();
    await _open();
  }

  Future<void> installBuiltInRules() async {
    final sources = <String, String>{};
    for (final asset in _analysisRuleAssets) {
      sources[asset] = await rootBundle.loadString(asset);
    }
    final catalog = await rootBundle.loadString(
      'assets/analysis_rules/catalog.yaml',
    );
    final result = await finance.installBuiltInRules!.call(
      sources,
      catalogSource: catalog,
    );
    if (result.diagnostics.isNotEmpty) {
      throw StateError('Bundled analysis rules failed to install.');
    }
  }

  Future<void> dispose() async {
    await database.close();
    await services.reset();
    if (await root.exists()) await root.delete(recursive: true);
  }
}

const _analysisRuleAssets = [
  'assets/analysis_rules/metrics/ANL-R001.yaml',
  'assets/analysis_rules/metrics/ANL-R002.yaml',
  'assets/analysis_rules/metrics/ANL-R003.yaml',
  'assets/analysis_rules/metrics/ANL-R004.yaml',
  'assets/analysis_rules/metrics/ANL-R010.yaml',
  'assets/analysis_rules/metrics/ANL-R016.yaml',
  'assets/analysis_rules/insights/ANL-R014.yaml',
  'assets/analysis_rules/insights/ANL-R020.yaml',
  'assets/analysis_rules/data_quality/ANL-R090.yaml',
  'assets/analysis_rules/data_quality/ANL-R091.yaml',
  'assets/analysis_rules/data_quality/ANL-R092.yaml',
];

Money money(String amount, String currency) =>
    Money(amount: DecimalValue.parse(amount), currency: CurrencyCode(currency));

PaymentSource paymentSource(String id, String name) => PaymentSource(
  id: PaymentSourceId(id),
  name: name,
  type: PaymentSourceType.card,
  lastFour: '1234',
  currency: 'USD',
);

CreateTransactionCommand manualCommand({
  required String id,
  required String description,
  required String date,
  String amount = '12.34',
  String provenanceId = 'manual-provenance',
  String? paymentSourceId,
}) => CreateTransactionCommand(
  id: id,
  provenanceId: provenanceId,
  timing: const UnknownTransactionTime(UnknownTransactionTimeReason.unknown),
  money: money(amount, 'USD'),
  direction: TransactionDirection.expense,
  transactionDate: date,
  description: description,
  rawCounterparty: description,
  paymentSourceId: paymentSourceId,
);

PaymentTransactionCommand importedCommand({
  required String id,
  required String description,
  required String date,
  String amount = '12.34',
}) => PaymentTransactionCommand(
  id: id,
  provenanceId: '$id-provenance',
  money: money(amount, 'USD'),
  direction: TransactionDirection.expense,
  transactionDate: date,
  originalRepresentation: '$date,$amount,USD,expense,$description',
  sourceId: 'fixture.csv',
  description: description,
  sourceType: TransactionSourceType.import,
  provenanceSourceType: ProvenanceSourceType.import,
);
