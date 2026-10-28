import 'dart:convert';

import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../database/butlerly_database.dart';

final class SqliteFinancialProfileRepository
    implements FinancialProfileRepository {
  const SqliteFinancialProfileRepository(this.database);

  final ButlerlyDatabase database;

  @override
  Future<FinancialProfile?> load() async {
    try {
      final rows = await database.connection.query(
        'financial_profiles',
        where: 'profile_id = ?',
        whereArgs: [FinancialProfile.defaultProfileId],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return _fromRow(rows.single);
    } on RepositoryException {
      rethrow;
    } on Exception {
      throw const RepositoryException(
        RepositoryFailureCode.integrity,
        'load financial profile',
      );
    }
  }

  @override
  Future<void> save(FinancialProfile profile) async {
    try {
      final row = _toRow(profile);
      await database.connection.transaction((transaction) async {
        await transaction.insert(
          'financial_profiles',
          row,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        await transaction.delete(
          'entity_tombstones',
          where: 'entity_type = ? AND entity_id = ?',
          whereArgs: ['financial_profiles', profile.profileId],
        );
      });
    } on RepositoryException {
      rethrow;
    } on Exception {
      throw const RepositoryException(
        RepositoryFailureCode.unknown,
        'save financial profile',
      );
    }
  }

  @override
  Future<void> clear() async {
    try {
      await database.connection.transaction((transaction) async {
        await transaction.delete(
          'financial_profiles',
          where: 'profile_id = ?',
          whereArgs: [FinancialProfile.defaultProfileId],
        );
        await transaction.insert('entity_tombstones', {
          'entity_type': 'financial_profiles',
          'entity_id': FinancialProfile.defaultProfileId,
          'deleted_at': DateTime.now().toUtc().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      });
    } on RepositoryException {
      rethrow;
    } on Exception {
      throw const RepositoryException(
        RepositoryFailureCode.unknown,
        'clear financial profile',
      );
    }
  }

  Map<String, Object?> _toRow(FinancialProfile profile) => {
    'profile_id': profile.profileId,
    'schema_version': profile.schemaVersion,
    'survey_version': profile.surveyVersion,
    'household_size': profile.householdSize?.name,
    'dependents_count': profile.dependentsCount?.name,
    'housing_situation': profile.housingSituation?.name,
    'primary_spending_categories': jsonEncode(
      profile.primarySpendingCategoryIds,
    ),
    'expense_predictability': profile.expensePredictability?.name,
    'categories_to_improve': jsonEncode(profile.categoriesToImprove),
    'primary_financial_goal': profile.primaryFinancialGoal?.name,
    'has_monthly_savings_target': profile.hasMonthlySavingsTarget == null
        ? null
        : profile.hasMonthlySavingsTarget!
        ? 1
        : 0,
    'monthly_savings_target': profile.monthlySavingsTarget?.toString(),
    'monthly_savings_target_currency':
        profile.monthlySavingsTargetCurrency?.value,
    'goal_timeframe': profile.goalTimeframe?.name,
    'budgeting_preference': profile.budgetingPreference?.name,
    'preferred_insight_types': jsonEncode(
      profile.preferredInsightTypes.map((value) => value.name).toList(),
    ),
    'survey_status': profile.status.name,
    'created_at': profile.createdAt.toIso8601String(),
    'updated_at': profile.updatedAt.toIso8601String(),
    'completed_at': profile.completedAt?.toIso8601String(),
  };

  FinancialProfile _fromRow(Map<String, Object?> row) {
    try {
      return FinancialProfile(
        profileId: row['profile_id']! as String,
        schemaVersion: row['schema_version']! as int,
        surveyVersion: row['survey_version']! as String,
        householdSize: _enumValue(row['household_size'], HouseholdSize.values),
        dependentsCount: _enumValue(
          row['dependents_count'],
          DependentsCount.values,
        ),
        housingSituation: _enumValue(
          row['housing_situation'],
          HousingSituation.values,
        ),
        primarySpendingCategoryIds: _decodeStringList(
          row['primary_spending_categories'],
        ),
        expensePredictability: _enumValue(
          row['expense_predictability'],
          ExpensePredictability.values,
        ),
        categoriesToImprove: _decodeStringList(row['categories_to_improve']),
        primaryFinancialGoal: _enumValue(
          row['primary_financial_goal'],
          PrimaryFinancialGoal.values,
        ),
        hasMonthlySavingsTarget: _bool(row['has_monthly_savings_target']),
        monthlySavingsTarget: _decimal(row['monthly_savings_target']),
        monthlySavingsTargetCurrency: _currency(
          row['monthly_savings_target_currency'],
        ),
        goalTimeframe: _enumValue(row['goal_timeframe'], GoalTimeframe.values),
        budgetingPreference: _enumValue(
          row['budgeting_preference'],
          BudgetingPreference.values,
        ),
        preferredInsightTypes: [
          for (final value in _decodeStringList(row['preferred_insight_types']))
            _enumValue(value, FinancialInsightType.values)!,
        ],
        status: _enumValue(
          row['survey_status'],
          FinancialProfileStatus.values,
        )!,
        createdAt: DateTime.parse(row['created_at']! as String),
        updatedAt: DateTime.parse(row['updated_at']! as String),
        completedAt: _date(row['completed_at']),
      );
    } on DomainValidationException {
      rethrow;
    } on Exception catch (error) {
      throw RepositoryException(
        RepositoryFailureCode.integrity,
        'reconstruct financial profile: $error',
      );
    }
  }

  List<String> _decodeStringList(Object? value) {
    if (value is! String) {
      throw const FormatException('Financial profile list is not text.');
    }
    final decoded = jsonDecode(value);
    if (decoded is! List || decoded.any((item) => item is! String)) {
      throw const FormatException('Financial profile list is invalid.');
    }
    return decoded.cast<String>();
  }

  T? _enumValue<T extends Enum>(Object? raw, List<T> values) {
    if (raw == null) return null;
    if (raw is! String) throw const FormatException('Invalid profile answer.');
    for (final value in values) {
      if (value.name == raw) return value;
    }
    throw const FormatException('Unknown profile answer.');
  }

  DecimalValue? _decimal(Object? value) =>
      value == null ? null : DecimalValue.parse(value as String);

  CurrencyCode? _currency(Object? value) =>
      value == null ? null : CurrencyCode(value as String);

  bool? _bool(Object? value) {
    if (value == null) return null;
    if (value is int && (value == 0 || value == 1)) return value == 1;
    throw const FormatException('Invalid profile boolean.');
  }

  DateTime? _date(Object? value) =>
      value == null ? null : DateTime.parse(value as String);
}
