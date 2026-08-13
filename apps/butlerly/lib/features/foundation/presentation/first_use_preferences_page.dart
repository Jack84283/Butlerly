import 'package:butlerly/app/locale/locale_provider.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
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
            ButlerlyCard(
              child: Column(
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: preference.locale,
                    decoration: InputDecoration(
                      labelText: context.l10n.text('language'),
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
                        ref
                            .read(userPreferenceProvider.notifier)
                            .saveChanges(locale: value);
                      }
                    },
                  ),
                  const SizedBox(height: ButlerlySpacing.standard),
                  DropdownButtonFormField<String>(
                    initialValue: preference.baseCurrency.value,
                    decoration: InputDecoration(
                      labelText: context.l10n.text('baseCurrency'),
                    ),
                    items: const ['USD', 'EUR', 'GBP', 'CNY', 'JPY']
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value),
                          ),
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
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.schedule_rounded),
                    title: Text(context.l10n.text('timeZone')),
                    subtitle: Text(preference.timeZoneId),
                  ),
                ],
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
