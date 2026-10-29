import 'dart:io';

import 'package:butlerly_database/butlerly_database.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'round-trips a completed financial profile across database reopen',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'butlerly-profile-',
      );
      final path = '${directory.path}/profile.db';
      final schema = await File('database/schema/v1.sql').readAsString();
      final deployment = await File(
        'database/migrations/deployment.sql',
      ).readAsString();

      Future<ButlerlyDatabase> open() async {
        final database = ButlerlyDatabase(
          factory: databaseFactoryFfi,
          path: path,
          schemaSql: schema,
          migrations: parseDeploymentMigrations(deployment),
        );
        await database.open();
        return database;
      }

      final now = DateTime.utc(2026, 10, 28, 12);
      final profile = FinancialProfile(
        householdSize: HouseholdSize.three,
        dependentsCount: DependentsCount.one,
        housingSituation: HousingSituation.mortgage,
        primarySpendingCategoryIds: const [
          'category.food',
          'category.transport',
        ],
        expensePredictability: ExpensePredictability.mixedFixedVariable,
        categoriesToImprove: const ['category.health'],
        primaryFinancialGoal: PrimaryFinancialGoal.saveMore,
        hasMonthlySavingsTarget: true,
        monthlySavingsTarget: DecimalValue.parse('750.25'),
        monthlySavingsTargetCurrency: CurrencyCode('USD'),
        goalTimeframe: GoalTimeframe.mediumTerm,
        budgetingPreference: BudgetingPreference.flexibleMonthly,
        preferredInsightTypes: const [
          FinancialInsightType.spendingTrends,
          FinancialInsightType.savingsOpportunities,
        ],
        status: FinancialProfileStatus.completed,
        createdAt: now,
        updatedAt: now.add(const Duration(minutes: 5)),
        completedAt: now.add(const Duration(minutes: 5)),
      );

      try {
        var database = await open();
        final repository = SqliteFinancialProfileRepository(database);
        await repository.save(profile);
        expect(await repository.load(), isNotNull);
        await database.close();

        database = await open();
        final reloaded = await SqliteFinancialProfileRepository(
          database,
        ).load();
        expect(reloaded?.profileId, FinancialProfile.defaultProfileId);
        expect(reloaded?.householdSize, HouseholdSize.three);
        expect(reloaded?.primarySpendingCategoryIds, [
          'category.food',
          'category.transport',
        ]);
        expect(reloaded?.monthlySavingsTarget, DecimalValue.parse('750.25'));
        expect(reloaded?.hasMonthlySavingsTarget, isTrue);
        expect(reloaded?.monthlySavingsTargetCurrency, CurrencyCode('USD'));
        expect(reloaded?.preferredInsightTypes, [
          FinancialInsightType.spendingTrends,
          FinancialInsightType.savingsOpportunities,
        ]);
        expect(reloaded?.status, FinancialProfileStatus.completed);
        final edited = reloaded!.copyWith(
          updatedAt: now.add(const Duration(minutes: 10)),
        );
        await SqliteFinancialProfileRepository(database).save(edited);
        final savedAfterEdit = await SqliteFinancialProfileRepository(
          database,
        ).load();
        expect(
          savedAfterEdit?.monthlySavingsTarget,
          DecimalValue.parse('750.25'),
        );
        final cleared = savedAfterEdit!.copyWith(householdSize: null);
        await SqliteFinancialProfileRepository(database).save(cleared);
        final reloadedAfterClear = await SqliteFinancialProfileRepository(
          database,
        ).load();
        expect(reloadedAfterClear?.householdSize, isNull);
        expect(reloadedAfterClear?.dependentsCount, DependentsCount.one);
        expect(reloadedAfterClear?.answeredQuestionCount, 10);
        await database.connection.insert('financial_profiles', {
          'profile_id': 'financial-profile:orphan',
          'schema_version': 1,
          'survey_version': '1.0',
          'primary_spending_categories': '[]',
          'categories_to_improve': '[]',
          'preferred_insight_types': '[]',
          'survey_status': 'inProgress',
          'created_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
        });
        await SqliteFinancialProfileRepository(database).clear();
        expect(await SqliteFinancialProfileRepository(database).load(), isNull);
        expect(await database.connection.query('financial_profiles'), isEmpty);
        expect(
          await database.connection.query(
            'entity_tombstones',
            where: 'entity_type = ? AND entity_id = ?',
            whereArgs: [
              'financial_profiles',
              FinancialProfile.defaultProfileId,
            ],
          ),
          hasLength(1),
        );
        await SqliteFinancialProfileRepository(database).save(profile);
        expect(
          await database.connection.query(
            'entity_tombstones',
            where: 'entity_type = ? AND entity_id = ?',
            whereArgs: [
              'financial_profiles',
              FinancialProfile.defaultProfileId,
            ],
          ),
          isEmpty,
        );
        await database.close();
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );
}
