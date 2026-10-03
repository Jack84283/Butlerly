import 'package:butlerly/app/shell/compact/compact_primary_shell.dart';
import 'package:butlerly/app/shell/medium/medium_primary_shell.dart';
import 'package:butlerly/app/shell/wide/wide_primary_shell.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/foundation/presentation/contextual_pages.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

export 'package:butlerly/app/shell/shared/primary_bottom_navigation.dart'
    show compactNavigationHeightForLabels;

const primaryShellRouteNamePrefix = 'primary-shell:';

class PrimaryShellVisibilityController extends ChangeNotifier {
  final Map<int, bool> _secondaryRouteVisible = <int, bool>{};
  bool _notificationScheduled = false;

  bool secondaryRouteVisibleFor(int branchIndex) =>
      _secondaryRouteVisible[branchIndex] ?? false;

  void updateTopRoute(int branchIndex, Route<dynamic>? route) {
    final isPrimaryShellRoute =
        route?.settings.name?.startsWith(primaryShellRouteNamePrefix) ?? false;
    final next = route != null && !isPrimaryShellRoute;
    if (_secondaryRouteVisible[branchIndex] == next) return;
    _secondaryRouteVisible[branchIndex] = next;
    _scheduleNotification();
  }

  void _scheduleNotification() {
    if (_notificationScheduled) return;
    _notificationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notificationScheduled = false;
      notifyListeners();
    });
  }
}

class PrimaryShellNavigatorObserver extends NavigatorObserver {
  PrimaryShellNavigatorObserver({
    required this.branchIndex,
    required this.controller,
    this.onPop,
  });

  final int branchIndex;
  final PrimaryShellVisibilityController controller;
  final VoidCallback? onPop;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    controller.updateTopRoute(branchIndex, route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    controller.updateTopRoute(branchIndex, previousRoute);
    onPop?.call();
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
  const AdaptiveShell({required this.child, required this.location, super.key});

  final Widget child;
  final String location;

  @override
  State<AdaptiveShell> createState() => _AdaptiveShellState();
}

class _AdaptiveShellState extends State<AdaptiveShell> {
  late int _wideParentIndex;

  @override
  void initState() {
    super.initState();
    _wideParentIndex = _parentIndexForLocation(widget.location);
  }

  @override
  void didUpdateWidget(covariant AdaptiveShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.location != widget.location) {
      _wideParentIndex = _parentIndexForLocation(
        widget.location,
        fallback: _wideParentIndex,
      );
    }
  }

  void _selectWideDestination(int branchIndex) {
    const paths = ['/', '/transactions', '/add', '/tools', '/settings'];
    context.go(paths[branchIndex]);
  }

  void _selectMoreSection(String section) {
    if (section == 'about') {
      context.go('/legal-licenses');
    }
  }

  @override
  Widget build(BuildContext context) {
    final layoutMode = ButlerlyLayout.mode(MediaQuery.sizeOf(context));
    if (layoutMode != ButlerlyLayoutMode.wide) return widget.child;

    return WidePrimaryShell(
      body: widget.child,
      currentIndex: _wideParentIndex,
      onSelected: _selectWideDestination,
      onMoreSectionSelected: _selectMoreSection,
      onImport: () => startLocalFileImport(context),
    );
  }
}

int _parentIndexForLocation(String location, {int fallback = 4}) {
  final path = Uri.parse(location).path;
  return switch (path) {
    '/' => 0,
    '/transactions' => 1,
    '/add' => 2,
    '/tools' => 3,
    '/settings' => 4,
    '/transactions/add' ||
    '/receipts/capture' ||
    '/statements' ||
    '/payment-sources' ||
    '/import-export' => 2,
    '/review' ||
    '/analysis' ||
    '/insights' ||
    '/payment-settlements' ||
    '/master-data' ||
    '/rules' => 3,
    '/privacy-data' || '/assistant' || '/legal-licenses' => 4,
    '/notifications' => 0,
    '/search' => fallback,
    _ => fallback,
  };
}

class PrimaryNavigationShell extends StatefulWidget {
  const PrimaryNavigationShell({
    required this.navigationShell,
    required this.visibilityController,
    super.key,
  });

  final StatefulNavigationShell navigationShell;
  final PrimaryShellVisibilityController visibilityController;

  @override
  State<PrimaryNavigationShell> createState() => _PrimaryNavigationShellState();
}

class _PrimaryNavigationShellState extends State<PrimaryNavigationShell> {
  static const _visualBranchIndexes = <int>[0, 1, 2, 3, 4];

  int _previousPrimaryIndex = 0;
  int _lastPrimaryIndex = 0;

  StatefulNavigationShell get navigationShell => widget.navigationShell;

  @override
  void initState() {
    super.initState();
    widget.visibilityController.addListener(_handleVisibilityChanged);
  }

  @override
  void didUpdateWidget(covariant PrimaryNavigationShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visibilityController != widget.visibilityController) {
      oldWidget.visibilityController.removeListener(_handleVisibilityChanged);
      widget.visibilityController.addListener(_handleVisibilityChanged);
    }
    final current = navigationShell.currentIndex;
    if (current == _lastPrimaryIndex) return;
    if (current == 2 && _lastPrimaryIndex != 2) {
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

  void _selectDestination(int branchIndex) {
    final current = navigationShell.currentIndex;
    if (branchIndex != current) {
      _previousPrimaryIndex = current;
      _lastPrimaryIndex = branchIndex;
    }
    navigationShell.goBranch(
      branchIndex,
      initialLocation: branchIndex == current,
    );
  }

  void _handleSystemBack(bool didPop, Object? result) {
    if (!didPop && navigationShell.currentIndex == 2) {
      navigationShell.goBranch(_previousPrimaryIndex);
    }
  }

  Map<int, NavigationDestination> _destinations(BuildContext context) => {
    0: NavigationDestination(
      icon: _adaptiveIcon(
        context,
        material: Icons.home_outlined,
        cupertino: CupertinoIcons.house,
      ),
      selectedIcon: _adaptiveIcon(
        context,
        material: Icons.home_rounded,
        cupertino: CupertinoIcons.house_fill,
      ),
      label: context.l10n.text('home'),
    ),
    1: NavigationDestination(
      icon: _adaptiveIcon(
        context,
        material: Icons.format_list_bulleted_rounded,
        cupertino: CupertinoIcons.list_bullet,
      ),
      selectedIcon: _adaptiveIcon(
        context,
        material: Icons.format_list_bulleted_rounded,
        cupertino: CupertinoIcons.list_bullet,
      ),
      label: context.l10n.text('transactions'),
    ),
    2: NavigationDestination(
      icon: _adaptiveIcon(
        context,
        material: Icons.add_rounded,
        cupertino: CupertinoIcons.add,
      ),
      selectedIcon: _adaptiveIcon(
        context,
        material: Icons.add_rounded,
        cupertino: CupertinoIcons.add,
      ),
      label: context.l10n.text('add'),
    ),
    3: NavigationDestination(
      icon: _adaptiveIcon(
        context,
        material: Icons.bar_chart_rounded,
        cupertino: CupertinoIcons.chart_bar,
      ),
      selectedIcon: _adaptiveIcon(
        context,
        material: Icons.bar_chart_rounded,
        cupertino: CupertinoIcons.chart_bar_fill,
      ),
      label: context.l10n.text('tools'),
    ),
    4: NavigationDestination(
      icon: _adaptiveIcon(
        context,
        material: Icons.more_horiz_rounded,
        cupertino: CupertinoIcons.ellipsis,
      ),
      selectedIcon: _adaptiveIcon(
        context,
        material: Icons.more_horiz_rounded,
        cupertino: CupertinoIcons.ellipsis,
      ),
      label: context.l10n.text('more'),
    ),
  };

  @override
  Widget build(BuildContext context) {
    final layoutMode = ButlerlyLayout.mode(MediaQuery.sizeOf(context));
    final secondaryRouteVisible = widget.visibilityController
        .secondaryRouteVisibleFor(navigationShell.currentIndex);
    if (secondaryRouteVisible) {
      final shell = layoutMode == ButlerlyLayoutMode.wide
          ? navigationShell
          : Scaffold(body: navigationShell);
      return PopScope(canPop: true, child: shell);
    }

    final destinations = _destinations(context);
    final shell = switch (layoutMode) {
      ButlerlyLayoutMode.compact => CompactPrimaryShell(
        body: navigationShell,
        destinations: destinations,
        visualBranchIndexes: _visualBranchIndexes,
        currentIndex: navigationShell.currentIndex,
        onSelected: _selectDestination,
      ),
      ButlerlyLayoutMode.medium => MediumPrimaryShell(
        body: navigationShell,
        destinations: destinations,
        visualBranchIndexes: _visualBranchIndexes,
        currentIndex: navigationShell.currentIndex,
        onSelected: _selectDestination,
      ),
      ButlerlyLayoutMode.wide => navigationShell,
    };

    return PopScope(
      canPop: navigationShell.currentIndex != 2,
      onPopInvokedWithResult: _handleSystemBack,
      child: shell,
    );
  }
}

Widget _adaptiveIcon(
  BuildContext context, {
  required IconData material,
  required IconData cupertino,
}) => Icon(
  Theme.of(context).platform == TargetPlatform.iOS ? cupertino : material,
);
