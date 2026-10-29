import 'dart:io';

import 'package:butlerly_database/butlerly_database.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as sqflite;

/// A real file-backed SQLite fixture shared by the #341 and #342 integration
/// tests. The fixture deliberately exposes repository reconstruction through
/// [reopen] so tests cannot accidentally pass with in-memory state.
final class PersistedFinancialFixture {
  PersistedFinancialFixture._({
    required this.root,
    required this.path,
    required this.schemaSql,
  });

  final Directory root;
  final String path;
  final String schemaSql;
  late ButlerlyDatabase database;

  SqliteTransactionRepository get transactions =>
      SqliteTransactionRepository(database);
  SqliteDuplicateCandidateGroupRepository get duplicateGroups =>
      SqliteDuplicateCandidateGroupRepository(database);
  SqliteReconciliationLinkRepository get reconciliationLinks =>
      SqliteReconciliationLinkRepository(database);
  SqliteReconciliationCandidateRepository get reconciliationCandidates =>
      SqliteReconciliationCandidateRepository(database);
  SqliteReconciliationWorkflowRepository get reconciliationWorkflow =>
      SqliteReconciliationWorkflowRepository(database);
  SqliteUserPreferenceRepository get preferences =>
      SqliteUserPreferenceRepository(database);
  SqliteCategoryRepository get categories => SqliteCategoryRepository(database);
  SqliteMerchantRepository get merchants => SqliteMerchantRepository(database);
  SqlitePaymentSourceRepository get paymentSources =>
      SqlitePaymentSourceRepository(database);
  SqliteAnalysisRuleResultRepository get analysisResults =>
      SqliteAnalysisRuleResultRepository(database);
  SqliteAnalysisFindingRepository get analysisFindings =>
      SqliteAnalysisFindingRepository(database);

  static Future<PersistedFinancialFixture> create({
    String timeZoneId = 'UTC',
    CurrencyCode? baseCurrency,
  }) async {
    final root = await Directory.systemTemp.createTemp(
      'butlerly-financial-fixture-',
    );
    final schemaSql = await File(
      '../butlerly_database/database/schema/v1.sql',
    ).readAsString();
    final fixture = PersistedFinancialFixture._(
      root: root,
      path: '${root.path}/butlerly.db',
      schemaSql: schemaSql,
    );
    await fixture._open();
    await fixture.preferences.save(
      UserPreference(
        locale: 'en',
        formattingLocale: 'en-US',
        baseCurrency: baseCurrency ?? CurrencyCode('USD'),
        timeZoneId: timeZoneId,
      ),
    );
    return fixture;
  }

  Future<void> _open() async {
    database = ButlerlyDatabase(
      factory: sqflite.databaseFactoryFfi,
      path: path,
      schemaSql: schemaSql,
    );
    await database.open();
  }

  Future<void> reopen() async {
    await database.close();
    await _open();
  }

  Future<void> saveCategory(Category category) => categories.save(category);

  Future<void> saveMerchant(Merchant merchant) => merchants.save(merchant);

  Future<void> savePaymentSource(PaymentSource source) =>
      paymentSources.save(source);

  Future<void> saveTransaction(Transaction transaction) =>
      transactions.save(transaction);

  Future<void> saveDuplicateGroup(DuplicateCandidateGroup group) =>
      duplicateGroups.save(group);

  Future<void> saveReconciliationCandidate(ReconciliationCandidate candidate) =>
      reconciliationCandidates.save(candidate);

  Future<void> saveReconciliationLink({
    required String id,
    required TransactionId receiptTransactionId,
    required TransactionId paymentTransactionId,
    DateTime? createdAt,
  }) async {
    final at = (createdAt ?? DateTime.utc(2026, 9, 1)).toUtc();
    final candidateId = '$id-candidate';
    await database.connection.insert('reconciliation_candidates', {
      'id': candidateId,
      'receipt_transaction_id': receiptTransactionId.value,
      'payment_transaction_id': paymentTransactionId.value,
      'score': 1.0,
      'reasons_json': '[]',
      'status': ReconciliationCandidateStatus.confirmed.name,
      'created_at': at.toIso8601String(),
      'updated_at': at.toIso8601String(),
    });
    await reconciliationLinks.save(
      ReconciliationLink(
        id: id,
        candidateId: candidateId,
        receiptTransactionId: receiptTransactionId,
        paymentTransactionId: paymentTransactionId,
        createdAt: at,
      ),
    );
  }

  Future<void> dispose() async {
    await database.close();
    if (await root.exists()) await root.delete(recursive: true);
  }
}
