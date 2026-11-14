import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_button.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/help/data/help_catalog.dart';
import 'package:butlerly/features/help/presentation/help_copy.dart';
import 'package:butlerly/features/help/presentation/help_guide_section.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

/// Stable guide chapter targets for each interactive Butlerly destination.
/// Chapters live in the bundled offline, trilingual Help catalog.
String? contextualHelpArticleForPath(String path) => switch (path) {
  '/launch' || '/help' => null,
  '/welcome' => 'ch-2',
  '/' => 'home.overview',
  '/transactions' => 'transactions.list',
  '/transactions/add' => 'add.manual',
  '/add' => 'add.overview',
  '/tools' => 'tools.overview',
  '/rules' => 'tools.rules',
  '/payment-settlements' => 'tools.settlements',
  '/settings' => 'more.overview',
  '/legal-licenses' => 'more.about',
  '/analysis' => 'tools.analysis',
  '/insights' => 'tools.insights',
  '/budgets' => 'tools.budgets',
  '/financial-profile' => 'more.financial-profile',
  '/review' => 'tools.review',
  '/search' => 'transactions.search',
  '/payment-sources' => 'add.payment-source',
  '/import-export' => 'add.import',
  '/statements' => 'add.statement',
  '/receipts/capture' => 'add.receipt',
  '/privacy-data' => 'more.privacy',
  '/master-data' => 'tools.master-data',
  '/notifications' => 'more.operational-features',
  '/assistant' => 'tools.assistant',
  // Always fall back to the screen-based navigation guide for new routes.
  _ => 'guide-navigation',
};

/// Identifies pages hosted by the wide desktop shell.
class ButlerlyDesktopHeaderScope extends InheritedWidget {
  const ButlerlyDesktopHeaderScope({required super.child, super.key});

  static bool isActive(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<ButlerlyDesktopHeaderScope>() !=
      null;

  @override
  bool updateShouldNotify(covariant ButlerlyDesktopHeaderScope oldWidget) =>
      false;
}

/// Shared close affordance for embedded desktop detail and editor panels.
/// Full-page navigation retains its own Back action.
class ButlerlyPanelCloseButton extends StatelessWidget {
  const ButlerlyPanelCloseButton({
    required this.onPressed,
    this.buttonKey,
    super.key,
  });

  final VoidCallback? onPressed;
  final Key? buttonKey;

  @override
  Widget build(BuildContext context) => Center(
    child: IconButton(
      key: buttonKey,
      tooltip: context.l10n.text('close'),
      onPressed: onPressed,
      // AppBar.leading can allocate a wider slot than the Back button's
      // actual visual circle. Keep hit size and painted circle independent.
      style: IconButton.styleFrom(
        fixedSize: const Size.square(ButlerlySize.minimumTarget),
        minimumSize: const Size.square(ButlerlySize.minimumTarget),
        padding: EdgeInsets.zero,
        backgroundColor: Colors.transparent,
        disabledBackgroundColor: Colors.transparent,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      iconSize: ButlerlyButtonTokens.iconSize,
      icon: SizedBox.square(
        key: const ValueKey('desktop-panel-close-circle'),
        dimension: ButlerlyButtonTokens.iconVisualSize,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: context.colors.subtleSurface,
            shape: BoxShape.circle,
          ),
          child: const Center(
            child: Icon(
              Icons.close_rounded,
              size: ButlerlyButtonTokens.iconSize,
            ),
          ),
        ),
      ),
    ),
  );
}

/// Prominent page-header action, shared by regular pages and custom AppBars.
/// Router-backed pages navigate to Help; setup/recovery screens use an offline
/// overlay when no router is available. The Help reader hides its own action.
class ButlerlyContextHelpButton extends StatelessWidget {
  const ButlerlyContextHelpButton({
    this.articleId,
    this.visualGapAfterAdd,
    this.onPressed,
    super.key,
  });

  final String? articleId;

  /// Optional navigation override for router error screens, where the
  /// invalid route cannot always be used as the base for context.push().
  final VoidCallback? onPressed;

  /// Requested gap between the preceding 32px header Add circle and this
  /// 32px Help circle. The Help hit target remains 44px.
  final double? visualGapAfterAdd;

  static String? articleForContext(BuildContext context) {
    final router = GoRouter.maybeOf(context);
    if (router == null) return null;
    // GoRouterState.of(context) expects a GoRouter-managed modal route.
    // Details opened with Navigator.push(MaterialPageRoute), including Payment
    // Settlements, do not have their own GoRouterState. Resolve the active
    // destination from the enclosing router without inspecting the modal route.
    return contextualHelpArticleForPath(router.state.uri.path);
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
      key: const ValueKey('page-context-help-padding'),
      padding: EdgeInsets.only(
        left: visualGapAfterAdd == null
            ? ButlerlySpacing.small
            : visualGapAfterAdd! - (ButlerlySize.minimumTarget - 32) / 2,
        right: ButlerlyDesktopHeaderScope.isActive(context)
            ? ButlerlySpacing.small
            : ButlerlySpacing.none,
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
        onPressed:
            onPressed ??
            () {
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

/// Local Navigator for first-use and blocking recovery screens above GoRouter.
///
/// Preserves the active setup/recovery workflow while giving offline Help a
/// real route. System Back dismisses Help before the underlying gate. Each
/// independent gate must use a distinct key.
class ButlerlyRouterlessRecoveryHost extends StatefulWidget {
  const ButlerlyRouterlessRecoveryHost({required this.child, super.key});

  final Widget child;

  @override
  State<ButlerlyRouterlessRecoveryHost> createState() =>
      _ButlerlyRouterlessRecoveryHostState();
}

class _ButlerlyRouterlessRecoveryHostState
    extends State<ButlerlyRouterlessRecoveryHost>
    with WidgetsBindingObserver {
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    // MaterialApp.router.builder inserts recovery and first-use gates ABOVE
    // its Router; BackButtonListener requires a Router ancestor and crashes
    // there. Listen directly to platform Back only while this gate is active.
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Future<bool> didPopRoute() async {
    final navigator = _navigatorKey.currentState;
    if (navigator == null || !navigator.canPop()) return false;
    return navigator.maybePop();
  }

  @override
  Widget build(BuildContext context) => Navigator(
    key: _navigatorKey,
    onGenerateRoute: (settings) => MaterialPageRoute<void>(
      settings: settings,
      builder: (_) => widget.child,
    ),
  );
}

/// The app's setup/recovery gates use ButlerlyRouterlessRecoveryHost;
/// independent routerless Overlay hosts retain a fallback Help reader.
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
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {const SingleActivator(LogicalKeyboardKey.escape): onClose},
    child: Focus(
      autofocus: true,
      child: Material(
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
              initialData: HelpCatalog.cachedBundle,
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
                  return Center(
                    child: Text(HelpCopy.text(context, 'noResults')),
                  );
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
                    for (final paragraph in article.body.split(
                      RegExp(r'\n\s*\n'),
                    ))
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
    ),
  );
}
