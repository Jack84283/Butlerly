import 'package:butlerly/app/theme/app_theme.dart';
import 'package:butlerly/design_system/components/butlerly_toast.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('success toast uses green and expires after five seconds', (
    tester,
  ) async {
    late BuildContext toastContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              toastContext = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    ButlerlyToast.success(toastContext, 'Encrypted backup saved');
    await tester.pump();
    await tester.pumpAndSettle();
    final snackbar = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(snackbar.backgroundColor, ButlerlySemanticColors.light.success);
    expect(snackbar.duration, const Duration(seconds: 5));
    expect(find.text('Encrypted backup saved'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    expect(find.text('Encrypted backup saved'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('Encrypted backup saved'), findsNothing);
  });

  testWidgets('error toast stays red until Close and Details never closes it', (
    tester,
  ) async {
    late BuildContext toastContext;
    var detailCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              toastContext = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    ButlerlyToast.error(
      toastContext,
      'Backup could not be verified',
      closeLabel: 'Close',
      detailsLabel: 'Details',
      onDetails: () => detailCount++,
    );
    await tester.pump();
    await tester.pumpAndSettle();
    final snackbar = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(snackbar.backgroundColor, ButlerlySemanticColors.dark.error);
    expect(find.text('Backup could not be verified'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('butlerly-toast-details')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('butlerly-toast-close')), findsOneWidget);

    await tester.pump(const Duration(seconds: 30));
    expect(find.text('Backup could not be verified'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('butlerly-toast-details')));
    await tester.pump();
    expect(detailCount, 1);
    expect(find.text('Backup could not be verified'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('butlerly-toast-close')));
    await tester.pumpAndSettle();
    expect(find.text('Backup could not be verified'), findsNothing);
  });

  testWidgets(
    'error action labels and close icons contrast with white buttons '
    'in both app themes',
    (tester) async {
      for (final theme in [AppTheme.light, AppTheme.dark]) {
        late BuildContext toastContext;
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            themeAnimationDuration: Duration.zero,
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  toastContext = context;
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        );

        ButlerlyToast.error(
          toastContext,
          'Backup merge failed',
          closeLabel: 'Close',
          detailsLabel: 'Details',
          onDetails: () {},
        );
        await tester.pump();
        await tester.pumpAndSettle();

        final details = tester.widget<TextButton>(
          find.byKey(const ValueKey('butlerly-toast-details')),
        );
        final close = tester.widget<IconButton>(
          find.byKey(const ValueKey('butlerly-toast-close')),
        );
        const white = Colors.white;
        const darkText = Color(0xFF202020);

        expect(details.style?.backgroundColor?.resolve({}), white);
        expect(details.style?.foregroundColor?.resolve({}), darkText);
        expect(close.style?.backgroundColor?.resolve({}), white);
        expect(close.style?.foregroundColor?.resolve({}), darkText);
        final closeIcon = tester.widget<Icon>(
          find.descendant(
            of: find.byKey(const ValueKey('butlerly-toast-close')),
            matching: find.byIcon(Icons.close_rounded),
          ),
        );
        // The icon inherits the dark foreground from the IconButton style.
        expect(closeIcon.color, isNull);

        final lighter = white.computeLuminance() + 0.05;
        final darker = darkText.computeLuminance() + 0.05;
        expect(lighter / darker, greaterThanOrEqualTo(4.5));
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const ValueKey('butlerly-toast-close')));
        await tester.pumpAndSettle();
      }
    },
  );
}
