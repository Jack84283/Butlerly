import 'package:butlerly/features/foundation/presentation/reconciliation_labels.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const reasons = [
    'amount and currency match',
    'amount is within 10% (possible tip or adjustment)',
    'transaction date matches',
    'transaction date is within one day',
    'merchant text matches',
    'merchant text is similar',
    'payment source matches',
  ];
  const conflicts = [
    'transaction direction conflicts',
    'currency conflicts',
    'amount differs',
    'transaction date differs',
    'merchant text differs',
    'payment source differs',
  ];

  for (final locale in [const Locale('es'), const Locale('zh', 'CN')]) {
    testWidgets('reconciliation labels are localized for $locale', (
      tester,
    ) async {
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Builder(
            builder: (value) {
              context = value;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      final localizedReasons = reasons
          .map((value) => localizedReconciliationReason(context, value))
          .toList();
      final localizedConflicts = conflicts
          .map((value) => localizedReconciliationConflict(context, value))
          .toList();
      for (var index = 0; index < reasons.length; index++) {
        expect(localizedReasons[index], isNot(reasons[index]));
      }
      for (var index = 0; index < conflicts.length; index++) {
        expect(localizedConflicts[index], isNot(conflicts[index]));
      }
      expect(localizedReasons, everyElement(isNotEmpty));
      expect(localizedConflicts, everyElement(isNotEmpty));
    });
  }
}
