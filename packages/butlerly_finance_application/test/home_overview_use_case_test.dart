import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:test/test.dart';

void main() {
  late _Transactions transactions;
  late _Preferences preferences;
  late GetHomeOverview loadHomeOverview;

  setUp(() {
    transactions = _Transactions([
      _transaction('sep-1', '2026-09-01', '10'),
      _transaction('sep-2', '2026-09-02', '20'),
      _transaction('sep-3', '2026-09-03', '30'),
      _transaction('sep-4', '2026-09-04', '40'),
      _transaction('sep-5', '2026-09-05', '50'),
      _transaction('august-review', '2026-08-15', '99', review: true),
      _transaction('sep-review', '2026-09-06', '60', review: true),
    ]);
    preferences = _Preferences();
    loadHomeOverview = _homeOverview(transactions, preferences, [
      _expenseRule(),
    ]);
  });

  test(
    'composes current-month analysis, trend, recent items, and reviews',
    () async {
      final result = await loadHomeOverview(
        instant: DateTime.utc(2026, 9, 16, 12),
      );

      final overview = (result as ApplicationSuccess<HomeOverview>).value;
      final context = overview.context!;
      expect(context.periodType, 'current_month');
      expect(context.period.timeZoneId, 'America/Los_Angeles');
      expect(context.baseCurrency, CurrencyCode('EUR'));
      expect(context.period.startDate, '2026-09-01');
      expect(overview.analysis?.spending?.value, DecimalValue.parse('210'));
      expect(overview.monthlyTrend, hasLength(6));
      expect(
        overview.monthlyTrend.last.spending?.value,
        DecimalValue.parse('210'),
      );
      expect(overview.monthlyTrendUnavailable, isFalse);
      expect(overview.recentTransactions.map((value) => value.id), [
        'sep-1',
        'sep-2',
        'sep-3',
        'sep-4',
        'sep-5',
      ]);
      expect(overview.reviewCount, 1);
      expect(overview.reviewUnavailable, isFalse);
      expect(overview.insights, isEmpty);
    },
  );

  test(
    'uses the selected historical month for context and transactions',
    () async {
      final result = await loadHomeOverview(
        instant: DateTime.utc(2026, 9, 16, 12),
        selectedMonth: DateTime(2026, 8, 1),
      );

      final overview = (result as ApplicationSuccess<HomeOverview>).value;
      final context = overview.context!;
      expect(context.periodType, 'selected_month');
      expect(context.period.startDate, '2026-08-01');
      expect(context.period.endDate, '2026-08-31');
      expect(overview.displayMonth, DateTime(2026, 8, 1));
      expect(overview.currentFinancialMonth, DateTime(2026, 9, 1));
      expect(overview.recentTransactions.map((value) => value.id), [
        'august-review',
      ]);
      expect(overview.reviewCount, 1);
    },
  );

  test('keeps review failures distinct from zero review items', () async {
    transactions.failReviewQueries = true;

    final failed = await loadHomeOverview(
      instant: DateTime.utc(2026, 9, 16, 12),
    );
    final failedOverview = (failed as ApplicationSuccess<HomeOverview>).value;
    expect(failedOverview.reviewCount, 0);
    expect(failedOverview.reviewUnavailable, isTrue);

    transactions.failReviewQueries = false;
    transactions.values.removeWhere((value) => value.reviewIssues.isNotEmpty);
    final empty = await loadHomeOverview(
      instant: DateTime.utc(2026, 9, 16, 12),
    );
    final emptyOverview = (empty as ApplicationSuccess<HomeOverview>).value;
    expect(emptyOverview.reviewCount, 0);
    expect(emptyOverview.reviewUnavailable, isFalse);
  });

  test(
    'keeps duplicate-query failures distinct from zero duplicate groups',
    () async {
      final groups = _Groups(const [], fail: true);
      loadHomeOverview = _homeOverview(transactions, preferences, [
        _expenseRule(),
      ], duplicateGroups: groups);

      final result = await loadHomeOverview(
        instant: DateTime.utc(2026, 9, 16, 12),
      );
      final overview = (result as ApplicationSuccess<HomeOverview>).value;

      expect(overview.possibleDuplicateCount, 0);
      expect(overview.reviewUnavailable, isFalse);
      expect(overview.duplicateUnavailable, isTrue);
    },
  );

  test(
    'returns transactions when analysis calculation is unavailable',
    () async {
      transactions.failListAll = true;

      final result = await loadHomeOverview(
        instant: DateTime.utc(2026, 9, 16, 12),
      );

      final overview = (result as ApplicationSuccess<HomeOverview>).value;
      expect(overview.analysis, isNull);
      expect(overview.analysisUnavailable, isTrue);
      expect(overview.recentTransactions, hasLength(5));
    },
  );

  test(
    'returns a typed transaction-unavailable state with its period',
    () async {
      transactions.failTransactionQueries = true;

      final result = await loadHomeOverview(
        instant: DateTime.utc(2026, 9, 16, 12),
      );

      final overview = (result as ApplicationSuccess<HomeOverview>).value;
      expect(overview.status, HomeOverviewStatus.transactionsUnavailable);
      expect(overview.context?.period.startDate, '2026-09-01');
      expect(overview.currentFinancialMonth, DateTime(2026, 9, 1));
      expect(overview.displayMonth, DateTime(2026, 9, 1));
      expect(overview.recentTransactions, isEmpty);
    },
  );

  test('returns a typed period-unavailable state without a period', () async {
    preferences.timeZoneId = 'Invalid/Timezone';

    final result = await loadHomeOverview(
      instant: DateTime.utc(2026, 9, 16, 12),
    );

    final overview = (result as ApplicationSuccess<HomeOverview>).value;
    expect(overview.status, HomeOverviewStatus.periodUnavailable);
    expect(overview.context, isNull);
    expect(overview.currentFinancialMonth, isNull);
    expect(overview.displayMonth, isNull);
  });

  test('projects scoped semantic attention counts for Home', () async {
    transactions.values.addAll([
      _transaction(
        'merchant-safeway-1',
        '2026-09-07',
        '8',
        rawCounterparty: 'SAFEWAY #123',
        reviewReason: ReviewIssueReason.merchantNeedsReview,
      ),
      _transaction(
        'merchant-safeway-2',
        '2026-09-08',
        '9',
        rawCounterparty: 'SAFEWAY #123',
        reviewReason: ReviewIssueReason.merchantNeedsReview,
      ),
      _transaction(
        'merchant-trader-joes',
        '2026-09-09',
        '10',
        rawCounterparty: 'TRADER JOES',
        reviewReason: ReviewIssueReason.merchantNeedsReview,
      ),
      _transaction(
        'merchant-description-fallback',
        '2026-09-10',
        '11',
        rawCounterparty: '   ',
        description: 'UNKNOWN MERCHANT',
        reviewReason: ReviewIssueReason.merchantNeedsReview,
      ),
    ]);
    loadHomeOverview = _homeOverview(
      transactions,
      preferences,
      [_expenseRule()],
      duplicateGroups: _Groups([
        DuplicateCandidateGroup(
          id: 'duplicate-1',
          transactionIds: [TransactionId('sep-1'), TransactionId('sep-2')],
          duplicateKey: DuplicateTransactionKey(
            transactionDate: '2026-09-01',
            amount: DecimalValue.parse('10'),
            currency: 'EUR',
            direction: 'expense',
          ),
          status: DuplicateCandidateGroupStatus.unresolved,
          createdAt: DateTime.utc(2026, 9, 1),
          updatedAt: DateTime.utc(2026, 9, 1),
        ),
      ]),
    );

    final result = await loadHomeOverview(
      instant: DateTime.utc(2026, 9, 16, 12),
    );
    final overview = (result as ApplicationSuccess<HomeOverview>).value;

    expect(overview.merchantReviewCount, 3);
    expect(overview.possibleDuplicateCount, 1);
    expect(overview.uncategorizedTransactionCount, greaterThan(0));
  });

  test('returns insights in the shared policy ranking order', () async {
    final result = await _homeOverview(transactions, preferences, [
      _expenseRule(),
      _insightRule(
        'ANL-R021',
        outputType: InsightOutputType.pattern,
        severity: RuleSeverity.critical,
      ),
      _insightRule(
        'ANL-R024',
        outputType: InsightOutputType.alert,
        severity: RuleSeverity.info,
      ),
    ])(instant: DateTime.utc(2026, 9, 16, 12));

    final overview = (result as ApplicationSuccess<HomeOverview>).value;
    expect(overview.insights.map((value) => value.rule.identity.value), [
      'ANL-R024',
      'ANL-R021',
    ]);
  });

  test(
    'exposes trend calculation failure separately from empty history',
    () async {
      final result = await _homeOverview(transactions, preferences, [])(
        instant: DateTime.utc(2026, 9, 16, 12),
      );

      final overview = (result as ApplicationSuccess<HomeOverview>).value;
      expect(overview.analysis, isNotNull);
      expect(overview.monthlyTrend, isEmpty);
      expect(overview.monthlyTrendUnavailable, isTrue);
    },
  );
}

GetHomeOverview _homeOverview(
  _Transactions transactions,
  _Preferences preferences,
  List<AnalysisRuleDefinition> rules, {
  DuplicateCandidateGroupRepository? duplicateGroups,
}) {
  final analysis = CalculateAnalysisOverview(
    _Rules(rules),
    AnalysisDatasetBuilder(transactions, preferences, null),
    const AnalysisRuleEngine(),
  );
  return GetHomeOverview(
    resolveHomePeriod: ResolveHomePeriod(preferences),
    calculateAnalysis: analysis,
    calculateInsights: CalculateInsights(analysis),
    listTransactions: ListTransactions(transactions, preferences: preferences),
    listReviewItems: ListReviewItems(transactions),
    listDuplicateCandidateGroups: duplicateGroups == null
        ? null
        : ListDuplicateCandidateGroups(duplicateGroups),
  );
}

Transaction _transaction(
  String id,
  String date,
  String amount, {
  bool review = false,
  ReviewIssueReason? reviewReason,
  String? rawCounterparty,
  String? description,
}) {
  final at = DateTime.utc(2026, 9, 1, 12);
  return Transaction(
    id: TransactionId(id),
    timing: KnownTransactionTime(at),
    money: Money(
      amount: DecimalValue.parse(amount),
      currency: CurrencyCode('EUR'),
    ),
    direction: TransactionDirection.expense,
    sourceType: TransactionSourceType.manual,
    transactionDate: date,
    description: description,
    rawCounterparty: rawCounterparty,
    reviewIssues: review || reviewReason != null
        ? [
            ReviewIssue(
              id: ReviewIssueId('issue-$id'),
              transactionId: TransactionId(id),
              reason: reviewReason ?? ReviewIssueReason.uncertain,
              createdAt: at,
            ),
          ]
        : const [],
    provenance: [
      Provenance(
        id: ProvenanceId('provenance-$id'),
        sourceType: ProvenanceSourceType.userEntry,
        capturedAt: at,
      ),
    ],
    createdAt: at,
    updatedAt: at,
  );
}

AnalysisRuleDefinition _expenseRule() => AnalysisRuleDefinition(
  identity: RuleIdentity('ANL-R001'),
  version: RuleVersion('1.0.0'),
  schemaVersion: '1.0.0',
  type: AnalysisRuleType.metric,
  nameKey: 'analysis.rule.expense.name',
  descriptionKey: 'analysis.rule.expense.description',
  enabled: true,
  status: AnalysisRuleStatus.active,
  period: 'selected_period',
  measure: const RuleMeasure(
    operation: RuleOperation.sum,
    field: 'amount',
    currencyBasis: CurrencyBasis.baseCurrency,
  ),
  grouping: RuleGrouping.none,
  baseline: RuleBaseline.none,
  condition: const RuleCondition(operator: 'none'),
  severity: RuleSeverity.info,
  surface: AnalysisSurface.overview,
  role: AnalysisSemanticRole.expenseTotal,
  filters: const [
    AnalysisFilter(kind: AnalysisFilterKind.direction, values: ['expense']),
  ],
  definitionHash: RuleDefinitionHash('a' * 64),
);

AnalysisRuleDefinition _insightRule(
  String id, {
  required InsightOutputType outputType,
  required RuleSeverity severity,
}) => AnalysisRuleDefinition(
  identity: RuleIdentity(id),
  version: RuleVersion('1.0.0'),
  schemaVersion: '1.0.0',
  type: AnalysisRuleType.insight,
  nameKey: 'analysis.rule.$id.name',
  descriptionKey: 'analysis.rule.$id.description',
  enabled: true,
  status: AnalysisRuleStatus.active,
  period: 'selected_period',
  measure: const RuleMeasure(
    operation: RuleOperation.sum,
    field: 'amount',
    currencyBasis: CurrencyBasis.baseCurrency,
  ),
  grouping: RuleGrouping.none,
  baseline: RuleBaseline.previousEquivalentPeriod,
  condition: RuleCondition(
    operator: 'gte',
    left: 'percentageChange',
    value: DecimalValue.fromParts(coefficient: BigInt.zero, scale: 0),
  ),
  severity: severity,
  surface: AnalysisSurface.insights,
  outputType: outputType,
  resultPersistence: ResultPersistencePolicy.finding,
  filters: const [
    AnalysisFilter(kind: AnalysisFilterKind.direction, values: ['expense']),
  ],
  definitionHash: RuleDefinitionHash('b' * 64),
);

final class _Transactions implements TransactionRepository {
  _Transactions(this.values);

  final List<Transaction> values;
  bool failListAll = false;
  bool failTransactionQueries = false;
  bool failReviewQueries = false;

  @override
  Future<Transaction?> findById(TransactionId id) async =>
      values.where((value) => value.id == id).firstOrNull;

  @override
  Future<List<Transaction>> listAll() async {
    if (failListAll) {
      throw const RepositoryException(
        RepositoryFailureCode.unavailable,
        'list all transactions',
      );
    }
    return values;
  }

  @override
  Future<List<Transaction>> query(TransactionRepositoryQuery query) async {
    if (failTransactionQueries && query.needsReview != true) {
      throw const RepositoryException(
        RepositoryFailureCode.unavailable,
        'list transactions',
      );
    }
    if (failReviewQueries && query.needsReview == true) {
      throw const RepositoryException(
        RepositoryFailureCode.unavailable,
        'list review transactions',
      );
    }
    return values
        .where((transaction) {
          if (query.needsReview == true && transaction.reviewIssues.isEmpty) {
            return false;
          }
          if (query.status != null && transaction.status != query.status) {
            return false;
          }
          final date = DateTime.parse(transaction.transactionDate!);
          final from = query.from;
          final to = query.to;
          return (from == null || !date.isBefore(from)) &&
              (to == null || !date.isAfter(to));
        })
        .toList(growable: false);
  }

  @override
  Future<void> removePermanently(TransactionId id) async {}

  @override
  Future<void> save(Transaction transaction) async {}
}

final class _Preferences implements UserPreferenceRepository {
  String timeZoneId = 'America/Los_Angeles';

  @override
  Future<UserPreference?> load() async => UserPreference(
    locale: 'en',
    baseCurrency: CurrencyCode('EUR'),
    timeZoneId: timeZoneId,
  );

  @override
  Future<void> save(UserPreference preference) async {}
}

final class _Rules implements AnalysisRuleRepository {
  _Rules(this.values);

  final List<AnalysisRuleDefinition> values;

  @override
  Future<List<AnalysisRuleDefinition>> listActive() async => values;

  @override
  Future<List<AnalysisRuleDefinition>> listDefinitions() async => values;

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

final class _Groups implements DuplicateCandidateGroupRepository {
  _Groups(this.values, {this.fail = false});

  final List<DuplicateCandidateGroup> values;
  final bool fail;

  @override
  Future<List<DuplicateCandidateGroup>> list({
    DuplicateCandidateGroupStatus? status,
  }) async {
    if (fail) {
      throw const RepositoryException(
        RepositoryFailureCode.unavailable,
        'list possible duplicate groups',
      );
    }
    return values
        .where((value) => status == null || value.status == status)
        .toList(growable: false);
  }

  @override
  Future<List<DuplicateTransactionGroupMatch>>
  findActiveDuplicateGroups() async => const [];

  @override
  Future<List<TransactionId>> findActiveTransactionIdsForKey(
    DuplicateTransactionKey key,
  ) async => const [];

  @override
  Future<void> save(DuplicateCandidateGroup group) async {}

  @override
  Future<void> remove(String id) async {}
}
