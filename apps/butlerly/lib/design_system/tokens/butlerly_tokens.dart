import 'package:flutter/foundation.dart';
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

  static const pagePadding = small;
  static const contentPadding = standard;
  static const cardPadding = small;
  static const cardGap = small;
  static const sectionSpacing = section;
  static const compactActionSpacing = compact;
  static const bottomActionSpacing = section;
  static const pinnedControlTopGap = compact;
  static const periodSelectorGap = standard;
  static const periodPinnedHeaderTopGap = none;
  static const periodPinnedHeaderBottomGap = none;
  static const periodPinnedBodyGap = none;
}

/// Stable categorical colors shared by charts and their legends.
abstract final class ButlerlyChartColors {
  static const _stableCategoryPaletteLength = 32;

  static const categoryPalette = <Color>[
    Color(0xFF0072B2),
    Color(0xFFE69F00),
    Color(0xFF009E73),
    Color(0xFFD55E00),
    Color(0xFFCC79A7),
    Color(0xFF56B4E9),
    Color(0xFFF0E442),
    Color(0xFF882255),
    Color(0xFF332288),
    Color(0xFF117733),
    Color(0xFF44AA99),
    Color(0xFF88CCEE),
    Color(0xFFDDCC77),
    Color(0xFFAA4499),
    Color(0xFF661100),
    Color(0xFF999933),
    Color(0xFF1B9E77),
    Color(0xFFD95F02),
    Color(0xFF7570B3),
    Color(0xFFE7298A),
    Color(0xFF66A61E),
    Color(0xFFE6AB02),
    Color(0xFFA6761D),
    Color(0xFF666666),
    Color(0xFF3B5BA5),
    Color(0xFFB2182B),
    Color(0xFF2166AC),
    Color(0xFF762A83),
    Color(0xFF1B7837),
    Color(0xFFB35806),
    Color(0xFF5E3C99),
    Color(0xFF4D9221),
    Color(0xFF1F77B4),
    Color(0xFFFF7F0E),
    Color(0xFF2CA02C),
    Color(0xFFD62728),
    Color(0xFF9467BD),
    Color(0xFF8C564B),
    Color(0xFFE377C2),
    Color(0xFF17BECF),
    Color(0xFF393B79),
    Color(0xFF637939),
    Color(0xFF8C6D31),
    Color(0xFF843C39),
    Color(0xFF7B4173),
    Color(0xFF3182BD),
    Color(0xFF31A354),
    Color(0xFF756BB1),
  ];

  static Color category(String categoryId) {
    return categoryPalette[_paletteIndex(categoryId)];
  }

  static List<Color> distinctSeriesColors(Iterable<Color?> requestedColors) {
    final resolved = <Color>[];
    final used = <Color>{};

    bool isSeparated(Color candidate) =>
        !used.contains(candidate) &&
        used.every((color) => !_colorsTooClose(color, candidate));

    Color nextPaletteColor() {
      for (final candidate in categoryPalette) {
        if (isSeparated(candidate)) return candidate;
      }
      for (final candidate in categoryPalette) {
        if (!used.contains(candidate)) return candidate;
      }
      return categoryPalette[resolved.length % categoryPalette.length];
    }

    for (final requested in requestedColors) {
      final color = requested != null && isSeparated(requested)
          ? requested
          : nextPaletteColor();
      resolved.add(color);
      used.add(color);
    }
    return resolved;
  }

  static bool _colorsTooClose(Color left, Color right) {
    final red = (left.r - right.r) * 255;
    final green = (left.g - right.g) * 255;
    final blue = (left.b - right.b) * 255;
    return red * red + green * green + blue * blue < 3600;
  }

  static Map<String, Color> forCategories(Iterable<String> categoryIds) {
    final ids = categoryIds.toSet().toList()..sort();
    final assigned = <String, Color>{};
    final used = <int>{};
    for (final id in ids) {
      final base = _paletteIndex(id);
      var index = base;
      while (used.contains(index) &&
          used.length < _stableCategoryPaletteLength) {
        index = (index + 1) % _stableCategoryPaletteLength;
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
    return hash % _stableCategoryPaletteLength;
  }
}

abstract final class ButlerlyRadius {
  static const small = 6.0;
  static const standard = 12.0;
  static const large = 18.0;
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
  static const compactPageToolbarHeight = 40.0;
  static const refreshIndicatorDisplacement = compactPageToolbarHeight;
  static const phoneBreakpoint = 600.0;
  static const tabletBreakpoint = phoneBreakpoint;
  static const desktopBreakpoint = 1024.0;
  static const phoneContentMaxWidth = 600.0;
  static const phoneGutter = 12.0;
  static const tabletGutter = 24.0;
  static const desktopGutter = 32.0;
  static const readableWidth = 760.0;
  static const pageContentMaxWidth = readableWidth;
  static const stateContentWidth = 520.0;
  static const recordRowMinHeight = 68.0;
  static const standardIcon = 24.0;
  static const categoryIconGlyph = 24.0;
  static const categoryIconContainer = 40.0;
  static const compactActionIconSize = 18.0;
  static const navigationLabelGap = ButlerlySpacing.xxs;
  static const sourcePreviewWidth = 64.0;
  static const sourcePreviewHeight = 80.0;
  static const navigationBarHeight = 60.0;
  static const primaryNavigationAddIconSize = 44.0;
  static const primaryNavigationAddGlyphSize = 28.0;
  static const primaryNavigationArchRise = 12.0;
  static const primaryNavigationArchWidth = 76.0;
  static const primaryNavigationArchHeight = 32.0;
  static const searchPinnedHeaderHeight =
      minimumTarget + ButlerlySpacing.pinnedControlTopGap;
  static const analysisPeriodSelectorHeight =
      preferredTarget + ButlerlySpacing.section;
  static const desktopNavigationLeadingIconSize = 14.0;
  static const dividerWidth = 1.0;
}

abstract final class ButlerlyOpacity {
  static const primaryNavigationBorder = 0.55;
}

enum ButlerlyDeviceClass { phone, tablet, desktop }

enum ButlerlyDesktopNavigationMode { bottom, rail, extendedRail }

/// Semantic responsive-layout policy. Device shell identity is intentionally
/// separate from the current window size so an iPad remains an iPad while its
/// app window is resized. Content sizing still follows the current viewport.
abstract final class ButlerlyLayout {
  static ButlerlyDeviceClass deviceClass(
    Size viewport, {
    TargetPlatform? platform,
    Size? deviceDisplaySize,
  }) {
    final resolvedPlatform = platform ?? defaultTargetPlatform;
    switch (resolvedPlatform) {
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
        return ButlerlyDeviceClass.desktop;
      case TargetPlatform.iOS:
        final identitySize = deviceDisplaySize ?? viewport;
        return identitySize.shortestSide >= ButlerlySize.tabletBreakpoint
            ? ButlerlyDeviceClass.tablet
            : ButlerlyDeviceClass.phone;
      case TargetPlatform.android:
      case TargetPlatform.fuchsia:
        return viewport.shortestSide >= ButlerlySize.tabletBreakpoint
            ? ButlerlyDeviceClass.tablet
            : ButlerlyDeviceClass.phone;
    }
  }

  /// Preserves the pre-device-split desktop behavior until the dedicated
  /// desktop menu/submenu redesign replaces it.
  static ButlerlyDesktopNavigationMode desktopNavigationMode(Size viewport) {
    if (viewport.width >= ButlerlySize.desktopBreakpoint) {
      return ButlerlyDesktopNavigationMode.extendedRail;
    }
    if (viewport.shortestSide >= ButlerlySize.tabletBreakpoint) {
      return ButlerlyDesktopNavigationMode.rail;
    }
    return ButlerlyDesktopNavigationMode.bottom;
  }

  static bool desktopNavigationExtended(Size viewport) =>
      desktopNavigationMode(viewport) ==
      ButlerlyDesktopNavigationMode.extendedRail;

  static double contentMaxWidth(Size viewport, {TargetPlatform? platform}) {
    final device = deviceClass(viewport, platform: platform);
    final compactDesktop =
        device == ButlerlyDeviceClass.desktop &&
        desktopNavigationMode(viewport) == ButlerlyDesktopNavigationMode.bottom;
    return device == ButlerlyDeviceClass.phone || compactDesktop
        ? ButlerlySize.phoneContentMaxWidth
        : ButlerlySize.pageContentMaxWidth;
  }
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
  static const raised = 0.0;
  static const overlay = 4.0;
  static const modal = 8.0;
  static const card = raised;
  static const dialog = modal;
  static const bottomSheet = modal;
  static const floating = overlay;
}
