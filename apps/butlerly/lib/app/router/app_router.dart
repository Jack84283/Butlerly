import 'package:butlerly/app/shell/adaptive_shell.dart';
import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/features/analysis/presentation/analysis_page.dart';
import 'package:butlerly/features/foundation/presentation/add_page.dart';
import 'package:butlerly/features/foundation/presentation/contextual_pages.dart';
import 'package:butlerly/features/foundation/presentation/home_page.dart';
import 'package:butlerly/features/foundation/presentation/payment_sources_page.dart';
import 'package:butlerly/features/foundation/presentation/privacy_data_page.dart';
import 'package:butlerly/features/foundation/presentation/receipt_capture_page.dart';
import 'package:butlerly/features/foundation/presentation/review_page.dart';
import 'package:butlerly/features/foundation/presentation/search_page.dart';
import 'package:butlerly/features/foundation/presentation/settings_page.dart';
import 'package:butlerly/features/foundation/presentation/statement_capture_page.dart';
import 'package:butlerly/features/foundation/presentation/transactions_page.dart';
import 'package:butlerly/features/tools/presentation/tools_page.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

final _primaryShellVisibility = PrimaryShellVisibilityController();

PrimaryShellNavigatorObserver _primaryObserver(int branchIndex) =>
    PrimaryShellNavigatorObserver(
      branchIndex: branchIndex,
      controller: _primaryShellVisibility,
    );

NoTransitionPage<void> _primaryPage(String name, Widget child) =>
    NoTransitionPage<void>(
      name: '$primaryShellRouteNamePrefix$name',
      child: child,
    );

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/launch', builder: (_, _) => const LaunchPage()),
    GoRoute(path: '/welcome', builder: (_, _) => const WelcomePage()),

    // Primary app shell. Every section-level destination below keeps the
    // footer/navigation rail visible. Detail and workflow routes stay outside
    // this StatefulShellRoute.
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) => AdaptiveShell(
        navigationShell: navigationShell,
        visibilityController: _primaryShellVisibility,
      ),
      branches: [
        StatefulShellBranch(
          observers: [_primaryObserver(0)],
          routes: [
            GoRoute(
              path: '/',
              pageBuilder: (context, state) =>
                  _primaryPage('home', const HomePage()),
            ),
          ],
        ),
        StatefulShellBranch(
          observers: [_primaryObserver(1)],
          routes: [
            GoRoute(
              path: '/add',
              pageBuilder: (context, state) =>
                  _primaryPage('add', const AddPage()),
            ),
          ],
        ),
        StatefulShellBranch(
          observers: [_primaryObserver(2)],
          routes: [
            GoRoute(
              path: '/transactions',
              pageBuilder: (context, state) =>
                  _primaryPage('transactions', const TransactionsPage()),
            ),
          ],
        ),
        StatefulShellBranch(
          observers: [_primaryObserver(3)],
          routes: [
            GoRoute(
              path: '/tools',
              pageBuilder: (context, state) =>
                  _primaryPage('tools', const ToolsPage()),
            ),
            GoRoute(
              path: '/review',
              pageBuilder: (context, state) => _primaryPage(
                'review',
                ReviewPage(
                  showPossibleDuplicates:
                      state.uri.queryParameters['view'] == 'duplicates',
                ),
              ),
            ),
            GoRoute(
              path: '/search',
              pageBuilder: (context, state) =>
                  _primaryPage('search', const SearchPage()),
            ),
            GoRoute(
              path: '/analysis',
              pageBuilder: (context, state) =>
                  _primaryPage('analysis', const AnalysisPage()),
            ),
            GoRoute(
              path: '/insights',
              pageBuilder: (context, state) =>
                  _primaryPage('insights', const InsightsPage()),
            ),
          ],
        ),
        StatefulShellBranch(
          observers: [_primaryObserver(4)],
          routes: [
            GoRoute(
              path: '/settings',
              pageBuilder: (context, state) =>
                  _primaryPage('more', const SettingsPage()),
            ),
          ],
        ),
      ],
    ),

    // Secondary navigation. These pages intentionally render outside the
    // primary shell and therefore never show the footer/navigation rail.
    GoRoute(
      path: '/transactions/add',
      builder: (context, state) => services.isRegistered<FinanceServices>()
          ? TransactionEditorPage(finance: services<FinanceServices>())
          : Scaffold(
              body: ButlerlyEmptyState(
                icon: Icons.storage_outlined,
                title: context.l10n.text('localStorageUnavailable'),
                message: context.l10n.text('dataPreserved'),
              ),
            ),
    ),
    GoRoute(
      path: '/payment-sources',
      builder: (_, _) => const PaymentSourcesPage(),
    ),
    GoRoute(
      path: '/import-export',
      builder: (_, _) => const ImportExportPage(),
    ),
    GoRoute(
      path: '/receipts/capture',
      builder: (_, _) => const ReceiptCapturePage(),
    ),
    GoRoute(
      path: '/statements',
      builder: (context, _) => services.isRegistered<FinanceServices>()
          ? const StatementCapturePage()
          : Scaffold(
              body: ButlerlyEmptyState(
                icon: Icons.storage_outlined,
                title: context.l10n.text('localStorageUnavailable'),
                message: context.l10n.text('dataPreserved'),
              ),
            ),
    ),
    GoRoute(path: '/privacy-data', builder: (_, _) => const PrivacyDataPage()),
    GoRoute(
      path: '/notifications',
      builder: (_, _) => const NotificationsPage(),
    ),
    GoRoute(
      path: '/assistant',
      builder: (_, _) => const AssistantUnavailablePage(),
    ),
  ],
  errorBuilder: (context, state) => Scaffold(
    body: ButlerlyErrorState(
      title: context.l10n.text('pageUnavailable'),
      message: context.l10n.text('pageUnavailableBody'),
      preserved: context.l10n.text('dataPreserved'),
      actionLabel: context.l10n.text('tryAgain'),
      onAction: () => context.go('/'),
    ),
  ),
);
