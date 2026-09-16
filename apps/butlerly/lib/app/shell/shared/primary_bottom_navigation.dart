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
  final availableWidth = itemWidth > 0 ? itemWidth : 1.0;

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
      ButlerlySpacing.micro +
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
                color: context.colors.interactive.withValues(
                  alpha: ButlerlyOpacity.primaryNavigationBorder,
                ),
              ),
            ),
            child: IconTheme(
              data: IconThemeData(
                size: ButlerlySize.primaryNavigationAddGlyphSize,
                color: selected ? Colors.white : context.colors.interactive,
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
                    ? ButlerlySpacing.micro
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
  Widget build(BuildContext context) => DecoratedBox(
    key: navigationKey,
    decoration: BoxDecoration(
      color: Theme.of(context).navigationBarTheme.backgroundColor,
      border: Border(
        top: BorderSide(
          width: ButlerlySize.dividerWidth,
          color: context.colors.cardDivider,
        ),
      ),
    ),
    child: Material(
      type: MaterialType.transparency,
      child: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) => SizedBox(
            height: _navigationHeight(context, constraints.maxWidth),
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
      ),
    ),
  );
}
