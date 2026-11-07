import 'package:butlerly/features/help/data/help_catalog.dart';
import 'package:butlerly/features/help/presentation/help_copy.dart';
import 'package:butlerly/features/help/presentation/help_guide_section.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Stable guide chapter targets for each interactive Butlerly destination.
/// Chapters live in the bundled offline, trilingual Help catalog.
String? contextualHelpArticleForPath(String path) => switch (path) {
  '/launch' || '/help' => null,
  '/welcome' => 'ch-2',
  '/' => 'ch-12',
  '/transactions' || '/transactions/add' || '/add' => 'ch-5',
  '/tools' || '/rules' || '/payment-settlements' => 'ch-16',
  '/settings' || '/legal-licenses' => 'ch-17',
  '/analysis' || '/insights' => 'ch-14',
  '/budgets' => 'ch-15',
  '/financial-profile' => 'ch-4',
  '/review' => 'ch-11',
  '/search' => 'ch-13',
  '/payment-sources' => 'ch-7',
  '/import-export' || '/statements' => 'ch-10',
  '/receipts/capture' => 'ch-9',
  '/privacy-data' => 'ch-20',
  '/master-data' => 'ch-8',
  '/notifications' => 'ch-3',
  '/assistant' => 'ch-25',
  // An unrecognized future destination should still offer offline Help.
  // Map it to the navigation overview until its dedicated chapter exists.
  _ => 'ch-3',
};

/// Small page-header action, shared by regular pages and custom AppBars.
/// No action is shown outside the app router or on the Help page itself.
class ButlerlyContextHelpButton extends StatelessWidget {
  const ButlerlyContextHelpButton({this.articleId, super.key});

  final String? articleId;

  static String? articleForContext(BuildContext context) {
    final router = GoRouter.maybeOf(context);
    if (router == null) return null;
    // Prefer the route associated with this page: imperative push() may
    // keep the public route-information URI at the original destination.
    try {
      return contextualHelpArticleForPath(GoRouterState.of(context).uri.path);
    } catch (_) {
      // Dialog and nested Navigator contexts may lack a route-local state.
      return contextualHelpArticleForPath(router.state.uri.path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = GoRouter.maybeOf(context);
    final target = articleId ?? articleForContext(context);
    if (target == null) return const SizedBox.shrink();
    return IconButton(
      key: const ValueKey('page-context-help'),
      tooltip: context.l10n.text('contextHelp'),
      icon: const Icon(Icons.help_outline_rounded),
      onPressed: () {
        if (router == null) {
          _openStandaloneHelp(context, target);
        } else {
          context.push('/help?article=${Uri.encodeComponent(target)}');
        }
      },
    );
  }
}

/// Startup and recovery overlays replace the router's Navigator. Show the
/// same bundled guide chapter in their own overlay without leaving the safe
/// recovery/setup flow or requiring a network connection.
void _openStandaloneHelp(BuildContext context, String articleId) {
  final overlay = Overlay.maybeOf(context);
  if (overlay == null) return;
  final future = HelpCatalog.load();
  late final OverlayEntry entry;
  void close() {
    entry.remove();
    entry.dispose();
  }

  entry = OverlayEntry(
    builder: (overlayContext) => Material(
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            key: const ValueKey('context-help-close'),
            tooltip: HelpCopy.text(overlayContext, 'back'),
            onPressed: close,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          title: Text(HelpCopy.text(overlayContext, 'guide')),
        ),
        body: SafeArea(
          child: FutureBuilder<HelpCatalog>(
            future: future,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Text(HelpCopy.text(context, 'loadFailed')),
                );
              }
              final catalog = snapshot.data;
              if (catalog == null) {
                return const Center(child: CircularProgressIndicator());
              }
              final language = Localizations.localeOf(context).languageCode;
              final article = catalog.articleById(
                articleId,
                languageCode: language,
              );
              if (article == null) {
                return Center(child: Text(HelpCopy.text(context, 'noResults')));
              }
              return ListView(
                key: const ValueKey('context-help-offline-reader'),
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    article.title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  for (final paragraph in article.body.split(RegExp(r'\n\s*\n')))
                    if (paragraph.trim().isNotEmpty) ...[
                      helpGuideSection(context, paragraph),
                      const SizedBox(height: 12),
                    ],
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
  overlay.insert(entry);
}
