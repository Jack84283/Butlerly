import 'package:butlerly/app/theme/theme_mode_provider.dart';
import 'package:butlerly/features/foundation/presentation/payment_sources_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Settings', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 24),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.account_balance_wallet_outlined),
          title: const Text('Payment sources'),
          subtitle: const Text(
            'Manage local accounts, cards, cash, and wallets.',
          ),
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const PaymentSourcesPage())),
        ),
        const SizedBox(height: 24),
        DropdownButtonFormField<ThemeMode>(
          initialValue: themeMode,
          decoration: const InputDecoration(labelText: 'Appearance'),
          items: const [
            DropdownMenuItem(value: ThemeMode.system, child: Text('System')),
            DropdownMenuItem(value: ThemeMode.light, child: Text('Light')),
            DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
          ],
          onChanged: (value) {
            if (value != null) {
              ref.read(themeModeProvider.notifier).state = value;
            }
          },
        ),
        const SizedBox(height: 24),
        const ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.lock_outline),
          title: Text('Local-first by default'),
          subtitle: Text(
            'Core use does not require an account, cloud service, or AI provider.',
          ),
        ),
      ],
    );
  }
}
