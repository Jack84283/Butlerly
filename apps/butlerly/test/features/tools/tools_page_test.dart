import 'package:butlerly/features/tools/presentation/tools_page.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('Tools exposes finance utilities and operational management', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/tools',
      routes: [
        GoRoute(path: '/tools', builder: (_, _) => const ToolsPage()),
        GoRoute(
          path: '/payment-settlements',
          builder: (_, _) =>
              const Scaffold(body: Text('payment-settlement-route')),
        ),
        GoRoute(
          path: '/review',
          builder: (_, _) => const Scaffold(body: Text('review-route')),
        ),
        GoRoute(
          path: '/master-data',
          builder: (_, _) => const Scaffold(body: Text('master-data-route')),
        ),
        GoRoute(
          path: '/rules',
          builder: (_, _) => const Scaffold(body: Text('rules-route')),
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
    expect(find.text('Review'), findsOneWidget);
    expect(find.text('Master data'), findsOneWidget);
    expect(find.text('Rules'), findsOneWidget);
    expect(find.text('Payment sources'), findsNothing);

    await tester.tap(find.text('Payment settlements'));
    await tester.pumpAndSettle();

    expect(find.text('payment-settlement-route'), findsOneWidget);

    for (final entry in const {
      'Review': 'review-route',
      'Master data': 'master-data-route',
      'Rules': 'rules-route',
    }.entries) {
      router.go('/tools');
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text(entry.key),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text(entry.key));
      await tester.pumpAndSettle();
      expect(find.text(entry.value), findsOneWidget);
    }
  });
}
