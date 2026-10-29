import 'dart:async';

import 'package:butlerly_database/butlerly_database.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as sqflite;
import 'package:test/test.dart';

import 'support/persisted_financial_fixture.dart';

void main() {
  setUpAll(sqflite.sqfliteFfiInit);

  test(
    'serializes transaction mutation with analysis and preserves totals after restart',
    () async {
      final fixture = await PersistedFinancialFixture.create();
      addTearDown(fixture.dispose);
      final original = _transaction('concurrent-transaction', '25');
      await fixture.saveTransaction(original);

      final rules = _Rules();
      final gate = AnalysisConsistencyGate();
      final invalidation = InvalidateAnalysis(
        fixture.analysisFindings,
        results: fixture.analysisResults,
        rules: rules,
      );
      final blockingTransactions = _BlockingTransactions(fixture.transactions);
      final reviewingTransactions = DuplicateReviewingTransactionRepository(
        blockingTransactions,
        RefreshDuplicateGroupForTransaction(
          fixture.duplicateGroups,
          const _Clock(),
        ),
        invalidateAnalysis: invalidation,
        consistencyGate: gate,
      );
      final analysis = _analysis(blockingTransactions, fixture, rules, gate);
      final context = _success(
        await analysis.contextForDates(
          startDate: '2026-09-01',
          endDate: '2026-09-30',
        ),
      );

      final initialResults = _success(await analysis(context));
      expect(_metricValue(initialResults), '25');
      expect(_metricTransactionIds(initialResults), ['concurrent-transaction']);

      final updated = _transaction(
        'concurrent-transaction',
        '50',
        updatedAt: DateTime.utc(2026, 9, 2),
      );
      final mutation = reviewingTransactions.save(updated);
      await blockingTransactions.saveStarted.future;

      var analysisCompleted = false;
      final concurrentAnalysis = analysis(context).then((result) {
        analysisCompleted = true;
        return result;
      });
      await Future<void>.delayed(Duration.zero);
      expect(
        analysisCompleted,
        isFalse,
        reason: 'analysis must wait for the source mutation gate',
      );

      blockingTransactions.allowSave.complete();
      await mutation;
      final updatedResults = _success(await concurrentAnalysis);
      expect(_metricValue(updatedResults), '50');
      expect(_metricTransactionIds(updatedResults), ['concurrent-transaction']);

      await fixture.reopen();
      final restartedGate = AnalysisConsistencyGate();
      final restartedAnalysis = _analysis(
        fixture.transactions,
        fixture,
        rules,
        restartedGate,
      );
      final restartedContext = _success(
        await restartedAnalysis.contextForDates(
          startDate: '2026-09-01',
          endDate: '2026-09-30',
        ),
      );
      final restartedResults = _success(
        await restartedAnalysis(restartedContext),
      );
      expect(_metricValue(restartedResults), '50');
      expect(_metricTransactionIds(restartedResults), [
        'concurrent-transaction',
      ]);
    },
  );

  test(
    'serializes statement import with analysis and preserves totals after restart',
    () async {
      final fixture = await PersistedFinancialFixture.create();
      addTearDown(fixture.dispose);
      final now = DateTime.utc(2026, 9, 1);
      final evidence = SqliteEvidenceRepository(fixture.database);
      await evidence.save(
        EvidenceItem(
          id: EvidenceId('concurrent-statement-evidence'),
          type: EvidenceType.document,
          originalName: 'statement.pdf',
          mediaType: 'application/pdf',
          provenance: Provenance(
            id: ProvenanceId('concurrent-statement-provenance'),
            sourceType: ProvenanceSourceType.scan,
            capturedAt: now,
            originalRepresentation: 'statement.pdf',
          ),
          createdAt: now,
        ),
      );
      final statement = FinancialStatement(
        id: 'concurrent-statement',
        evidenceId: 'concurrent-statement-evidence',
        status: StatementStatus.ready,
        createdAt: now,
        updatedAt: now,
      );
      final row = StatementRow(
        id: 'concurrent-statement-row',
        statementId: statement.id,
        position: 0,
        originalText: 'Concurrent expense 25 USD',
        transactionDate: now,
        description: 'Concurrent expense',
        amount: '25',
        currency: 'USD',
        direction: TransactionDirection.expense.name,
        status: StatementRowStatus.pending,
        createdAt: now,
        updatedAt: now,
      );
      final statements = SqliteStatementRepository(fixture.database);
      await fixture.savePaymentSource(
        PaymentSource(
          id: PaymentSourceId('source'),
          name: 'Concurrent source',
          type: PaymentSourceType.account,
        ),
      );
      await fixture.saveMerchant(
        Merchant(
          id: MerchantId('concurrent expense'),
          name: 'Concurrent expense',
        ),
      );
      await statements.saveStatementWithRows(statement, [row]);
      final gate = AnalysisConsistencyGate();
      final rules = _Rules();
      final invalidation = InvalidateAnalysis(
        fixture.analysisFindings,
        results: fixture.analysisResults,
        rules: rules,
      );
      final blockingWorkflow = _BlockingStatementWorkflow(statements);
      final service = StatementServices(
        statements,
        fixture.transactions,
        blockingWorkflow,
        const _Clock(),
        duplicateGroups: fixture.duplicateGroups,
        duplicateChecker: DuplicateTransactionChecker(fixture.transactions),
        invalidateAnalysis: invalidation,
        consistencyGate: gate,
      );
      final analysis = _analysis(fixture.transactions, fixture, rules, gate);
      final context = _success(
        await analysis.contextForDates(
          startDate: '2026-09-01',
          endDate: '2026-09-30',
        ),
      );

      final import = service.importBatch(statement, [row], 'source');
      await blockingWorkflow.saveStarted.future;

      var analysisCompleted = false;
      final concurrentAnalysis = analysis(context).then((result) {
        analysisCompleted = true;
        return result;
      });
      await Future<void>.delayed(Duration.zero);
      expect(
        analysisCompleted,
        isFalse,
        reason: 'analysis must wait for the statement mutation gate',
      );

      blockingWorkflow.allowSave.complete();
      final imported = await import;
      expect(imported, isA<ApplicationSuccess<StatementImportSummary>>());
      final importedResults = _success(await concurrentAnalysis);
      expect(_metricValue(importedResults), '25');
      expect(_metricTransactionIds(importedResults), [
        'statement-concurrent-statement-concurrent-statement-row',
      ]);

      await fixture.reopen();
      final restartedRules = _Rules();
      final restartedGate = AnalysisConsistencyGate();
      final restartedAnalysis = _analysis(
        fixture.transactions,
        fixture,
        restartedRules,
        restartedGate,
      );
      final restartedContext = _success(
        await restartedAnalysis.contextForDates(
          startDate: '2026-09-01',
          endDate: '2026-09-30',
        ),
      );
      final restartedResults = _success(
        await restartedAnalysis(restartedContext),
      );
      expect(_metricValue(restartedResults), '25');
      expect(_metricTransactionIds(restartedResults), [
        'statement-concurrent-statement-concurrent-statement-row',
      ]);
    },
  );

  test(
    'serializes concurrent transaction mutations and preserves the latest total after restart',
    () async {
      final fixture = await PersistedFinancialFixture.create();
      addTearDown(fixture.dispose);
      final original = _transaction('concurrent-updates', '25');
      await fixture.saveTransaction(original);

      final rules = _Rules();
      final gate = AnalysisConsistencyGate();
      final invalidation = InvalidateAnalysis(
        fixture.analysisFindings,
        results: fixture.analysisResults,
        rules: rules,
        consistencyGate: gate,
      );
      final blockingTransactions = _BlockingTransactions(fixture.transactions);
      final reviewingTransactions = DuplicateReviewingTransactionRepository(
        blockingTransactions,
        RefreshDuplicateGroupForTransaction(
          fixture.duplicateGroups,
          const _Clock(),
        ),
        invalidateAnalysis: invalidation,
        consistencyGate: gate,
      );
      final update = UpdateTransaction(
        reviewingTransactions,
        const _Clock(),
        preferences: fixture.preferences,
        consistencyGate: gate,
      );
      final firstUpdate = update(
        UpdateTransactionCommand(
          id: original.id.value,
          timing: original.timing,
          money: Money(
            amount: DecimalValue.parse('50'),
            currency: CurrencyCode('USD'),
          ),
          direction: original.direction,
        ),
      );
      await blockingTransactions.saveStarted.future;

      var secondCompleted = false;
      final secondUpdate =
          update(
            UpdateTransactionCommand(
              id: original.id.value,
              timing: original.timing,
              money: Money(
                amount: DecimalValue.parse('75'),
                currency: CurrencyCode('USD'),
              ),
              direction: original.direction,
            ),
          ).then((result) {
            secondCompleted = true;
            return result;
          });
      await Future<void>.delayed(Duration.zero);
      expect(
        secondCompleted,
        isFalse,
        reason: 'the second mutation must wait for the first read/write cycle',
      );

      blockingTransactions.allowSave.complete();
      expect(await firstUpdate, isA<ApplicationSuccess<TransactionDto>>());
      expect(await secondUpdate, isA<ApplicationSuccess<TransactionDto>>());

      final analysis = _analysis(blockingTransactions, fixture, rules, gate);
      final context = _success(
        await analysis.contextForDates(
          startDate: '2026-09-01',
          endDate: '2026-09-30',
        ),
      );
      final results = _success(await analysis(context));
      expect(_metricValue(results), '75');
      expect(_metricTransactionIds(results), ['concurrent-updates']);

      await fixture.reopen();
      final restartedAnalysis = _analysis(
        fixture.transactions,
        fixture,
        _Rules(),
        AnalysisConsistencyGate(),
      );
      final restartedContext = _success(
        await restartedAnalysis.contextForDates(
          startDate: '2026-09-01',
          endDate: '2026-09-30',
        ),
      );
      final restartedResults = _success(
        await restartedAnalysis(restartedContext),
      );
      expect(_metricValue(restartedResults), '75');
      expect(_metricTransactionIds(restartedResults), ['concurrent-updates']);
    },
  );

  test(
    'invalidates persisted analysis when a legacy category hierarchy changes',
    () async {
      final fixture = await PersistedFinancialFixture.create();
      addTearDown(fixture.dispose);
      await fixture.saveCategory(
        Category(
          id: CategoryId('old-root'),
          name: 'Old root',
          origin: CategoryOrigin.user,
        ),
      );
      await fixture.saveCategory(
        Category(
          id: CategoryId('new-root'),
          name: 'New root',
          origin: CategoryOrigin.user,
        ),
      );
      await fixture.saveCategory(
        Category(
          id: CategoryId('legacy-leaf'),
          name: 'Legacy leaf',
          origin: CategoryOrigin.user,
        ),
      );
      await fixture.saveTransaction(_categorizedTransaction());

      final rules = _Rules(grouping: RuleGrouping.subcategory);
      final gate = AnalysisConsistencyGate();
      final invalidation = InvalidateAnalysis(
        fixture.analysisFindings,
        results: fixture.analysisResults,
        rules: rules,
      );
      final analysis = _analysis(
        fixture.transactions,
        fixture,
        rules,
        gate,
        categories: fixture.categories,
      );
      final context = _success(
        await analysis.contextForDates(
          startDate: '2026-09-01',
          endDate: '2026-09-30',
        ),
      );
      final initial = _success(await analysis(context));
      expect(initial.single.metric?.dimension, 'no_subcategory:value');
      expect(_metricValue(initial), '25');

      final saveCategory = SaveCategory(
        fixture.categories,
        invalidateAnalysis: invalidation,
        consistencyGate: gate,
      );
      final moved = await saveCategory(
        Category(
          id: CategoryId('legacy-leaf'),
          name: 'Legacy leaf',
          parentId: CategoryId('new-root'),
          origin: CategoryOrigin.user,
        ),
      );
      expect(moved, isA<ApplicationSuccess<Category>>());

      final afterMutation = _success(await analysis(context));
      expect(afterMutation.single.metric?.dimension, 'legacy-leaf:value');
      expect(_metricValue(afterMutation), '25');

      await fixture.reopen();
      final restartedRules = _Rules(grouping: RuleGrouping.subcategory);
      final restartedAnalysis = _analysis(
        fixture.transactions,
        fixture,
        restartedRules,
        AnalysisConsistencyGate(),
        categories: fixture.categories,
      );
      final restartedContext = _success(
        await restartedAnalysis.contextForDates(
          startDate: '2026-09-01',
          endDate: '2026-09-30',
        ),
      );
      final restarted = _success(await restartedAnalysis(restartedContext));
      expect(restarted.single.metric?.dimension, 'legacy-leaf:value');
      expect(_metricValue(restarted), '25');
    },
  );

  test(
    'serializes normalization with analysis and preserves totals after restart',
    () async {
      final fixture = await PersistedFinancialFixture.create();
      addTearDown(fixture.dispose);
      final original = _transaction('concurrent-normalization', '25');
      await fixture.saveTransaction(original);

      final rules = _Rules();
      final gate = AnalysisConsistencyGate();
      final invalidation = InvalidateAnalysis(
        fixture.analysisFindings,
        results: fixture.analysisResults,
        rules: rules,
        consistencyGate: gate,
      );
      final blockingTransactions = _BlockingTransactions(fixture.transactions);
      final reviewingTransactions = DuplicateReviewingTransactionRepository(
        blockingTransactions,
        RefreshDuplicateGroupForTransaction(
          fixture.duplicateGroups,
          const _Clock(),
        ),
        invalidateAnalysis: invalidation,
        consistencyGate: gate,
      );
      final analysis = _analysis(reviewingTransactions, fixture, rules, gate);
      final context = _success(
        await analysis.contextForDates(
          startDate: '2026-09-01',
          endDate: '2026-09-30',
        ),
      );
      expect(_metricValue(_success(await analysis(context))), '25');

      final evaluation = EvaluateTransactionNormalization(
        reviewingTransactions,
        fixture.preferences,
        null,
        const _Clock(),
        consistencyGate: gate,
      ).call(original.id);
      await blockingTransactions.saveStarted.future;

      var analysisCompleted = false;
      final concurrentAnalysis = analysis(context).then((result) {
        analysisCompleted = true;
        return result;
      });
      await Future<void>.delayed(Duration.zero);
      expect(analysisCompleted, isFalse);

      blockingTransactions.allowSave.complete();
      expect(await evaluation, isA<ApplicationSuccess<TransactionDto>>());
      expect(_metricValue(_success(await concurrentAnalysis)), '25');

      await fixture.reopen();
      final restartedAnalysis = _analysis(
        fixture.transactions,
        fixture,
        _Rules(),
        AnalysisConsistencyGate(),
      );
      final restartedContext = _success(
        await restartedAnalysis.contextForDates(
          startDate: '2026-09-01',
          endDate: '2026-09-30',
        ),
      );
      expect(
        _metricValue(_success(await restartedAnalysis(restartedContext))),
        '25',
      );
    },
  );

  test('the consistency gate permits nested persistence operations', () async {
    final gate = AnalysisConsistencyGate();
    final result = await gate.runExclusive(
      () => gate.runExclusive(() async => 'nested-complete'),
    );
    expect(result, 'nested-complete');
  });
}

CalculateAnalysisOverview _analysis(
  TransactionRepository transactions,
  PersistedFinancialFixture fixture,
  AnalysisRuleRepository rules,
  AnalysisConsistencyGate gate, {
  CategoryRepository? categories,
}) => CalculateAnalysisOverview(
  rules,
  AnalysisDatasetBuilder(
    transactions,
    fixture.preferences,
    null,
    categories: categories,
  ),
  const AnalysisRuleEngine(),
  findings: fixture.analysisFindings,
  results: fixture.analysisResults,
  consistencyGate: gate,
);

String _metricValue(List<RuleExecutionResult> results) =>
    results.single.metric!.value.toString();

List<String> _metricTransactionIds(List<RuleExecutionResult> results) => results
    .single
    .metric!
    .evidence
    .map((value) => value.transactionId.value)
    .toList(growable: false);

T _success<T>(ApplicationResult<T> result) {
  expect(result, isA<ApplicationSuccess<T>>());
  return (result as ApplicationSuccess<T>).value;
}

Transaction _transaction(
  String id,
  String amount, {
  DateTime? updatedAt,
  String? categoryId,
}) {
  final at = DateTime.utc(2026, 9, 1);
  return Transaction(
    id: TransactionId(id),
    timing: const UnknownTransactionTime(UnknownTransactionTimeReason.unknown),
    money: Money(
      amount: DecimalValue.parse(amount),
      currency: CurrencyCode('USD'),
    ),
    direction: TransactionDirection.expense,
    sourceType: TransactionSourceType.manual,
    transactionDate: '2026-09-01',
    categoryId: categoryId == null ? null : CategoryId(categoryId),
    provenance: [
      Provenance(
        id: ProvenanceId('$id-provenance'),
        sourceType: ProvenanceSourceType.userEntry,
        capturedAt: at,
      ),
    ],
    createdAt: at,
    updatedAt: updatedAt ?? at,
  );
}

Transaction _categorizedTransaction() => _transaction(
  'legacy-category-transaction',
  '25',
  categoryId: 'legacy-leaf',
);

final class _BlockingTransactions implements TransactionRepository {
  _BlockingTransactions(this.delegate);

  final TransactionRepository delegate;
  final saveStarted = Completer<void>();
  final allowSave = Completer<void>();

  @override
  Future<void> save(Transaction value) async {
    if (!saveStarted.isCompleted) {
      saveStarted.complete();
      await allowSave.future;
    }
    await delegate.save(value);
  }

  @override
  Future<Transaction?> findById(TransactionId id) => delegate.findById(id);

  @override
  Future<List<Transaction>> listAll() => delegate.listAll();

  @override
  Future<List<Transaction>> query(TransactionRepositoryQuery query) =>
      delegate.query(query);

  @override
  Future<void> removePermanently(TransactionId id) =>
      delegate.removePermanently(id);
}

final class _BlockingStatementWorkflow implements StatementWorkflowRepository {
  _BlockingStatementWorkflow(this.delegate);

  final StatementWorkflowRepository delegate;
  final saveStarted = Completer<void>();
  final allowSave = Completer<void>();

  @override
  Future<void> saveRowTransactions(List<StatementRowTransaction> values) async {
    if (!saveStarted.isCompleted) {
      saveStarted.complete();
      await allowSave.future;
    }
    await delegate.saveRowTransactions(values);
  }

  @override
  Future<void> saveRowTransaction(StatementRow row, Transaction transaction) =>
      delegate.saveRowTransaction(row, transaction);

  @override
  Future<void> linkRow(StatementRow row) => delegate.linkRow(row);
}

final class _Clock implements ApplicationClock {
  const _Clock();

  @override
  DateTime now() => DateTime.utc(2026, 9, 1);
}

final class _Rules implements AnalysisRuleRepository {
  _Rules({this.grouping = RuleGrouping.none});

  final RuleGrouping grouping;

  @override
  Future<List<AnalysisRuleDefinition>> listActive() async => [_rule(grouping)];

  @override
  Future<List<AnalysisRuleDefinition>> listDefinitions() async => [
    _rule(grouping),
  ];

  @override
  Future<AnalysisRuleActivation?> existingActivation(RuleIdentity id) async =>
      null;

  @override
  Future<void> activate(
    RuleIdentity id,
    RuleVersion version,
    bool enabled,
    DateTime at,
  ) async {}

  @override
  Future<void> install(
    AnalysisRuleDefinition definition, {
    required String sourceType,
    required String canonicalDefinition,
  }) async {}
}

AnalysisRuleDefinition _rule([RuleGrouping grouping = RuleGrouping.none]) =>
    AnalysisRuleDefinition(
      identity: RuleIdentity('ANL-R001'),
      version: RuleVersion('1.0.0'),
      schemaVersion: '1.0.0',
      type: AnalysisRuleType.metric,
      nameKey: 'expense',
      descriptionKey: 'expense',
      enabled: true,
      status: AnalysisRuleStatus.active,
      period: 'selected_period',
      measure: const RuleMeasure(operation: RuleOperation.sum, field: 'amount'),
      grouping: grouping,
      baseline: RuleBaseline.none,
      condition: RuleCondition(operator: 'none'),
      severity: RuleSeverity.info,
      surface: AnalysisSurface.overview,
      definitionHash: RuleDefinitionHash('e' * 64),
      role: 'expenseTotal',
      resultPersistence: ResultPersistencePolicy.materialized,
    );
