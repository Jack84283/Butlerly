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

  var requiredHeight =
      ButlerlySize.primaryNavigationAddIconSize +
      ButlerlySpacing.xxs +
      labelHeight(addLabel);

  for (final label in standardLabels) {
    final destinationHeight =
        ButlerlySize.standardIcon +
        ButlerlySize.navigationLabelGap +
        labelHeight(label);
    if (destinationHeight > requiredHeight) {
      requiredHeight = destinationHeight;
    }
  }

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
              icon,
              SizedBox(
                height: add
                    ? ButlerlySpacing.xxs
                    : ButlerlySize.navigationLabelGap,
              ),
              Text(
                destination.label,
                textAlign: TextAlign.center,
                softWrap: true,
                style: labelStyle,
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
                    decoration: BoxDecoration(
                      color: navigationColor,
                      border: Border(top: divider),
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
                        height: ButlerlySize.primaryNavigationArchHeight,
                        decoration: BoxDecoration(
                          color: navigationColor,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(
                              ButlerlySize.primaryNavigationArchWidth / 2,
                            ),
                          ),
                        ),
                        foregroundDecoration: _PrimaryNavigationArchEdge(
                          color: divider.color,
                          width: divider.width,
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

class _PrimaryNavigationArchEdge extends Decoration {
  const _PrimaryNavigationArchEdge({
    required this.color,
    required this.width,
  });

  final Color color;
  final double width;

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _PrimaryNavigationArchEdgePainter(color: color, width: width);
}

class _PrimaryNavigationArchEdgePainter extends BoxPainter {
  _PrimaryNavigationArchEdgePainter({
    required this.color,
    required this.width,
  });

  final Color color;
  final double width;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size;
    if (size == null) return;

    final rect = offset & size;
    final radius = ButlerlySize.primaryNavigationArchWidth / 2;
    final rrect = BorderRadius.vertical(
      top: Radius.circular(radius),
    ).toRRect(rect);

    canvas.save();
    canvas.clipRect(
      Rect.fromLTWH(
        rect.left - width,
        rect.top - width,
        rect.width + (width * 2),
        ButlerlySize.primaryNavigationArchRise + width,
      ),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..color = color,
    );
    canvas.restore();
  }
}
