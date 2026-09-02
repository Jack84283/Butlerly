import 'package:flutter/material.dart';

abstract final class ButlerlySpacing {
  static const none = 0.0;
  static const xxs = 2.0;
  static const xs = micro;
  static const sm = compact;
  static const md = standard;
  static const lg = section;
  static const xl = large;
  static const xxl = major;
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
  /// Analysis series colors. This palette is intentionally separate from the
  /// persistent eight-color category identity palette below the theme layer.
  static const categoryPalette = <Color>[
    Color(0xFF0072B2), // blue
    Color(0xFFE69F00), // amber
    Color(0xFF009E73), // green
    Color(0xFFD55E00), // orange
    Color(0xFFCC79A7), // purple
    Color(0xFF56B4E9), // sky
    Color(0xFFF0E442), // yellow
    Color(0xFF882255), // wine
    Color(0xFF332288), // indigo
    Color(0xFF117733), // forest
    Color(0xFF44AA99), // teal
    Color(0xFF88CCEE), // cyan
    Color(0xFFDDCC77), // sand
    Color(0xFFAA4499), // violet
    Color(0xFF661100), // brown
    Color(0xFF999933), // olive
    Color(0xFF1B9E77), // emerald
    Color(0xFFD95F02), // pumpkin
    Color(0xFF7570B3), // periwinkle
    Color(0xFFE7298A), // magenta
    Color(0xFF66A61E), // leaf
    Color(0xFFE6AB02), // gold
    Color(0xFFA6761D), // ochre
    Color(0xFF666666), // charcoal
    Color(0xFF3B5BA5), // cobalt
    Color(0xFFB2182B), // crimson
    Color(0xFF2166AC), // ocean
    Color(0xFF762A83), // plum
    Color(0xFF1B7837), // pine
    Color(0xFFB35806), // sienna
    Color(0xFF5E3C99), // grape
    Color(0xFF4D9221), // moss
  ];

  /// Returns a deterministic palette color for a category identifier.
  ///
  /// The palette is finite by design. Identifiers beyond its capacity reuse a
  /// palette entry based on a stable string hash rather than creating shades.
  static Color category(String categoryId) {
    return categoryPalette[_paletteIndex(categoryId)];
  }

  /// Assigns unique colors to visible categories while palette colors remain.
  ///
  /// IDs are sorted before collision resolution so the result is independent
  /// of query order. Once all 32 colors are in use, the stable base color is
  /// reused for additional categories.
  static Map<String, Color> forCategories(Iterable<String> categoryIds) {
    final ids = categoryIds.toSet().toList()..sort();
    final assigned = <String, Color>{};
    final used = <int>{};
    for (final id in ids) {
      final base = _paletteIndex(id);
      var index = base;
      while (used.contains(index) && used.length < categoryPalette.length) {
        index = (index + 1) % categoryPalette.length;
      }
      assigned[id] = categoryPalette[index];
      used.add(index);
    }
    return assigned;
  }

  static int _paletteIndex(String categoryId) {
    var hash = 0;
    for (final codeUnit in categoryId.codeUnits) {
      hash = (hash * 31 + codeUnit) & 0x7fffffff;
    }
    return hash % categoryPalette.length;
  }
}

abstract final class ButlerlyRadius {
  static const small = 6.0;
  static const standard = 10.0;
  static const large = 16.0;
  static const full = 999.0;
  static const control = small;
  static const input = standard;
  static const card = standard;
  static const sheet = large;
  static const dialog = large;
  static const pill = full;
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

  /// Maximum width for page content on larger viewports.
  ///
  /// Phone layouts remain constrained by the page gutters; larger layouts use
  /// this value to keep content readable instead of stretching edge to edge.
  static const pageContentMaxWidth = readableWidth;
  static const stateContentWidth = 520.0;
  static const recordRowMinHeight = 72.0;
  static const standardIcon = 24.0;
  static const categoryIconGlyph = 24.0;
  static const categoryIconContainer = 40.0;
  static const compactActionIconSize = 18.0;
  static const navigationLabelGap = ButlerlySpacing.xxs;
  static const sourcePreviewWidth = 64.0;
  static const sourcePreviewHeight = 80.0;
  static const navigationBarHeight = 72.0;
}

abstract final class ButlerlyMotion {
  static const fast = Duration(milliseconds: 120);
  static const standard = Duration(milliseconds: 200);
  static const deliberate = Duration(milliseconds: 300);
  static const long = deliberate;
  static const curve = Curves.easeInOut;

  static Duration responsive(BuildContext context, Duration duration) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;
}

abstract final class ButlerlyAccessibility {
  static const minimumContrastRatio = 4.5;
  static const minimumTouchTarget = ButlerlySize.minimumTarget;
}

abstract final class ButlerlyElevation {
  static const base = 0.0;
  static const raised = 1.0;
  static const overlay = 4.0;
  static const modal = 8.0;
  static const card = raised;
  static const dialog = modal;
  static const bottomSheet = modal;
  static const floating = overlay;
}
