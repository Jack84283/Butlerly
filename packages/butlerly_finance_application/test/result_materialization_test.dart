import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:test/test.dart';

void main() {
  final context = AnalysisContext(
    period: AnalysisPeriod(
      startDate: '2026-01-01',
      endDate: '2026-01-31',
      timeZoneId: 'UTC',
    ),
    datasetMode: DatasetMode.allEligible,
    currencyBasis: CurrencyBasis.original,
  );
  final rule = AnalysisRuleDefinition(
    identity: RuleIdentity('ANL-R001'),
    version: RuleVersion('1.0.0'),
    schemaVersion: '1.0.0',
    type: AnalysisRuleType.metric,
    nameKey: 'name',
    descriptionKey: 'description',
    enabled: true,
    status: AnalysisRuleStatus.active,
    period: 'selected_period',
    measure: const RuleMeasure(operation: RuleOperation.sum, field: 'amount'),
    grouping: RuleGrouping.none,
    baseline: RuleBaseline.none,
    condition: const RuleCondition(operator: 'none'),
    severity: RuleSeverity.info,
    definitionHash: RuleDefinitionHash('a' * 64),
  );

  test('metric materialization restores evidence and quality metadata', () {
    final issue = DataQualityIssue(
      code: 'missingFx',
      detail: 'Normalization unavailable.',
      transactionId: TransactionId('t1'),
    );
    final metric = AnalysisMetric(
      id: 'metric',
      rule: rule,
      context: context,
      value: DecimalValue.parse('12.50'),
      currency: CurrencyCode('USD'),
      dimension: 'value',
      transactionCount: 1,
      evidence: [
        EvidenceReference(
          transactionId: TransactionId('t1'),
          evidenceId: EvidenceId('e1'),
        ),
      ],
      qualityIssues: [issue],
      calculatedAt: DateTime.utc(2026, 1, 2),
    );
    final restored = restoreResult(
      materializeResult(
        RuleExecutionResult(rule: rule, metric: metric),
        context: context,
        at: DateTime.utc(2026, 1, 2),
      ),
      rule,
    ).metric!;
    expect(restored.value, metric.value);
    expect(restored.currency, metric.currency);
    expect(restored.evidence.single.transactionId.value, 't1');
    expect(restored.evidence.single.evidenceId!.value, 'e1');
    expect(restored.qualityIssues.single.code, issue.code);
    expect(restored.qualityIssues.single.detail, issue.detail);
    expect(restored.qualityIssues.single.transactionId!.value, 't1');
  });

  test('comparison materialization restores results without a finding', () {
    final comparison = AnalysisComparison(
      currentValue: DecimalValue.parse('92'),
      baselineValue: DecimalValue.parse('100'),
      absoluteChange: DecimalValue.parse('-8'),
      percentageChange: DecimalValue.parse('-8'),
      availability: AnalysisDataAvailability.sufficient,
    );
    final restored = restoreResult(
      materializeResult(
        RuleExecutionResult(rule: rule, comparison: comparison),
        context: context,
        at: DateTime.utc(2026, 1, 2),
      ),
      rule,
    ).comparison!;
    expect(restored.currentValue, comparison.currentValue);
    expect(restored.baselineValue, comparison.baselineValue);
    expect(restored.absoluteChange, comparison.absoluteChange);
    expect(restored.percentageChange, comparison.percentageChange);
    expect(restored.availability, AnalysisDataAvailability.sufficient);
  });

  test(
    'analysis identity changes with every calculation context component',
    () {
      final contexts = [
        context,
        AnalysisContext(
          period: AnalysisPeriod(
            startDate: '2026-01-02',
            endDate: '2026-01-31',
            timeZoneId: 'UTC',
          ),
          datasetMode: DatasetMode.allEligible,
          currencyBasis: CurrencyBasis.original,
        ),
        AnalysisContext(
          period: context.period,
          datasetMode: DatasetMode.verifiedOnly,
          currencyBasis: CurrencyBasis.original,
        ),
        AnalysisContext(
          period: context.period,
          datasetMode: DatasetMode.allEligible,
          currencyBasis: CurrencyBasis.baseCurrency,
          baseCurrency: CurrencyCode('USD'),
        ),
      ];
      final identities = contexts
          .map(
            (value) => AnalysisResultIdentity.forRule(
              rule: rule,
              context: value,
              dimension: 'dining',
            ).value,
          )
          .toSet();
      expect(identities, hasLength(contexts.length));
      expect(
        AnalysisResultIdentity.forRule(
          rule: rule,
          context: context,
          dimension: 'dining',
        ).value,
        isNot(
          AnalysisResultIdentity.forRule(
            rule: rule,
            context: context,
            dimension: 'travel',
          ).value,
        ),
      );
    },
  );
}
