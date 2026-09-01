import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

const primaryShellRouteNamePrefix = 'primary-shell:';

class PrimaryShellVisibilityController extends ChangeNotifier {
  final Map<int, bool> _secondaryRouteVisible = <int, bool>{};

  bool secondaryRouteVisibleFor(int branchIndex) =>
      _secondaryRouteVisible[branchIndex] ?? false;

  void updateTopRoute(int branchIndex, Route<dynamic>? route) {
    final isPrimaryShellRoute =
        route?.settings.name?.startsWith(primaryShellRouteNamePrefix) ?? false;
    final next = route != null && !isPrimaryShellRoute;
    if (_secondaryRouteVisible[branchIndex] == next) return;
    _secondaryRouteVisible[branchIndex] = next;
    notifyListeners();
  }
}

class PrimaryShellNavigatorObserver extends NavigatorObserver {
  PrimaryShellNavigatorObserver({
    required this.branchIndex,
    required this.controller,
  });

  final int branchIndex;
  final PrimaryShellVisibilityController controller;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    controller.updateTopRoute(branchIndex, route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    controller.updateTopRoute(branchIndex, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    controller.updateTopRoute(branchIndex, newRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    controller.updateTopRoute(branchIndex, previousRoute);
  }
}

class AdaptiveShell extends StatefulWidget {
  const AdaptiveShell({
    required this.navigationShell,
    required this.visibilityController,
    super.key,
  });

  final StatefulNavigationShell navigationShell;
  final PrimaryShellVisibilityController visibilityController;

  @override
  State<AdaptiveShell> createState() => _AdaptiveShellState();
}

class _AdaptiveShellState extends State<AdaptiveShell> {
  int _previousPrimaryIndex = 0;
  int _lastPrimaryIndex = 0;

  StatefulNavigationShell get navigationShell => widget.navigationShell;

  @override
  void initState() {
    super.initState();
    widget.visibilityController.addListener(_handleVisibilityChanged);
  }

  @override
  void didUpdateWidget(covariant AdaptiveShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visibilityController != widget.visibilityController) {
      oldWidget.visibilityController.removeListener(_handleVisibilityChanged);
      widget.visibilityController.addListener(_handleVisibilityChanged);
    }
    final current = navigationShell.currentIndex;
    if (current == _lastPrimaryIndex) return;
    if (current == 1 && _lastPrimaryIndex != 1) {
      _previousPrimaryIndex = _lastPrimaryIndex;
    }
    _lastPrimaryIndex = current;
  }

  @override
  void dispose() {
    widget.visibilityController.removeListener(_handleVisibilityChanged);
    super.dispose();
  }

  void _handleVisibilityChanged() {
    if (mounted) setState(() {});
  }

  void _selectDestination(int index) {
    final current = navigationShell.currentIndex;
    if (index != current) {
      _previousPrimaryIndex = current;
      _lastPrimaryIndex = index;
    }
    navigationShell.goBranch(
      index,
      initialLocation: index == current,
    );
  }

  void _handleSystemBack(bool didPop, Object? result) {
    if (!didPop && navigationShell.currentIndex == 1) {
      navigationShell.goBranch(_previousPrimaryIndex);
    }
  }

  List<NavigationDestination> _destinations(BuildContext context) => [
    NavigationDestination(
      icon: const Icon(Icons.home_outlined),
      selectedIcon: const Icon(Icons.home_rounded),
      label: context.l10n.text('home'),
    ),
    NavigationDestination(
      icon: const Icon(Icons.add_circle_outline_rounded),
      selectedIcon: const Icon(Icons.add_circle_rounded),
      label: context.l10n.text('add'),
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

  Widget _destination(
    BuildContext context,
    NavigationDestination destination,
    int index,
  ) {
    final selected = navigationShell.currentIndex == index;
    final labelStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: selected
          ? context.colors.interactive
          : context.colors.secondaryText,
      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
    );
    return Semantics(
      button: true,
      selected: selected,
      label: index == 1
          ? context.l10n.text('addTransactionAction')
          : destination.label,
      excludeSemantics: true,
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
              if (index == 1)
                RichText(
                  text: TextSpan(text: destination.label, style: labelStyle),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textScaler: MediaQuery.textScalerOf(context),
                )
              else
                Text(
                  destination.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: labelStyle,
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
  Widget build(BuildContext context) {
    final secondaryRouteVisible = widget.visibilityController
        .secondaryRouteVisibleFor(navigationShell.currentIndex);
    return PopScope(
      canPop: secondaryRouteVisible || navigationShell.currentIndex != 1,
      onPopInvokedWithResult: _handleSystemBack,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (secondaryRouteVisible) {
            return Scaffold(body: navigationShell);
          }

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
}
