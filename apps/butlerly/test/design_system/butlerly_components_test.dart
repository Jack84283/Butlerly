import 'package:butlerly/app/theme/app_theme.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
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

  testWidgets('compact action button uses the shared icon-size token', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: ButlerlyCompactActionButton(
            onPressed: () {},
            icon: Icons.save_outlined,
            child: const Text('Save'),
          ),
        ),
      ),
    );

    expect(
      tester.widget<Icon>(find.byIcon(Icons.save_outlined)).size,
      ButlerlySize.compactActionIconSize,
    );
  });

  testWidgets('destructive action uses the centralized error treatment', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: ButlerlyDestructiveButton(
            onPressed: () {},
            child: const Text('Delete'),
          ),
        ),
      ),
    );

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    final style = button.style!;
    expect(
      style.backgroundColor?.resolve({}),
      AppTheme.light.colorScheme.error,
    );
    expect(
      style.foregroundColor?.resolve({}),
      AppTheme.light.colorScheme.onError,
    );
  });
}
