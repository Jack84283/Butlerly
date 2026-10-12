import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:test/test.dart';

void main() {
  test('legacy leaf categories count in their real subcategory', () async {
    final categories = [
      Category(
        id: CategoryId('food'),
        name: 'Food',
        origin: CategoryOrigin.user,
      ),
      Category(
        id: CategoryId('groceries'),
        name: 'Groceries',
        parentId: CategoryId('food'),
        origin: CategoryOrigin.user,
      ),
      Category(
        id: CategoryId('travel'),
        name: 'Travel',
        origin: CategoryOrigin.user,
      ),
      Category(
        id: CategoryId('taxi'),
        name: 'Taxi',
        parentId: CategoryId('travel'),
        origin: CategoryOrigin.user,
      ),
    ];
    final builder = AnalysisDatasetBuilder(
      _Transactions([
        _expense('legacy-grocery', '10', category: 'groceries'),
        _expense(
          'modern-grocery',
          '20',
          category: 'food',
          subcategory: 'groceries',
        ),
        _expense('legacy-taxi', '30', category: 'taxi'),
        _expense('category-only', '40', category: 'food'),
        _expense('no-category', '5'),
      ]),
      _Preferences(),
      null,
      categories: _Categories(categories),
    );
    final context = AnalysisContext(
      period: AnalysisPeriod(
        startDate: '2026-08-01',
        endDate: '2026-08-31',
        timeZoneId: 'UTC',
      ),
      datasetMode: DatasetMode.allEligible,
      currencyBasis: CurrencyBasis.original,
    );
    final built = await builder.build(context);
    expect(built, isA<ApplicationDatasetSuccess>());
    final dataset = (built as ApplicationDatasetSuccess).dataset;

    // Normalize the selected period and its comparison to the same taxonomy.
    final selected = dataset.primaryTransactionsByPeriod['selected_period']!;
    final legacy = selected.singleWhere((t) => t.id.value == 'legacy-grocery');
    expect(legacy.categoryId?.value, 'food');
    expect(legacy.subcategoryId?.value, 'groceries');
    final modern = selected.singleWhere((t) => t.id.value == 'modern-grocery');
    expect(modern.categoryId?.value, 'food');
    expect(modern.subcategoryId?.value, 'groceries');

    AnalysisRuleDefinition rule(String id, RuleGrouping grouping) =>
        AnalysisRuleDefinition(
          identity: RuleIdentity(id),
          version: RuleVersion('1.0.0'),
          schemaVersion: '1.0.0',
          type: AnalysisRuleType.metric,
          nameKey: 'analysis.test',
          descriptionKey: 'analysis.test',
          enabled: true,
          status: AnalysisRuleStatus.active,
          period: 'selected_period',
          measure: const RuleMeasure(
            operation: RuleOperation.sum,
            field: 'amount',
          ),
          grouping: grouping,
          surface: AnalysisSurface.spending,
          baseline: RuleBaseline.none,
          condition: const RuleCondition(operator: 'none'),
          severity: RuleSeverity.info,
          definitionHash: RuleDefinitionHash('a' * 64),
          filters: [
            AnalysisFilter(
              kind: AnalysisFilterKind.direction,
              values: ['expense'],
            ),
          ],
        );
    final results = const AnalysisRuleEngine().execute(
      dataset: dataset,
      definitions: [
        rule('ANL-TEST-CAT', RuleGrouping.category),
        rule('ANL-TEST-SUB', RuleGrouping.subcategory),
      ],
    );
    final subcategories = {
      for (final result in results.where(
        (r) => r.rule.grouping == RuleGrouping.subcategory,
      ))
        result.metric!.dimension!.split(':').first: result.metric!,
    };
    expect(subcategories['groceries']?.value, DecimalValue.parse('30'));
    expect(subcategories['taxi']?.value, DecimalValue.parse('30'));
    expect(subcategories['uncategorized']?.value, DecimalValue.parse('45'));
    expect(
      subcategories['groceries']!.evidence
          .map((e) => e.transactionId.value)
          .toSet(),
      {'legacy-grocery', 'modern-grocery'},
    );
    expect(
      subcategories['uncategorized']!.evidence
          .map((e) => e.transactionId.value)
          .toSet(),
      {'category-only', 'no-category'},
    );
    final groupedCategories = {
      for (final result in results.where(
        (r) => r.rule.grouping == RuleGrouping.category,
      ))
        result.metric!.dimension!.split(':').first: result.metric!,
    };
    expect(groupedCategories['food']?.value, DecimalValue.parse('70'));
    expect(groupedCategories['travel']?.value, DecimalValue.parse('30'));
    expect(groupedCategories['uncategorized']?.value, DecimalValue.parse('5'));
  });
}

Transaction _expense(
  String id,
  String amount, {
  String? category,
  String? subcategory,
}) {
  final at = DateTime.utc(2026, 8, 10, 12);
  return Transaction(
    id: TransactionId(id),
    timing: KnownTransactionTime(at),
    transactionDate: '2026-08-10',
    money: Money(
      amount: DecimalValue.parse(amount),
      currency: CurrencyCode('USD'),
    ),
    direction: TransactionDirection.expense,
    sourceType: TransactionSourceType.manual,
    categoryId: category == null ? null : CategoryId(category),
    subcategoryId: subcategory == null ? null : CategoryId(subcategory),
    provenance: [
      Provenance(
        id: ProvenanceId('$id-provenance'),
        sourceType: ProvenanceSourceType.userEntry,
        capturedAt: at,
      ),
    ],
    createdAt: at,
    updatedAt: at,
  );
}

final class _Categories implements CategoryRepository {
  const _Categories(this.values);
  final List<Category> values;

  @override
  Future<Category?> findById(CategoryId id) async =>
      values.where((value) => value.id == id).firstOrNull;

  @override
  Future<List<Category>> listAll() async => values;

  @override
  Future<void> save(Category category) async {}
}

final class _Transactions implements TransactionRepository {
  const _Transactions(this.values);
  final List<Transaction> values;

  @override
  Future<Transaction?> findById(TransactionId id) async =>
      values.where((value) => value.id == id).firstOrNull;

  @override
  Future<List<Transaction>> listAll() async => values;

  @override
  Future<List<Transaction>> query(TransactionRepositoryQuery query) async =>
      values;

  @override
  Future<void> removePermanently(TransactionId id) async {}

  @override
  Future<void> save(Transaction transaction) async {}
}

final class _Preferences implements UserPreferenceRepository {
  @override
  Future<UserPreference?> load() async => UserPreference(
    locale: 'en',
    baseCurrency: CurrencyCode('USD'),
    timeZoneId: 'UTC',
  );

  @override
  Future<void> save(UserPreference preference) async {}
}
