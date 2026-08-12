import 'package:butlerly/app/locale/locale_provider.dart';
import 'package:butlerly/app/theme/theme_mode_provider.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/foundation/presentation/legal_licenses_page.dart';
import 'package:butlerly/features/foundation/presentation/payment_sources_page.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeProvider) ?? Localizations.localeOf(context);
    return ButlerlyPage(
      title: context.l10n.text('settings'),
      children: [
        ButlerlyCard(
          color: context.colors.brand.withValues(alpha: 0.1),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: context.colors.brand,
                foregroundColor: Colors.white,
                child: const Icon(Icons.lock_outline_rounded),
              ),
              const SizedBox(width: ButlerlySpacing.standard),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.text('localOnlyStatus'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      context.l10n.text('localOnlyBody'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              ButlerlyStatusChip(
                label: context.l10n.text('clear'),
                status: ButlerlyStatus.success,
                icon: Icons.check_rounded,
              ),
            ],
          ),
        ),
        ButlerlySectionHeader(title: context.l10n.text('appearance')),
        ButlerlyCard(
          child: Column(
            children: [
              DropdownButtonFormField<ThemeMode>(
                initialValue: themeMode,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: context.l10n.text('appearance'),
                  prefixIcon: const Icon(Icons.palette_outlined),
                ),
                items: [
                  DropdownMenuItem(
                    value: ThemeMode.system,
                    child: Text(context.l10n.text('system')),
                  ),
                  DropdownMenuItem(
                    value: ThemeMode.light,
                    child: Text(context.l10n.text('light')),
                  ),
                  DropdownMenuItem(
                    value: ThemeMode.dark,
                    child: Text(context.l10n.text('dark')),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    ref.read(themeModeProvider.notifier).state = value;
                  }
                },
              ),
              const SizedBox(height: ButlerlySpacing.standard),
              DropdownButtonFormField<String>(
                initialValue: locale.languageCode,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: context.l10n.text('language'),
                  prefixIcon: const Icon(Icons.language_rounded),
                ),
                items: [
                  DropdownMenuItem(
                    value: 'en',
                    child: Text(context.l10n.text('english')),
                  ),
                  DropdownMenuItem(
                    value: 'es',
                    child: Text(context.l10n.text('spanish')),
                  ),
                  DropdownMenuItem(
                    value: 'zh',
                    child: Text(context.l10n.text('chinese')),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    ref.read(localeProvider.notifier).state = Locale(value);
                  }
                },
              ),
            ],
          ),
        ),
        ButlerlySectionHeader(title: context.l10n.text('transactions')),
        _SettingsRow(
          icon: Icons.account_balance_wallet_outlined,
          title: context.l10n.text('paymentSources'),
          subtitle: context.l10n.text('paymentSourcesBody'),
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const PaymentSourcesPage())),
        ),
        ButlerlySectionHeader(title: context.l10n.text('privacyAndData')),
        _SettingsRow(
          icon: Icons.import_export_rounded,
          title: context.l10n.text('importExport'),
          subtitle: context.l10n.text('importExportBody'),
          onTap: () => context.push('/import-export'),
        ),
        _SettingsRow(
          icon: Icons.privacy_tip_outlined,
          title: context.l10n.text('privacyAndData'),
          subtitle: context.l10n.text('privacyAndDataBody'),
          onTap: () => _showPrivacy(context),
        ),
        ButlerlySectionHeader(title: context.l10n.text('optionalFeatures')),
        _SettingsRow(
          icon: Icons.insights_outlined,
          title: context.l10n.text('insights'),
          subtitle: context.l10n.text('insightsBody'),
          onTap: () => context.push('/insights'),
        ),
        _SettingsRow(
          icon: Icons.auto_awesome_outlined,
          title: context.l10n.text('assistant'),
          subtitle: context.l10n.text('assistantUnavailableBody'),
          onTap: () => context.push('/assistant'),
        ),
        _SettingsRow(
          icon: Icons.notifications_none_rounded,
          title: context.l10n.text('notifications'),
          subtitle: context.l10n.text('notificationsBody'),
          onTap: () => context.push('/notifications'),
        ),
        ButlerlySectionHeader(title: context.l10n.text('about')),
        _SettingsRow(
          icon: Icons.gavel_outlined,
          title: context.l10n.text('legalLicenses'),
          subtitle: context.l10n.text('legalLicensesBody'),
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const LegalLicensesPage())),
        ),
        const SizedBox(height: ButlerlySpacing.structural),
      ],
    );
  }

  void _showPrivacy(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(
          ButlerlySpacing.section,
          0,
          ButlerlySpacing.section,
          ButlerlySpacing.large,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.text('privacyAndData'),
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: ButlerlySpacing.small),
            Text(context.l10n.text('localOnlyBody')),
            const SizedBox(height: ButlerlySpacing.section),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.download_outlined),
              label: Text(context.l10n.text('exportToFile')),
            ),
            TextButton.icon(
              onPressed: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(context.l10n.text('eraseNotAvailable')),
                  ),
                );
              },
              icon: const Icon(Icons.delete_forever_outlined),
              label: Text(context.l10n.text('resetAllData')),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: ButlerlySpacing.small),
    child: ButlerlyCard(
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, color: context.colors.interactive),
          const SizedBox(width: ButlerlySpacing.standard),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.bodyLarge),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
    ),
  );
}
