import 'package:butlerly/features/tools/presentation/tools_page.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('Tools exposes payment settlements as a secondary workflow', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/tools',
      routes: [
        GoRoute(
          path: '/tools',
          builder: (_, _) => const ToolsPage(),
        ),
        GoRoute(
          path: '/payment-settlements',
          builder: (_, _) => const Scaffold(
            body: Text('payment-settlement-route'),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Payment settlements'), findsOneWidget);

    await tester.tap(find.text('Payment settlements'));
    await tester.pumpAndSettle();

    expect(find.text('payment-settlement-route'), findsOneWidget);
  });
}
