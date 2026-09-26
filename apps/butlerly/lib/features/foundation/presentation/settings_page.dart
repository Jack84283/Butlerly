import 'package:butlerly/app/locale/locale_provider.dart';
import 'package:butlerly/app/theme/theme_mode_provider.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/components/butlerly_modal_sheet.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/foundation/presentation/legal_licenses_page.dart';
import 'package:butlerly/features/foundation/presentation/time_zone_catalog.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
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
      title: context.l10n.text('more'),
      children: [
        _LocalOnlyBanner(),
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
                  ref
                      .read(userPreferenceProvider.notifier)
                      .saveChanges(appearance: value.name);
                }
              },
            ),
            _SettingsDropdownRow<String>(
              value: preference?.colorTheme ?? 'butlerRed',
              label: context.l10n.text('colorTheme'),
              icon: Icons.color_lens_outlined,
              items: [
                DropdownMenuItem(
                  value: 'butlerRed',
                  child: Text(context.l10n.text('butlerRed')),
                ),
                DropdownMenuItem(
                  value: 'skyBlue',
                  child: Text(context.l10n.text('skyBlue')),
                ),
                DropdownMenuItem(
                  value: 'green',
                  child: Text(context.l10n.text('green')),
                ),
              ],
              onChanged: (value) {
                if (value != null) {
                  ref
                      .read(userPreferenceProvider.notifier)
                      .saveChanges(colorTheme: value);
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
            FutureBuilder<List<TimezoneInfo>>(
              future: FlutterTimezone.getAvailableTimezones(
                Localizations.localeOf(context).toLanguageTag(),
              ),
              builder: (context, snapshot) {
                final availableZones =
                    snapshot.data ??
                    timeZoneCatalog
                        .map((zone) => TimezoneInfo(identifier: zone.id))
                        .toList(growable: false);
                final zones =
                    {
                      for (final zone in availableZones) zone.identifier: zone,
                    }.values.toList(growable: false)..sort(
                      (left, right) =>
                          left.identifier.compareTo(right.identifier),
                    );
                final selected = preference?.timeZoneId ?? 'UTC';
                return _SettingsDropdownRow<String>(
                  value: zones.any((zone) => zone.identifier == selected)
                      ? selected
                      : 'UTC',
                  label: context.l10n.text('timeZone'),
                  icon: Icons.schedule_rounded,
                  items: [
                    for (final zone in zones)
                      DropdownMenuItem(
                        value: zone.identifier,
                        child: Text(
                          zone.localizedName?.name ?? zone.identifier,
                        ),
                      ),
                  ],
                  onChanged: preference == null
                      ? (_) {}
                      : (value) {
                          if (value != null) {
                            ref
                                .read(userPreferenceProvider.notifier)
                                .saveChanges(timeZoneId: value);
                          }
                        },
                );
              },
            ),
          ],
        ),
        ButlerlySectionHeader(title: context.l10n.text('privacyAndData')),
        _SettingsSectionCard(
          children: [
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
              secondary: _SettingsIcon(icon: Icons.cloud_off_outlined),
              title: Text(context.l10n.text('externalAiConsent')),
              subtitle: Text(
                context.l10n.text('externalAiConsentBody'),
                style: _settingsSubtitleStyle(context),
              ),
              value: preference?.externalAiEnabled ?? false,
              onChanged: preference == null
                  ? null
                  : (value) => ref
                        .read(userPreferenceProvider.notifier)
                        .saveChanges(externalAiEnabled: value),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: ButlerlySpacing.standard,
              ),
            ),
            _SettingsRow(
              icon: Icons.auto_awesome_outlined,
              title: context.l10n.text('assistant'),
              subtitle: context.l10n.text('assistantUnavailableBody'),
              onTap: () => context.push('/assistant'),
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
}

class _LocalOnlyBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: context.colors.selection,
      borderRadius: BorderRadius.circular(ButlerlyRadius.standard),
      border: Border.all(
        color: context.colors.interactive.withValues(alpha: 0.25),
      ),
    ),
    child: Padding(
      padding: const EdgeInsets.all(ButlerlySpacing.standard),
      child: Row(
        children: [
          Container(
            width: ButlerlySize.preferredTarget,
            height: ButlerlySize.preferredTarget,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: context.colors.brand.withValues(alpha: 0.2),
            ),
            child: Icon(
              Icons.lock_outline_rounded,
              color: context.colors.interactive,
            ),
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
                const SizedBox(height: ButlerlySpacing.xxs),
                Text(
                  context.l10n.text('localOnlyBody'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Icon(Icons.check_rounded, color: context.colors.success),
        ],
      ),
    ),
  );
}

class _SettingsIcon extends StatelessWidget {
  const _SettingsIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    width: 36,
    height: 36,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: context.colors.selection,
    ),
    child: Icon(icon, size: 19, color: context.colors.interactive),
  );
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
    contentPadding: const EdgeInsets.symmetric(
      horizontal: ButlerlySpacing.standard,
      vertical: ButlerlySpacing.xxs,
    ),
    leading: _SettingsIcon(icon: icon),
    title: Text(title, style: Theme.of(context).textTheme.titleMedium),
    subtitle: Text(subtitle, style: _settingsSubtitleStyle(context)),
    trailing: Icon(
      Icons.chevron_right_rounded,
      color: context.colors.tertiaryText,
    ),
    onTap: onTap,
  );
}

TextStyle? _settingsSubtitleStyle(BuildContext context) => Theme.of(
  context,
).textTheme.bodySmall?.copyWith(color: context.colors.secondaryText);

class _SettingsSectionCard extends StatelessWidget {
  const _SettingsSectionCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Material(
    color: context.colors.subtleSurface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(ButlerlyRadius.standard),
      side: BorderSide(color: context.colors.border),
    ),
    clipBehavior: Clip.antiAlias,
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

  Future<void> _select(BuildContext context) async {
    final selected = await showButlerlySelectionSheet<T>(
      context: context,
      title: label,
      selectedValue: value,
      options: [
        for (final item in items)
          ButlerlySelectionOption(value: item.value as T, child: item.child),
      ],
    );
    if (selected != null) onChanged(selected);
  }

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(
      horizontal: ButlerlySpacing.standard,
      vertical: ButlerlySpacing.xxs,
    ),
    leading: _SettingsIcon(icon: icon),
    title: Text(label, style: Theme.of(context).textTheme.bodySmall),
    subtitle: _selectedItem(context),
    trailing: Icon(
      Icons.keyboard_arrow_down_rounded,
      color: context.colors.tertiaryText,
    ),
    dense: true,
    minVerticalPadding: ButlerlySpacing.compact,
    onTap: () => _select(context),
  );

  Widget _selectedItem(BuildContext context) {
    final selected = items.where((item) => item.value == value).first;
    return DefaultTextStyle.merge(
      style: Theme.of(context).textTheme.bodyLarge,
      child: selected.child,
    );
  }
}
