import 'package:butlerly/app/theme/app_theme.dart';
import 'package:butlerly/features/foundation/presentation/add_page.dart';
import 'package:butlerly/features/foundation/presentation/home_page.dart';
import 'package:butlerly/features/foundation/presentation/payment_sources_page.dart';
import 'package:butlerly/features/foundation/presentation/receipt_capture_page.dart';
import 'package:butlerly/features/foundation/presentation/review_page.dart';
import 'package:butlerly/features/foundation/presentation/search_page.dart';
import 'package:butlerly/features/foundation/presentation/settings_page.dart';
import 'package:butlerly/features/foundation/presentation/transaction_master_data.dart';
import 'package:butlerly/features/foundation/presentation/transactions_page.dart';
import 'package:butlerly/features/tools/presentation/tools_page.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const cases = [
    (Size(320, 568), Brightness.light, Locale('en'), 1.0),
    (Size(390, 844), Brightness.dark, Locale('es'), 1.5),
    (Size(430, 932), Brightness.light, Locale('zh', 'CN'), 2.0),
    (Size(900, 800), Brightness.dark, Locale('zh', 'CN'), 1.5),
  ];
  final pages = <String, Widget Function()>{
    'Home': () => const HomePage(),
    'Transactions': () => const TransactionsPage(),
    'Review': () => const ReviewPage(),
    'Search': () => const SearchPage(),
    'More': () => const SettingsPage(),
    'Tools': () => const ToolsPage(),
    'Add': () => const AddPage(),
    'Payment Sources': () => const PaymentSourcesPage(),
    'Receipt Capture': () => ReceiptCapturePage(
      loadInitialData: () async => const ReceiptCaptureInitialData(
        preference: null,
        snapshot: TransactionMasterDataSnapshot(
          presentation: TransactionMasterData(),
          merchants: [],
          categories: [],
          tags: [],
          paymentSources: [],
        ),
      ),
    ),
  };

  for (final entry in pages.entries) {
    for (final testCase in cases) {
      testWidgets(
        '${entry.key} remains operable at ${testCase.$1.width}x${testCase.$1.height}, '
        '${testCase.$3.languageCode}, scale ${testCase.$4}',
        (tester) async {
          tester.view.physicalSize = testCase.$1;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final theme = testCase.$2 == Brightness.dark
              ? AppTheme.dark
              : AppTheme.light;
          await tester.pumpWidget(
            ProviderScope(
              child: MaterialApp(
                theme: theme,
                locale: testCase.$3,
                supportedLocales: AppLocalizations.supportedLocales,
                localizationsDelegates: const [
                  AppLocalizations.delegate,
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                home: MediaQuery(
                  data: MediaQueryData(
                    size: testCase.$1,
                    textScaler: TextScaler.linear(testCase.$4),
                  ),
                  child: entry.value(),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
