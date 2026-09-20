import 'dart:math' as math;

import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/design_system/tokens/butlerly_typography.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

double phoneNavigationHeightForLabels({
  required TextScaler textScaler,
  required double itemWidth,
  required Iterable<String> standardLabels,
  required String addLabel,
  required TextStyle labelStyle,
  required TextDirection textDirection,
}) {
  final availableWidth = itemWidth > 0 ? itemWidth : double.minPositive;

  double labelHeight(String label) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: labelStyle),
      textScaler: textScaler,
      textDirection: textDirection,
      textAlign: TextAlign.center,
    )..layout(maxWidth: availableWidth);
    return painter.height;
  }

  var maximumLabelHeight = labelHeight(addLabel);
  for (final label in standardLabels) {
    final height = labelHeight(label);
    if (height > maximumLabelHeight) {
      maximumLabelHeight = height;
    }
  }

  final requiredHeight =
      ButlerlySize.primaryNavigationAddIconSize + maximumLabelHeight;

  return requiredHeight < ButlerlySize.navigationBarHeight
      ? ButlerlySize.navigationBarHeight
      : requiredHeight;
}

class PrimaryBottomNavigation extends StatelessWidget {
  const PrimaryBottomNavigation({
    required this.navigationKey,
    required this.destinations,
    required this.visualBranchIndexes,
    required this.currentIndex,
    required this.onSelected,
    super.key,
  });

  final Key navigationKey;
  final Map<int, NavigationDestination> destinations;
  final List<int> visualBranchIndexes;
  final int currentIndex;
  final ValueChanged<int> onSelected;

  Widget _destination(
    BuildContext context,
    NavigationDestination destination,
    int branchIndex,
    double labelSlotHeight,
  ) {
    final selected = currentIndex == branchIndex;
    final add = branchIndex == 1;
    final labelStyle = ButlerlyTypography.navigationLabel(
      Theme.of(context).textTheme.labelSmall!,
      color: selected
          ? context.colors.interactive
          : context.colors.secondaryText,
      selected: selected,
    );
    final baseIcon = selected
        ? (destination.selectedIcon ?? destination.icon)
        : destination.icon;
    final icon = add
        ? Container(
            width: ButlerlySize.primaryNavigationAddIconSize,
            height: ButlerlySize.primaryNavigationAddIconSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected
                  ? context.colors.brandStrong
                  : context.colors.selection,
              border: Border.all(
                width: ButlerlySize.dividerWidth,
                color: context.colors.interactive.withValues(
                  alpha: ButlerlyOpacity.primaryNavigationBorder,
                ),
              ),
            ),
            child: IconTheme(
              data: IconThemeData(
                size: ButlerlySize.primaryNavigationAddGlyphSize,
                color: selected
                    ? Theme.of(context).colorScheme.onPrimary
                    : context.colors.interactive,
              ),
              child: baseIcon,
            ),
          )
        : IconTheme(
            data: IconThemeData(
              size: ButlerlySize.standardIcon,
              color: selected
                  ? context.colors.interactive
                  : context.colors.secondaryText,
            ),
            child: baseIcon,
          );
    final iconSlot = SizedBox(
      height: ButlerlySize.primaryNavigationAddIconSize,
      child: Center(
        child: add
            ? Transform.translate(
                offset: const Offset(
                  0,
                  -ButlerlySize.primaryNavigationAddLift,
                ),
                child: icon,
              )
            : icon,
      ),
    );

    return Semantics(
      button: true,
      selected: selected,
      label: add
          ? context.l10n.text('addTransactionAction')
          : destination.label,
      excludeSemantics: true,
      child: InkWell(
        onTap: () => onSelected(branchIndex),
        child: SizedBox(
          height: double.infinity,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              iconSlot,
              const SizedBox(height: ButlerlySpacing.none),
              SizedBox(
                width: double.infinity,
                height: labelSlotHeight,
                child: Text(
                  destination.label,
                  textAlign: TextAlign.center,
                  softWrap: true,
                  style: labelStyle,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  double _navigationHeight(BuildContext context, double availableWidth) {
    final labelStyle = ButlerlyTypography.navigationLabel(
      Theme.of(context).textTheme.labelSmall!,
      color: context.colors.secondaryText,
      selected: true,
    );
    return phoneNavigationHeightForLabels(
      textScaler: MediaQuery.textScalerOf(context),
      itemWidth: availableWidth / visualBranchIndexes.length,
      standardLabels: [
        for (final branchIndex in visualBranchIndexes)
          if (branchIndex != 1) destinations[branchIndex]!.label,
      ],
      addLabel: destinations[1]!.label,
      labelStyle: labelStyle,
      textDirection: Directionality.of(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    final navigationColor =
        Theme.of(context).navigationBarTheme.backgroundColor ??
        context.colors.background;
    final divider = BorderSide(
      width: ButlerlySize.dividerWidth,
      color: context.colors.cardDivider,
    );
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Material(
      key: navigationKey,
      color: Colors.transparent,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final navigationHeight = _navigationHeight(
            context,
            constraints.maxWidth,
          );
          return SizedBox(
            height: navigationHeight + bottomInset,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: _PrimaryNavigationBase(
                      fillColor: navigationColor,
                      edgeColor: divider.color,
                      edgeWidth: divider.width,
                      hasAddArch: visualBranchIndexes.contains(1),
                    ),
                  ),
                ),
                if (visualBranchIndexes.contains(1))
                  Positioned(
                    left: 0,
                    right: 0,
                    top: -ButlerlySize.primaryNavigationArchRise,
                    child: Center(
                      child: Container(
                        key: const ValueKey('primary-navigation-add-arch'),
                        width: ButlerlySize.primaryNavigationArchWidth,
                        height: ButlerlySize.primaryNavigationArchRise,
                        decoration: _PrimaryNavigationCircularArch(
                          fillColor: navigationColor,
                          edgeColor: divider.color,
                          edgeWidth: divider.width,
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: navigationHeight,
                  child: SizedBox(
                    key: const ValueKey('primary-navigation-content'),
                    height: navigationHeight,
                    child: Row(
                      children: [
                        for (final branchIndex in visualBranchIndexes)
                          Expanded(
                            child: _destination(
                              context,
                              destinations[branchIndex]!,
                              branchIndex,
                              navigationHeight -
                                  ButlerlySize.primaryNavigationAddIconSize,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _PrimaryNavigationBase extends Decoration {
  const _PrimaryNavigationBase({
    required this.fillColor,
    required this.edgeColor,
    required this.edgeWidth,
    required this.hasAddArch,
  });

  final Color fillColor;
  final Color edgeColor;
  final double edgeWidth;
  final bool hasAddArch;

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _PrimaryNavigationBasePainter(
        fillColor: fillColor,
        edgeColor: edgeColor,
        edgeWidth: edgeWidth,
        hasAddArch: hasAddArch,
      );
}

class _PrimaryNavigationBasePainter extends BoxPainter {
  _PrimaryNavigationBasePainter({
    required this.fillColor,
    required this.edgeColor,
    required this.edgeWidth,
    required this.hasAddArch,
  });

  final Color fillColor;
  final Color edgeColor;
  final double edgeWidth;
  final bool hasAddArch;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size;
    if (size == null) return;

    final rect = offset & size;
    canvas.drawRect(
      rect,
      Paint()
        ..style = PaintingStyle.fill
        ..color = fillColor,
    );

    final edgePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = edgeWidth
      ..strokeCap = StrokeCap.butt
      ..color = edgeColor;
    final boundaryY = rect.top;
    if (!hasAddArch) {
      canvas.drawLine(
        Offset(rect.left, boundaryY),
        Offset(rect.right, boundaryY),
        edgePaint,
      );
      return;
    }

    final radius = ButlerlySize.primaryNavigationArchWidth / 2;
    final centerY = radius - ButlerlySize.primaryNavigationArchRise;
    final halfChord = math.sqrt(radius * radius - centerY * centerY);
    final centerX = rect.center.dx;
    canvas.drawLine(
      Offset(rect.left, boundaryY),
      Offset(centerX - halfChord, boundaryY),
      edgePaint,
    );
    canvas.drawLine(
      Offset(centerX + halfChord, boundaryY),
      Offset(rect.right, boundaryY),
      edgePaint,
    );
  }
}

class _PrimaryNavigationCircularArch extends Decoration {
  const _PrimaryNavigationCircularArch({
    required this.fillColor,
    required this.edgeColor,
    required this.edgeWidth,
  });

  final Color fillColor;
  final Color edgeColor;
  final double edgeWidth;

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _PrimaryNavigationCircularArchPainter(
        fillColor: fillColor,
        edgeColor: edgeColor,
        edgeWidth: edgeWidth,
      );
}

class _PrimaryNavigationCircularArchPainter extends BoxPainter {
  _PrimaryNavigationCircularArchPainter({
    required this.fillColor,
    required this.edgeColor,
    required this.edgeWidth,
  });

  final Color fillColor;
  final Color edgeColor;
  final double edgeWidth;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size;
    if (size == null) return;

    final radius = ButlerlySize.primaryNavigationArchWidth / 2;
    final circle = Rect.fromCircle(
      center: Offset(offset.dx + size.width / 2, offset.dy + radius),
      radius: radius,
    );
    final clip = offset & size;

    canvas.save();
    canvas.clipRect(clip);

    canvas.drawCircle(
      circle.center,
      radius,
      Paint()
        ..style = PaintingStyle.fill
        ..color = fillColor,
    );

    canvas.drawArc(
      circle,
      math.pi,
      math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = edgeWidth
        ..strokeCap = StrokeCap.round
        ..color = edgeColor,
    );

    canvas.restore();
  }
}
