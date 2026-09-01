import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AdaptiveShell extends StatelessWidget {
  const AdaptiveShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  void _selectDestination(int index) => navigationShell.goBranch(
    index,
    initialLocation: index == navigationShell.currentIndex,
  );

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
      icon: const Icon(Icons.build_outlined),
      selectedIcon: const Icon(Icons.build_rounded),
      label: context.l10n.text('tools'),
    ),
    NavigationDestination(
      icon: const Icon(Icons.settings_outlined),
      selectedIcon: const Icon(Icons.settings_rounded),
      label: context.l10n.text('more'),
    ),
  ];

  Widget _addButton(BuildContext context) => Tooltip(
    message: context.l10n.text('addTransactionAction'),
    child: Semantics(
      button: true,
      label: context.l10n.text('addTransactionAction'),
      child: IconButton.filled(
        onPressed: () => context.push('/add'),
        icon: const Icon(Icons.add_rounded),
        iconSize: 30,
        style: IconButton.styleFrom(
          minimumSize: const Size.square(ButlerlySize.preferredTarget),
          backgroundColor: context.colors.interactive,
          foregroundColor: Theme.of(context).colorScheme.onPrimary,
        ),
      ),
    ),
  );

  Widget _destination(
    BuildContext context,
    NavigationDestination destination,
    int index,
  ) {
    final selected = navigationShell.currentIndex == index;
    return Semantics(
      button: true,
      selected: selected,
      label: destination.label,
      child: InkWell(
        onTap: () => _selectDestination(index),
        child: SizedBox(
          height: double.infinity,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              selected
                  ? (destination.selectedIcon ?? destination.icon)
                  : destination.icon,
              const SizedBox(height: 2),
              Text(
                destination.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: selected
                      ? context.colors.interactive
                      : context.colors.secondaryText,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _phoneNavigation(BuildContext context) {
    final destinations = _destinations(context);
    return Material(
      color: Theme.of(context).navigationBarTheme.backgroundColor,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 80,
          child: Row(
            children: [
              Expanded(child: _destination(context, destinations[0], 0)),
              Expanded(child: _destination(context, destinations[1], 1)),
              Expanded(child: _addButton(context)),
              Expanded(child: _destination(context, destinations[2], 2)),
              Expanded(child: _destination(context, destinations[3], 3)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < ButlerlySize.phoneBreakpoint) {
        return Scaffold(
          body: SafeArea(bottom: false, child: navigationShell),
          bottomNavigationBar: _phoneNavigation(context),
        );
      }

      final extended = constraints.maxWidth >= ButlerlySize.desktopBreakpoint;
      final destinations = _destinations(context);
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
                      _addButton(context),
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
