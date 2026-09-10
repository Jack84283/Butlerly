import '../entities/transaction.dart';
import '../errors/domain_error.dart';
import '../value_objects/currency_code.dart';
import '../value_objects/decimal_value.dart';
import '../value_objects/domain_id.dart';
import '../value_objects/money.dart';

enum AnalysisRuleType { metric, insight, dataQuality }

enum AnalysisSurface {
  overview,
  spending,
  trends,
  calendar,
  insights,
  dataQuality,
}

enum AnalysisRuleStatus { active, disabled, retired }

enum DatasetMode { allEligible, verifiedOnly }

enum CurrencyBasis { original, baseCurrency }

enum RuleOperation {
  sum,
  count,
  average,
  median,
  minimum,
  maximum,
  distinctCount,
  frequency,
  difference,
}

enum RuleGrouping {
  none,
  category,
  subcategory,
  merchant,
  paymentSource,
  tag,
  day,
  week,
  month,
  adaptive,
}

enum RuleBaseline {
  none,
  previousPeriod,
  previousEquivalentPeriod,
  rollingAverage,
  rollingMedian,
  fixedThreshold,
}

enum RuleSeverity { info, attention, warning, critical }

enum FindingLifecycle { active, acknowledged, dismissed, superseded }

enum ResultPersistencePolicy { transient, materialized, finding }

enum RefreshPolicy { manual, onInvalidation, scheduled }

enum AnalysisResultType { metric, finding, dataQuality }

enum AnalysisResultFreshness { fresh, stale }

enum AnalysisDataAvailability { sufficient, empty, insufficient }

/// Describes how an analysis result is presented. This is a declarative
/// property of a rule, rather than a presentation decision based on a rule ID.
enum InsightOutputType { summary, pattern, alert, dataQuality, unresolved }

enum AnalysisFilterKind {
  direction,
  category,
  merchant,
  paymentSource,
  tag,
  currency,
  reviewState,
  status,
}

final class RuleIdentity {
  RuleIdentity(String value) : value = _validate(value);
  final String value;
  static String _validate(String value) {
    final normalized = value.trim();
    if (!RegExp(r'^ANL-R\d{3}$').hasMatch(normalized)) {
      invalid(
        code: DomainErrorCode.invalidState,
        field: 'ruleId',
        message: 'Invalid analysis rule ID.',
      );
    }
    return normalized;
  }

  @override
  bool operator ==(Object other) =>
      other is RuleIdentity && other.value == value;
  @override
  int get hashCode => value.hashCode;
}

final class RuleVersion {
  RuleVersion(String value) : value = _validate(value);
  final String value;
  static String _validate(String value) {
    final normalized = value.trim();
    if (!RegExp(r'^\d+\.\d+\.\d+$').hasMatch(normalized)) {
      invalid(
        code: DomainErrorCode.invalidState,
        field: 'ruleVersion',
        message: 'Invalid analysis rule version.',
      );
    }
    return normalized;
  }

  @override
  bool operator ==(Object other) =>
      other is RuleVersion && other.value == value;
  @override
  int get hashCode => value.hashCode;
}

final class RuleDefinitionHash {
  RuleDefinitionHash(String value) : value = _validate(value);
  final String value;
  static String _validate(String value) {
    final normalized = value.trim().toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(normalized)) {
      invalid(
        code: DomainErrorCode.invalidState,
        field: 'definitionHash',
        message: 'A SHA-256 rule definition hash is required.',
      );
    }
    return normalized;
  }

  @override
  bool operator ==(Object other) =>
      other is RuleDefinitionHash && other.value == value;
  @override
  int get hashCode => value.hashCode;
}

final class AnalysisPeriod {
  AnalysisPeriod({
    required this.startDate,
    required this.endDate,
    required this.timeZoneId,
  }) {
    if (startDate.compareTo(endDate) > 0) {
      invalid(
        code: DomainErrorCode.invalidRange,
        field: 'period',
        message: 'Analysis period start must not be after end.',
      );
    }
    if (timeZoneId.trim().isEmpty ||
        (timeZoneId != 'UTC' && !timeZoneId.contains('/'))) {
      invalid(
        code: DomainErrorCode.invalidState,
        field: 'timeZoneId',
        message: 'Analysis periods require an IANA timezone identifier.',
      );
    }
  }
  final String startDate;
  final String endDate;
  final String timeZoneId;
}

final class AnalysisFilter {
  const AnalysisFilter({required this.kind, required this.values});
  final AnalysisFilterKind kind;
  final List<String> values;
}

final class AnalysisContext {
  const AnalysisContext({
    required this.period,
    required this.datasetMode,
    required this.currencyBasis,
    this.baseCurrency,
    this.periodType = 'selected_period',
  });
  final AnalysisPeriod period;
  final DatasetMode datasetMode;
  final CurrencyBasis currencyBasis;
  final CurrencyCode? baseCurrency;

  /// The semantic period selected by the user, retained separately from its
  /// resolved dates so equivalent-period comparisons remain correct.
  final String periodType;
}

/// Canonical identity for every materialized analysis calculation.
///
/// Length-prefixing each component keeps the key unambiguous without using
/// localized or display-facing values. Metrics and findings deliberately use
/// the same identity space so lifecycle state cannot collide with another
/// calculation context.
final class AnalysisResultIdentity {
  const AnalysisResultIdentity._(this.value);

  factory AnalysisResultIdentity.forRule({
    required AnalysisRuleDefinition rule,
    required AnalysisContext context,
    String? dimension,
  }) => AnalysisResultIdentity._(
    [
      rule.identity.value,
      rule.version.value,
      rule.definitionHash.value,
      context.period.startDate,
      context.period.endDate,
      context.period.timeZoneId,
      context.datasetMode.name,
      context.currencyBasis.name,
      context.baseCurrency?.value,
      context.periodType,
      dimension,
    ].map(_encodePart).join('|'),
  );

  final String value;
}

String _encodePart(String? value) =>
    value == null ? '-' : '${value.length}:$value';

final class AnalysisEconomicTransaction {
  const AnalysisEconomicTransaction({
    required this.id,
    required this.money,
    required this.direction,
    required this.transactionDate,
    this.status = TransactionStatus.active,
    this.normalizedMoney,
    this.categoryId,
    this.subcategoryId,
    this.merchantId,
    this.paymentSourceId,
    this.tagIds = const [],
    this.verified = true,
    this.dataQuality = const [],
  });
  final TransactionId id;
  final Money money;
  final Money? normalizedMoney;
  final TransactionDirection direction;
  final TransactionStatus status;
  final String? transactionDate;
  final CategoryId? categoryId;
  final CategoryId? subcategoryId;
  final MerchantId? merchantId;
  final PaymentSourceId? paymentSourceId;
  final List<TagId> tagIds;
  final bool verified;
  final List<DataQualityIssue> dataQuality;
}

final class AnalysisDataset {
  const AnalysisDataset({
    required this.transactions,
    required this.context,
    this.baselineTransactions = const [],
    this.primaryTransactionsByPeriod = const {},
    this.baselineTransactionsByPeriod = const {},
    this.qualityIssues = const [],
  });
  final List<AnalysisEconomicTransaction> transactions;
  final AnalysisContext context;
  final List<AnalysisEconomicTransaction> baselineTransactions;
  final Map<String, List<AnalysisEconomicTransaction>>
  primaryTransactionsByPeriod;
  final Map<String, List<AnalysisEconomicTransaction>>
  baselineTransactionsByPeriod;
  final List<DataQualityIssue> qualityIssues;
}

final class RuleDependency {
  const RuleDependency({required this.ruleId, this.minimumVersion});
  final RuleIdentity ruleId;
  final RuleVersion? minimumVersion;
}

final class RuleMeasure {
  const RuleMeasure({
    required this.operation,
    required this.field,
    this.currencyBasis = CurrencyBasis.original,
    this.key = 'value',
    this.filters = const [],
  });
  final RuleOperation operation;
  final String field;
  final CurrencyBasis currencyBasis;
  final String key;
  final List<AnalysisFilter> filters;
}

final class RuleCondition {
  const RuleCondition({
    required this.operator,
    this.value,
    this.left,
    this.right,
    this.children = const [],
  });
  final String operator;
  final DecimalValue? value;
  final String? left;
  final String? right;
  final List<RuleCondition> children;
}

final class AnalysisRuleDefinition {
  const AnalysisRuleDefinition({
    required this.identity,
    required this.version,
    required this.schemaVersion,
    required this.type,
    required this.nameKey,
    required this.descriptionKey,
    required this.enabled,
    required this.status,
    required this.period,
    required this.measure,
    required this.grouping,
    required this.baseline,
    required this.condition,
    required this.severity,
    required this.definitionHash,
    this.surface = AnalysisSurface.overview,
    this.measures = const [],
    this.dependencies = const [],
    this.filters = const [],
    this.resultPersistence = ResultPersistencePolicy.transient,
    this.refreshPolicy = RefreshPolicy.onInvalidation,
    this.role,
    this.outputType = InsightOutputType.pattern,
  });
  final RuleIdentity identity;
  final RuleVersion version;
  final String schemaVersion;
  final AnalysisRuleType type;
  final String nameKey;
  final String descriptionKey;
  final bool enabled;
  final AnalysisRuleStatus status;
  final String period;
  final RuleMeasure measure;
  final List<RuleMeasure> measures;
  final AnalysisSurface surface;
  final RuleGrouping grouping;
  final RuleBaseline baseline;
  final RuleCondition condition;
  final RuleSeverity severity;
  final List<RuleDependency> dependencies;
  final List<AnalysisFilter> filters;
  final ResultPersistencePolicy resultPersistence;
  final RefreshPolicy refreshPolicy;
  final RuleDefinitionHash definitionHash;
  final String? role;
  final InsightOutputType outputType;
}

final class EvidenceReference {
  const EvidenceReference({required this.transactionId, this.evidenceId});
  final TransactionId transactionId;
  final EvidenceId? evidenceId;
}

final class AnalysisMetric {
  const AnalysisMetric({
    required this.id,
    required this.rule,
    required this.context,
    required this.value,
    this.currency,
    this.dimension,
    this.transactionCount = 0,
    this.availability = AnalysisDataAvailability.sufficient,
    this.evidence = const [],
    this.qualityIssues = const [],
    required this.calculatedAt,
  });
  final String id;
  final AnalysisRuleDefinition rule;
  final AnalysisContext context;
  final DecimalValue value;
  final CurrencyCode? currency;
  final String? dimension;
  final int transactionCount;
  final AnalysisDataAvailability availability;
  final List<EvidenceReference> evidence;
  final List<DataQualityIssue> qualityIssues;
  final DateTime calculatedAt;
}

/// A backend-owned comparison for a metric. A comparison may exist even when
/// a condition-triggered insight is not emitted.
final class AnalysisComparison {
  const AnalysisComparison({
    required this.currentValue,
    this.baselineValue,
    this.absoluteChange,
    this.percentageChange,
    this.baselineMetricId,
    required this.availability,
  });

  final DecimalValue currentValue;
  final DecimalValue? baselineValue;
  final DecimalValue? absoluteChange;
  final DecimalValue? percentageChange;
  final String? baselineMetricId;
  final AnalysisDataAvailability availability;
}

final class AnalysisFinding {
  const AnalysisFinding({
    required this.id,
    required this.rule,
    required this.context,
    required this.severity,
    required this.lifecycle,
    this.currentValue,
    this.baselineValue,
    this.absoluteChange,
    this.percentageChange,
    this.dimension,
    this.supportingMetrics = const [],
    this.evidence = const [],
    this.qualityIssues = const [],
    required this.generatedAt,
  });
  final String id;
  final AnalysisRuleDefinition rule;
  final AnalysisContext context;
  final RuleSeverity severity;
  final FindingLifecycle lifecycle;
  final DecimalValue? currentValue;
  final DecimalValue? baselineValue;
  final DecimalValue? absoluteChange;
  final DecimalValue? percentageChange;
  final String? dimension;
  final List<String> supportingMetrics;
  final List<EvidenceReference> evidence;
  final List<DataQualityIssue> qualityIssues;
  final DateTime generatedAt;
}

final class DataQualityIssue {
  const DataQualityIssue({
    required this.code,
    required this.detail,
    this.transactionId,
  });
  final String code;
  final String detail;
  final TransactionId? transactionId;
}

final class RuleExecutionResult {
  const RuleExecutionResult({
    required this.rule,
    this.metric,
    this.finding,
    this.comparison,
    this.issues = const [],
    this.failure,
  });
  final AnalysisRuleDefinition rule;
  final AnalysisMetric? metric;
  final AnalysisFinding? finding;
  final AnalysisComparison? comparison;
  final List<DataQualityIssue> issues;
  final AnalysisFailure? failure;
}

/// The selected and comparison windows used to explain an Insights result.
/// These are kept alongside the values so a presentation layer never has to
/// infer comparison semantics from a label or recalculate a period.
final class AnalysisPeriodComparison {
  const AnalysisPeriodComparison({this.selected, this.baseline});
  final AnalysisContext? selected;
  final AnalysisContext? baseline;
}

/// A stable, presentation-ready output from the Insights application use
/// case. Financial values and evidence are produced by the Analysis engine.
final class InsightResult {
  const InsightResult({
    required this.outputType,
    required this.rule,
    required this.context,
    this.baselineContext,
    this.finding,
    this.currentValue,
    this.baselineValue,
    this.absoluteChange,
    this.percentageChange,
    this.currency,
    this.dimension,
    this.evidence = const [],
    this.limitations = const [],
    this.exclusions = const [],
    this.failure,
  });
  final InsightOutputType outputType;
  final AnalysisRuleDefinition rule;
  final AnalysisContext context;
  final AnalysisContext? baselineContext;
  final AnalysisFinding? finding;
  final DecimalValue? currentValue;
  final DecimalValue? baselineValue;
  final DecimalValue? absoluteChange;
  final DecimalValue? percentageChange;
  final CurrencyCode? currency;
  final String? dimension;
  final List<EvidenceReference> evidence;
  final List<DataQualityIssue> limitations;
  final List<String> exclusions;
  final AnalysisFailure? failure;

  DateTime get generatedAt =>
      finding?.generatedAt ??
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  bool get isActive => finding?.lifecycle == FindingLifecycle.active;
}

final class PeriodSummary {
  const PeriodSummary({
    required this.context,
    this.baselineContext,
    this.expenseSpending,
    this.income,
    this.netCashFlow,
    this.eligibleTransactionCount = 0,
    this.currency,
    this.comparisonAvailable = false,
    this.comparisonUnavailableReason,
    this.expenseChange,
    this.incomeChange,
    this.netCashFlowChange,
    this.limitations = const [],
    this.exclusions = const [],
  });
  final AnalysisContext context;
  final AnalysisContext? baselineContext;
  final DecimalValue? expenseSpending;
  final DecimalValue? income;
  final DecimalValue? netCashFlow;
  final int eligibleTransactionCount;
  final CurrencyCode? currency;
  final bool comparisonAvailable;
  final String? comparisonUnavailableReason;
  final AnalysisComparison? expenseChange;
  final AnalysisComparison? incomeChange;
  final AnalysisComparison? netCashFlowChange;
  final List<DataQualityIssue> limitations;
  final List<String> exclusions;
}

final class InsightsEvaluation {
  const InsightsEvaluation({
    required this.summary,
    required this.results,
    this.limitations = const [],
    this.hasSufficientHistory = true,
  });
  final PeriodSummary summary;
  final List<InsightResult> results;
  final List<DataQualityIssue> limitations;
  final bool hasSufficientHistory;

  List<InsightResult> get activeFindings => results
      .where(
        (result) =>
            result.isActive &&
            result.outputType != InsightOutputType.dataQuality,
      )
      .toList(growable: false);

  List<InsightResult> get alerts => activeFindings
      .where((result) => result.outputType == InsightOutputType.alert)
      .toList(growable: false);

  List<InsightResult> get patterns => activeFindings
      .where((result) => result.outputType == InsightOutputType.pattern)
      .toList(growable: false);
}

/// Calculates a percentage change without converting the financial values to
/// binary floating point. Six fractional digits are retained before normal
/// decimal normalization, which is sufficient for threshold comparisons while
/// preserving exact values such as 50% and 20%.
DecimalValue? calculatePercentageChange(
  DecimalValue change,
  DecimalValue baseline,
) {
  if (baseline.isZero) return null;
  const precision = 6;
  final numerator =
      change.coefficient *
      BigInt.from(100) *
      BigInt.from(10).pow(baseline.scale + precision);
  return DecimalValue.fromParts(
    coefficient: numerator ~/ baseline.coefficient.abs(),
    scale: change.scale + precision,
  );
}

final class AnalysisRuleResult {
  const AnalysisRuleResult({
    required this.id,
    required this.ruleId,
    required this.ruleVersion,
    required this.definitionHash,
    required this.resultType,
    required this.surface,
    required this.context,
    required this.payload,
    required this.calculatedAt,
    required this.sourceRevision,
    required this.freshness,
    required this.createdAt,
    required this.updatedAt,
    this.dimension,
    this.resultSetKey,
    this.resultSetSize = 1,
  });

  final String id;
  final RuleIdentity ruleId;
  final RuleVersion ruleVersion;
  final RuleDefinitionHash definitionHash;
  final AnalysisResultType resultType;
  final AnalysisSurface surface;
  final AnalysisContext context;
  final String? dimension;
  final String payload;
  final DateTime calculatedAt;
  final int sourceRevision;
  final AnalysisResultFreshness freshness;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Identifies all outputs produced by one rule/context execution.
  final String? resultSetKey;

  /// The number of rows that must be present before the set is reusable.
  final int resultSetSize;
}

final class AnalysisFailure {
  const AnalysisFailure({
    required this.code,
    required this.message,
    this.ruleId,
    this.field,
  });
  final String code;
  final String message;
  final RuleIdentity? ruleId;
  final String? field;
}
