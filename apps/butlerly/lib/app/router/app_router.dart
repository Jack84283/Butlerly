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
import 'package:butlerly/l10n/app_localizations.dart';
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
              pageBuilder: (context, state) => NoTransitionPage(
                child: ReviewPage(
                  showPossibleDuplicates:
                      state.uri.queryParameters['view'] == 'duplicates',
                ),
              ),
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
          : Scaffold(
              body: ButlerlyEmptyState(
                icon: Icons.storage_outlined,
                title: context.l10n.text('localStorageUnavailable'),
                message: context.l10n.text('dataPreserved'),
              ),
            ),
    ),
    GoRoute(path: '/add', builder: (_, _) => const AddPage()),
    GoRoute(
      path: '/payment-sources',
      builder: (_, _) => const PaymentSourcesPage(),
    ),
    GoRoute(
      path: '/import-export',
      builder: (context, state) => ImportExportPage(
        startWithFileImport: state.uri.queryParameters['start'] == 'file',
      ),
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
    GoRoute(path: '/analysis', builder: (_, _) => const AnalysisPage()),
    GoRoute(path: '/insights', redirect: (_, _) => '/analysis'),
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
