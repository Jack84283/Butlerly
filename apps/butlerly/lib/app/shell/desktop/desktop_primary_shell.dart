import 'package:butlerly/app/shell/shared/primary_bottom_navigation.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

class DesktopPrimaryShell extends StatelessWidget {
  const DesktopPrimaryShell({
    required this.body,
    required this.destinations,
    required this.visualBranchIndexes,
    required this.currentIndex,
    required this.onSelected,
    super.key,
  });

  final Widget body;
  final Map<int, NavigationDestination> destinations;
  final List<int> visualBranchIndexes;
  final int currentIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context);
    final navigationMode = ButlerlyLayout.desktopNavigationMode(viewport);

    if (navigationMode == ButlerlyDesktopNavigationMode.bottom) {
      return Scaffold(
        body: SafeArea(
          bottom: false,
          child: ColoredBox(
            key: const ValueKey('primary-desktop-compact-body-surface'),
            color: context.colors.subtleSurface,
            child: body,
          ),
        ),
        bottomNavigationBar: PrimaryBottomNavigation(
          navigationKey: const ValueKey('primary-desktop-compact-navigation'),
          destinations: destinations,
          visualBranchIndexes: visualBranchIndexes,
          currentIndex: currentIndex,
          onSelected: onSelected,
        ),
      );
    }

    final selectedVisualIndex = visualBranchIndexes.indexOf(currentIndex);
    final extended =
        navigationMode == ButlerlyDesktopNavigationMode.extendedRail;

    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            NavigationRail(
              key: const ValueKey('primary-desktop-navigation'),
              extended: extended,
              selectedIndex: selectedVisualIndex,
              onDestinationSelected: (visualIndex) =>
                  onSelected(visualBranchIndexes[visualIndex]),
              leading: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: ButlerlySpacing.section,
                ),
                child: extended
                    ? Text(
                        context.l10n.text('appName'),
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(color: context.colors.primaryText),
                      )
                    : Icon(
                        Icons.circle,
                        size: ButlerlySize.desktopNavigationLeadingIconSize,
                        color: context.colors.interactive,
                      ),
              ),
              destinations: [
                for (final branchIndex in visualBranchIndexes)
                  NavigationRailDestination(
                    icon: destinations[branchIndex]!.icon,
                    selectedIcon: destinations[branchIndex]!.selectedIcon,
                    label: Text(destinations[branchIndex]!.label),
                  ),
              ],
            ),
            VerticalDivider(
              width: ButlerlySize.dividerWidth,
              color: context.colors.cardDivider,
            ),
            Expanded(
              child: ColoredBox(
                key: const ValueKey('primary-desktop-body-surface'),
                color: context.colors.subtleSurface,
                child: body,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
