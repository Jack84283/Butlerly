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
}
