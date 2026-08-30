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
