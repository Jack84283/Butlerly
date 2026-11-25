import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';
import 'package:vm_service/vm_service_io.dart';

Future<void> main() async {
  final endpoint = Uri.parse(Platform.environment['VM_SERVICE_URL']!);
  final service = await vmServiceConnectUri(
    endpoint.replace(scheme: 'ws', path: '${endpoint.path}ws').toString(),
  );
  service.onExtensionEvent.listen((event) async {
    if (event.extensionKind != 'butlerly.settlementBenchmark') return;
    final data = event.extensionData!.data;
    final isolateId = event.isolate!.id!;
    try {
      final stage = data['stage'] as String;
      final profile = await service.getAllocationProfile(isolateId);
      final heap = profile.memoryUsage!;
      final stats = <String, Object?>{
        'count': data['count'],
        'stage': stage,
        'dart_heap_bytes': heap.heapUsage,
        'dart_external_bytes': heap.externalUsage,
        'dart_allocated_bytes': profile.members!.fold<int>(
          0,
          (sum, member) => sum + (member.accumulatedSize ?? 0),
        ),
      };
      if (stage != 'before') {
        final start = data['startMicros'] as int;
        final end = data['endMicros'] as int;
        final cpu = await service.getCpuSamples(isolateId, start, end - start);
        stats['dart_cpu_samples'] = cpu.sampleCount;
        stats['dart_cpu_sample_period_us'] = cpu.samplePeriod;
      }
      stdout.writeln('SETTLEMENT_PROFILE ${jsonEncode(stats)}');
    } finally {
      await service.callServiceExtension(
        'ext.butlerly.resumeSettlementBenchmark',
        isolateId: isolateId,
      );
    }
  });
  await service.streamListen('Extension');
  await integrationDriver();
}
