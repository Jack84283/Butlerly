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
        await SqliteFinancialProfileRepository(database).clear();
        expect(await SqliteFinancialProfileRepository(database).load(), isNull);
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
