import 'dart:io';

import 'package:butlerly/core/config/app_configuration.dart';
import 'package:butlerly/core/database/local_database.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/core/logging/app_logger.dart';
import 'package:butlerly/features/financial_profile/presentation/financial_profile_page.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly_database/butlerly_database.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  late Directory root;
  late LocalDatabase database;

  setUp(() async {
    await services.reset();
    root = await Directory.systemTemp.createTemp('butlerly-financial-profile-');
    database = LocalDatabase(
      logger: AppLogger(),
      factory: databaseFactoryFfi,
      databaseDirectory: root.path,
    );
    await database.initialize();
    configureDependencies(
      configuration: const AppConfiguration(),
      database: database,
      logger: AppLogger(),
    );
  });

  tearDown(() async {
    await services.reset();
    await database.close();
    await root.delete(recursive: true);
  });

  Widget app({Locale locale = const Locale('en'), bool onboarding = false}) =>
      ProviderScope(
        child: MaterialApp(
          locale: locale,
          themeMode: ThemeMode.light,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: FinancialProfilePage(onboarding: onboarding)),
        ),
      );

  testWidgets('completes with all optional questions unanswered', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await _pumpUntilVisible(
      tester,
      find.byKey(const ValueKey('financial-profile-edit')),
    );
    await tester.tap(find.byKey(const ValueKey('financial-profile-edit')));
    await tester.pumpAndSettle();
    expect(find.text('Household'), findsOneWidget);

    for (var step = 0; step < 3; step++) {
      await _tapSurveyAction(
        tester,
        const ValueKey('financial-profile-continue'),
      );
      await tester.pumpAndSettle();
    }
    await _tapSurveyAction(tester, const ValueKey('financial-profile-save'));
    await _pumpWithRealAsync(tester);

    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('0 of 11 questions answered'), findsOneWidget);
    final stored = await tester.runAsync(
      () =>
          SqliteFinancialProfileRepository(database.persistenceDatabase).load(),
    );
    expect(stored?.status, FinancialProfileStatus.completed);
    expect(stored?.answeredQuestionCount, 0);
  });

  testWidgets('cancel discards unsaved answers', (tester) async {
    await tester.pumpWidget(app());
    await _pumpUntilVisible(
      tester,
      find.byKey(const ValueKey('financial-profile-edit')),
    );
    await tester.tap(find.byKey(const ValueKey('financial-profile-edit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(RadioListTile<HouseholdSize>).first);
    await _tapSurveyAction(
      tester,
      const ValueKey('financial-profile-continue'),
    );
    await _tapSurveyAction(tester, const ValueKey('financial-profile-cancel'));
    await tester.pumpAndSettle();

    expect(find.text('No Financial Profile yet.'), findsOneWidget);
    final stored = await tester.runAsync(
      () =>
          SqliteFinancialProfileRepository(database.persistenceDatabase).load(),
    );
    expect(stored, isNull);
  });

  testWidgets('formats a savings target with the Spanish decimal separator', (
    tester,
  ) async {
    await tester.pumpWidget(app(locale: const Locale('es')));
    await _pumpUntilVisible(
      tester,
      find.byKey(const ValueKey('financial-profile-edit')),
    );
    await tester.tap(find.byKey(const ValueKey('financial-profile-edit')));
    await tester.pumpAndSettle();
    for (var step = 0; step < 2; step++) {
      await _tapSurveyAction(
        tester,
        const ValueKey('financial-profile-continue'),
      );
    }
    await tester.pumpAndSettle();
    final targetOptions = find.byType(RadioListTile<bool>);
    await tester.tap(targetOptions.last);
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('financial-profile-savings-target')),
      '12,50',
    );
    for (var step = 0; step < 1; step++) {
      await _tapSurveyAction(
        tester,
        const ValueKey('financial-profile-continue'),
      );
    }
    await _tapSurveyAction(tester, const ValueKey('financial-profile-save'));
    await _pumpWithRealAsync(tester);

    expect(find.text('Perfil financiero'), findsOneWidget);
    expect(find.textContaining('12,5'), findsOneWidget);
  });

  testWidgets('survey remains usable at large text size', (tester) async {
    tester.view.platformDispatcher.textScaleFactorTestValue = 3;
    addTearDown(tester.view.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(app(onboarding: true));
    await _pumpUntilVisible(tester, find.text('Step 1 of 4'));

    expect(tester.takeException(), isNull);
    expect(find.text('Step 1 of 4'), findsOneWidget);
  });
}

Future<void> _pumpUntilVisible(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for the requested widget.');
}

Future<void> _tapSurveyAction(WidgetTester tester, ValueKey<String> key) async {
  final action = find.byKey(key);
  await tester.scrollUntilVisible(
    action,
    400,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(action);
}

Future<void> _pumpWithRealAsync(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  await tester.pumpAndSettle();
}
