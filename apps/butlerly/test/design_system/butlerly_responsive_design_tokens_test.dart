import 'package:butlerly/app/theme/app_theme.dart';
import 'package:butlerly/design_system/theme/butlerly_responsive_design_tokens.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Compact Home type is reduced without changing Medium or Wide', () {
    final compact = ButlerlyHomeTypographyTokens.forMode(
      ButlerlyLayoutMode.compact,
    );
    final medium = ButlerlyHomeTypographyTokens.forMode(
      ButlerlyLayoutMode.medium,
    );
    final wide = ButlerlyHomeTypographyTokens.forMode(ButlerlyLayoutMode.wide);

    expect(compact.brand, 24);
    expect(compact.greeting, 20);
    expect(compact.cardTitle, 14);
    expect(compact.summaryAmount, 20);
    expect(compact.categoryText, 13);
    expect(compact.chartLabel, 12);
    expect(medium.brand, 32);
    expect(medium.greeting, 24);
    expect(medium.cardTitle, 16);
    expect(medium.summaryAmount, 24);
    expect(wide.greeting, 16);
    expect(wide.cardTitle, medium.cardTitle);
    expect(wide.summaryAmount, medium.summaryAmount);
  });

  test('Semantic gutters, inner card padding and card gaps remain aligned', () {
    for (final mode in ButlerlyLayoutMode.values) {
      final spacing = ButlerlyGeometryTokens.forMode(mode);
      expect(spacing.pageGutter, ButlerlySize.contentGutter);
      expect(spacing.cardPadding, ButlerlySpacing.cardPadding);
      expect(spacing.cardGap, ButlerlySpacing.cardGap);
      expect(spacing.innerCardGutter, 12);
      expect(spacing.innerCardPadding, 12);
    }
  });

  testWidgets('Resolved design uses the active light/dark palette', (
    tester,
  ) async {
    for (final theme in [AppTheme.light, AppTheme.dark]) {
      ButlerlyResponsiveDesignTokens? design;
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Builder(
            builder: (context) {
              design = context.designTokens;
              return const Scaffold(body: SizedBox.shrink());
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      final colors = theme.extension<ButlerlySemanticColors>()!;
      expect(design?.colors.background, colors.background);
      expect(design?.colors.primaryText, colors.primaryText);
      expect(design?.colors.interactive, colors.interactive);
      expect(design?.homeColors.onMetric, Colors.white);
      expect(design?.geometry.cardGap, ButlerlySpacing.cardGap);
    }
  });
}
