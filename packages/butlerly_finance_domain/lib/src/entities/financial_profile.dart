import 'dart:collection';

import '../errors/domain_error.dart';
import '../value_objects/currency_code.dart';
import '../value_objects/decimal_value.dart';

enum FinancialProfileStatus { notStarted, inProgress, completed }

enum HouseholdSize { one, two, three, four, fiveOrMore }

enum DependentsCount { none, one, two, threeOrMore }

enum HousingSituation { renting, mortgage, ownOutright, other, preferNotToSay }

enum ExpensePredictability { mostlyFixed, mixedFixedVariable, highlyVariable }

enum PrimaryFinancialGoal {
  understandSpending,
  saveMore,
  reduceExpenses,
  improveCashFlow,
  reduceDebt,
}

enum GoalTimeframe { shortTerm, mediumTerm, longTerm }

enum BudgetingPreference {
  fixedMonthly,
  flexibleMonthly,
  trackingOnly,
  notSure,
}

enum FinancialInsightType {
  spendingTrends,
  unusualExpenses,
  savingsOpportunities,
  budgetTracking,
}

/// The one locally persisted Financial Profile for this account-free workspace.
///
/// Answer enums are stable identifiers. Localized labels belong to the
/// presentation layer and must never be persisted in their place.
final class FinancialProfile {
  FinancialProfile({
    this.profileId = defaultProfileId,
    this.schemaVersion = currentSchemaVersion,
    this.surveyVersion = currentSurveyVersion,
    this.householdSize,
    this.dependentsCount,
    this.housingSituation,
    Iterable<String> primarySpendingCategoryIds = const [],
    this.expensePredictability,
    Iterable<String> categoriesToImprove = const [],
    this.primaryFinancialGoal,
    this.hasMonthlySavingsTarget,
    this.monthlySavingsTarget,
    this.monthlySavingsTargetCurrency,
    this.goalTimeframe,
    this.budgetingPreference,
    Iterable<FinancialInsightType> preferredInsightTypes = const [],
    this.status = FinancialProfileStatus.notStarted,
    required DateTime createdAt,
    required DateTime updatedAt,
    DateTime? completedAt,
  }) : primarySpendingCategoryIds = UnmodifiableListView(
         _validateCategoryIds(
           primarySpendingCategoryIds,
           field: 'primarySpendingCategoryIds',
           max: 3,
         ),
       ),
       categoriesToImprove = UnmodifiableListView(
         _validateCategoryIds(
           categoriesToImprove,
           field: 'categoriesToImprove',
         ),
       ),
       preferredInsightTypes = UnmodifiableListView(
         _unique(preferredInsightTypes),
       ),
       createdAt = createdAt.toUtc(),
       updatedAt = updatedAt.toUtc(),
       completedAt = completedAt?.toUtc() {
    if (profileId.trim().isEmpty) {
      invalid(
        code: DomainErrorCode.emptyValue,
        field: 'profileId',
        message: 'A financial profile identifier is required.',
      );
    }
    if (profileId != defaultProfileId) {
      invalid(
        code: DomainErrorCode.invalidState,
        field: 'profileId',
        message: 'Only the default local financial profile is supported.',
      );
    }
    if (schemaVersion < 1) {
      invalid(
        code: DomainErrorCode.invalidRange,
        field: 'schemaVersion',
        message: 'Financial profile schema version must be positive.',
      );
    }
    if (surveyVersion.trim().isEmpty) {
      invalid(
        code: DomainErrorCode.emptyValue,
        field: 'surveyVersion',
        message: 'A survey version is required.',
      );
    }
    final target = monthlySavingsTarget;
    if (target != null && hasMonthlySavingsTarget != true) {
      invalid(
        code: DomainErrorCode.relationshipMismatch,
        field: 'hasMonthlySavingsTarget',
        message: 'A savings target requires the target option to be selected.',
      );
    }
    if (target != null) {
      if (target.isNegative) {
        invalid(
          code: DomainErrorCode.invalidRange,
          field: 'monthlySavingsTarget',
          message: 'A savings target cannot be negative.',
        );
      }
      if (target.coefficient.abs().toString().length > maxSavingsTargetDigits ||
          target.scale > maxSavingsTargetScale) {
        invalid(
          code: DomainErrorCode.invalidRange,
          field: 'monthlySavingsTarget',
          message: 'The savings target exceeds supported storage limits.',
        );
      }
      if (monthlySavingsTargetCurrency == null) {
        invalid(
          code: DomainErrorCode.relationshipMismatch,
          field: 'monthlySavingsTargetCurrency',
          message: 'A savings target currency is required.',
        );
      }
    } else if (monthlySavingsTargetCurrency != null) {
      invalid(
        code: DomainErrorCode.relationshipMismatch,
        field: 'monthlySavingsTargetCurrency',
        message: 'A savings target currency requires a savings target.',
      );
    }
  }

  factory FinancialProfile.empty({
    required DateTime now,
    FinancialProfileStatus status = FinancialProfileStatus.inProgress,
  }) => FinancialProfile(
    status: status,
    monthlySavingsTargetCurrency: null,
    createdAt: now,
    updatedAt: now,
  );

  static const defaultProfileId = 'financial-profile:default';
  static const currentSchemaVersion = 1;
  static const currentSurveyVersion = '1.0';
  static const maxSavingsTargetDigits = 38;
  static const maxSavingsTargetScale = 9;

  final String profileId;
  final int schemaVersion;
  final String surveyVersion;
  final HouseholdSize? householdSize;
  final DependentsCount? dependentsCount;
  final HousingSituation? housingSituation;
  final List<String> primarySpendingCategoryIds;
  final ExpensePredictability? expensePredictability;
  final List<String> categoriesToImprove;
  final PrimaryFinancialGoal? primaryFinancialGoal;
  final bool? hasMonthlySavingsTarget;
  final DecimalValue? monthlySavingsTarget;
  final CurrencyCode? monthlySavingsTargetCurrency;
  final GoalTimeframe? goalTimeframe;
  final BudgetingPreference? budgetingPreference;
  final List<FinancialInsightType> preferredInsightTypes;
  final FinancialProfileStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? completedAt;

  int get answeredQuestionCount {
    var count = 0;
    if (householdSize != null) count++;
    if (dependentsCount != null) count++;
    if (housingSituation != null) count++;
    if (primarySpendingCategoryIds.isNotEmpty) count++;
    if (expensePredictability != null) count++;
    if (categoriesToImprove.isNotEmpty) count++;
    if (primaryFinancialGoal != null) count++;
    if (hasMonthlySavingsTarget != null) count++;
    if (goalTimeframe != null) count++;
    if (budgetingPreference != null) count++;
    if (preferredInsightTypes.isNotEmpty) count++;
    return count;
  }

  double get completionFraction => answeredQuestionCount / totalQuestionCount;

  static const totalQuestionCount = 11;

  FinancialProfile copyWith({
    Object? profileId = _unspecified,
    Object? schemaVersion = _unspecified,
    Object? surveyVersion = _unspecified,
    Object? householdSize = _unspecified,
    Object? dependentsCount = _unspecified,
    Object? housingSituation = _unspecified,
    Iterable<String>? primarySpendingCategoryIds,
    Object? expensePredictability = _unspecified,
    Iterable<String>? categoriesToImprove,
    Object? primaryFinancialGoal = _unspecified,
    Object? hasMonthlySavingsTarget = _unspecified,
    Object? monthlySavingsTarget = _unspecified,
    Object? monthlySavingsTargetCurrency = _unspecified,
    Object? goalTimeframe = _unspecified,
    Object? budgetingPreference = _unspecified,
    Iterable<FinancialInsightType>? preferredInsightTypes,
    Object? status = _unspecified,
    DateTime? createdAt,
    DateTime? updatedAt,
    Object? completedAt = _unspecified,
  }) => FinancialProfile(
    profileId: identical(profileId, _unspecified)
        ? this.profileId
        : profileId! as String,
    schemaVersion: identical(schemaVersion, _unspecified)
        ? this.schemaVersion
        : schemaVersion! as int,
    surveyVersion: identical(surveyVersion, _unspecified)
        ? this.surveyVersion
        : surveyVersion! as String,
    householdSize: identical(householdSize, _unspecified)
        ? this.householdSize
        : householdSize as HouseholdSize?,
    dependentsCount: identical(dependentsCount, _unspecified)
        ? this.dependentsCount
        : dependentsCount as DependentsCount?,
    housingSituation: identical(housingSituation, _unspecified)
        ? this.housingSituation
        : housingSituation as HousingSituation?,
    primarySpendingCategoryIds:
        primarySpendingCategoryIds ?? this.primarySpendingCategoryIds,
    expensePredictability: identical(expensePredictability, _unspecified)
        ? this.expensePredictability
        : expensePredictability as ExpensePredictability?,
    categoriesToImprove: categoriesToImprove ?? this.categoriesToImprove,
    primaryFinancialGoal: identical(primaryFinancialGoal, _unspecified)
        ? this.primaryFinancialGoal
        : primaryFinancialGoal as PrimaryFinancialGoal?,
    hasMonthlySavingsTarget: identical(hasMonthlySavingsTarget, _unspecified)
        ? this.hasMonthlySavingsTarget
        : hasMonthlySavingsTarget as bool?,
    monthlySavingsTarget: identical(monthlySavingsTarget, _unspecified)
        ? this.monthlySavingsTarget
        : monthlySavingsTarget as DecimalValue?,
    monthlySavingsTargetCurrency:
        identical(monthlySavingsTargetCurrency, _unspecified)
        ? this.monthlySavingsTargetCurrency
        : monthlySavingsTargetCurrency as CurrencyCode?,
    goalTimeframe: identical(goalTimeframe, _unspecified)
        ? this.goalTimeframe
        : goalTimeframe as GoalTimeframe?,
    budgetingPreference: identical(budgetingPreference, _unspecified)
        ? this.budgetingPreference
        : budgetingPreference as BudgetingPreference?,
    preferredInsightTypes: preferredInsightTypes ?? this.preferredInsightTypes,
    status: identical(status, _unspecified)
        ? this.status
        : status! as FinancialProfileStatus,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    completedAt: identical(completedAt, _unspecified)
        ? this.completedAt
        : completedAt as DateTime?,
  );

  static List<String> _validateCategoryIds(
    Iterable<String> values, {
    required String field,
    int? max,
  }) {
    final result = <String>[];
    for (final raw in values) {
      final value = raw.trim();
      if (value.isEmpty) {
        invalid(
          code: DomainErrorCode.emptyValue,
          field: field,
          message: 'Category identifiers cannot be empty.',
        );
      }
      if (!result.contains(value)) result.add(value);
    }
    if (max != null && result.length > max) {
      invalid(
        code: DomainErrorCode.invalidRange,
        field: field,
        message: 'Too many categories were selected.',
      );
    }
    return result;
  }

  static List<FinancialInsightType> _unique(
    Iterable<FinancialInsightType> values,
  ) {
    final seen = <FinancialInsightType>{};
    final result = <FinancialInsightType>[];
    for (final value in values) {
      if (seen.add(value)) result.add(value);
    }
    return result;
  }
}

const _unspecified = Object();
