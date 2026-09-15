import 'package:butlerly/app/butlerly_app.dart';
import 'package:butlerly/app/router/app_router.dart';
import 'package:butlerly/features/foundation/presentation/first_use_preferences_page.dart';
import 'package:butlerly/features/foundation/presentation/restore_recovery_required_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => appRouter.go('/launch'));
  tearDown(() => appRouter.go('/'));

  testWidgets(
    'production app keeps the branded cold-launch surface before Home',
    (tester) async {
      await tester.pumpWidget(const ProviderScope(child: ButlerlyApp()));
      await tester.pump();

      expect(appRouter.routeInformationProvider.value.uri.path, '/launch');
      expect(
        find.byKey(const ValueKey('butlerly-launch-screen')),
        findsOneWidget,
      );
      expect(find.byType(FirstUsePreferencesPage), findsNothing);
      expect(find.byType(RestoreRecoveryRequiredPage), findsNothing);

      await tester.pump(const Duration(seconds: 4, milliseconds: 999));
      expect(appRouter.routeInformationProvider.value.uri.path, '/launch');
      expect(
        find.byKey(const ValueKey('butlerly-launch-screen')),
        findsOneWidget,
      );
      expect(find.byType(FirstUsePreferencesPage), findsNothing);
      expect(find.byType(RestoreRecoveryRequiredPage), findsNothing);

      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();

      expect(appRouter.routeInformationProvider.value.uri.path, '/');
      expect(
        find.byKey(const ValueKey('butlerly-launch-screen')),
        findsNothing,
      );

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
