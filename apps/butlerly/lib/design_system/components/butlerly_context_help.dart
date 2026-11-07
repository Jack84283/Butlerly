import 'package:butlerly/features/help/data/help_catalog.dart';
import 'package:butlerly/features/help/presentation/help_copy.dart';
import 'package:butlerly/features/help/presentation/help_guide_section.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
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

/// Prominent page-header action, shared by regular pages and custom AppBars.
/// Router-backed pages navigate to Help; setup/recovery screens use an offline
/// overlay when no router is available. The Help reader hides its own action.
class ButlerlyContextHelpButton extends StatelessWidget {
  const ButlerlyContextHelpButton({
    this.articleId,
    this.visualGapAfterAdd,
    super.key,
  });

  final String? articleId;

  /// Requested gap between the preceding 32px header Add circle and this
  /// 32px Help circle. The Help hit target remains 44px.
  final double? visualGapAfterAdd;

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
    final scheme = Theme.of(context).colorScheme;
    // Keep the painted Help control compact while retaining a 44px hit
    // target for touch and keyboard accessibility. Its left spacing is
    // independent of the visual circle diameter.
    return Padding(
      padding: EdgeInsets.only(
        left: visualGapAfterAdd == null
            ? ButlerlySpacing.small
            : visualGapAfterAdd! -
                  (ButlerlySize.minimumTarget - 32) / 2,
      ),
      child: IconButton(
        key: const ValueKey('page-context-help'),
        tooltip: context.l10n.text('contextHelp'),
        icon: SizedBox.square(
          key: const ValueKey('page-context-help-visual'),
          dimension: 32,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.primary,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Icon(
                Icons.question_mark_rounded,
                size: 16,
                color: scheme.onPrimary,
              ),
            ),
          ),
        ),
        style: IconButton.styleFrom(
          backgroundColor: Colors.transparent,
          minimumSize: const Size.square(44),
          maximumSize: const Size.square(44),
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: const CircleBorder(),
        ),
        onPressed: () {
          if (router == null) {
            _openStandaloneHelp(context, target);
          } else {
            context.push('/help?article=${Uri.encodeComponent(target)}');
          }
        },
      ),
    );
  }
}

/// Local Navigator for blocking recovery screens rendered above GoRouter.
///
/// This preserves the recovery workflow while giving modal confirmations and
/// offline contextual Help a route stack. System Back dismisses Help, not the
/// recovery screen. The host must have a distinct key for each recovery mode.
class ButlerlyRouterlessRecoveryHost extends StatelessWidget {
  const ButlerlyRouterlessRecoveryHost({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => Navigator(
    onGenerateRoute: (settings) =>
        MaterialPageRoute<void>(settings: settings, builder: (_) => child),
  );
}

/// Setup screens may have an Overlay but no Navigator; recovery screens use
/// ButlerlyRouterlessRecoveryHost. Both paths display the same offline reader.
void _openStandaloneHelp(BuildContext context, String articleId) {
  final future = HelpCatalog.load();
  final navigator = Navigator.maybeOf(context);
  if (navigator != null) {
    navigator.push<void>(
      MaterialPageRoute<void>(
        builder: (_) => _StandaloneHelpReader(
          articleId: articleId,
          future: future,
          onClose: () => navigator.pop(),
        ),
      ),
    );
    return;
  }

  final overlay = Overlay.maybeOf(context);
  if (overlay == null) return;
  late final OverlayEntry entry;
  void close() {
    entry.remove();
    entry.dispose();
  }

  entry = OverlayEntry(
    builder: (_) => _StandaloneHelpReader(
      articleId: articleId,
      future: future,
      onClose: close,
    ),
  );
  overlay.insert(entry);
}

class _StandaloneHelpReader extends StatelessWidget {
  const _StandaloneHelpReader({
    required this.articleId,
    required this.future,
    required this.onClose,
  });

  final String articleId;
  final Future<HelpCatalog> future;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Material(
    child: Scaffold(
      appBar: AppBar(
        leading: IconButton(
          key: const ValueKey('context-help-close'),
          tooltip: HelpCopy.text(context, 'back'),
          onPressed: onClose,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Text(HelpCopy.text(context, 'guide')),
      ),
      body: SafeArea(
        child: FutureBuilder<HelpCatalog>(
          future: future,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Text(HelpCopy.text(context, 'loadFailed')));
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
  );
}
