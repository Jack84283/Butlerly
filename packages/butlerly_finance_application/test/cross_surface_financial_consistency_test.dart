import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as sqflite;
import 'package:test/test.dart';

import 'support/persisted_financial_fixture.dart';

void main() {
  setUpAll(sqflite.sqfliteFfiInit);

  test(
    'one persisted fixture stays consistent across surfaces, mutations, and restart',
    () async {
      final fixture = await PersistedFinancialFixture.create(
        timeZoneId: 'America/Los_Angeles',
      );
      addTearDown(fixture.dispose);
      await _seedFixture(fixture);
      final rules = _Rules(_rules());
      final invalidateAnalysis = InvalidateAnalysis(
        fixture.analysisFindings,
        results: fixture.analysisResults,
        rules: rules,
      );
      final reviewingTransactions = DuplicateReviewingTransactionRepository(
        fixture.transactions,
        RefreshDuplicateGroupForTransaction(
          fixture.duplicateGroups,
          const _Clock(),
        ),
        invalidateAnalysis: invalidateAnalysis,
      );
      final analysis = _analysis(fixture, rules);
      final context = _success(
        await analysis.contextForDates(
          startDate: '2026-09-01',
          endDate: '2026-09-30',
        ),
      );

      final initial = _success(await analysis(context));
      final initialOverview = AnalysisOverview.fromResults(initial);
      _expectOverview(
        initialOverview,
        expense: '59.25',
        income: '100',
        net: '40.75',
        count: '7',
        expenseIds: [
          'archived-groceries',
          'foreign-travel',
          'groceries',
          'groceries-ordinary',
          'occurrence-only',
          'payment',
        ],
        categoryTotals: {
          'category.food:value': '23.75',
          'category.travel:value': '35.50',
        },
        subcategoryTotals: {
          'subcategory.groceries:value': '23.75',
          'subcategory.travel:value': '35.50',
        },
        merchantTotals: {
          'merchant.grocery:value': '23.75',
          'merchant.travel:value': '35.50',
        },
      );

      final insights = _success(
        await CalculateInsights(analysis).call(context, forceRefresh: false),
      );
      expect(insights.summary.expenseSpending, DecimalValue.parse('59.25'));
      expect(insights.summary.income, DecimalValue.parse('100'));
      expect(insights.summary.netCashFlow, DecimalValue.parse('40.75'));

      final report = _success(
        await CalculatePeriodicFinancialReport(
          analysis,
          DetectRecurringPatterns(
            fixture.transactions,
            preferences: fixture.preferences,
            links: fixture.reconciliationLinks,
            candidates: fixture.reconciliationCandidates,
            duplicateGroups: fixture.duplicateGroups,
          ),
        ).call(context),
      );
      expect(report.overview.spending?.value, DecimalValue.parse('59.25'));
      expect(report.overview.income?.value, DecimalValue.parse('100'));
      expect(report.overview.net?.value, DecimalValue.parse('40.75'));

      final calendar = _success(
        await CalculateAnalysisCalendar(
          _dataset(fixture),
          rules,
          const AnalysisRuleEngine(),
        ).call(
          year: 2026,
          month: 9,
          datasetMode: DatasetMode.allEligible,
          currencyBasis: CurrencyBasis.baseCurrency,
          baseCurrency: CurrencyCode('USD'),
        ),
      );
      expect(
        calendar.days
            .firstWhere((day) => day.financialDate == '2026-09-04')
            .expenseTotal
            ?.amount,
        DecimalValue.parse('30'),
      );
      expect(
        calendar.days
            .firstWhere((day) => day.financialDate == '2026-09-04')
            .evidence
            .map((value) => value.transactionId.value)
            .toSet(),
        {'payment'},
      );

      final drillThrough = _success(
        await QueryTransactionsForFinancialDate(
          fixture.transactions,
          preferences: fixture.preferences,
          links: fixture.reconciliationLinks,
          candidates: fixture.reconciliationCandidates,
          duplicateGroups: fixture.duplicateGroups,
        )('2026-09-04'),
      );
      expect(drillThrough.map((value) => value.id), ['payment']);

      final home = _success(
        await GetHomeOverview(
          resolveHomePeriod: ResolveHomePeriod(fixture.preferences),
          calculateAnalysis: analysis,
          calculateInsights: CalculateInsights(analysis),
          listTransactions: ListTransactions(
            fixture.transactions,
            preferences: fixture.preferences,
          ),
          listReviewItems: ListReviewItems(fixture.transactions),
          listDuplicateCandidateGroups: ListDuplicateCandidateGroups(
            fixture.duplicateGroups,
            transactions: ListTransactions(
              fixture.transactions,
              preferences: fixture.preferences,
            ),
          ),
          canonicalTransactionIds: () async => selectCanonicalTransactions(
            source: await fixture.transactions.listAll(),
            links: await fixture.reconciliationLinks.listAll(),
            reconciliationCandidates: await fixture.reconciliationCandidates
                .listAll(),
            duplicateGroups: await fixture.duplicateGroups.list(),
          ).transactions.map((value) => value.id.value).toSet(),
        ).call(instant: DateTime.utc(2026, 9, 30, 12)),
      );
      expect(home.analysis?.spending?.value, DecimalValue.parse('59.25'));
      expect(home.analysis?.income?.value, DecimalValue.parse('100'));
      expect(home.analysis?.net?.value, DecimalValue.parse('40.75'));

      final relinkCandidate = ReconciliationCandidate(
        id: 'relink-candidate',
        receiptTransactionId: TransactionId('out-of-period-receipt'),
        paymentTransactionId: TransactionId('groceries-ordinary'),
        score: .95,
        reasons: const ['exact match'],
        status: ReconciliationCandidateStatus.confirmed,
      );
      await fixture.saveReconciliationCandidate(relinkCandidate);
      final relink =
          await SaveReconciliationLink(
            fixture.reconciliationLinks,
            candidates: fixture.reconciliationCandidates,
            invalidateAnalysis: invalidateAnalysis,
          )(
            ReconciliationLink(
              id: 'relink',
              candidateId: relinkCandidate.id,
              receiptTransactionId: relinkCandidate.receiptTransactionId,
              paymentTransactionId: relinkCandidate.paymentTransactionId,
              createdAt: DateTime.utc(2026, 9, 19),
            ),
          );
      expect(relink, isA<ApplicationSuccess<void>>());
      expect(
        await fixture.database.connection.query(
          'analysis_rule_results',
          where: 'freshness = ?',
          whereArgs: [AnalysisResultFreshness.stale.name],
        ),
        isNotEmpty,
      );
      _expectOverview(
        AnalysisOverview.fromResults(_success(await analysis(context))),
        expense: '59.25',
        income: '100',
        net: '40.75',
        count: '7',
        expenseIds: [
          'archived-groceries',
          'foreign-travel',
          'groceries',
          'groceries-ordinary',
          'occurrence-only',
          'payment',
        ],
        categoryTotals: {
          'category.food:value': '23.75',
          'category.travel:value': '35.50',
        },
        subcategoryTotals: {
          'subcategory.groceries:value': '23.75',
          'subcategory.travel:value': '35.50',
        },
        merchantTotals: {
          'merchant.grocery:value': '23.75',
          'merchant.travel:value': '35.50',
        },
      );

      final consolidated = (await fixture.duplicateGroups.list()).single;
      final duplicateResolution = await ResolveDuplicateCandidateGroup(
        fixture.duplicateGroups,
        const _Clock(),
        invalidateAnalysis: invalidateAnalysis,
      )(consolidated.id, DuplicateCandidateGroupStatus.keepBoth);
      expect(duplicateResolution, isA<ApplicationSuccess<void>>());
      final afterKeepBoth = AnalysisOverview.fromResults(
        _success(await analysis(context)),
      );
      _expectOverview(
        afterKeepBoth,
        expense: '69.25',
        income: '100',
        net: '30.75',
        count: '8',
        expenseIds: [
          'archived-groceries',
          'duplicate-groceries',
          'foreign-travel',
          'groceries',
          'groceries-ordinary',
          'occurrence-only',
          'payment',
        ],
        categoryTotals: {
          'category.food:value': '33.75',
          'category.travel:value': '35.50',
        },
        subcategoryTotals: {
          'subcategory.groceries:value': '33.75',
          'subcategory.travel:value': '35.50',
        },
        merchantTotals: {
          'merchant.grocery:value': '33.75',
          'merchant.travel:value': '35.50',
        },
      );

      final changed = _transaction(
        id: 'groceries-ordinary',
        amount: '9.75',
        date: '2026-09-02',
        categoryId: 'category.food',
        subcategoryId: 'subcategory.groceries',
        merchantId: 'merchant.grocery',
        paymentSourceId: 'payment-source',
      );
      await reviewingTransactions.save(changed);
      final afterMutation = AnalysisOverview.fromResults(
        _success(await analysis(context)),
      );
      expect(afterMutation.spending?.value, DecimalValue.parse('71.25'));
      expect(
        afterMutation.categories
            .singleWhere((value) => value.dimension == 'category.food:value')
            .value,
        DecimalValue.parse('35.75'),
      );
      expect(
        afterMutation.spending!.evidence.map(
          (value) => value.transactionId.value,
        ),
        contains('groceries-ordinary'),
      );

      await fixture.reopen();
      final rebuiltAnalysis = _analysis(fixture, rules);
      final rebuilt = AnalysisOverview.fromResults(
        _success(await rebuiltAnalysis(context)),
      );
      expect(rebuilt.spending?.value, DecimalValue.parse('71.25'));
      expect(rebuilt.income?.value, DecimalValue.parse('100'));
      expect(rebuilt.net?.value, DecimalValue.parse('28.75'));
      expect(
        rebuilt.spending!.evidence.map((value) => value.transactionId.value),
        containsAll(['duplicate-groceries', 'groceries-ordinary']),
      );

      final missingFxContext = _success(
        await rebuiltAnalysis.contextForDates(
          startDate: '2026-10-01',
          endDate: '2026-10-31',
        ),
      );
      final missingFx = AnalysisOverview.fromResults(
        _success(await rebuiltAnalysis(missingFxContext)),
      );
      expect(
        missingFx.spending?.availability,
        AnalysisDataAvailability.insufficient,
      );
      expect(
        CalculateInsights(rebuiltAnalysis)
            .fromResults(
              missingFxContext,
              _success(await rebuiltAnalysis(missingFxContext)),
            )
            .summary
            .expenseSpending,
        isNull,
      );

      final emptyContext = _success(
        await rebuiltAnalysis.contextForDates(
          startDate: '2026-11-01',
          endDate: '2026-11-30',
        ),
      );
      final empty = AnalysisOverview.fromResults(
        _success(await rebuiltAnalysis(emptyContext)),
      );
      expect(empty.spending?.availability, AnalysisDataAvailability.empty);
      expect(empty.spending?.value, DecimalValue.parse('0'));

      final preference = (await fixture.preferences.load())!;
      final restartedInvalidateAnalysis = InvalidateAnalysis(
        fixture.analysisFindings,
        results: fixture.analysisResults,
        rules: rules,
      );
      final preferenceSave =
          await SaveUserPreference(
            fixture.preferences,
            invalidateAnalysis: restartedInvalidateAnalysis,
          )(
            UserPreference(
              locale: preference.locale,
              formattingLocale: preference.formattingLocale,
              regionCode: preference.regionCode,
              baseCurrency: CurrencyCode('EUR'),
              timeZoneId: preference.timeZoneId,
              externalAiEnabled: preference.externalAiEnabled,
              transactionSaveSoundEnabled:
                  preference.transactionSaveSoundEnabled,
              firstUseCompleted: preference.firstUseCompleted,
              appearance: preference.appearance,
              colorTheme: preference.colorTheme,
              displayName: preference.displayName,
            ),
          );
      if (preferenceSave case ApplicationFailure<UserPreference>(
        :final failure,
      )) {
        fail('${failure.code}: ${failure.detail}');
      }
      expect(preferenceSave, isA<ApplicationSuccess<UserPreference>>());
      expect(
        await fixture.database.connection.query(
          'analysis_rule_results',
          where: 'freshness = ?',
          whereArgs: [AnalysisResultFreshness.stale.name],
        ),
        isNotEmpty,
      );

      final rejectedCandidate = ReconciliationCandidate(
        id: 'rejected-after-restart',
        receiptTransactionId: TransactionId('receipt'),
        paymentTransactionId: TransactionId('groceries-ordinary'),
        score: .80,
        reasons: const ['near match'],
      );
      await fixture.saveReconciliationCandidate(rejectedCandidate);
      final rejection = await RejectReconciliation(
        fixture.reconciliationWorkflow,
        transactions: fixture.transactions,
        invalidateAnalysis: restartedInvalidateAnalysis,
      ).call(rejectedCandidate);
      expect(rejection, isA<ApplicationSuccess<void>>());
      expect(
        await fixture.database.connection.query(
          'analysis_rule_results',
          where: 'freshness = ?',
          whereArgs: [AnalysisResultFreshness.stale.name],
        ),
        isNotEmpty,
      );
    },
  );
}

AnalysisDatasetBuilder _dataset(PersistedFinancialFixture fixture) =>
    AnalysisDatasetBuilder(
      fixture.transactions,
      fixture.preferences,
      fixture.reconciliationLinks,
      candidates: fixture.reconciliationCandidates,
      duplicateGroups: fixture.duplicateGroups,
      categories: fixture.categories,
    );

CalculateAnalysisOverview _analysis(
  PersistedFinancialFixture fixture,
  AnalysisRuleRepository rules,
) => CalculateAnalysisOverview(
  rules,
  _dataset(fixture),
  const AnalysisRuleEngine(),
  findings: fixture.analysisFindings,
  results: fixture.analysisResults,
);

T _success<T>(ApplicationResult<T> result) {
  expect(result, isA<ApplicationSuccess<T>>());
  return (result as ApplicationSuccess<T>).value;
}

void _expectOverview(
  AnalysisOverview overview, {
  required String expense,
  required String income,
  required String net,
  required String count,
  required List<String> expenseIds,
  required Map<String, String> categoryTotals,
  required Map<String, String> subcategoryTotals,
  required Map<String, String> merchantTotals,
}) {
  expect(overview.spending?.value, DecimalValue.parse(expense));
  expect(overview.income?.value, DecimalValue.parse(income));
  expect(overview.net?.value, DecimalValue.parse(net));
  expect(overview.transactionCount?.value, DecimalValue.parse(count));
  expect(
    overview.spending!.evidence.map((value) => value.transactionId.value),
    expenseIds,
  );
  expect(_metricTotals(overview.categories), _parseTotals(categoryTotals));
  expect(
    _metricTotals(overview.subcategories),
    _parseTotals(subcategoryTotals),
  );
  expect(_metricTotals(overview.merchants), _parseTotals(merchantTotals));
}

Map<String, DecimalValue> _metricTotals(List<AnalysisMetric> metrics) => {
  for (final metric in metrics) metric.dimension!: metric.value,
};

Map<String, DecimalValue> _parseTotals(Map<String, String> values) => {
  for (final entry in values.entries)
    entry.key: DecimalValue.parse(entry.value),
};

List<AnalysisRuleDefinition> _rules() => [
  _rule(
    'ANL-R001',
    AnalysisSemanticRole.expenseTotal,
    AnalysisSurface.overview,
    RuleGrouping.none,
    filters: const ['expense'],
  ),
  _rule(
    'ANL-R002',
    AnalysisSemanticRole.incomeTotal,
    AnalysisSurface.overview,
    RuleGrouping.none,
    filters: const ['income'],
  ),
  _rule(
    'ANL-R003',
    AnalysisSemanticRole.netCashFlow,
    AnalysisSurface.overview,
    RuleGrouping.none,
    operation: RuleOperation.difference,
    dependencies: const ['ANL-R001', 'ANL-R002'],
  ),
  _rule(
    'ANL-R004',
    AnalysisSemanticRole.eligibleTransactionCount,
    AnalysisSurface.overview,
    RuleGrouping.none,
    operation: RuleOperation.count,
  ),
  _rule(
    'ANL-R005',
    null,
    AnalysisSurface.spending,
    RuleGrouping.category,
    filters: const ['expense'],
  ),
  _rule(
    'ANL-R006',
    null,
    AnalysisSurface.spending,
    RuleGrouping.subcategory,
    filters: const ['expense'],
  ),
  _rule(
    'ANL-R007',
    null,
    AnalysisSurface.spending,
    RuleGrouping.merchant,
    filters: const ['expense'],
  ),
  _rule(
    'ANL-R008',
    AnalysisSemanticRole.expenseTotal,
    AnalysisSurface.calendar,
    RuleGrouping.day,
    filters: const ['expense'],
  ),
  _rule(
    'ANL-R009',
    AnalysisSemanticRole.incomeTotal,
    AnalysisSurface.calendar,
    RuleGrouping.day,
    filters: const ['income'],
  ),
  _rule(
    'ANL-R010',
    AnalysisSemanticRole.eligibleTransactionCount,
    AnalysisSurface.calendar,
    RuleGrouping.day,
    operation: RuleOperation.count,
  ),
];

AnalysisRuleDefinition _rule(
  String id,
  String? role,
  AnalysisSurface surface,
  RuleGrouping grouping, {
  RuleOperation operation = RuleOperation.sum,
  List<String> filters = const [],
  List<String> dependencies = const [],
}) => AnalysisRuleDefinition(
  identity: RuleIdentity(id),
  version: RuleVersion('1.0.0'),
  schemaVersion: '1.0.0',
  type: AnalysisRuleType.metric,
  nameKey: id,
  descriptionKey: id,
  enabled: true,
  status: AnalysisRuleStatus.active,
  period: 'selected_period',
  measure: RuleMeasure(
    operation: operation,
    field: operation == RuleOperation.count ? 'transaction' : 'amount',
    currencyBasis: CurrencyBasis.baseCurrency,
    key: surface == AnalysisSurface.calendar
        ? switch (role) {
            AnalysisSemanticRole.expenseTotal =>
              AnalysisSemanticRole.expenseTotal,
            AnalysisSemanticRole.incomeTotal =>
              AnalysisSemanticRole.incomeTotal,
            _ => 'transactionCount',
          }
        : 'value',
  ),
  grouping: grouping,
  baseline: RuleBaseline.none,
  condition: const RuleCondition(operator: 'none'),
  severity: RuleSeverity.info,
  surface: surface,
  role: role,
  dependencies: [
    for (final dependency in dependencies)
      RuleDependency(ruleId: RuleIdentity(dependency)),
  ],
  resultPersistence: ResultPersistencePolicy.materialized,
  definitionHash: RuleDefinitionHash('a' * 64),
  filters: [
    if (filters.isNotEmpty)
      AnalysisFilter(kind: AnalysisFilterKind.direction, values: filters),
  ],
);

Future<void> _seedFixture(PersistedFinancialFixture fixture) async {
  await fixture.saveCategory(
    Category(
      id: CategoryId('category.food'),
      name: 'Food',
      origin: CategoryOrigin.user,
    ),
  );
  await fixture.saveCategory(
    Category(
      id: CategoryId('subcategory.groceries'),
      name: 'Groceries',
      origin: CategoryOrigin.user,
      parentId: CategoryId('category.food'),
    ),
  );
  await fixture.saveCategory(
    Category(
      id: CategoryId('category.travel'),
      name: 'Travel',
      origin: CategoryOrigin.user,
    ),
  );
  await fixture.saveCategory(
    Category(
      id: CategoryId('subcategory.travel'),
      name: 'Transport',
      origin: CategoryOrigin.user,
      parentId: CategoryId('category.travel'),
    ),
  );
  await fixture.saveMerchant(
    Merchant(id: MerchantId('merchant.grocery'), name: 'Grocery'),
  );
  await fixture.saveMerchant(
    Merchant(id: MerchantId('merchant.travel'), name: 'Travel'),
  );
  await fixture.savePaymentSource(
    PaymentSource(
      id: PaymentSourceId('payment-source'),
      name: 'Checking',
      type: PaymentSourceType.account,
    ),
  );
  for (final transaction in [
    _transaction(
      id: 'groceries',
      amount: '10',
      date: '2026-09-01',
      categoryId: 'category.food',
      subcategoryId: 'subcategory.groceries',
      merchantId: 'merchant.grocery',
      paymentSourceId: 'payment-source',
    ),
    _transaction(
      id: 'duplicate-groceries',
      amount: '10',
      date: '2026-09-01',
      categoryId: 'category.food',
      subcategoryId: 'subcategory.groceries',
      merchantId: 'merchant.grocery',
      paymentSourceId: 'payment-source',
    ),
    _transaction(
      id: 'groceries-ordinary',
      amount: '7.75',
      date: '2026-09-02',
      categoryId: 'category.food',
      subcategoryId: 'subcategory.groceries',
      merchantId: 'merchant.grocery',
      paymentSourceId: 'payment-source',
    ),
    _transaction(
      id: 'archived-groceries',
      amount: '4',
      date: '2026-09-03',
      categoryId: 'category.food',
      subcategoryId: 'subcategory.groceries',
      merchantId: 'merchant.grocery',
      paymentSourceId: 'payment-source',
      status: TransactionStatus.archived,
    ),
    _transaction(
      id: 'receipt',
      amount: '30',
      date: '2026-09-04',
      categoryId: 'category.travel',
      subcategoryId: 'subcategory.travel',
      merchantId: 'merchant.travel',
      sourceType: TransactionSourceType.evidenceCapture,
    ),
    _transaction(
      id: 'payment',
      amount: '30',
      date: '2026-09-04',
      categoryId: 'category.travel',
      subcategoryId: 'subcategory.travel',
      merchantId: 'merchant.travel',
      paymentSourceId: 'payment-source',
      sourceType: TransactionSourceType.import,
    ),
    _transaction(
      id: 'foreign-travel',
      amount: '5',
      currency: 'EUR',
      date: '2026-09-05',
      normalizedAmount: '5.50',
      categoryId: 'category.travel',
      subcategoryId: 'subcategory.travel',
      merchantId: 'merchant.travel',
      paymentSourceId: 'payment-source',
    ),
    _transaction(
      id: 'occurrence-only',
      amount: '2',
      date: null,
      occurredAt: DateTime.utc(2026, 9, 6, 12),
      categoryId: 'category.food',
      subcategoryId: 'subcategory.groceries',
      merchantId: 'merchant.grocery',
      paymentSourceId: 'payment-source',
    ),
    _transaction(
      id: 'salary',
      amount: '100',
      date: '2026-09-15',
      direction: TransactionDirection.income,
      paymentSourceId: 'payment-source',
    ),
    _transaction(
      id: 'missing-fx',
      amount: '8',
      currency: 'EUR',
      date: '2026-10-02',
      categoryId: 'category.travel',
      subcategoryId: 'subcategory.travel',
      merchantId: 'merchant.travel',
      paymentSourceId: 'payment-source',
    ),
    _transaction(
      id: 'out-of-period-receipt',
      amount: '4',
      date: '2026-08-31',
      categoryId: 'category.food',
      subcategoryId: 'subcategory.groceries',
      merchantId: 'merchant.grocery',
      paymentSourceId: 'payment-source',
    ),
  ]) {
    await fixture.saveTransaction(transaction);
  }
  await fixture.saveDuplicateGroup(
    DuplicateCandidateGroup(
      id: 'duplicate-groceries-group',
      transactionIds: [
        TransactionId('duplicate-groceries'),
        TransactionId('groceries'),
      ],
      duplicateKey: DuplicateTransactionKey(
        transactionDate: '2026-09-01',
        amount: DecimalValue.parse('10'),
        currency: 'USD',
        direction: 'expense',
      ),
      status: DuplicateCandidateGroupStatus.consolidated,
      selectedTransactionId: TransactionId('groceries'),
      createdAt: DateTime.utc(2026, 9, 1),
      updatedAt: DateTime.utc(2026, 9, 1),
    ),
  );
  await fixture.saveReconciliationLink(
    id: 'receipt-payment',
    receiptTransactionId: TransactionId('receipt'),
    paymentTransactionId: TransactionId('payment'),
    createdAt: DateTime.utc(2026, 9, 4),
  );
}

Transaction _transaction({
  required String id,
  required String amount,
  String? date,
  String currency = 'USD',
  String? normalizedAmount,
  TransactionDirection direction = TransactionDirection.expense,
  TransactionStatus status = TransactionStatus.active,
  DateTime? occurredAt,
  String? categoryId,
  String? subcategoryId,
  String? merchantId,
  String? paymentSourceId,
  TransactionSourceType sourceType = TransactionSourceType.manual,
}) {
  final money = Money(
    amount: DecimalValue.parse(amount),
    currency: CurrencyCode(currency),
  );
  return Transaction(
    id: TransactionId(id),
    timing: occurredAt == null
        ? const UnknownTransactionTime(UnknownTransactionTimeReason.unknown)
        : KnownTransactionTime(occurredAt),
    money: money,
    direction: direction,
    sourceType: sourceType,
    status: status,
    transactionDate: date,
    categoryId: categoryId == null ? null : CategoryId(categoryId),
    subcategoryId: subcategoryId == null ? null : CategoryId(subcategoryId),
    merchantId: merchantId == null ? null : MerchantId(merchantId),
    paymentSourceId: paymentSourceId == null
        ? null
        : PaymentSourceId(paymentSourceId),
    normalizedMoney: normalizedAmount == null
        ? const []
        : [
            NormalizedMoney(
              original: money,
              converted: Money(
                amount: DecimalValue.parse(normalizedAmount),
                currency: CurrencyCode('USD'),
              ),
              baseCurrency: CurrencyCode('USD'),
              effectiveDate: date ?? '',
            ),
          ],
    provenance: [
      Provenance(
        id: ProvenanceId('$id-provenance'),
        sourceType: ProvenanceSourceType.userEntry,
        capturedAt: DateTime.utc(2026, 9, 1),
        originalRepresentation: id,
      ),
    ],
    createdAt: DateTime.utc(2026, 9, 1),
    updatedAt: DateTime.utc(2026, 9, 1),
  );
}

final class _Rules implements AnalysisRuleRepository {
  const _Rules(this.values);
  final List<AnalysisRuleDefinition> values;

  @override
  Future<List<AnalysisRuleDefinition>> listActive() async => values;

  @override
  Future<List<AnalysisRuleDefinition>> listDefinitions() async => values;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _Clock implements ApplicationClock {
  const _Clock();

  @override
  DateTime now() => DateTime.utc(2026, 9, 20);
}
