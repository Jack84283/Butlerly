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
  testWidgets('compact footer floats its destinations in a centered pill', (
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
    final pill = find.byKey(const ValueKey('primary-navigation-pill'));
    final pillRect = tester.getRect(pill);
    final navigationContentRect = tester.getRect(
      find.byKey(const ValueKey('primary-navigation-content')),
    );
    final navigationMaterial = tester.widget<Material>(
      find.byKey(const ValueKey('primary-compact-navigation')),
    );
    final pillContainer = tester.widget<Container>(pill);
    final pillDecoration = pillContainer.decoration! as BoxDecoration;

    expect(bodyRect.bottom, closeTo(navigationRect.top, 0.01));
    expect(navigationMaterial.color, Colors.transparent);
    expect(pillRect.top, closeTo(navigationRect.top + 8, 0.01));
    expect(pillRect.width, lessThan(navigationRect.width));
    expect(pillRect.width, closeTo(navigationRect.width - 32, 0.01));
    expect(pillRect.center.dx, closeTo(navigationRect.center.dx, 0.01));
    expect(navigationContentRect, pillRect);
    expect(
      navigationContentRect.height,
      closeTo(ButlerlySize.navigationBarHeight, 0.01),
    );
    expect(ButlerlySize.navigationBarHeight, 72);
    expect(
      pillDecoration.borderRadius,
      BorderRadius.circular(ButlerlyRadius.pill),
    );
    expect(find.byKey(const ValueKey('primary-navigation-base')), findsNothing);
    final addButton = find.byKey(
      const ValueKey('primary-navigation-add-button'),
    );
    expect(addButton, findsOneWidget);
    final addDecoration =
        tester.widget<Container>(addButton).decoration! as BoxDecoration;
    expect(addDecoration.shape, BoxShape.circle);
    expect(find.text('Add'), findsNothing);

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
        (Locale('en'), [(0, 'Home'), (1, 'Txns'), (3, 'Tools'), (4, 'More')]),
        (Locale('es'), [(0, 'Ini.'), (1, 'Tr.'), (3, 'Her.'), (4, 'Más')]),
        (Locale('zh'), [(0, '首页'), (1, '交易'), (3, '工具'), (4, '更多')]),
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
          for (final (branchIndex, visibleLabel) in visibleLabels) {
            expect(find.text(visibleLabel), findsOneWidget);
            final labelSlot = find.byKey(
              ValueKey('primary-navigation-label-$branchIndex'),
            );
            final paragraph = tester.renderObject(
              find.descendant(of: labelSlot, matching: find.byType(Text)),
            ) as RenderParagraph;
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

