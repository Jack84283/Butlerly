import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AdaptiveShell extends StatelessWidget {
  const AdaptiveShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  void _selectDestination(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  List<NavigationDestination> _destinations(BuildContext context) => [
    NavigationDestination(
      icon: const Icon(Icons.home_outlined),
      selectedIcon: const Icon(Icons.home_rounded),
      label: context.l10n.text('home'),
    ),
    NavigationDestination(
      icon: const Icon(Icons.receipt_long_outlined),
      selectedIcon: const Icon(Icons.receipt_long_rounded),
      label: context.l10n.text('transactions'),
    ),
    NavigationDestination(
      icon: const Icon(Icons.fact_check_outlined),
      selectedIcon: const Icon(Icons.fact_check_rounded),
      label: context.l10n.text('review'),
    ),
    NavigationDestination(
      icon: const Icon(Icons.search_outlined),
      selectedIcon: const Icon(Icons.search_rounded),
      label: context.l10n.text('search'),
    ),
    NavigationDestination(
      icon: const Icon(Icons.settings_outlined),
      selectedIcon: const Icon(Icons.settings_rounded),
      label: context.l10n.text('settings'),
    ),
  ];

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final destinations = _destinations(context);
      if (constraints.maxWidth < ButlerlySize.phoneBreakpoint) {
        return Scaffold(
          body: SafeArea(bottom: false, child: navigationShell),
          bottomNavigationBar: NavigationBar(
            selectedIndex: navigationShell.currentIndex,
            onDestinationSelected: _selectDestination,
            destinations: destinations,
          ),
        );
      }

      final extended = constraints.maxWidth >= ButlerlySize.desktopBreakpoint;
      return Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              NavigationRail(
                extended: extended,
                selectedIndex: navigationShell.currentIndex,
                onDestinationSelected: _selectDestination,
                leading: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: ButlerlySpacing.standard,
                  ),
                  child: Column(
                    children: [
                      if (extended)
                        Text(
                          context.l10n.text('appName'),
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(color: context.colors.brandStrong),
                        )
                      else
                        Icon(
                          Icons.shield_outlined,
                          color: context.colors.brandStrong,
                        ),
                      const SizedBox(height: ButlerlySpacing.standard),
                      FilledButton.icon(
                        onPressed: () => context.push('/add'),
                        icon: const Icon(Icons.add_rounded),
                        label: extended
                            ? Text(context.l10n.text('addData'))
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
                destinations: destinations
                    .map(
                      (destination) => NavigationRailDestination(
                        icon: destination.icon,
                        selectedIcon: destination.selectedIcon,
                        label: Text(destination.label),
                      ),
                    )
                    .toList(growable: false),
              ),
              const VerticalDivider(width: 1),
              Expanded(child: navigationShell),
            ],
          ),
        ),
      );
    },
  );
}
