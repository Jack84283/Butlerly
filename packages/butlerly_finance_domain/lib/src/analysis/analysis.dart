import '../entities/transaction.dart';
import '../errors/domain_error.dart';
import '../value_objects/currency_code.dart';
import '../value_objects/decimal_value.dart';
import '../value_objects/domain_id.dart';
import '../value_objects/money.dart';

enum AnalysisRuleType { metric, insight, dataQuality }

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
  merchant,
  paymentSource,
  tag,
  day,
  week,
  month,
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
  });
  final AnalysisPeriod period;
  final DatasetMode datasetMode;
  final CurrencyBasis currencyBasis;
  final CurrencyCode? baseCurrency;
}

final class AnalysisEconomicTransaction {
  const AnalysisEconomicTransaction({
    required this.id,
    required this.money,
    required this.direction,
    required this.transactionDate,
    this.status = TransactionStatus.active,
    this.normalizedMoney,
    this.categoryId,
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
    this.qualityIssues = const [],
  });
  final List<AnalysisEconomicTransaction> transactions;
  final AnalysisContext context;
  final List<AnalysisEconomicTransaction> baselineTransactions;
  final Map<String, List<AnalysisEconomicTransaction>>
  primaryTransactionsByPeriod;
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
  });
  final RuleOperation operation;
  final String field;
  final CurrencyBasis currencyBasis;
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
    this.dependencies = const [],
    this.filters = const [],
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
  final RuleGrouping grouping;
  final RuleBaseline baseline;
  final RuleCondition condition;
  final RuleSeverity severity;
  final List<RuleDependency> dependencies;
  final List<AnalysisFilter> filters;
  final RuleDefinitionHash definitionHash;
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
  final List<EvidenceReference> evidence;
  final List<DataQualityIssue> qualityIssues;
  final DateTime calculatedAt;
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
    this.issues = const [],
    this.failure,
  });
  final AnalysisRuleDefinition rule;
  final AnalysisMetric? metric;
  final AnalysisFinding? finding;
  final List<DataQualityIssue> issues;
  final AnalysisFailure? failure;
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
