import 'package:flutter/material.dart';

abstract final class ButlerlySpacing {
  static const micro = 4.0;
  static const compact = 8.0;
  static const small = 12.0;
  static const standard = 16.0;
  static const section = 24.0;
  static const large = 32.0;
  static const major = 48.0;
  static const structural = 64.0;
  static const modalHorizontal = standard;
  static const modalBottom = standard;
  static const modalItem = standard;

  // Semantic aliases keep feature layouts declarative while preserving the
  // shared spacing scale above.
  static const pagePadding = standard;
  static const contentPadding = standard;
  static const cardPadding = small;
  static const cardGap = small;
  static const sectionSpacing = section;
  static const compactActionSpacing = compact;
  static const bottomActionSpacing = section;
}

/// Stable categorical colors shared by charts and their legends.
abstract final class ButlerlyChartColors {
  static const categoryPalette = <Color>[
    Color(0xFF0072B2), // blue
    Color(0xFFE69F00), // amber
    Color(0xFF009E73), // green
    Color(0xFFD55E00), // orange
    Color(0xFFCC79A7), // purple
    Color(0xFF56B4E9), // sky
    Color(0xFFF0E442), // yellow
    Color(0xFF882255), // wine
  ];

  /// Returns a deterministic palette color for a category identifier.
  ///
  /// The palette is finite by design. Identifiers beyond its capacity reuse a
  /// palette entry based on a stable string hash rather than creating shades.
  static Color category(String categoryId) {
    var hash = 0;
    for (final codeUnit in categoryId.codeUnits) {
      hash = (hash * 31 + codeUnit) & 0x7fffffff;
    }
    return categoryPalette[hash % categoryPalette.length];
  }
}

abstract final class ButlerlyRadius {
  static const small = 6.0;
  static const standard = 10.0;
  static const large = 16.0;
  static const full = 999.0;
}

abstract final class ButlerlySize {
  static const minimumTarget = 44.0;
  static const preferredTarget = 48.0;
  static const phoneBreakpoint = 600.0;
  static const desktopBreakpoint = 1024.0;
  static const phoneGutter = 16.0;
  static const tabletGutter = 24.0;
  static const desktopGutter = 32.0;
  static const readableWidth = 760.0;
  static const stateContentWidth = 520.0;
  static const recordRowMinHeight = 72.0;
  static const compactActionIconSize = 18.0;
  static const sourcePreviewWidth = 64.0;
  static const sourcePreviewHeight = 80.0;
}

abstract final class ButlerlyMotion {
  static const fast = Duration(milliseconds: 120);
  static const standard = Duration(milliseconds: 200);
  static const deliberate = Duration(milliseconds: 300);

  static Duration responsive(BuildContext context, Duration duration) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;
}

abstract final class ButlerlyElevation {
  static const base = 0.0;
  static const raised = 1.0;
  static const overlay = 4.0;
  static const modal = 8.0;
}
