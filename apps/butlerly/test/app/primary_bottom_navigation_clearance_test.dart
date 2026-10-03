import 'dart:ui' show SemanticsAction, Tristate;

import 'package:butlerly/app/shell/compact/compact_primary_shell.dart';
import 'package:butlerly/app/theme/app_theme.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
        home: CompactPrimaryShell(
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
            1: NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long),
              label: 'Transactions',
            ),
            2: NavigationDestination(
              icon: Icon(Icons.add_rounded),
              selectedIcon: Icon(Icons.add_rounded),
              label: 'Add',
            ),
            3: NavigationDestination(
              icon: Icon(Icons.bar_chart_rounded),
              selectedIcon: Icon(Icons.bar_chart_rounded),
              label: 'Tools',
            ),
            4: NavigationDestination(
              icon: Icon(Icons.more_horiz_rounded),
              selectedIcon: Icon(Icons.more_horiz_rounded),
              label: 'More',
            ),
          },
          visualBranchIndexes: const [0, 1, 2, 3, 4],
          currentIndex: 0,
          onSelected: (index) => selectedBranch = index,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final bodyRect = tester.getRect(
      find.byKey(const ValueKey('primary-compact-body-surface')),
    );
    final navigationRect = tester.getRect(
      find.byKey(const ValueKey('primary-compact-navigation')),
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
    expect(navigationContentRect.top, closeTo(navigationRect.top, 0.01));
    expect(
      navigationContentRect.height,
      closeTo(ButlerlySize.navigationBarHeight, 0.01),
    );
    expect(ButlerlySize.navigationBarHeight, 48);
    expect(
      find.byKey(const ValueKey('primary-navigation-add-arch')),
      findsNothing,
    );
    final addButton = find.byKey(
      const ValueKey('primary-navigation-add-button'),
    );
    expect(addButton, findsOneWidget);
    expect(
      find.descendant(of: addButton, matching: find.byType(Container)),
      findsNothing,
    );
    expect(find.text('Add'), findsOneWidget);

    await tester.tap(find.text('Txns'));
    expect(selectedBranch, 1);

    await tester.tap(find.byKey(const ValueKey('bottom-page-action')));
    expect(tapped, isTrue);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets(
    'compact navigation labels wrap without clipping across locales and text scales',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const cases = [
        (Locale('en'), ['Home', 'Txns', 'Add', 'Tools', 'More']),
        (Locale('es'), ['Ini.', 'Tr.', 'Añ.', 'Her.', 'Más']),
        (Locale('zh'), ['首页', '交易', '添加', '工具', '更多']),
      ];
      for (final (locale, visibleLabels) in cases) {
        for (final scale in [1.0, 2.5]) {
          await tester.pumpWidget(
            MaterialApp(
              locale: locale,
              theme: AppTheme.light,
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Builder(
                  builder: (context) => CompactPrimaryShell(
                    body: const SizedBox.shrink(),
                    destinations: {
                      0: NavigationDestination(
                        icon: Icon(Icons.home_outlined),
                        selectedIcon: Icon(Icons.home),
                        label: context.l10n.text('home'),
                      ),
                      1: NavigationDestination(
                        icon: Icon(Icons.receipt_long_outlined),
                        selectedIcon: Icon(Icons.receipt_long),
                        label: context.l10n.text('transactions'),
                      ),
                      2: NavigationDestination(
                        icon: Icon(Icons.add_rounded),
                        selectedIcon: Icon(Icons.add_rounded),
                        label: context.l10n.text('add'),
                      ),
                      3: NavigationDestination(
                        icon: Icon(Icons.bar_chart_rounded),
                        selectedIcon: Icon(Icons.bar_chart_rounded),
                        label: context.l10n.text('tools'),
                      ),
                      4: NavigationDestination(
                        icon: Icon(Icons.more_horiz_rounded),
                        selectedIcon: Icon(Icons.more_horiz_rounded),
                        label: context.l10n.text('more'),
                      ),
                    },
                    visualBranchIndexes: const [0, 1, 2, 3, 4],
                    currentIndex: 0,
                    onSelected: (_) {},
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          for (var index = 0; index < visibleLabels.length; index++) {
            expect(find.text(visibleLabels[index]), findsOneWidget);
            final labelSlot = find.byKey(
              ValueKey('primary-navigation-label-$index'),
            );
            final paragraph =
                tester.renderObject(
                      find.descendant(
                        of: labelSlot,
                        matching: find.byType(Text),
                      ),
                    )
                    as RenderParagraph;
            final label = tester.widget<Text>(
              find.descendant(of: labelSlot, matching: find.byType(Text)),
            );
            expect(label.maxLines, isNull);
            expect(label.softWrap, isTrue);
            expect(label.overflow, TextOverflow.visible);
            expect(paragraph.didExceedMaxLines, isFalse);
            expect(
              paragraph.textSize.width,
              lessThanOrEqualTo(paragraph.size.width + 0.01),
            );
            expect(
              paragraph.textSize.height,
              lessThanOrEqualTo(paragraph.size.height + 0.01),
            );
          }

          final fullHomeLabel = switch (locale.languageCode) {
            'es' => 'Inicio',
            'zh' => '首页',
            _ => 'Home',
          };
          expect(
            tester
                .getSemantics(find.bySemanticsLabel(fullHomeLabel))
                .flagsCollection
                .isSelected,
            Tristate.isTrue,
          );
          expect(
            tester
                .getSemantics(find.bySemanticsLabel(fullHomeLabel))
                .getSemanticsData()
                .hasAction(SemanticsAction.tap),
            isTrue,
          );
        }
      }
    },
  );
}
