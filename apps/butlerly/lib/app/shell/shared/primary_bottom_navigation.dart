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

  final scaledLabelFontSize = textScaler.scale(
    ButlerlyTypography.navigationLabelFontSize,
  );
  final normalScale =
      scaledLabelFontSize <= ButlerlyTypography.navigationLabelFontSize + 0.01;

  if (normalScale) {
    return ButlerlySize.navigationBarHeight;
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
    final labelStyle = ButlerlyTypography.navigationLabel(
      Theme.of(context).textTheme.labelSmall!,
      color: selected
          ? context.colors.interactive
          : context.colors.secondaryText,
      selected: selected,
    );
    final textScaler = MediaQuery.textScalerOf(context);
    final normalScale =
        textScaler.scale(ButlerlyTypography.navigationLabelFontSize) <=
        ButlerlyTypography.navigationLabelFontSize + 0.01;
    final baseIcon = selected
        ? (destination.selectedIcon ?? destination.icon)
        : destination.icon;
    final icon = IconTheme(
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
      label: branchIndex == 1
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
              SizedBox(
                key: branchIndex == 1
                    ? const ValueKey('primary-navigation-add-button')
                    : null,
                height:
                    ButlerlySize.primaryNavigationAddIconSize -
                    ButlerlySize.navigationLabelGap,
                child: Align(alignment: Alignment.bottomCenter, child: icon),
              ),
              const SizedBox(height: ButlerlySize.navigationLabelGap),
              SizedBox(
                width: double.infinity,
                height: labelSlotHeight,
                child: Text(
                  destination.label,
                  textAlign: TextAlign.center,
                  softWrap: !normalScale,
                  maxLines: normalScale ? 1 : null,
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
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    key: const ValueKey('primary-navigation-base'),
                    decoration: BoxDecoration(
                      color: navigationColor,
                      border: Border(top: divider),
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
