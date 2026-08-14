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
    final preference = ref.watch(userPreferenceProvider).value;
    final locale = preference == null
        ? Localizations.localeOf(context)
        : Locale(preference.locale);
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
        _SettingsSectionCard(
          children: [
            _SettingsDropdownRow<ThemeMode>(
              value: themeMode,
              label: context.l10n.text('appearance'),
              icon: Icons.palette_outlined,
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
            _SettingsDropdownRow<String>(
              value: locale.languageCode,
              label: context.l10n.text('language'),
              icon: Icons.language_rounded,
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
                  ref
                      .read(userPreferenceProvider.notifier)
                      .saveChanges(locale: value);
                }
              },
            ),
            _SettingsDropdownRow<String>(
              value: preference?.baseCurrency.value ?? 'USD',
              label: context.l10n.text('baseCurrency'),
              icon: Icons.currency_exchange_rounded,
              items: const ['USD', 'EUR', 'GBP', 'CNY', 'JPY']
                  .map(
                    (code) => DropdownMenuItem(value: code, child: Text(code)),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  ref
                      .read(userPreferenceProvider.notifier)
                      .saveChanges(baseCurrency: value);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.schedule_rounded),
              title: Text(context.l10n.text('timeZone')),
              subtitle: Text(
                preference?.timeZoneId ?? DateTime.now().timeZoneName,
              ),
              trailing: const Icon(Icons.edit_outlined),
              onTap: preference == null
                  ? null
                  : () => _editTimeZone(context, ref, preference.timeZoneId),
            ),
          ],
        ),
        ButlerlySectionHeader(title: context.l10n.text('transactions')),
        _SettingsSectionCard(
          children: [
            _SettingsRow(
              icon: Icons.account_balance_wallet_outlined,
              title: context.l10n.text('paymentSources'),
              subtitle: context.l10n.text('paymentSourcesBody'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PaymentSourcesPage()),
              ),
            ),
          ],
        ),
        ButlerlySectionHeader(title: context.l10n.text('privacyAndData')),
        _SettingsSectionCard(
          children: [
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
              onTap: () => context.push('/privacy-data'),
            ),
          ],
        ),
        ButlerlySectionHeader(title: context.l10n.text('optionalFeatures')),
        _SettingsSectionCard(
          children: [
            SwitchListTile(
              secondary: const Icon(Icons.cloud_off_outlined),
              title: Text(context.l10n.text('externalAiConsent')),
              subtitle: Text(context.l10n.text('externalAiConsentBody')),
              value: preference?.externalAiEnabled ?? false,
              onChanged: preference == null
                  ? null
                  : (value) => ref
                        .read(userPreferenceProvider.notifier)
                        .saveChanges(externalAiEnabled: value),
            ),
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
          ],
        ),
        ButlerlySectionHeader(title: context.l10n.text('about')),
        _SettingsSectionCard(
          children: [
            _SettingsRow(
              icon: Icons.gavel_outlined,
              title: context.l10n.text('legalLicenses'),
              subtitle: context.l10n.text('legalLicensesBody'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const LegalLicensesPage()),
              ),
            ),
          ],
        ),
        const SizedBox(height: ButlerlySpacing.structural),
      ],
    );
  }

  Future<void> _editTimeZone(
    BuildContext context,
    WidgetRef ref,
    String current,
  ) async {
    final controller = TextEditingController(text: current);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.text('timeZone')),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: context.l10n.text('ianaTimeZone'),
            helperText: context.l10n.text('ianaTimeZoneHelp'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.text('cancel')),
          ),
          FilledButton(
            onPressed: () {
              final normalized = controller.text.trim();
              if (_validTimeZone(normalized)) {
                Navigator.pop(context, normalized);
              }
            },
            child: Text(context.l10n.text('save')),
          ),
        ],
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    if (value != null) {
      await ref
          .read(userPreferenceProvider.notifier)
          .saveChanges(timeZoneId: value);
    }
  }

  bool _validTimeZone(String value) =>
      value == 'UTC' ||
      RegExp(r'^[A-Za-z_+-]+/[A-Za-z0-9_+\-/]+$').hasMatch(value);
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
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon, color: context.colors.interactive),
    title: Text(title),
    subtitle: Text(subtitle),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: onTap,
  );
}

class _SettingsSectionCard extends StatelessWidget {
  const _SettingsSectionCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ButlerlyCard(
    padding: EdgeInsets.zero,
    child: ButlerlySeparatedList(children: children),
  );
}

class _SettingsDropdownRow<T> extends StatelessWidget {
  const _SettingsDropdownRow({
    required this.value,
    required this.label,
    required this.icon,
    required this.items,
    required this.onChanged,
  });

  final T value;
  final String label;
  final IconData icon;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: ButlerlySpacing.standard),
    child: DropdownButtonFormField<T>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: context.colors.interactive),
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: ButlerlySpacing.standard,
          vertical: ButlerlySpacing.small,
        ),
      ),
      items: items,
      onChanged: onChanged,
    ),
  );
}
