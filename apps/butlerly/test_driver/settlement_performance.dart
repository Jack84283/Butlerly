import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';
import 'package:vm_service/vm_service_io.dart';

Future<void> main() async {
  final endpoint = Uri.parse(Platform.environment['VM_SERVICE_URL']!);
  final service = await vmServiceConnectUri(
    endpoint.replace(scheme: 'ws', path: '${endpoint.path}ws').toString(),
  );
  final phaseStarts = <(int, String), int>{};
  String? inkWellClassId;
  service.onExtensionEvent.listen((event) async {
    if (event.extensionKind != 'butlerly.settlementBenchmark') return;
    final data = event.extensionData!.data;
    final isolateId = event.isolate!.id!;
    try {
      final stage = data['stage'] as String;
      final count = data['count'] as int;
      final phaseStart = stage.startsWith('before_');
      final phase = phaseStart ? stage.substring('before_'.length) : stage;
      if (inkWellClassId == null) {
        final classes = await service.getClassList(isolateId);
        final rowWidget = classes.classes!.singleWhere(
          (cls) => cls.name == 'InkWell',
        );
        inkWellClassId = rowWidget.id!;
        await service.setTraceClassAllocation(isolateId, inkWellClassId!, true);
      }
      final profile = await service.getAllocationProfile(isolateId);
      final counters = profile.members!.map((member) => member.bytesCurrent);
      if (counters.any((bytes) => bytes == null || bytes < 0)) {
        throw StateError(
          'Dart VM did not provide a complete allocation snapshot.',
        );
      }
      final liveBytes = counters.fold(0, (sum, bytes) => sum + bytes!);
      final heap = profile.memoryUsage!;
      final stats = <String, Object?>{
        'count': count,
        'stage': stage,
        'dart_heap_bytes': heap.heapUsage,
        'dart_external_bytes': heap.externalUsage,
        'live_dart_object_bytes': liveBytes,
      };
      if (phaseStart) {
        phaseStarts[(count, phase)] = liveBytes;
      } else {
        // Current object bytes describe heap snapshots before and after a phase.
        stats['net_dart_object_bytes'] =
            liveBytes - phaseStarts.remove((count, phase))!;
        final start = data['startMicros'] as int;
        final end = data['endMicros'] as int;
        final cpu = await service.getCpuSamples(isolateId, start, end - start);
        stats['dart_cpu_samples'] = cpu.sampleCount;
        stats['dart_cpu_sample_period_us'] = cpu.samplePeriod;
        final rowAllocations = await service.getAllocationTraces(
          isolateId,
          timeOriginMicros: start,
          timeExtentMicros: end - start,
          classId: inkWellClassId,
        );
        final samples = rowAllocations.sampleCount!;
        if (stage == 'startup' && samples == 0) {
          throw StateError('No InkWell allocation traces during row startup.');
        }
        stats['inkwell_allocation_samples'] = samples;
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
