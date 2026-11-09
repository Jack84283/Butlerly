import 'package:butlerly/app/shell/adaptive_shell.dart';
import 'package:butlerly/design_system/components/butlerly_brand_icon.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/components/butlerly_responsive_body.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

// Read the app version from the bundled Flutter manifest so the displayed
// version always matches pubspec.yaml without a database field.
Future<String> _readBundledVersion() async {
  final manifest = await rootBundle.loadString('pubspec.yaml');
  final match = RegExp(
    r'^version:\s*([^\s#]+)',
    multiLine: true,
  ).firstMatch(manifest);
  return match?.group(1) ?? '—';
}

final Future<String> _bundledVersion = _readBundledVersion();

/// Offline reader for the bundled legal review documents.
///
/// LEG-0001–0004 v1.1 are review editions, not published legal agreements.
/// Do not lift this release gate without issue #380 approval.
class LegalLicensesPage extends StatelessWidget {
  const LegalLicensesPage({super.key});

  @override
  Widget build(BuildContext context) {
    if (effectiveButlerlyLayoutMode(
          context,
          MediaQuery.sizeOf(context).width,
        ) ==
        ButlerlyLayoutMode.wide) {
      return const _DesktopLegalLicensesPage();
    }
    return ButlerlyPage(
      title: context.l10n.text('legalLicenses'),
      leading: IconButton(
        tooltip: MaterialLocalizations.of(context).backButtonTooltip,
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () {
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          } else {
            context.go('/settings');
          }
        },
      ),
      children: [
        ButlerlyCard(
          child: ButlerlyBrandVersionTile(
            appName: context.l10n.text('appName'),
            versionLabel: context.l10n.text('appVersionLabel'),
            version: _bundledVersion,
          ),
        ),
        const SizedBox(height: ButlerlySpacing.section),
        const _LegalReviewNotice(),
        const SizedBox(height: ButlerlySpacing.small),
        ButlerlyCard(
          padding: EdgeInsets.zero,
          child: ButlerlySeparatedList(
            children: [
              for (final document in _documents)
                ListTile(
                  leading: Icon(
                    Icons.description_outlined,
                    color: context.colors.interactive,
                  ),
                  title: Text(context.l10n.text(document.titleKey)),
                  trailing: Icon(
                    Icons.chevron_right_rounded,
                    color: context.colors.interactive,
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => LegalDocumentPage(document: document),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DesktopLegalLicensesPage extends StatefulWidget {
  const _DesktopLegalLicensesPage();

  @override
  State<_DesktopLegalLicensesPage> createState() =>
      _DesktopLegalLicensesPageState();
}

class _DesktopLegalLicensesPageState extends State<_DesktopLegalLicensesPage> {
  int _selectedDocument = 0;
  final Map<String, Future<String>> _contents = {};

  Future<String> _contentFor(LegalDocument document, Locale locale) {
    final path = document.assetPathFor(locale);
    return _contents.putIfAbsent(path, () => rootBundle.loadString(path));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final selected = _documents[_selectedDocument];
    final locale = Localizations.localeOf(context);
    final readerHeight = (MediaQuery.sizeOf(context).height - 190).clamp(
      440.0,
      950.0,
    );

    final documentList = ButlerlyCard(
      padding: const EdgeInsets.all(ButlerlySpacing.standard),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.text('desktopLegalDocuments'),
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: ButlerlySpacing.standard),
          Expanded(
            child: ListView.separated(
              key: const ValueKey('desktop-legal-document-list'),
              itemCount: _documents.length,
              separatorBuilder: (_, _) =>
                  Divider(height: 1, color: context.colors.cardDivider),
              itemBuilder: (context, index) {
                final document = _documents[index];
                final active = index == _selectedDocument;
                return Material(
                  color: active ? context.colors.selection : Colors.transparent,
                  borderRadius: BorderRadius.circular(ButlerlyRadius.control),
                  child: ListTile(
                    key: ValueKey('desktop-legal-document-$index'),
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: ButlerlySpacing.compact,
                    ),
                    leading: Icon(
                      Icons.description_outlined,
                      size: 20,
                      color: active
                          ? context.colors.interactive
                          : context.colors.secondaryText,
                    ),
                    title: Text(
                      l10n.text(document.titleKey),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: active ? context.colors.interactive : null,
                        fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                    selected: active,
                    onTap: () => setState(() => _selectedDocument = index),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );

    final reader = ButlerlyCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(ButlerlySpacing.standard),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.text(selected.titleKey),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Icon(
                  Icons.description_outlined,
                  color: context.colors.secondaryText,
                ),
              ],
            ),
          ),
          Divider(height: 1, color: context.colors.cardDivider),
          const _LegalReviewNotice(),
          Expanded(
            child: FutureBuilder<String>(
              key: ValueKey(
                'desktop-legal-reader-$_selectedDocument-${locale.languageCode}',
              ),
              future: _contentFor(selected, locale),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text(l10n.text('legalDocumentLoadError')),
                  );
                }
                if (!snapshot.hasData) {
                  return const ButlerlyLoadingState();
                }
                return SingleChildScrollView(
                  key: const ValueKey('desktop-legal-reader-scroll'),
                  padding: const EdgeInsets.all(ButlerlySpacing.standard),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 840),
                    child: SelectableText(
                      snapshot.requireData,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(height: 1.6),
                    ),
                  ),
                );
              },
            ),
          ),
          Divider(height: 1, color: context.colors.cardDivider),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: ButlerlySpacing.standard,
              vertical: ButlerlySpacing.small,
            ),
            child: Row(
              children: [
                const ButlerlyBrandIcon(size: 24),
                const SizedBox(width: ButlerlySpacing.compact),
                Expanded(
                  child: FutureBuilder<String>(
                    future: _bundledVersion,
                    builder: (context, snapshot) => Text(
                      '${l10n.text('appName')} · ${l10n.text('appVersionLabel')} ${snapshot.data ?? '—'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: context.colors.secondaryText,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return ButlerlyPage(
      title: l10n.text('legalLicenses'),
      subtitle: l10n.text('desktopLegalSubtitle'),
      fullWidth: true,
      leading: IconButton(
        tooltip: MaterialLocalizations.of(context).backButtonTooltip,
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () =>
            context.canPop() ? context.pop() : context.go('/settings'),
      ),
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 610) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(height: 250, child: documentList),
                  const SizedBox(height: ButlerlySpacing.small),
                  SizedBox(height: readerHeight, child: reader),
                ],
              );
            }
            return SizedBox(
              height: readerHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 2, child: documentList),
                  const SizedBox(width: ButlerlySpacing.small),
                  Expanded(flex: 4, child: reader),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class LegalDocumentPage extends StatefulWidget {
  const LegalDocumentPage({required this.document, super.key});

  final LegalDocument document;

  @override
  State<LegalDocumentPage> createState() => _LegalDocumentPageState();
}

class _LegalDocumentPageState extends State<LegalDocumentPage> {
  late Future<String> _contents;
  String? _loadedPath;

  // didChangeDependencies is needed for a runtime app-language switch while
  // this document detail route is already open.
  void _loadForCurrentLocale() {
    final path = widget.document.assetPathFor(Localizations.localeOf(context));
    if (path == _loadedPath) return;
    _loadedPath = path;
    _contents = rootBundle.loadString(path);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadForCurrentLocale();
  }

  @override
  void didUpdateWidget(covariant LegalDocumentPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _loadForCurrentLocale();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(context.l10n.text(widget.document.titleKey)),
      actions: const [ButlerlyContextHelpButton(articleId: 'ch-17')],
    ),
    body: SafeArea(
      child: ButlerlyResponsiveBody(
        contentKey: const ValueKey('legal-document-content'),
        child: FutureBuilder<String>(
          key: ValueKey('legal-document-body-$_loadedPath'),
          future: _contents,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(ButlerlySpacing.section),
                  child: Text(context.l10n.text('legalDocumentLoadError')),
                ),
              );
            }
            if (!snapshot.hasData) {
              return const ButlerlyLoadingState();
            }
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: ButlerlySize.contentGutter,
                vertical: ButlerlySpacing.section,
              ),
              child: SelectableText(snapshot.requireData),
            );
          },
        ),
      ),
    ),
  );
}

class LegalDocument {
  const LegalDocument(this.titleKey, this.assetPath);
  final String titleKey;

  /// English asset path; localized variants are bundled alongside it.
  final String assetPath;

  String assetPathFor(Locale locale) {
    final suffix = switch (locale.languageCode) {
      'zh' => '_zh',
      'es' => '_es',
      _ => '',
    };
    return '${assetPath.substring(0, assetPath.length - 4)}$suffix.txt';
  }
}

class _LegalReviewNotice extends StatelessWidget {
  const _LegalReviewNotice();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: ButlerlySpacing.standard,
      vertical: ButlerlySpacing.small,
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.info_outline_rounded,
          size: 18,
          color: context.colors.secondaryText,
        ),
        const SizedBox(width: ButlerlySpacing.compact),
        Expanded(
          child: Text(
            context.l10n.text('legalReviewNotApproved'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: context.colors.secondaryText,
            ),
          ),
        ),
      ],
    ),
  );
}

const _documents = [
  LegalDocument('termsOfUse', 'assets/legal/terms_of_use.txt'),
  LegalDocument('privacyPolicy', 'assets/legal/privacy_policy.txt'),
  LegalDocument(
    'softwareLicenseThirdPartyNotices',
    'assets/legal/third_party_notices.txt',
  ),
  LegalDocument(
    'aiProfessionalAdviceDisclosures',
    'assets/legal/ai_disclosures.txt',
  ),
];
