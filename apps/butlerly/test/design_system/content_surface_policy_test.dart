import 'package:butlerly/app/theme/app_theme.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/components/butlerly_responsive_body.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('ButlerlyPage keeps page padding inside the content surface', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: ButlerlyPage(
            children: [
              SizedBox(key: ValueKey('surface-policy-child'), height: 20),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final canvas = tester.widget<ColoredBox>(
      find.byKey(const ValueKey('butlerly-page-canvas')),
    );
    final surface = tester.widget<DecoratedSliver>(
      find.byKey(const ValueKey('butlerly-page-content-surface')),
    );
    final colors = AppTheme.light.extension<ButlerlySemanticColors>()!;
    expect(canvas.color, colors.subtleSurface);
    expect((surface.decoration as BoxDecoration).color, colors.background);

    final childRect = tester.getRect(
      find.byKey(const ValueKey('surface-policy-child')),
    );
    expect(childRect.width, ButlerlySize.pageContentMaxWidth);
    expect(
      childRect.left,
      closeTo((1200 - ButlerlySize.pageContentMaxWidth) / 2, 0.01),
    );
    expect(childRect.top, closeTo(ButlerlySpacing.standard, 0.01));
  });

  testWidgets('responsive body distinguishes content from outside canvas', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(body: ButlerlyResponsiveBody(child: SizedBox())),
      ),
    );
    await tester.pumpAndSettle();

    final canvas = tester.widget<ColoredBox>(
      find.byKey(const ValueKey('butlerly-responsive-body-canvas')),
    );
    final surface = tester.widget<Material>(
      find.byKey(const ValueKey('butlerly-responsive-body-content-surface')),
    );
    final colors = AppTheme.light.extension<ButlerlySemanticColors>()!;
    expect(canvas.color, colors.subtleSurface);
    expect(surface.color, colors.background);
    expect(
      tester
          .getSize(
            find.byKey(
              const ValueKey('butlerly-responsive-body-content-surface'),
            ),
          )
          .width,
      ButlerlySize.pageContentMaxWidth,
    );
  });
}
