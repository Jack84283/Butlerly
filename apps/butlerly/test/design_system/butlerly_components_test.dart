import 'package:butlerly/app/theme/app_theme.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shared loading state is available in both themes', (
    tester,
  ) async {
    for (final theme in [AppTheme.light, AppTheme.dark]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const Scaffold(body: ButlerlyLoadingState(message: 'Loading')),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Loading'), findsOneWidget);
    }
  });

  testWidgets('review actions inherit localized labels from the app', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: ButlerlyReviewCard(
            title: 'Review',
            reason: 'Reason',
            recommendation: 'Recommendation',
            primaryLabel: 'Confirm',
            onPrimary: () {},
            onEdit: () {},
            onDismiss: () {},
          ),
        ),
      ),
    );

    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Dismiss'), findsOneWidget);
  });
}
