import 'package:butlerly/app/shell/iphone/iphone_primary_shell.dart';
import 'package:butlerly/app/theme/app_theme.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('flat footer keeps all primary destinations vertically aligned', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var tapped = false;
    var selectedBranch = -1;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: IPhonePrimaryShell(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: TextButton(
              key: const ValueKey('bottom-page-action'),
              onPressed: () => tapped = true,
              child: const Text('Bottom action'),
            ),
          ),
          destinations: const <int, NavigationDestination>{
            0: NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Home',
            ),
            1: NavigationDestination(icon: Icon(Icons.add), label: 'Add'),
            2: NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long),
              label: 'Transactions',
            ),
            3: NavigationDestination(
              icon: Icon(Icons.more_horiz),
              label: 'More',
            ),
          },
          visualBranchIndexes: const [0, 1, 2, 3],
          currentIndex: 0,
          onSelected: (index) => selectedBranch = index,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final bodyRect = tester.getRect(
      find.byKey(const ValueKey('primary-phone-body-surface')),
    );
    final navigationRect = tester.getRect(
      find.byKey(const ValueKey('primary-phone-navigation')),
    );
    final baseRect = tester.getRect(
      find.byKey(const ValueKey('primary-navigation-base')),
    );
    final navigationContentRect = tester.getRect(
      find.byKey(const ValueKey('primary-navigation-content')),
    );

    expect(bodyRect.bottom, closeTo(navigationRect.top, 0.01));
    expect(baseRect.top, closeTo(navigationRect.top, 0.01));
    expect(baseRect.bottom, closeTo(navigationRect.bottom, 0.01));
    expect(
      navigationContentRect.top - navigationRect.top,
      closeTo(ButlerlySize.primaryNavigationArchRise, 0.01),
    );
    expect(
      navigationContentRect.height,
      greaterThanOrEqualTo(ButlerlySize.navigationBarHeight),
    );
    expect(
      find.byKey(const ValueKey('primary-navigation-add-arch')),
      findsNothing,
    );

    final addLabelTop = tester.getTopLeft(find.text('Add')).dy;
    for (final label in ['Home', 'Transactions', 'More']) {
      final labelTop = tester.getTopLeft(find.text(label)).dy;
      expect(labelTop, closeTo(addLabelTop, 0.01));
    }

    final addRect = tester.getRect(
      find.byKey(const ValueKey('primary-navigation-add-button')),
    );

    await tester.tapAt(addRect.center);
    expect(selectedBranch, 1);

    await tester.tap(find.byKey(const ValueKey('bottom-page-action')));
    expect(tapped, isTrue);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
}
