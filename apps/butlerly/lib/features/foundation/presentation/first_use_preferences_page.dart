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
                    _SetupSelectionRow(
                      label: context.l10n.text('language'),
                      value: switch (preference.locale) {
                        'zh' => context.l10n.text('chinese'),
                        'es' => context.l10n.text('spanish'),
                        _ => context.l10n.text('english'),
                      },
                      onTap: () async {
                        final value = await _showSetupSelection<String>(
                          context,
                          context.l10n.text('language'),
                          [
                            ('en', context.l10n.text('english')),
                            ('es', context.l10n.text('spanish')),
                            ('zh', context.l10n.text('chinese')),
                          ],
                        );
                        if (value != null && context.mounted) {
                          await ref
                              .read(userPreferenceProvider.notifier)
                              .saveChanges(locale: value);
                        }
                      },
                    ),
                    const SizedBox(height: ButlerlySpacing.standard),
                    _SetupSelectionRow(
                      label: context.l10n.text('baseCurrency'),
                      value: preference.baseCurrency.value,
                      onTap: () async {
                        final value = await _showSetupSelection<String>(
                          context,
                          context.l10n.text('baseCurrency'),
                          [
                            for (final code in [
                              'USD',
                              'EUR',
                              'GBP',
                              'CNY',
                              'JPY',
                            ])
                              (code, code),
                          ],
                        );
                        if (value != null && context.mounted) {
                          await ref
                              .read(userPreferenceProvider.notifier)
                              .saveChanges(baseCurrency: value);
                        }
                      },
                    ),
                    const SizedBox(height: ButlerlySpacing.standard),
                    _SetupSelectionRow(
                      label: context.l10n.text('timeZone'),
                      value: timeZoneCatalog
                          .firstWhere(
                            (zone) => zone.id == preference.timeZoneId,
                            orElse: () => timeZoneCatalog.first,
                          )
                          .label(Localizations.localeOf(context)),
                      onTap: () async {
                        final value = await _showSetupSelection<String>(
                          context,
                          context.l10n.text('timeZone'),
                          [
                            for (final zone in timeZoneCatalog)
                              (
                                zone.id,
                                zone.label(Localizations.localeOf(context)),
                              ),
                          ],
                        );
                        if (value != null && context.mounted) {
                          await ref
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

class _SetupSelectionRow extends StatelessWidget {
  const _SetupSelectionRow({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(label),
    subtitle: Text(value),
    trailing: const Icon(Icons.arrow_drop_down_rounded),
    onTap: onTap,
  );
}

Future<T?> _showSetupSelection<T>(
  BuildContext context,
  String title,
  List<(T, String)> options,
) => showModalBottomSheet<T>(
  context: context,
  showDragHandle: true,
  builder: (context) => SafeArea(
    child: ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.only(bottom: ButlerlySpacing.standard),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: ButlerlySpacing.standard,
          ),
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        for (final option in options)
          ListTile(
            title: Text(option.$2),
            onTap: () => Navigator.of(context).pop(option.$1),
          ),
      ],
    ),
  ),
);
