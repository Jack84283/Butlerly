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

/// Offline reader for the bundled, authoritative Legal document set.
class LegalLicensesPage extends StatelessWidget {
  const LegalLicensesPage({super.key});

  @override
  Widget build(BuildContext context) => ButlerlyPage(
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
        child: ListTile(
          leading: Icon(
            Icons.info_outline_rounded,
            color: context.colors.interactive,
          ),
          title: Text(context.l10n.text('appName')),
          subtitle: FutureBuilder<String>(
            future: _bundledVersion,
            builder: (context, snapshot) {
              return Text('Version ${snapshot.data ?? '—'}');
            },
          ),
        ),
      ),
      const SizedBox(height: ButlerlySpacing.section),
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

class LegalDocumentPage extends StatelessWidget {
  const LegalDocumentPage({required this.document, super.key});

  final LegalDocument document;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.l10n.text(document.titleKey))),
    body: SafeArea(
      child: ButlerlyResponsiveBody(
        contentKey: const ValueKey('legal-document-content'),
        child: FutureBuilder<String>(
          future: rootBundle.loadString(document.assetPath),
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
  final String assetPath;
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
