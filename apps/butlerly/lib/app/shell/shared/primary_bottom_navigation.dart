import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/design_system/tokens/butlerly_typography.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

double compactNavigationHeightForLabels({
  required TextScaler textScaler,
  required double itemWidth,
  required Iterable<String> standardLabels,
  String? addLabel,
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

  var maximumLabelHeight = addLabel == null ? 0.0 : labelHeight(addLabel);
  for (final label in standardLabels) {
    final height = labelHeight(label);
    if (height > maximumLabelHeight) {
      maximumLabelHeight = height;
    }
  }

  final requiredHeight =
      ButlerlySize.primaryNavigationAddIconSize +
      maximumLabelHeight +
      2 * ButlerlySize.dividerWidth;

  return requiredHeight < ButlerlySize.navigationBarHeight
      ? ButlerlySize.navigationBarHeight
      : requiredHeight;
}

String compactNavigationLabel(
  BuildContext context,
  NavigationDestination destination,
  int branchIndex,
) => switch (branchIndex) {
  0 => context.l10n.text('homeCompact'),
  1 => context.l10n.text('transactionsCompact'),
  2 => context.l10n.text('addCompact'),
  3 => context.l10n.text('toolsCompact'),
  4 => context.l10n.text('moreCompact'),
  _ => destination.label,
};

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
    final isAddAction = branchIndex == 2;
    final visibleLabel = compactNavigationLabel(
      context,
      destination,
      branchIndex,
    );
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
    final icon = IconTheme(
      data: IconThemeData(
        size: isAddAction
            ? ButlerlySize.primaryNavigationAddGlyphSize
            : ButlerlySize.standardIcon,
        color: isAddAction
            ? Theme.of(context).colorScheme.onPrimary
            : selected
            ? context.colors.interactive
            : context.colors.secondaryText,
      ),
      child: baseIcon,
    );
    return Semantics(
      button: true,
      selected: selected,
      onTap: () => onSelected(branchIndex),
      label: isAddAction
          ? context.l10n.text('addTransactionAction')
          : destination.label,
      excludeSemantics: true,
      child: InkWell(
        onTap: () => onSelected(branchIndex),
        child: SizedBox(
          height: double.infinity,
          child: isAddAction
              ? Center(
                  child: Container(
                    key: const ValueKey('primary-navigation-add-button'),
                    width: ButlerlySize.primaryNavigationAddIconSize,
                    height: ButlerlySize.primaryNavigationAddIconSize,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: icon,
                  ),
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      height:
                          ButlerlySize.primaryNavigationAddIconSize -
                          ButlerlySize.navigationLabelGap,
                      child: Align(alignment: Alignment.center, child: icon),
                    ),
                    const SizedBox(height: ButlerlySize.navigationLabelGap),
                    SizedBox(
                      key: ValueKey('primary-navigation-label-$branchIndex'),
                      width: double.infinity,
                      height: labelSlotHeight,
                      child: Text(
                        visibleLabel,
                        softWrap: true,
                        overflow: TextOverflow.visible,
                        textAlign: TextAlign.center,
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
    return compactNavigationHeightForLabels(
      textScaler: MediaQuery.textScalerOf(context),
      itemWidth: availableWidth / visualBranchIndexes.length,
      standardLabels: [
        for (final branchIndex in visualBranchIndexes)
          if (branchIndex != 2)
            compactNavigationLabel(
              context,
              destinations[branchIndex]!,
              branchIndex,
            ),
      ],
      addLabel: null,
      labelStyle: labelStyle,
      textDirection: Directionality.of(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    final navigationColor =
        Theme.of(context).navigationBarTheme.backgroundColor ??
        context.colors.surface;
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
            height: navigationHeight + ButlerlySpacing.compact + bottomInset,
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(
                  top: ButlerlySpacing.compact,
                  left: ButlerlySpacing.standard,
                  right: ButlerlySpacing.standard,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 390),
                  child: Container(
                    key: const ValueKey('primary-navigation-pill'),
                    width: double.infinity,
                    height: navigationHeight,
                    decoration: BoxDecoration(
                      color: navigationColor,
                      borderRadius: BorderRadius.circular(ButlerlyRadius.pill),
                      border: Border.all(
                        width: ButlerlySize.dividerWidth,
                        color: context.colors.cardDivider.withValues(
                          alpha: ButlerlyOpacity.primaryNavigationBorder,
                        ),
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Row(
                      key: const ValueKey('primary-navigation-content'),
                      children: [
                        for (final branchIndex in visualBranchIndexes)
                          Expanded(
                            child: _destination(
                              context,
                              destinations[branchIndex]!,
                              branchIndex,
                              navigationHeight -
                                  ButlerlySize.primaryNavigationAddIconSize -
                                  2 * ButlerlySize.dividerWidth,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
