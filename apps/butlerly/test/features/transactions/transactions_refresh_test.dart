import 'dart:async';

import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/features/foundation/presentation/transactions_page.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() async {
    await services.reset();
  });

  tearDown(() async {
    await services.reset();
  });

  testWidgets(
    'refresh keeps transactions content and pinned controls visible',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      final transactions = _ControllableTransactionRepository();
      services.registerSingleton<FinanceServices>(
        FinanceServices(
          transactions,
          _EmptyPaymentSourceRepository(),
          _EmptyMerchantRepository(),
          _EmptyCategoryRepository(),
          _EmptyTagRepository(),
          _UnusedEvidenceRepository(),
          _UnusedUserPreferenceRepository(),
        ),
      );

      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: TransactionsPage(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No transactions'), findsOneWidget);
      expect(find.text('All'), findsOneWidget);

      await tester.drag(
        find.byType(CustomScrollView),
        const Offset(0, 320),
      );
      await tester.pump();

      expect(transactions.queryCount, 2);
      expect(find.text('No transactions'), findsOneWidget);
      expect(find.text('All'), findsOneWidget);

      transactions.completeRefresh();
      await tester.pumpAndSettle();

      expect(find.text('No transactions'), findsOneWidget);
    },
  );
}

final class _ControllableTransactionRepository
    implements TransactionRepository {
  final _refresh = Completer<List<Transaction>>();
  int queryCount = 0;

  void completeRefresh() {
    if (!_refresh.isCompleted) {
      _refresh.complete(const <Transaction>[]);
    }
  }

  @override
  Future<List<Transaction>> query(TransactionRepositoryQuery query) {
    queryCount++;
    if (queryCount == 1) {
      return Future.value(const <Transaction>[]);
    }
    return _refresh.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _EmptyPaymentSourceRepository implements PaymentSourceRepository {
  @override
  Future<List<PaymentSource>> listAll() async => const <PaymentSource>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _EmptyMerchantRepository implements MerchantRepository {
  @override
  Future<List<Merchant>> listAll() async => const <Merchant>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _EmptyCategoryRepository implements CategoryRepository {
  @override
  Future<List<Category>> listAll() async => const <Category>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _EmptyTagRepository implements TagRepository {
  @override
  Future<List<Tag>> listAll() async => const <Tag>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _UnusedEvidenceRepository implements EvidenceRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _UnusedUserPreferenceRepository
    implements UserPreferenceRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
