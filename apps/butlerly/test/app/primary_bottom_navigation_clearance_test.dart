import 'package:butlerly/app/shell/iphone/iphone_primary_shell.dart';
import 'package:butlerly/app/theme/app_theme.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('raised Add arch does not cover primary page actions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var tapped = false;
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
          onSelected: (_) {},
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
    final archFinder = find.byKey(
      const ValueKey('primary-navigation-add-arch'),
    );
    final archRect = tester.getRect(archFinder);
    final arch = tester.widget<Container>(archFinder);
    final navigationContentRect = tester.getRect(
      find.byKey(const ValueKey('primary-navigation-content')),
    );

    expect(bodyRect.bottom, closeTo(navigationRect.top, 0.01));
    expect(
      archRect.top,
      closeTo(
        navigationRect.top - ButlerlySize.primaryNavigationArchRise,
        0.01,
      ),
    );
    expect(archRect.bottom, greaterThan(navigationRect.top));
    expect(arch.foregroundDecoration, isNotNull);
    expect(navigationContentRect.height, ButlerlySize.navigationBarHeight);

    await tester.tap(find.byKey(const ValueKey('bottom-page-action')));
    expect(tapped, isTrue);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
}
