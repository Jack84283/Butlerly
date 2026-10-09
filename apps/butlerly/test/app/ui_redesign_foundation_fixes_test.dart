import 'package:butlerly/app/butlerly_app.dart';
import 'package:butlerly/app/router/app_router.dart';
import 'package:butlerly/app/shell/adaptive_shell.dart';
import 'package:butlerly/app/theme/app_theme.dart';
import 'package:butlerly/design_system/components/butlerly_action_group.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/design_system/tokens/butlerly_transaction_item.dart';
import 'package:butlerly/design_system/tokens/butlerly_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => appRouter.go('/'));

  test('small and hint text preserve accessible semantic roles', () {
    final lightTheme = AppTheme.light;
    final lightColors = lightTheme.extension<ButlerlySemanticColors>()!;
    final lightBodySmallColor = lightTheme.textTheme.bodySmall!.color!;
    final lightHintColor = lightTheme.inputDecorationTheme.hintStyle!.color!;

    expect(lightBodySmallColor, lightColors.secondaryText);
    expect(lightHintColor, lightColors.secondaryText);
    expect(
      _contrastRatio(lightBodySmallColor, lightColors.background),
      greaterThanOrEqualTo(ButlerlyAccessibility.minimumContrastRatio),
    );
    expect(
      _contrastRatio(lightBodySmallColor, lightColors.subtleSurface),
      greaterThanOrEqualTo(ButlerlyAccessibility.minimumContrastRatio),
    );
    expect(
      _contrastRatio(lightHintColor, lightColors.subtleSurface),
      greaterThanOrEqualTo(ButlerlyAccessibility.minimumContrastRatio),
    );

    final darkTheme = AppTheme.dark;
    final darkColors = darkTheme.extension<ButlerlySemanticColors>()!;
    final darkBodySmallColor = darkTheme.textTheme.bodySmall!.color!;
    final darkHintColor = darkTheme.inputDecorationTheme.hintStyle!.color!;

    expect(darkBodySmallColor, darkColors.secondaryText);
    expect(darkHintColor, darkColors.tertiaryText);
    expect(
      _contrastRatio(darkBodySmallColor, darkColors.background),
      greaterThanOrEqualTo(ButlerlyAccessibility.minimumContrastRatio),
    );
    expect(
      _contrastRatio(darkBodySmallColor, darkColors.subtleSurface),
      greaterThanOrEqualTo(ButlerlyAccessibility.minimumContrastRatio),
    );
    expect(
      _contrastRatio(darkBodySmallColor, darkColors.dashboardSurface),
      greaterThanOrEqualTo(ButlerlyAccessibility.minimumContrastRatio),
    );
  });

  test('dark theme uses the refined near-black surface palette', () {
    final colors = AppTheme.dark.extension<ButlerlySemanticColors>()!;

    expect(colors.background, const Color(0xFF030405));
    expect(colors.subtleSurface, const Color(0xFF030405));
    expect(colors.surface, const Color(0xFF282B30));
    expect(colors.dashboardSurface, const Color(0xFF141516));
    expect(colors.elevatedSurface, const Color(0xFF2F3339));
    expect(colors.secondaryText, const Color(0xFFB9BDC7));
    expect(colors.primaryText, const Color(0xFFF6F7F8));
  });

  test('light theme uses the four-level solid gray surface palette', () {
    final colors = AppTheme.light.extension<ButlerlySemanticColors>()!;

    expect(colors.background, const Color(0xFFF2F3F9));
    expect(colors.surface, const Color(0xFFE7EBF1));
    expect(colors.subtleSurface, const Color(0xFFE7EBF1));
    expect(colors.dashboardSurface, const Color(0xFFEEF1F5));
    expect(colors.elevatedSurface, const Color(0xFFE0E5EC));
    expect(colors.cardDivider, const Color(0xFFD8DDE6));
    expect(colors.border, const Color(0xFFD8DDE6));
    expect(colors.primaryText, const Color(0xFF17191F));
    expect(colors.secondaryText, const Color(0xFF383838));
  });

  test('editorial placeholder keeps cross-platform serif fallbacks', () {
    expect(ButlerlyTypography.editorialFontFamily, 'Times New Roman');
    expect(
      ButlerlyTypography.editorialFontFallback,
      containsAll(const ['Times', 'Noto Serif', 'serif']),
    );
    expect(
      ButlerlyTypography.editorialFontFallback,
      isNot(contains('Georgia')),
    );
  });

  test('compact navigation stays at 56px at normal text scale', () {
    final labelStyle = ButlerlyTypography.navigationLabel(
      AppTheme.light.textTheme.labelSmall!,
      color: Colors.black,
      selected: true,
    );
    const itemWidth = 78.0;
    const labels = ['Home', 'Transactions', 'Tools', 'More', 'Add'];
    final height = compactNavigationHeightForLabels(
      textScaler: TextScaler.noScaling,
      itemWidth: itemWidth,
      standardLabels: labels.take(4),
      addLabel: labels.last,
      labelStyle: labelStyle,
      textDirection: TextDirection.ltr,
    );
    expect(ButlerlySize.navigationBarHeight, 56);
    expect(ButlerlySize.primaryNavigationAddIconSize, 32);
    expect(height, ButlerlySize.navigationBarHeight);
  });

  test('compact navigation uses one label slot across destinations', () {
    const scaler = TextScaler.linear(3);
    const itemWidth = 78.0;
    const standardLabels = ['Home', 'Transacciones', 'Herramientas', 'Más'];
    const addLabel = 'Add';
    final labelStyle = ButlerlyTypography.navigationLabel(
      AppTheme.light.textTheme.labelSmall!,
      color: Colors.black,
      selected: true,
    );

    final height = compactNavigationHeightForLabels(
      textScaler: scaler,
      itemWidth: itemWidth,
      standardLabels: standardLabels,
      addLabel: addLabel,
      labelStyle: labelStyle,
      textDirection: TextDirection.ltr,
    );

    final maximumLabelHeight = [...standardLabels, addLabel]
        .map(
          (label) => _navigationLabelHeight(
            label,
            style: labelStyle,
            textScaler: scaler,
            maxWidth: itemWidth,
          ),
        )
        .reduce((left, right) => left > right ? left : right);
    final expectedHeight = [
      ButlerlySize.navigationBarHeight,
      ButlerlySize.primaryNavigationAddIconSize +
          maximumLabelHeight +
          2 * ButlerlySize.dividerWidth,
    ].reduce((left, right) => left > right ? left : right);

    expect(height, expectedHeight);
  });

  test('compact navigation uses actual localized nonlinear label geometry', () {
    const scaler = _NavigationNonlinearTextScaler();
    final labelStyle = ButlerlyTypography.navigationLabel(
      AppTheme.light.textTheme.labelSmall!,
      color: Colors.black,
      selected: true,
    );
    final height = compactNavigationHeightForLabels(
      textScaler: scaler,
      itemWidth: 78,
      standardLabels: const ['Home', 'Transacciones', 'Herramientas', 'Más'],
      addLabel: 'Add',
      labelStyle: labelStyle,
      textDirection: TextDirection.ltr,
    );

    // The test scaler barely scales a 1 px probe but triples the real 10.5 px
    // navigation label. This catches regressions back to scale(1) and to the
    // previous fixed 102 px accessibility cap.
    expect(scaler.scale(1), 1.1);
    expect(
      scaler.scale(ButlerlyTypography.navigationLabelFontSize),
      ButlerlyTypography.navigationLabelFontSize * 3,
    );
    expect(height, greaterThan(102));
  });

  testWidgets('transaction metadata uses the readable small-text color', (
    tester,
  ) async {
    late TextStyle metadataStyle;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) {
            metadataStyle = context.transactionItemMetadata;
            return const SizedBox();
          },
        ),
      ),
    );

    expect(
      metadataStyle.color,
      AppTheme.light.extension<ButlerlySemanticColors>()!.secondaryText,
    );
  });

  testWidgets('Add and Tools share the action-group primitive', (tester) async {
    _setPhoneViewport(tester);
    await tester.pumpWidget(const ProviderScope(child: ButlerlyApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Add transaction'));
    await tester.pumpAndSettle();

    expect(find.byType(ButlerlyActionGroup), findsNWidgets(2));
    expect(find.byType(ButlerlyActionRow), findsNWidgets(5));
    final addSubtitle = tester.widget<Text>(
      find.text('Enter transaction details yourself'),
    );
    expect(
      addSubtitle.style?.color,
      AppTheme.light.extension<ButlerlySemanticColors>()!.secondaryText,
    );

    appRouter.go('/tools');
    await tester.pumpAndSettle();

    expect(find.byType(ButlerlyActionGroup), findsOneWidget);
    expect(find.byType(ButlerlyActionRow), findsNWidgets(6));
    expect(find.text('Payment settlements'), findsOneWidget);
    expect(find.text('Search'), findsNothing);
  });

  for (final textScale in const [1.0, 1.3, 1.5, 2.0, 3.0]) {
    testWidgets(
      'compact navigation has no overflow at ${textScale}x text scale',
      (tester) async {
        _setPhoneViewport(tester);
        tester.view.platformDispatcher.textScaleFactorTestValue = textScale;
        addTearDown(
          tester.view.platformDispatcher.clearTextScaleFactorTestValue,
        );

        await tester.pumpWidget(const ProviderScope(child: ButlerlyApp()));
        await tester.pumpAndSettle();

        _expectNoFlutterException(tester);
        expect(find.text('Home'), findsAtLeastNWidgets(1));
        expect(find.text('Txns'), findsOneWidget);
        expect(find.text('Tools'), findsOneWidget);
        expect(find.text('More'), findsAtLeastNWidgets(1));
        _expectNavigationLabelUsesWrappingPolicy(tester, 'Txns');
      },
    );
  }

  testWidgets('Spanish compact navigation remains readable at 3x text scale', (
    tester,
  ) async {
    _setPhoneViewport(tester);
    await tester.pumpWidget(const ProviderScope(child: ButlerlyApp()));
    await tester.pumpAndSettle();
    await _switchLanguage(tester, 'Spanish');

    tester.view.platformDispatcher.textScaleFactorTestValue = 3.0;
    addTearDown(tester.view.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();

    _expectNoFlutterException(tester);
    expect(find.text('Ini.'), findsOneWidget);
    expect(find.text('Tr.'), findsOneWidget);
    expect(find.text('Her.'), findsOneWidget);
    expect(find.text('Más'), findsAtLeastNWidgets(1));
    _expectNavigationLabelUsesWrappingPolicy(tester, 'Tr.');
    expect(
      tester.getSize(find.text('Tr.')).height,
      greaterThan(ButlerlyTypography.navigationLabelFontSize * 3),
    );
  });

  testWidgets('Chinese compact navigation remains readable at 3x text scale', (
    tester,
  ) async {
    _setPhoneViewport(tester);
    await tester.pumpWidget(const ProviderScope(child: ButlerlyApp()));
    await tester.pumpAndSettle();
    await _switchLanguage(tester, 'Chinese (Simplified)');

    tester.view.platformDispatcher.textScaleFactorTestValue = 3.0;
    addTearDown(tester.view.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();

    _expectNoFlutterException(tester);
    expect(find.text('首页'), findsOneWidget);
    expect(find.text('交易'), findsAtLeastNWidgets(1));
    expect(find.text('工具'), findsOneWidget);
    expect(find.text('更多'), findsAtLeastNWidgets(1));
    _expectNavigationLabelUsesWrappingPolicy(tester, '交易');
  });
}

Future<void> _switchLanguage(WidgetTester tester, String language) async {
  await tester.tap(find.text('More').last);
  await tester.pumpAndSettle();
  await tester.tap(find.text('English'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(language).last);
  await tester.pumpAndSettle();
}

void _setPhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void _expectNoFlutterException(WidgetTester tester) {
  final exception = tester.takeException();
  if (exception is FlutterError) {
    fail(exception.toStringDeep());
  }
  expect(exception, isNull);
}

void _expectNavigationLabelUsesWrappingPolicy(
  WidgetTester tester,
  String label,
) {
  final widget = tester.widget<Text>(find.text(label).last);
  expect(widget.maxLines, isNull);
  expect(widget.overflow, TextOverflow.visible);
  expect(widget.softWrap, isTrue);
  final paragraph =
      tester.renderObject(find.text(label).last) as RenderParagraph;
  expect(paragraph.didExceedMaxLines, isFalse);
  expect(
    paragraph.textSize.width,
    lessThanOrEqualTo(paragraph.size.width + 0.01),
  );
}

double _navigationLabelHeight(
  String label, {
  required TextStyle style,
  required TextScaler textScaler,
  required double maxWidth,
}) {
  final painter = TextPainter(
    text: TextSpan(text: label, style: style),
    textScaler: textScaler,
    textDirection: TextDirection.ltr,
    textAlign: TextAlign.center,
  )..layout(maxWidth: maxWidth);
  return painter.height;
}

double _contrastRatio(Color foreground, Color background) {
  final foregroundLuminance = foreground.computeLuminance();
  final backgroundLuminance = background.computeLuminance();
  final lighter = foregroundLuminance > backgroundLuminance
      ? foregroundLuminance
      : backgroundLuminance;
  final darker = foregroundLuminance > backgroundLuminance
      ? backgroundLuminance
      : foregroundLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}

class _NavigationNonlinearTextScaler extends TextScaler {
  const _NavigationNonlinearTextScaler();

  @override
  double scale(double fontSize) => fontSize < 2 ? fontSize * 1.1 : fontSize * 3;

  @override
  double get textScaleFactor => 3;
}
