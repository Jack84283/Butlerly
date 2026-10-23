import 'package:butlerly/app/locale/locale_provider.dart';
import 'package:butlerly/app/shell/adaptive_shell.dart';
import 'package:butlerly/app/theme/theme_mode_provider.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/components/butlerly_modal_sheet.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/foundation/presentation/legal_licenses_page.dart';
import 'package:butlerly/features/foundation/presentation/time_zone_catalog.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:go_router/go_router.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({this.initialSection, super.key});

  final String? initialSection;

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final _appearanceKey = GlobalKey();
  final _aboutKey = GlobalKey();
  String? _scheduledSection;
  late final Future<String> _desktopVersion = rootBundle
      .loadString('pubspec.yaml')
      .then((contents) {
        return RegExp(
              r'^version:\s*([^\s#]+)',
              multiLine: true,
            ).firstMatch(contents)?.group(1) ??
            '—';
      })
      .catchError((Object _) => '—');

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scheduleInitialScroll();
  }

  @override
  void didUpdateWidget(covariant SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialSection != widget.initialSection) {
      _scheduleInitialScroll();
    }
  }

  void _scheduleInitialScroll() {
    final section = widget.initialSection;
    if (section == null || section == _scheduledSection) return;
    _scheduledSection = section;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = switch (section) {
        'appearance' => _appearanceKey,
        'about' => _aboutKey,
        _ => null,
      };
      final targetContext = target?.currentContext;
      if (targetContext != null) {
        Scrollable.ensureVisible(
          targetContext,
          alignment: 0.0,
          duration: ButlerlyMotion.responsive(context, ButlerlyMotion.fast),
        );
      }
    });
  }

  Future<void> _editDisplayName(String currentName) async {
    // Let the text field own its controller for the entire sheet lifecycle.
    // A route can keep building during its exit animation after pop returns.
    var editedName = currentName;
    final updated = await showButlerlyBottomSheet<String>(
      context: context,
      builder: (sheetContext) => ButlerlySheet(
        title: Text(sheetContext.l10n.text('displayName')),
        content: TextFormField(
          key: const ValueKey('settings-display-name-input'),
          initialValue: currentName,
          onChanged: (value) => editedName = value,
          autofocus: true,
          maxLength: 10,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            hintText: sheetContext.l10n.text('displayNameHint'),
          ),
        ),
        actions: [
          ButlerlyCancelButton(
            onPressed: () => Navigator.of(sheetContext).pop(),
            child: Text(sheetContext.l10n.text('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(sheetContext).pop(editedName.trim()),
            child: Text(sheetContext.l10n.text('save')),
          ),
        ],
      ),
    );
    if (updated != null && mounted) {
      await ref
          .read(userPreferenceProvider.notifier)
          .saveChanges(displayName: updated);
    }
  }

  Future<void> _chooseDesktopValue<T>({
    required String label,
    required T value,
    required List<DropdownMenuItem<T>> options,
    required ValueChanged<T> onChanged,
  }) async {
    final selected = await showButlerlySelectionSheet<T>(
      context: context,
      title: label,
      selectedValue: value,
      options: [
        for (final option in options)
          ButlerlySelectionOption(
            value: option.value as T,
            child: option.child,
          ),
      ],
    );
    if (selected != null && mounted) onChanged(selected);
  }

  Widget _buildDesktopMore(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final preference = ref.watch(userPreferenceProvider).value;
    final locale = preference == null
        ? Localizations.localeOf(context)
        : Locale(preference.locale);
    final l10n = context.l10n;

    Widget tile(
      IconData icon,
      String label,
      String value,
      VoidCallback onTap,
    ) => _DesktopMoreRow(icon: icon, title: label, value: value, onTap: onTap);

    final preferences = <Widget>[
      tile(
        Icons.person_outline_rounded,
        l10n.text('displayName'),
        preference?.displayName.isNotEmpty == true
            ? preference!.displayName
            : l10n.text('displayNameNotSet'),
        () => _editDisplayName(preference?.displayName ?? ''),
      ),
      tile(
        Icons.palette_outlined,
        l10n.text('appearance'),
        l10n.text(themeMode.name),
        () => _chooseDesktopValue<ThemeMode>(
          label: l10n.text('appearance'),
          value: themeMode,
          options: [
            DropdownMenuItem(
              value: ThemeMode.system,
              child: Text(l10n.text('system')),
            ),
            DropdownMenuItem(
              value: ThemeMode.light,
              child: Text(l10n.text('light')),
            ),
            DropdownMenuItem(
              value: ThemeMode.dark,
              child: Text(l10n.text('dark')),
            ),
          ],
          onChanged: (value) => ref
              .read(userPreferenceProvider.notifier)
              .saveChanges(appearance: value.name),
        ),
      ),
      tile(
        Icons.color_lens_outlined,
        l10n.text('colorTheme'),
        l10n.text(preference?.colorTheme ?? 'butlerRed'),
        () => _chooseDesktopValue<String>(
          label: l10n.text('colorTheme'),
          value: preference?.colorTheme ?? 'butlerRed',
          options: [
            DropdownMenuItem(
              value: 'butlerRed',
              child: Text(l10n.text('butlerRed')),
            ),
            DropdownMenuItem(
              value: 'skyBlue',
              child: Text(l10n.text('skyBlue')),
            ),
            DropdownMenuItem(value: 'green', child: Text(l10n.text('green'))),
          ],
          onChanged: (value) => ref
              .read(userPreferenceProvider.notifier)
              .saveChanges(colorTheme: value),
        ),
      ),
      tile(
        Icons.language_rounded,
        l10n.text('language'),
        l10n.text(switch (locale.languageCode) {
          'es' => 'spanish',
          'zh' => 'chinese',
          _ => 'english',
        }),
        () => _chooseDesktopValue<String>(
          label: l10n.text('language'),
          value: locale.languageCode,
          options: [
            DropdownMenuItem(value: 'en', child: Text(l10n.text('english'))),
            DropdownMenuItem(value: 'es', child: Text(l10n.text('spanish'))),
            DropdownMenuItem(value: 'zh', child: Text(l10n.text('chinese'))),
          ],
          onChanged: (value) => ref
              .read(userPreferenceProvider.notifier)
              .saveChanges(locale: value),
        ),
      ),
      tile(
        Icons.currency_exchange_rounded,
        l10n.text('baseCurrency'),
        preference?.baseCurrency.value ?? 'USD',
        () => _chooseDesktopValue<String>(
          label: l10n.text('baseCurrency'),
          value: preference?.baseCurrency.value ?? 'USD',
          options: const ['USD', 'EUR', 'GBP', 'CNY', 'JPY']
              .map((code) => DropdownMenuItem(value: code, child: Text(code)))
              .toList(),
          onChanged: (value) => ref
              .read(userPreferenceProvider.notifier)
              .saveChanges(baseCurrency: value),
        ),
      ),
      FutureBuilder<List<TimezoneInfo>>(
        future: FlutterTimezone.getAvailableTimezones(
          Localizations.localeOf(context).toLanguageTag(),
        ),
        builder: (context, snapshot) {
          final zones =
              {
                  for (final zone
                      in snapshot.data ??
                          timeZoneCatalog.map(
                            (entry) => TimezoneInfo(identifier: entry.id),
                          ))
                    zone.identifier: zone,
                }.values.toList(growable: false)
                ..sort((a, b) => a.identifier.compareTo(b.identifier));
          final requestedZone = preference?.timeZoneId ?? 'UTC';
          final zone = zones.any((entry) => entry.identifier == requestedZone)
              ? requestedZone
              : 'UTC';
          final zoneLabel = zones
              .where((entry) => entry.identifier == zone)
              .firstOrNull;
          return tile(
            Icons.schedule_rounded,
            l10n.text('timeZone'),
            zoneLabel?.localizedName?.name ?? zone,
            () => _chooseDesktopValue<String>(
              label: l10n.text('timeZone'),
              value: zone,
              options: [
                for (final item in zones)
                  DropdownMenuItem(
                    value: item.identifier,
                    child: Text(item.localizedName?.name ?? item.identifier),
                  ),
              ],
              onChanged: (value) => ref
                  .read(userPreferenceProvider.notifier)
                  .saveChanges(timeZoneId: value),
            ),
          );
        },
      ),
    ];

    return ButlerlyPage(
      title: l10n.text('more'),
      subtitle: l10n.text('moreDescription'),
      fullWidth: true,
      children: [
        const _DesktopMoreProtectionBanner(),
        const SizedBox(height: ButlerlySpacing.standard),
        LayoutBuilder(
          builder: (context, constraints) {
            final left = _DesktopMoreCard(
              key: _appearanceKey,
              title: l10n.text('preferences'),
              icon: Icons.tune_rounded,
              children: preferences,
            );
            final right = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _DesktopMoreCard(
                  title: l10n.text('privacyAndData'),
                  icon: Icons.shield_outlined,
                  description: l10n.text('privacyAndDataBody'),
                  children: [
                    _DesktopMoreRow(
                      title: l10n.text('managePrivacyData'),
                      onTap: () => context.push('/privacy-data'),
                    ),
                  ],
                ),
                const SizedBox(height: ButlerlySpacing.small),
                _DesktopMoreCard(
                  title: l10n.text('optionalFeatures'),
                  icon: Icons.auto_awesome_outlined,
                  children: [
                    _DesktopMoreRow(
                      title: l10n.text('externalAiConsentTitle'),
                      value: preference?.externalAiEnabled == true
                          ? l10n.text('enabled')
                          : l10n.text('optional'),
                      onTap: preference == null
                          ? null
                          : () => _chooseDesktopValue<bool>(
                              label: l10n.text('externalAiConsentTitle'),
                              value: preference.externalAiEnabled,
                              options: [
                                DropdownMenuItem(
                                  value: false,
                                  child: Text(l10n.text('disabled')),
                                ),
                                DropdownMenuItem(
                                  value: true,
                                  child: Text(l10n.text('enabled')),
                                ),
                              ],
                              onChanged: (value) => ref
                                  .read(userPreferenceProvider.notifier)
                                  .saveChanges(externalAiEnabled: value),
                            ),
                    ),
                    _DesktopMoreRow(
                      title: l10n.text('assistant'),
                      onTap: () => context.push('/assistant'),
                    ),
                  ],
                ),
                const SizedBox(height: ButlerlySpacing.small),
                _DesktopMoreCard(
                  key: _aboutKey,
                  title: l10n.text('about'),
                  icon: Icons.info_outline_rounded,
                  footer: FutureBuilder<String>(
                    future: _desktopVersion,
                    builder: (context, snapshot) {
                      final parts = (snapshot.data ?? '—').split('+');
                      final build = parts.length > 1
                          ? ' (${l10n.text('buildLabel')} ${parts.last})'
                          : '';
                      return Text(
                        '${l10n.text('appVersionLabel')} ${parts.first}$build',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: context.colors.secondaryText,
                        ),
                      );
                    },
                  ),
                  children: [
                    _DesktopMoreRow(
                      title: l10n.text('legalLicenses'),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const LegalLicensesPage(),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            );
            if (constraints.maxWidth < 720) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  left,
                  const SizedBox(height: ButlerlySpacing.standard),
                  right,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 6, child: left),
                const SizedBox(width: ButlerlySpacing.standard),
                Expanded(flex: 5, child: right),
              ],
            );
          },
        ),
        const SizedBox(height: ButlerlySpacing.section),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final preference = ref.watch(userPreferenceProvider).value;
    final locale = preference == null
        ? Localizations.localeOf(context)
        : Locale(preference.locale);
    if (effectiveButlerlyLayoutMode(
          context,
          MediaQuery.sizeOf(context).width,
        ) ==
        ButlerlyLayoutMode.wide) {
      return _buildDesktopMore(context);
    }
    return ButlerlyPage(
      title: context.l10n.text('more'),
      children: [
        _LocalOnlyBanner(),
        ButlerlySectionHeader(
          key: _appearanceKey,
          title: context.l10n.text('appearance'),
        ),
        _SettingsSectionCard(
          children: [
            _SettingsRow(
              icon: Icons.person_outline_rounded,
              title: context.l10n.text('displayName'),
              titleStyle: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w400),
              subtitle: preference?.displayName.isNotEmpty == true
                  ? preference!.displayName
                  : context.l10n.text('displayNameNotSet'),
              onTap: () => _editDisplayName(preference?.displayName ?? ''),
            ),
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
        ButlerlySectionHeader(
          key: _aboutKey,
          title: context.l10n.text('about'),
        ),
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

class _DesktopMoreProtectionBanner extends StatelessWidget {
  const _DesktopMoreProtectionBanner();

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final green = context.colors.success;
    return Container(
      key: const ValueKey('desktop-more-protection'),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF1E342B) : const Color(0xFFE5F7ED),
        borderRadius: BorderRadius.circular(ButlerlyRadius.standard),
        border: Border.all(
          color: dark ? const Color(0xFF2A4438) : const Color(0xFFCBE6D7),
        ),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: ButlerlySpacing.standard,
        vertical: ButlerlySpacing.small,
      ),
      child: Row(
        children: [
          Container(
            height: 38,
            width: 38,
            decoration: BoxDecoration(
              color: dark ? const Color(0xFF2E875C) : const Color(0xFFB6E9CD),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.shield_outlined, color: green, size: 23),
          ),
          const SizedBox(width: ButlerlySpacing.standard),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.text('localOnlyProtection'),
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  context.l10n.text('localOnlyProtectionBody'),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.colors.secondaryText,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: ButlerlySpacing.standard),
          Icon(Icons.check_circle_rounded, color: green, size: 25),
        ],
      ),
    );
  }
}

class _DesktopMoreCard extends StatelessWidget {
  const _DesktopMoreCard({
    required this.title,
    required this.icon,
    required this.children,
    this.description,
    this.footer,
    super.key,
  });

  final String title;
  final IconData icon;
  final String? description;
  final List<Widget> children;
  final Widget? footer;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: context.colors.cardSurface,
      border: Border.all(color: context.colors.cardDivider),
      borderRadius: BorderRadius.circular(ButlerlyRadius.standard),
    ),
    padding: const EdgeInsets.symmetric(
      horizontal: ButlerlySpacing.standard,
      vertical: ButlerlySpacing.small,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(icon, size: 22, color: context.colors.primaryText),
            const SizedBox(width: ButlerlySpacing.standard),
            Expanded(
              child: Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        if (description != null) ...[
          const SizedBox(height: ButlerlySpacing.xxs),
          Padding(
            padding: const EdgeInsets.only(left: 38),
            child: Text(
              description!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: context.colors.secondaryText,
              ),
            ),
          ),
        ],
        const SizedBox(height: ButlerlySpacing.compact),
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0)
            Divider(height: 1, thickness: 1, color: context.colors.cardDivider),
          children[i],
        ],
        if (footer != null) ...[
          Divider(height: 1, thickness: 1, color: context.colors.cardDivider),
          Padding(
            padding: const EdgeInsets.only(
              left: 38,
              top: ButlerlySpacing.compact,
              bottom: ButlerlySpacing.xxs,
            ),
            child: footer!,
          ),
        ],
      ],
    ),
  );
}

class _DesktopMoreRow extends StatelessWidget {
  const _DesktopMoreRow({
    required this.title,
    this.icon,
    this.value,
    this.onTap,
  });

  final String title;
  final IconData? icon;
  final String? value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 43),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: ButlerlySpacing.compact,
          ),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 19, color: context.colors.secondaryText),
                const SizedBox(width: ButlerlySpacing.standard),
              ] else
                const SizedBox(width: 38),
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              if (value != null) ...[
                const SizedBox(width: ButlerlySpacing.compact),
                Flexible(
                  child: Text(
                    value!,
                    textAlign: TextAlign.end,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: context.colors.secondaryText,
                    ),
                  ),
                ),
              ],
              const SizedBox(width: ButlerlySpacing.compact),
              Icon(
                Icons.chevron_right_rounded,
                color: context.colors.tertiaryText,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    ),
  );
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
              _settingsIcon(context, Icons.lock_outline_rounded),
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
          Icon(
            _settingsIcon(context, Icons.check_rounded),
            color: context.colors.success,
          ),
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
    child: Icon(
      _settingsIcon(context, icon),
      size: 19,
      color: context.colors.interactive,
    ),
  );
}

IconData _settingsIcon(BuildContext context, IconData material) {
  if (kIsWeb || Theme.of(context).platform != TargetPlatform.iOS) {
    return material;
  }
  return switch (material) {
    Icons.lock_outline_rounded => CupertinoIcons.lock,
    Icons.check_rounded => CupertinoIcons.check_mark,
    Icons.palette_outlined => CupertinoIcons.paintbrush,
    Icons.color_lens_outlined => CupertinoIcons.paintbrush_fill,
    Icons.language_rounded => CupertinoIcons.globe,
    Icons.currency_exchange_rounded => CupertinoIcons.money_dollar_circle,
    Icons.schedule_rounded => CupertinoIcons.clock,
    Icons.privacy_tip_outlined => CupertinoIcons.lock_shield,
    Icons.cloud_off_outlined => CupertinoIcons.cloud,
    Icons.auto_awesome_outlined => CupertinoIcons.sparkles,
    Icons.gavel_outlined => CupertinoIcons.doc_text,
    Icons.chevron_right_rounded => CupertinoIcons.chevron_right,
    Icons.keyboard_arrow_down_rounded => CupertinoIcons.chevron_down,
    _ => material,
  };
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.title,
    this.titleStyle,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final TextStyle? titleStyle;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(
      horizontal: ButlerlySpacing.standard,
      vertical: ButlerlySpacing.xxs,
    ),
    leading: _SettingsIcon(icon: _settingsIcon(context, icon)),
    title: Text(
      title,
      style: titleStyle ?? Theme.of(context).textTheme.titleMedium,
    ),
    subtitle: Text(subtitle, style: _settingsSubtitleStyle(context)),
    trailing: Icon(
      _settingsIcon(context, Icons.chevron_right_rounded),
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
    leading: _SettingsIcon(icon: _settingsIcon(context, icon)),
    title: Text(label, style: Theme.of(context).textTheme.bodySmall),
    subtitle: _selectedItem(context),
    trailing: Icon(
      _settingsIcon(context, Icons.keyboard_arrow_down_rounded),
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
