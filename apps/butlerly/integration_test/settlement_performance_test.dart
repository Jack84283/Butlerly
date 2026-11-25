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
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
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
      final now = DateTime.utc(2026, 11, 20);
      final currencies = ['USD', 'CNY', 'EUR'].map(CurrencyCode.new).toList();
      for (var index = 0; index < count; index++) {
        final date = now.subtract(Duration(days: index ~/ 2));
        final periodEnd = date.subtract(Duration(days: index % 7));
        final periodStart = periodEnd.subtract(Duration(days: 23 + index % 13));
        final fraction = ((index * 19 + 41) % 1000).toString().padLeft(3, '0');
        await settlements.save(
          PaymentSettlement(
            id: PaymentSettlementId('benchmark-$index'),
            paymentSourceId: switch (index % 5) {
              0 || 1 => card.id,
              2 => PaymentSourceId('missing-$index'),
              3 => PaymentSourceId('missing-historical-card-$index'),
              _ => PaymentSourceId(
                'missing-historical-credit-card-source-with-a-migrated-id-$index',
              ),
            },
            payment: Money(
              amount: DecimalValue.parse(
                '${(index * 137 + 73) % 100000}.$fraction',
              ),
              currency: currencies[index % currencies.length],
            ),
            paymentDate: _isoDate(date),
            periodStart: _isoDate(periodStart),
            periodEnd: _isoDate(periodEnd),
            status: PaymentSettlementStatus
                .values[index % PaymentSettlementStatus.values.length],
            createdAt: date,
            updatedAt: date,
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
      final firstScroll = await _profileScroll(
        tester,
        count,
        position,
        sample,
        step: 30,
        phase: 'scroll',
      );
      debugPrint(
        'SETTLEMENT_BENCH ${jsonEncode({'count': count, 'viewport': '${viewport.width}x${viewport.height}', 'startup_ms': start.elapsedMilliseconds, 'mounted_rows': countRows, 'rss_delta_bytes': ProcessInfo.currentRss - beforeRss, ...firstScroll})}',
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
        final deepScroll = await _profileScroll(
          tester,
          count,
          position,
          sample,
          step: -30,
          phase: 'deep_scroll',
        );
        debugPrint(
          'SETTLEMENT_DEEP_SCROLL ${jsonEncode({'count': count, ...deepScroll})}',
        );
      }
      expect(tester.takeException(), isNull);
    }
    await services.reset();
  }, skip: !const bool.fromEnvironment('BUTLERLY_SETTLEMENT_PROFILE'));
}

String _isoDate(DateTime date) => date.toIso8601String().substring(0, 10);

Future<Map<String, Object>> _profileScroll(
  WidgetTester tester,
  int count,
  ScrollPosition position,
  Future<void> Function(int, String, {int? startMicros, int? endMicros})
  sample, {
  required double step,
  required String phase,
}) async {
  const frames = 48;
  final origin = position.pixels;
  final end = origin + step * frames;
  expect(
    end,
    inInclusiveRange(position.minScrollExtent, position.maxScrollExtent),
  );
  await Future<void>.delayed(const Duration(seconds: 2));
  await sample(count, 'before_$phase');
  final timings = <FrameTiming>[];
  final collect = timings.addAll;
  tester.binding.addTimingsCallback(collect);
  final startMicros = developer.Timeline.now;
  try {
    for (var index = 1; index <= frames; index++) {
      final target = origin + step * index;
      position.jumpTo(target);
      await tester.pump(const Duration(milliseconds: 16));
      expect(position.pixels, closeTo(target, 0.5));
    }
    await sample(
      count,
      phase,
      startMicros: startMicros,
      endMicros: developer.Timeline.now,
    );
    // Profile builds batch frame timings before delivering them.
    await Future<void>.delayed(const Duration(seconds: 2));
  } finally {
    tester.binding.removeTimingsCallback(collect);
  }
  expect(timings, isNotEmpty);
  return {
    'scroll_distance_px': position.pixels - origin,
    'scrolling_frames': timings.length,
    'build_p95_ms': _p95(timings.map((frame) => frame.buildDuration)),
    'raster_p95_ms': _p95(timings.map((frame) => frame.rasterDuration)),
  };
}

double _p95(Iterable<Duration> durations) {
  final sorted = durations.map((value) => value.inMicroseconds).toList()
    ..sort();
  return sorted[(sorted.length * 0.95).ceil() - 1] / 1000;
}
