import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AdaptiveShell extends StatefulWidget {
  const AdaptiveShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  State<AdaptiveShell> createState() => _AdaptiveShellState();
}

class _AdaptiveShellState extends State<AdaptiveShell> {
  int _previousPrimaryIndex = 0;

  StatefulNavigationShell get navigationShell => widget.navigationShell;

  void _selectDestination(int index) {
    final current = navigationShell.currentIndex;
    if (index != current) {
      _previousPrimaryIndex = current;
    }
    navigationShell.goBranch(
      index,
      initialLocation: index == current,
    );
  }

  Future<bool> _handleSystemBack() async {
    if (navigationShell.currentIndex != 2) return true;
    navigationShell.goBranch(_previousPrimaryIndex);
    return false;
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
      icon: const Icon(Icons.add_circle_outline_rounded),
      selectedIcon: const Icon(Icons.add_circle_rounded),
      label: context.l10n.text('add'),
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

  Widget _destination(
    BuildContext context,
    NavigationDestination destination,
    int index,
  ) {
    final selected = navigationShell.currentIndex == index;
    return Semantics(
      button: true,
      selected: selected,
      label: index == 2
          ? context.l10n.text('addTransactionAction')
          : destination.label,
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
              for (var index = 0; index < destinations.length; index++)
                Expanded(
                  child: _destination(context, destinations[index], index),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => WillPopScope(
    onWillPop: _handleSystemBack,
    child: LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < ButlerlySize.phoneBreakpoint) {
          return Scaffold(
            body: SafeArea(bottom: false, child: navigationShell),
            bottomNavigationBar: _phoneNavigation(context),
          );
        }

        final extended =
            constraints.maxWidth >= ButlerlySize.desktopBreakpoint;
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
                    child: extended
                        ? Text(
                            context.l10n.text('appName'),
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(color: context.colors.brandStrong),
                          )
                        : Icon(
                            Icons.shield_outlined,
                            color: context.colors.brandStrong,
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
    ),
  );
}
