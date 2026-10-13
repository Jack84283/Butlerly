import 'package:butlerly/features/analysis/presentation/analysis_search_selection.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final context = AnalysisContext(
    period: AnalysisPeriod(
      startDate: '2026-08-01',
      endDate: '2026-08-31',
      timeZoneId: 'UTC',
    ),
    datasetMode: DatasetMode.verifiedOnly,
    currencyBasis: CurrencyBasis.baseCurrency,
  );

  AnalysisRuleDefinition rule(String id) => AnalysisRuleDefinition(
    identity: RuleIdentity(id),
    version: RuleVersion('1.0.0'),
    schemaVersion: '1.0.0',
    type: AnalysisRuleType.metric,
    nameKey: 'analysis.test',
    descriptionKey: 'analysis.test',
    enabled: true,
    status: AnalysisRuleStatus.active,
    period: 'selected_period',
    measure: const RuleMeasure(operation: RuleOperation.sum, field: 'amount'),
    grouping: RuleGrouping.subcategory,
    surface: AnalysisSurface.spending,
    baseline: RuleBaseline.none,
    condition: const RuleCondition(operator: 'none'),
    severity: RuleSeverity.info,
    definitionHash: RuleDefinitionHash('a' * 64),
  );

  RuleExecutionResult result(
    String ruleId,
    String dimension,
    List<String> ids, {
    AnalysisDataAvailability availability = AnalysisDataAvailability.sufficient,
  }) {
    final definition = rule(ruleId);
    return RuleExecutionResult(
      rule: definition,
      metric: AnalysisMetric(
        id: '$ruleId-$dimension',
        rule: definition,
        context: context,
        value: DecimalValue.parse('10'),
        dimension: '$dimension:value',
        currency: CurrencyCode('USD'),
        availability: availability,
        evidence: [
          for (final id in ids)
            EvidenceReference(transactionId: TransactionId(id)),
        ],
        calculatedAt: DateTime.utc(2026, 8, 31),
      ),
    );
  }

  test('snapshot IDs stay authoritative without recalculation', () async {
    final selection = AnalysisSearchSelection(
      context: context,
      ruleId: 'ANL-R012',
      dimension: 'groceries',
      evidenceIds: ['t-1', 't-2', 't-1'],
    );
    var recalculated = false;
    final ids = await selection.resolveEvidence(
      calculate: (_) async {
        recalculated = true;
        return const ApplicationSuccess(<RuleExecutionResult>[]);
      },
    );
    expect(ids, ['t-1', 't-2']);
    expect(recalculated, isFalse);
  });

  test('missing evidence uses only the canonical Analysis rule results', () async {
    final selection = AnalysisSearchSelection(
      context: context,
      ruleId: 'ANL-R012',
      dimension: 'groceries',
    );
    final ids = await selection.resolveEvidence(
      calculate: (requested) async {
        expect(requested, same(context));
        expect(requested.datasetMode, DatasetMode.verifiedOnly);
        return ApplicationSuccess([
          result('ANL-R012', 'groceries', ['canonical-1', 'canonical-2']),
          result('ANL-R012', 'taxi', ['wrong-group']),
          result('ANL-R011', 'groceries', ['wrong-rule']),
          result(
            'ANL-R012',
            'groceries',
            ['not-available'],
            availability: AnalysisDataAvailability.insufficient,
          ),
        ]);
      },
    );
    expect(ids, ['canonical-1', 'canonical-2']);
  });

  test('aggregate selection includes all buckets of the same rule', () async {
    final selection = AnalysisSearchSelection(
      context: context,
      ruleId: 'ANL-R010',
      dimension: null,
    );
    final ids = await selection.resolveEvidence(
      calculate: (_) async => ApplicationSuccess([
        result('ANL-R010', 'food', ['a']),
        result('ANL-R010', 'travel', ['b', 'a']),
        result('ANL-R011', 'travel', ['wrong-rule']),
      ]),
    );
    expect(ids, ['a', 'b']);
  });

  test('missing and failed evidence never broadens to all transactions', () async {
    final selection = AnalysisSearchSelection(
      context: context,
      ruleId: 'ANL-R012',
      dimension: 'groceries',
    );
    expect(
      await selection.resolveEvidence(
        calculate: (_) async =>
            ApplicationSuccess([result('ANL-R012', 'taxi', ['unrelated'])]),
      ),
      isEmpty,
    );
    await expectLater(
      selection.resolveEvidence(
        calculate: (_) async => const ApplicationFailure(
          ApplicationFailureDetail(
            operation: 'calculate analysis overview',
            code: ApplicationFailureCode.unavailable,
          ),
        ),
      ),
      throwsStateError,
    );
  });
}
