import 'package:butlerly/app/locale/locale_provider.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/foundation/presentation/time_zone_catalog.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class FirstUsePreferencesPage extends ConsumerWidget {
  const FirstUsePreferencesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preference = ref.watch(userPreferenceProvider).value!;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(ButlerlySpacing.section),
          children: [
            const SizedBox(height: ButlerlySpacing.large),
            const Icon(Icons.lock_outline_rounded, size: 48),
            const SizedBox(height: ButlerlySpacing.section),
            Text(
              context.l10n.text('firstUseTitle'),
              style: Theme.of(context).textTheme.headlineLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: ButlerlySpacing.small),
            Text(
              context.l10n.text('firstUseBody'),
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            ButlerlySectionHeader(title: context.l10n.text('preferences')),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(ButlerlySpacing.standard),
                child: Column(
                  children: [
                    _SetupDropdown<String>(
                      label: context.l10n.text('language'),
                      value: preference.locale,
                      entries: [
                        DropdownMenuEntry(
                          value: 'en',
                          label: context.l10n.text('english'),
                        ),
                        DropdownMenuEntry(
                          value: 'es',
                          label: context.l10n.text('spanish'),
                        ),
                        DropdownMenuEntry(
                          value: 'zh',
                          label: context.l10n.text('chinese'),
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
                    const SizedBox(height: ButlerlySpacing.standard),
                    _SetupDropdown<String>(
                      label: context.l10n.text('baseCurrency'),
                      value: preference.baseCurrency.value,
                      entries: [
                        for (final value in const [
                          'USD',
                          'EUR',
                          'GBP',
                          'CNY',
                          'JPY',
                        ])
                          DropdownMenuEntry(value: value, label: value),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          ref
                              .read(userPreferenceProvider.notifier)
                              .saveChanges(baseCurrency: value);
                        }
                      },
                    ),
                    const SizedBox(height: ButlerlySpacing.standard),
                    _SetupDropdown<String>(
                      label: context.l10n.text('timeZone'),
                      value:
                          timeZoneCatalog.any(
                            (zone) => zone.id == preference.timeZoneId,
                          )
                          ? preference.timeZoneId
                          : 'UTC',
                      leadingIcon: Icons.schedule_rounded,
                      entries: [
                        for (final zone in timeZoneCatalog)
                          DropdownMenuEntry(
                            value: zone.id,
                            label: zone.label(Localizations.localeOf(context)),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          ref
                              .read(userPreferenceProvider.notifier)
                              .saveChanges(timeZoneId: value);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: ButlerlySpacing.section),
            FilledButton(
              onPressed: () => ref
                  .read(userPreferenceProvider.notifier)
                  .saveChanges(firstUseCompleted: true),
              child: Text(context.l10n.text('continueLocally')),
            ),
          ],
        ),
      ),
    );
  }
}

class _SetupDropdown<T> extends StatelessWidget {
  const _SetupDropdown({
    required this.label,
    required this.value,
    required this.entries,
    required this.onChanged,
    this.leadingIcon,
  });

  final String label;
  final T? value;
  final List<DropdownMenuEntry<T>> entries;
  final ValueChanged<T?> onChanged;
  final IconData? leadingIcon;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => DropdownMenu<T>(
      initialSelection: value,
      width: constraints.maxWidth,
      menuHeight: 192,
      label: Text(label),
      leadingIcon: leadingIcon == null ? null : Icon(leadingIcon),
      dropdownMenuEntries: entries,
      inputDecorationTheme: Theme.of(context).inputDecorationTheme,
      menuStyle: MenuStyle(
        minimumSize: WidgetStatePropertyAll(Size(constraints.maxWidth, 0)),
        maximumSize: WidgetStatePropertyAll(
          Size(constraints.maxWidth, double.infinity),
        ),
        backgroundColor: WidgetStatePropertyAll(
          Theme.of(context).colorScheme.surface,
        ),
      ),
      onSelected: onChanged,
    ),
  );
}
