import 'package:butlerly/app/shell/adaptive_shell.dart';
import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/features/foundation/presentation/contextual_pages.dart';
import 'package:butlerly/features/foundation/presentation/home_page.dart';
import 'package:butlerly/features/foundation/presentation/privacy_data_page.dart';
import 'package:butlerly/features/foundation/presentation/review_page.dart';
import 'package:butlerly/features/foundation/presentation/search_page.dart';
import 'package:butlerly/features/foundation/presentation/settings_page.dart';
import 'package:butlerly/features/foundation/presentation/transactions_page.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/launch', builder: (_, _) => const LaunchPage()),
    GoRoute(path: '/welcome', builder: (_, _) => const WelcomePage()),
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          AdaptiveShell(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/',
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: HomePage()),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/transactions',
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: TransactionsPage()),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/review',
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: ReviewPage()),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/search',
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: SearchPage()),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/settings',
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: SettingsPage()),
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      path: '/transactions/add',
      builder: (context, state) => services.isRegistered<FinanceServices>()
          ? TransactionEditorPage(finance: services<FinanceServices>())
          : const Scaffold(
              body: Center(child: Text('Local storage is unavailable.')),
            ),
    ),
    GoRoute(
      path: '/import-export',
      builder: (_, _) => const ImportExportPage(),
    ),
    GoRoute(path: '/privacy-data', builder: (_, _) => const PrivacyDataPage()),
    GoRoute(
      path: '/notifications',
      builder: (_, _) => const NotificationsPage(),
    ),
    GoRoute(path: '/insights', builder: (_, _) => const InsightsPage()),
    GoRoute(
      path: '/assistant',
      builder: (_, _) => const AssistantUnavailablePage(),
    ),
  ],
  errorBuilder: (context, state) => Scaffold(
    body: Center(child: Text('The requested page could not be opened.')),
  ),
);
