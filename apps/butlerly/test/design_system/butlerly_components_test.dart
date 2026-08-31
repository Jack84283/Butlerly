import 'package:butlerly/app/theme/app_theme.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_button.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/foundation/presentation/add_page.dart';
import 'package:butlerly/features/foundation/presentation/payment_sources_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('data-entry pages use semantic theme backgrounds and surfaces', (
    tester,
  ) async {
    for (final theme in [AppTheme.light, AppTheme.dark]) {
      for (final page in [const AddPage(), const PaymentSourcesPage()]) {
        await tester.pumpWidget(MaterialApp(theme: theme, home: page));
        await tester.pumpAndSettle();

        final colors = theme.extension<ButlerlySemanticColors>()!;
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is ColoredBox && widget.color == colors.background,
          ),
          findsOneWidget,
        );
        for (final card in tester.widgetList<Card>(find.byType(Card))) {
          expect(card.color ?? theme.cardTheme.color, colors.surface);
        }
      }
    }
  });

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
    expect(find.byType(OutlinedButton), findsOneWidget);
    expect(
      tester.widget<OutlinedButton>(find.byType(OutlinedButton)).style,
      isNull,
    );
  });

  testWidgets('secondary text action aligns its label to the leading edge', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: ButlerlySecondaryTextAction(
            onPressed: () {},
            child: const Text('View image'),
          ),
        ),
      ),
    );

    final button = tester.widget<TextButton>(find.byType(TextButton));
    expect(button.style?.alignment, Alignment.centerLeft);
    expect(find.text('View image'), findsOneWidget);
  });

  testWidgets('button bar owns responsive start-aligned action layout', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: ButlerlyButtonBar(
            alignment: ButlerlyButtonBarAlignment.start,
            density: ButlerlyButtonBarDensity.compact,
            children: [
              OutlinedButton(onPressed: () {}, child: const Text('Edit')),
              FilledButton(onPressed: () {}, child: const Text('Save')),
            ],
          ),
        ),
      ),
    );

    final wrap = tester.widget<Wrap>(find.byType(Wrap));
    expect(wrap.alignment, WrapAlignment.start);
    expect(wrap.spacing, ButlerlySpacing.compact);
    expect(wrap.runSpacing, ButlerlySpacing.compact);
    expect(find.byType(OutlinedButton), findsOneWidget);
    expect(find.byType(FilledButton), findsOneWidget);
    final buttonContext = tester.element(find.byType(OutlinedButton));
    final compactStyle = Theme.of(buttonContext).outlinedButtonTheme.style!;
    expect(
      compactStyle.padding?.resolve({}),
      const EdgeInsets.symmetric(
        horizontal: ButlerlyButtonTokens.compactHorizontalPadding,
        vertical: ButlerlyButtonTokens.compactVerticalPadding,
      ),
    );
    expect(
      compactStyle.minimumSize?.resolve({}),
      const Size(
        ButlerlyButtonTokens.compactMinimumHeight,
        ButlerlyButtonTokens.compactVisualHeight,
      ),
    );
    expect(compactStyle.tapTargetSize, MaterialTapTargetSize.padded);
  });

  testWidgets('button bar supports zero vertical spacing', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: ButlerlyButtonBar(
            alignment: ButlerlyButtonBarAlignment.start,
            density: ButlerlyButtonBarDensity.compact,
            spacing: ButlerlyButtonBarSpacing.none,
            children: [
              OutlinedButton(onPressed: () {}, child: const Text('Edit')),
            ],
          ),
        ),
      ),
    );

    final padding = tester.widget<Padding>(find.byType(Padding).first);
    expect(padding.padding, EdgeInsets.zero);
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
