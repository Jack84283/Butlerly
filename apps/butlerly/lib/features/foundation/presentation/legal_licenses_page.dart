import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Offline reader for the bundled, authoritative Legal document set.
class LegalLicensesPage extends StatelessWidget {
  const LegalLicensesPage({super.key});

  @override
  Widget build(BuildContext context) => ButlerlyPage(
    title: context.l10n.text('legalLicenses'),
    children: [
      ButlerlyCard(
        child: ListTile(
          leading: Icon(
            Icons.info_outline_rounded,
            color: context.colors.interactive,
          ),
          title: Text(context.l10n.text('appName')),
          subtitle: const Text('Version 1.0.0+1'),
        ),
      ),
      const SizedBox(height: ButlerlySpacing.section),
      for (final document in _documents)
        Padding(
          padding: const EdgeInsets.only(bottom: ButlerlySpacing.small),
          child: ButlerlyCard(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => LegalDocumentPage(document: document),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.description_outlined,
                  color: context.colors.interactive,
                ),
                const SizedBox(width: ButlerlySpacing.standard),
                Expanded(
                  child: Text(
                    document.title,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: context.colors.interactive,
                ),
              ],
            ),
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
    appBar: AppBar(title: Text(document.title)),
    body: FutureBuilder<String>(
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
          return const Center(child: CircularProgressIndicator());
        }
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(ButlerlySpacing.section),
            child: SelectableText(snapshot.requireData),
          ),
        );
      },
    ),
  );
}

class LegalDocument {
  const LegalDocument(this.title, this.assetPath);
  final String title;
  final String assetPath;
}

const _documents = [
  LegalDocument('Terms of Use', 'assets/legal/terms_of_use.txt'),
  LegalDocument('Privacy Policy', 'assets/legal/privacy_policy.txt'),
  LegalDocument(
    'Software License & Third-Party Notices',
    'assets/legal/third_party_notices.txt',
  ),
  LegalDocument(
    'AI & Professional-Advice Disclosures',
    'assets/legal/ai_disclosures.txt',
  ),
];
