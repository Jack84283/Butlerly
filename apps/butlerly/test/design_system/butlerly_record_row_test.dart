import 'package:butlerly/app/theme/app_theme.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/design_system/tokens/butlerly_transaction_item.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('possible duplicate indicator is accessible and navigable', (
    tester,
  ) async {
    var openedReview = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: ButlerlyRecordRow(
            title: 'Coffee',
            amount: '25.00',
            currency: 'USD',
            possibleDuplicate: true,
            possibleDuplicateLabel: 'Possible duplicate',
            onPossibleDuplicateTap: () => openedReview = true,
          ),
        ),
      ),
    );

    expect(find.bySemanticsLabel('Possible duplicate'), findsOneWidget);
    expect(find.byTooltip('Possible duplicate'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.warning_amber_rounded));
    expect(openedReview, isTrue);
  });

  testWidgets('non-duplicate rows do not render the indicator', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: ButlerlyRecordRow(
            title: 'Coffee',
            amount: '25.00',
            currency: 'USD',
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
  });

  testWidgets('common item renders compact three-line expense metadata', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: ButlerlyTransactionListItem(
            title: 'Safeway Store',
            subtitle: 'Food & Dining · Groceries · Personal',
            meta: 'Aug 14, 2026',
            amount: '42.19',
            currency: 'USD',
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.arrow_downward_rounded), findsOneWidget);
    expect(find.text('42.19 USD'), findsOneWidget);
    expect(find.text('Safeway Store'), findsOneWidget);
    expect(find.text('Food & Dining · Groceries · Personal'), findsOneWidget);
    expect(find.text('Aug 14, 2026'), findsOneWidget);
    expect(find.byType(Card), findsNothing);
  });

  testWidgets('canonical item uses signed amounts and renders optional tags', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: ButlerlyRecordRow(
            title: 'Whole Foods',
            amount: '82.47',
            currency: 'USD',
            categoryLabel: 'Groceries',
            subcategoryLabel: 'Supermarket',
            paymentSource: 'Visa ••••8421',
            tags: const ['Vacation', 'Family'],
            meta: 'Sep 2, 2026',
            showDate: true,
          ),
        ),
      ),
    );

    expect(find.text('−82.47 USD'), findsOneWidget);
    expect(find.text('Groceries · Supermarket'), findsOneWidget);
    expect(find.text('Visa ••••8421'), findsOneWidget);
    expect(find.text('Vacation'), findsOneWidget);
    expect(find.text('Family'), findsOneWidget);
    expect(find.text('Sep 2, 2026'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_downward_rounded), findsNothing);
  });

  testWidgets('canonical income item uses a plus sign', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: ButlerlyRecordRow(
            title: 'Payroll',
            amount: '4820.00',
            currency: 'USD',
            categoryLabel: 'Income',
            isIncome: true,
          ),
        ),
      ),
    );

    expect(find.text('+4820.00 USD'), findsOneWidget);
  });

  testWidgets('navigable item shows a decorative trailing chevron', (
    tester,
  ) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: ButlerlyTransactionListItem(
            title: 'Coffee',
            amount: '4.00',
            currency: 'USD',
            meta: 'Aug 14, 2026',
            onTap: () => tapped = true,
            showNavigationIndicator: true,
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
    final chevron = tester.widget<Icon>(
      find.byIcon(Icons.chevron_right_rounded),
    );
    expect(chevron.semanticLabel, isNull);
    await tester.tap(find.text('Coffee'));
    expect(tapped, isTrue);
  });

  testWidgets('non-navigable item omits the trailing chevron', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: ButlerlyTransactionListItem(
            title: 'Coffee',
            amount: '4.00',
            currency: 'USD',
            meta: 'Aug 14, 2026',
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
  });

  testWidgets('non-navigation tap does not imply a trailing chevron', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: ButlerlyTransactionListItem(
            title: 'Select me',
            amount: '4.00',
            currency: 'USD',
            onTap: () {},
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
  });

  testWidgets('transaction direction and review semantics are localized', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: ButlerlyTransactionListItem(
            title: 'Compra',
            amount: '4.00',
            currency: 'EUR',
            isIncome: true,
            needsReview: true,
          ),
        ),
      ),
    );

    expect(
      tester
          .widget<Icon>(find.byIcon(Icons.arrow_upward_rounded))
          .semanticLabel,
      'Ingresos',
    );
    expect(find.byTooltip('Necesita revisión'), findsOneWidget);
  });

  testWidgets('income uses upward direction and list dividers omit the last', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: ButlerlyTransactionList(
            children: const [
              ButlerlyTransactionListItem(
                title: 'Salary',
                amount: '100.00',
                currency: 'USD',
                isIncome: true,
              ),
              ButlerlyTransactionListItem(
                title: 'Coffee',
                amount: '4.00',
                currency: 'USD',
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
    expect(find.byType(Divider), findsOneWidget);
  });

  testWidgets('item typography comes from semantic transaction styles', (
    tester,
  ) async {
    final theme = AppTheme.light.copyWith(
      textTheme: AppTheme.light.textTheme.copyWith(
        titleMedium: const TextStyle(fontSize: 31, fontWeight: FontWeight.w300),
        bodyMedium: const TextStyle(fontSize: 23),
        bodySmall: const TextStyle(fontSize: 17),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: const ButlerlyTransactionListItem(
            title: 'Description',
            subtitle: 'Metadata',
            meta: 'Jan 1, 2026',
            amount: '1.00',
            currency: 'USD',
          ),
        ),
      ),
    );

    expect(tester.widget<Text>(find.text('1.00 USD')).style?.fontSize, 31);
    expect(tester.widget<Text>(find.text('Description')).style?.fontSize, 23);
    expect(tester.widget<Text>(find.text('Metadata')).style?.fontSize, 17);
    expect(
      ButlerlyTransactionItemTokens.horizontalInset,
      ButlerlySpacing.micro,
    );
    expect(ButlerlyTransactionItemTokens.topPadding, ButlerlySpacing.compact);
    expect(ButlerlyTransactionItemTokens.bottomPadding, ButlerlySpacing.micro);
    expect(ButlerlyTransactionItemTokens.dividerInset, ButlerlySpacing.micro);
    expect(ButlerlyTransactionItemTokens.minTouchHeight, 72);
  });
}
