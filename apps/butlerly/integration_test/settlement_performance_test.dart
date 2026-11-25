import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:ui';

import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/features/tools/presentation/payment_settlements_page.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/features/transactions/transaction_lifecycle_test.dart'
    as fixtures;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  Completer<void>? resume;
  developer.registerExtension('ext.butlerly.resumeSettlementBenchmark', (
    _,
    _,
  ) async {
    resume?.complete();
    return developer.ServiceExtensionResponse.result('{}');
  });

  Future<void> sample(
    int count,
    String stage, {
    int? startMicros,
    int? endMicros,
  }) async {
    final signal = Completer<void>();
    resume = signal;
    developer.postEvent('butlerly.settlementBenchmark', {
      'count': count,
      'stage': stage,
      'startMicros': ?startMicros,
      'endMicros': ?endMicros,
    });
    await signal.future.timeout(const Duration(seconds: 30));
    resume = null;
  }

  testWidgets('profiles desktop settlement startup and scrolling', (
    tester,
  ) async {
    for (final count in [100, 1000, 5000]) {
      await services.reset();
      final transactions = fixtures.MemoryTransactionRepository();
      final settlements = fixtures.MemoryPaymentSettlements();
      final sources = fixtures.MemoryPaymentSources();
      final merchants = fixtures.MemoryMerchants();
      final aliases = fixtures.MemoryMerchantAliases();
      final patterns = fixtures.MemoryMerchantPatterns();
      final card = PaymentSource(
        id: PaymentSourceId('benchmark-card'),
        name: 'Benchmark card',
        type: PaymentSourceType.card,
      );
      await sources.save(card);
      services.registerSingleton(
        FinanceServices(
          transactions,
          sources,
          merchants,
          fixtures.MemoryCategories(),
          fixtures.MemoryTags(),
          fixtures.MemoryEvidence(),
          fixtures.MemoryUserPreferences(),
          duplicateGroups: fixtures.MemoryDuplicateGroups(transactions),
          statements: fixtures.MemoryStatements(transactions),
          merchantAliases: aliases,
          merchantNormalizationPatterns: patterns,
          merchantMatchingConfiguration:
              fixtures.MemoryMerchantMatchingConfiguration(
                merchants,
                aliases,
                patterns,
              ),
          paymentSettlements: settlements,
        ),
      );
      final now = DateTime.utc(2026, 1, 20);
      final payment = Money(
        amount: DecimalValue.parse('73.019'),
        currency: CurrencyCode('USD'),
      );
      for (var index = 0; index < count; index++) {
        await settlements.save(
          PaymentSettlement(
            id: PaymentSettlementId('benchmark-$index'),
            paymentSourceId: index.isEven
                ? card.id
                : PaymentSourceId(
                    'missing-historical-credit-card-source-$index',
                  ),
            payment: payment,
            paymentDate: '2026-01-20',
            periodStart: '2026-01-01',
            periodEnd: '2026-01-20',
            status: PaymentSettlementStatus.open,
            createdAt: now,
            updatedAt: now,
          ),
        );
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await sample(count, 'before_startup');
      final beforeRss = ProcessInfo.currentRss;
      final startupStartMicros = developer.Timeline.now;
      final start = Stopwatch()..start();
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: PaymentSettlementsPage())),
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 16));
      start.stop();
      await sample(
        count,
        'startup',
        startMicros: startupStartMicros,
        endMicros: developer.Timeline.now,
      );
      final countRows = find
          .byWidgetPredicate(
            (widget) => widget.key.toString().contains(
              'desktop-payment-settlement-benchmark-',
            ),
            skipOffstage: false,
          )
          .evaluate()
          .length;
      final viewport = tester.view.physicalSize / tester.view.devicePixelRatio;
      final table = find.byKey(
        const ValueKey('desktop-payment-settlements-table'),
      );
      final row = find.byKey(
        const ValueKey('desktop-payment-settlement-benchmark-0'),
      );
      expect(table, findsOneWidget);
      expect(row, findsOneWidget);
      final position = Scrollable.of(
        tester.element(row),
        axis: Axis.vertical,
      ).position;
      const scrollStep = 30.0;
      const scrollSteps = 48;
      final scrollOrigin = position.pixels;
      expect(
        position.maxScrollExtent,
        greaterThan(scrollOrigin + scrollStep * scrollSteps),
      );
      // Let initial layout timings flush before collecting scroll frames.
      await Future<void>.delayed(const Duration(seconds: 2));
      await sample(count, 'before_scroll');
      final timings = <FrameTiming>[];
      final collectTimings = timings.addAll;
      binding.addTimingsCallback(collectTimings);
      final scrollStartMicros = developer.Timeline.now;
      try {
        for (var step = 1; step <= scrollSteps; step++) {
          final target = scrollOrigin + step * scrollStep;
          position.jumpTo(target);
          await tester.pump(const Duration(milliseconds: 16));
          expect(position.pixels, closeTo(target, 0.5));
        }
        await sample(
          count,
          'scroll',
          startMicros: scrollStartMicros,
          endMicros: developer.Timeline.now,
        );
        // Profile builds batch frame timings before delivering them.
        await Future<void>.delayed(const Duration(seconds: 2));
      } finally {
        binding.removeTimingsCallback(collectTimings);
      }
      expect(timings, isNotEmpty);
      debugPrint(
        'SETTLEMENT_BENCH ${jsonEncode({'count': count, 'viewport': '${viewport.width}x${viewport.height}', 'startup_ms': start.elapsedMilliseconds, 'mounted_rows': countRows, 'rss_delta_bytes': ProcessInfo.currentRss - beforeRss, 'scroll_distance_px': position.pixels - scrollOrigin, 'scrolling_frames': timings.length, 'build_p95_ms': _p95(timings.map((frame) => frame.buildDuration)), 'raster_p95_ms': _p95(timings.map((frame) => frame.rasterDuration))})}',
      );
      if (count == 5000) {
        await sample(count, 'before_jump');
        final jumpStart = developer.Timeline.now;
        final lastRow = find.byKey(
          const ValueKey('desktop-payment-settlement-benchmark-4999'),
        );
        for (
          var attempt = 0;
          attempt < 5 && lastRow.hitTestable().evaluate().isEmpty;
          attempt++
        ) {
          position.jumpTo(position.maxScrollExtent);
          await tester.pumpAndSettle(const Duration(milliseconds: 16));
        }
        final jumpEnd = developer.Timeline.now;
        expect(lastRow.hitTestable(), findsOneWidget);
        await sample(count, 'jump', startMicros: jumpStart, endMicros: jumpEnd);
        debugPrint(
          'SETTLEMENT_JUMP ${jsonEncode({'count': count, 'duration_ms': (jumpEnd - jumpStart) / 1000})}',
        );
      }
      expect(tester.takeException(), isNull);
    }
    await services.reset();
  });
}

double _p95(Iterable<Duration> durations) {
  final sorted = durations.map((value) => value.inMicroseconds).toList()
    ..sort();
  return sorted[(sorted.length * 0.95).ceil() - 1] / 1000;
}
