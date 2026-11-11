import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:flutter/material.dart';

/// Two solid gold bands at the bottom of desktop AppBars and SliverAppBars.
///
/// Each band is 1px high (deep gold above light gold), with no gradient.
/// The desktop-only theme keeps device AppBars unchanged.
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
    final stripeHeight = thickness / 2;
    canvas.drawRect(
      Rect.fromLTWH(
        rect.left,
        rect.bottom - thickness,
        rect.width,
        stripeHeight,
      ),
      Paint()..color = ButlerlyGoldAccentTokens.deepGold,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        rect.left,
        rect.bottom - stripeHeight,
        rect.width,
        stripeHeight,
      ),
      Paint()..color = ButlerlyGoldAccentTokens.lightGold,
    );
  }

  @override
  ShapeBorder scale(double t) =>
      ButlerlyDesktopGoldBottomBorder(thickness: thickness * t);
}

/// Full-width, two-stripe solid separator above desktop panel action footers.
class ButlerlyDesktopGoldDivider extends StatelessWidget {
  const ButlerlyDesktopGoldDivider({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox(
    height: ButlerlyGoldAccentTokens.thickness,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: ButlerlyGoldAccentTokens.stripeHeight,
          child: ColoredBox(color: ButlerlyGoldAccentTokens.deepGold),
        ),
        SizedBox(
          height: ButlerlyGoldAccentTokens.stripeHeight,
          child: ColoredBox(color: ButlerlyGoldAccentTokens.lightGold),
        ),
      ],
    ),
  );
}
