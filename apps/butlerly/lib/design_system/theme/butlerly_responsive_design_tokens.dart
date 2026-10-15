import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/design_system/tokens/butlerly_typography.dart';
import 'package:flutter/material.dart';

/// Design values are resolved in one place from the current layout mode and
/// theme. Screens should use semantic roles instead of checking widths or
/// brightness for individual text, color, padding, or gutter decisions.
@immutable
class ButlerlyResponsiveDesignTokens {
  const ButlerlyResponsiveDesignTokens({
    required this.mode,
    required this.colors,
    required this.homeTypography,
    required this.homeColors,
    required this.geometry,
  });

  final ButlerlyLayoutMode mode;
  final ButlerlySemanticColors colors;
  final ButlerlyHomeTypographyTokens homeTypography;
  final ButlerlyHomeColorTokens homeColors;
  final ButlerlyGeometryTokens geometry;

  static ButlerlyResponsiveDesignTokens of(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    // Match the shell's tablet-landscape promotion to Wide.
    final tabletLandscape =
        size.width > size.height &&
        size.shortestSide >= 500 &&
        size.width >= ButlerlySize.compactBreakpoint;
    final mode = ButlerlyLayout.modeForWidth(
      size.width,
      tabletLandscape: tabletLandscape,
    );
    return forMode(mode, colors: context.colors);
  }

  /// Injectable, deterministic resolver for unit and golden tests.
  static ButlerlyResponsiveDesignTokens forMode(
    ButlerlyLayoutMode mode, {
    required ButlerlySemanticColors colors,
  }) => ButlerlyResponsiveDesignTokens(
    mode: mode,
    colors: colors,
    homeTypography: ButlerlyHomeTypographyTokens.forMode(mode),
    homeColors: ButlerlyHomeColorTokens.forMode(mode),
    geometry: ButlerlyGeometryTokens.forMode(mode),
  );
}

extension ButlerlyResponsiveDesignContext on BuildContext {
  ButlerlyResponsiveDesignTokens get designTokens =>
      ButlerlyResponsiveDesignTokens.of(this);
}

/// Semantic Home typography. Compact is one step smaller; Medium retains its
/// approved sizes and desktop/Wide keeps its separate header hierarchy.
/// Colors and weights are inherited from the canonical theme typography.
@immutable
class ButlerlyHomeTypographyTokens {
  const ButlerlyHomeTypographyTokens({
    required this.brand,
    required this.greeting,
    required this.description,
    required this.cardTitle,
    required this.summaryLabel,
    required this.summaryAmount,
    required this.trendAmount,
    required this.trendChange,
    required this.chartLabel,
    required this.categoryText,
    required this.categoryMetadata,
    required this.attentionTitle,
    required this.attentionSubtitle,
  });

  final double brand;
  final double greeting;
  final double description;
  final double cardTitle;
  final double summaryLabel;
  final double summaryAmount;
  final double trendAmount;
  final double trendChange;
  final double chartLabel;
  final double categoryText;
  final double categoryMetadata;
  final double attentionTitle;
  final double attentionSubtitle;

  static const compact = ButlerlyHomeTypographyTokens(
    brand: 24,
    greeting: 20,
    description: 13,
    cardTitle: 14,
    summaryLabel: 14,
    summaryAmount: 20,
    trendAmount: 20,
    trendChange: 13,
    chartLabel: 12,
    categoryText: 13,
    categoryMetadata: 12,
    attentionTitle: 14,
    attentionSubtitle: 13,
  );

  static const medium = ButlerlyHomeTypographyTokens(
    brand: 32,
    greeting: 24,
    description: 14,
    cardTitle: 16,
    summaryLabel: 16,
    summaryAmount: 24,
    trendAmount: 24,
    trendChange: 14,
    chartLabel: 13,
    categoryText: 14,
    categoryMetadata: 13,
    attentionTitle: 16,
    attentionSubtitle: 14,
  );

  // Wide has its own desktop Home composition and is intentionally unchanged.
  static const wide = medium;

  static ButlerlyHomeTypographyTokens forMode(ButlerlyLayoutMode mode) =>
      switch (mode) {
        ButlerlyLayoutMode.compact => compact,
        ButlerlyLayoutMode.medium => medium,
        ButlerlyLayoutMode.wide => wide,
      };

  TextStyle appTitle(TextStyle base) => ButlerlyTypography.editorialText(
    ButlerlyTypography.pageHeroTitle(base),
  ).copyWith(fontSize: brand);

  TextStyle greetingTitle(TextStyle base) =>
      ButlerlyTypography.homeGreetingTitle(base).copyWith(fontSize: greeting);

  TextStyle subtitle(TextStyle base) =>
      ButlerlyTypography.cardSubtitle(base).copyWith(fontSize: description);

  TextStyle sectionTitle(TextStyle base) =>
      ButlerlyTypography.compactCardTitle(base).copyWith(fontSize: cardTitle);

  TextStyle trendValue(TextStyle base) =>
      ButlerlyTypography.metricValue(base).copyWith(fontSize: trendAmount);

  TextStyle trendComparison(TextStyle base) =>
      ButlerlyTypography.metricChange(base).copyWith(fontSize: trendChange);

  TextStyle axisLabel(TextStyle base) =>
      ButlerlyTypography.badgeLabel(base).copyWith(fontSize: chartLabel);

  TextStyle categoryTitle(TextStyle base) =>
      ButlerlyTypography.compactRowTitle(base).copyWith(fontSize: categoryText);

  TextStyle categoryAmount(TextStyle base) =>
      ButlerlyTypography.compactRowAmount(
        base,
      ).copyWith(fontSize: categoryText);

  TextStyle categoryDetails(TextStyle base) =>
      ButlerlyTypography.compactRowMetadata(
        base,
      ).copyWith(fontSize: categoryMetadata);

  TextStyle reviewTitle(TextStyle base) =>
      ButlerlyTypography.rowTitle(base).copyWith(fontSize: attentionTitle);

  TextStyle reviewSubtitle(TextStyle base) => ButlerlyTypography.rowMetadata(
    base,
  ).copyWith(fontSize: attentionSubtitle);
}

/// Shared Home financial accent and on-tint colors. The same semantic
/// accents work in light and dark themes; surface/text colors come from the
/// current ButlerlySemanticColors palette in the resolved design tokens.
@immutable
class ButlerlyHomeColorTokens {
  const ButlerlyHomeColorTokens({
    required this.income,
    required this.spending,
    required this.net,
    required this.onMetric,
    required this.onMetricMuted,
  });

  final Color income;
  final Color spending;
  final Color net;
  final Color onMetric;
  final Color onMetricMuted;

  static const standard = ButlerlyHomeColorTokens(
    income: Color(0xFF009B61),
    spending: Color(0xFFE24247),
    net: Color(0xFF1769E8),
    onMetric: Colors.white,
    onMetricMuted: Colors.white70,
  );

  static ButlerlyHomeColorTokens forMode(ButlerlyLayoutMode mode) => standard;
}

/// Semantic geometry for pages and reusable components. Geometry can vary by
/// mode without scattering conditionals or hard-coded pixels across screens.
/// The current values preserve the approved Home gutters and card spacing.
@immutable
class ButlerlyGeometryTokens {
  const ButlerlyGeometryTokens({
    required this.pageGutter,
    required this.cardPadding,
    required this.cardGap,
    required this.innerCardGutter,
    required this.innerCardPadding,
    required this.contentGap,
  });

  final double pageGutter;
  final double cardPadding;
  final double cardGap;
  final double innerCardGutter;
  final double innerCardPadding;
  final double contentGap;

  static const compact = ButlerlyGeometryTokens(
    pageGutter: ButlerlySize.contentGutter,
    cardPadding: ButlerlySpacing.cardPadding,
    cardGap: ButlerlySpacing.cardGap,
    innerCardGutter: ButlerlySpacing.small,
    innerCardPadding: ButlerlySpacing.small,
    contentGap: ButlerlySpacing.compact,
  );

  static const medium = compact;
  static const wide = compact;

  static ButlerlyGeometryTokens forMode(ButlerlyLayoutMode mode) =>
      switch (mode) {
        ButlerlyLayoutMode.compact => compact,
        ButlerlyLayoutMode.medium => medium,
        ButlerlyLayoutMode.wide => wide,
      };
}
