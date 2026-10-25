import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/features/foundation/presentation/add_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('shows six localized grouped actions and preserves navigation', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => AddPage(
            onLocalFileImport: (context) => context.push('/import-export'),
          ),
        ),
        GoRoute(
          path: '/transactions/add',
          builder: (_, _) => const Text('transaction destination'),
        ),
        GoRoute(
          path: '/receipts/capture',
          builder: (_, _) => const Text('receipt destination'),
        ),
        GoRoute(
          path: '/statements',
          builder: (_, _) => const Text('statement destination'),
        ),
        GoRoute(
          path: '/import-export',
          builder: (_, _) => const Text('import from file destination'),
        ),
        GoRoute(
          path: '/budgets',
          builder: (_, _) => const Text('budgets destination'),
        ),
        GoRoute(
          path: '/payment-sources',
          builder: (_, _) => const Text('payment source destination'),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.byType(ButlerlyCard), findsNWidgets(3));
    expect(find.byType(Divider), findsNWidgets(3));
    expect(find.text('Add transaction manually'), findsOneWidget);
    expect(find.text('Budgets'), findsWidgets);
    expect(find.text('Enter transaction details yourself'), findsOneWidget);
    expect(find.text('Scan receipt'), findsOneWidget);
    expect(
      find.text('Scan a receipt to extract transaction details'),
      findsOneWidget,
    );
    expect(find.text('Import statement'), findsOneWidget);
    expect(
      find.text('Scan a statement to review and add transactions'),
      findsOneWidget,
    );
    expect(find.text('Import file'), findsOneWidget);
    expect(
      find.text('Import transaction from a supported transaction file'),
      findsOneWidget,
    );
    expect(
      find.text('Add and manage cards, accounts, and other payment sources'),
      findsOneWidget,
    );

    await tester.tap(find.text('Add transaction manually'));
    await tester.pumpAndSettle();
    expect(find.text('transaction destination'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.receipt_long_outlined));
    await tester.pumpAndSettle();
    expect(find.text('receipt destination'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.document_scanner_outlined));
    await tester.pumpAndSettle();
    expect(find.text('statement destination'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.file_open_outlined));
    await tester.pumpAndSettle();
    expect(find.text('import from file destination'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.account_balance_wallet_outlined));
    await tester.pumpAndSettle();
    expect(find.text('payment source destination'), findsOneWidget);
  });
  testWidgets('wide Add offers six cards across the right workspace', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var fileImportSelected = false;
    final router = GoRouter(
      initialLocation: '/add',
      routes: [
        GoRoute(
          path: '/add',
          builder: (context, _) => AddPage(
            onLocalFileImport: (_) async {
              fileImportSelected = true;
            },
          ),
        ),
        GoRoute(
          path: '/payment-sources',
          builder: (_, state) => Text(
            'payment source destination: '
            "${state.uri.queryParameters['create']}",
          ),
        ),
        GoRoute(
          path: '/transactions/add',
          builder: (_, _) => const Text('manual destination'),
        ),
        GoRoute(
          path: '/receipts/capture',
          builder: (_, _) => const Text('receipt destination'),
        ),
        GoRoute(
          path: '/statements',
          builder: (_, _) => const Text('statement destination'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('desktop-add-actions')), findsOneWidget);
    expect(find.byType(ButlerlyCard), findsNWidgets(6));
    expect(find.text('Add transaction manually'), findsOneWidget);
    expect(find.text('Add transaction from receipts'), findsOneWidget);
    expect(find.text('Import statement'), findsOneWidget);
    expect(find.text('Import from local file'), findsOneWidget);
    expect(find.text('Add payment source'), findsOneWidget);

    final first = tester.getRect(find.byType(ButlerlyCard).at(0));
    final second = tester.getRect(find.byType(ButlerlyCard).at(1));
    expect(second.left, greaterThan(first.right));
    expect(first.width, greaterThan(350));

    await tester.tap(find.text('Import from local file'));
    await tester.pumpAndSettle();
    expect(fileImportSelected, isTrue);

    await tester.tap(find.text('Add payment source'));
    await tester.pumpAndSettle();
    expect(find.text('payment source destination: true'), findsOneWidget);
  });
}
