import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:flutter/material.dart';

/// Single 1px solid gold rule at the bottom of desktop AppBars and SliverAppBars.
///
/// The desktop-only AppBar theme leaves device headers unchanged.
class ButlerlyDesktopGoldBottomBorder extends ShapeBorder {
  const ButlerlyDesktopGoldBottomBorder({
    this.thickness = ButlerlyGoldAccentTokens.thickness,
  });

  final double thickness;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.only(bottom: thickness);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      Path()..addRect(rect);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      Path()..addRect(rect);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (rect.isEmpty || thickness <= 0) return;
    canvas.drawRect(
      Rect.fromLTWH(
        rect.left,
        rect.bottom - thickness,
        rect.width,
        thickness,
      ),
      Paint()..color = ButlerlyGoldAccentTokens.desktopDividerGold,
    );
  }

  @override
  ShapeBorder scale(double t) =>
      ButlerlyDesktopGoldBottomBorder(thickness: thickness * t);
}

/// Single 1px solid gold line above desktop right-panel action footers.
class ButlerlyDesktopGoldDivider extends StatelessWidget {
  const ButlerlyDesktopGoldDivider({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox(
    height: ButlerlyGoldAccentTokens.thickness,
    child: ColoredBox(color: ButlerlyGoldAccentTokens.desktopDividerGold),
  );
}

/// Solid 1px gold line along the desktop navigation panel's right edge.
///
/// The shape border reserves its width within the rail so collapsed icons stay
/// centered consistently, without affecting device navigation.
class ButlerlyDesktopGoldRightBorder extends ShapeBorder {
  const ButlerlyDesktopGoldRightBorder({
    this.thickness = ButlerlyGoldAccentTokens.thickness,
  });

  final double thickness;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.only(right: thickness);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      Path()..addRect(rect);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      Path()..addRect(rect);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (rect.isEmpty || thickness <= 0) return;
    canvas.drawRect(
      Rect.fromLTWH(rect.right - thickness, rect.top, thickness, rect.height),
      Paint()..color = ButlerlyGoldAccentTokens.desktopDividerGold,
    );
  }

  @override
  ShapeBorder scale(double t) =>
      ButlerlyDesktopGoldRightBorder(thickness: thickness * t);
}

/// Full-height single 1px gold line separating desktop results/details.
class ButlerlyDesktopGoldVerticalDivider extends StatelessWidget {
  const ButlerlyDesktopGoldVerticalDivider({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox(
    width: ButlerlyGoldAccentTokens.thickness,
    height: double.infinity,
    child: ColoredBox(color: ButlerlyGoldAccentTokens.desktopDividerGold),
  );
}
