import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:test/test.dart';

void main() {
  late List<String> events;
  late _Gateway gateway;
  late WorkspaceDataService service;
  setUp(() {
    events = [];
    gateway = _Gateway(events);
    service = WorkspaceDataService(
      gateway,
      refreshSystemData: () async => events.add('system-data'),
    );
  });

  for (final operation in ['restore', 'recover', 'reset']) {
    test(
      '$operation refreshes system data before UI, inside the safety gate',
      () async {
        Future<void> refresh() async => events.add('presentation');
        switch (operation) {
          case 'restore':
            await service.restore(
              'selected-backup',
              mode: LocalRestoreMode.merge,
              password: 'secret',
              refreshPresentation: refresh,
            );
            expect(gateway.password, 'secret');
            break;
          case 'recover':
            await service.recoverControlledState(refreshPresentation: refresh);
            break;
          case 'reset':
            await service.resetControlledRecovery(refreshPresentation: refresh);
        }
        expect(events, ['activate', 'system-data', 'presentation', 'complete']);
      },
    );
  }

  test(
    'refresh failure propagates inside restore instead of reporting success',
    () async {
      service = WorkspaceDataService(
        gateway,
        refreshSystemData: () async {
          events.add('system-data-failed');
          throw StateError('seed failed');
        },
      );
      await expectLater(
        service.restore(
          'selected-backup',
          mode: LocalRestoreMode.replace,
          refreshPresentation: () async => events.add('presentation'),
        ),
        throwsStateError,
      );
      expect(events, ['activate', 'system-data-failed']);
    },
  );

  test('erase reseeds and refreshes only after storage succeeds', () async {
    await service.eraseAll(
      refreshPresentation: () async => events.add('presentation'),
    );
    expect(events, ['erase', 'system-data', 'presentation']);
    events.clear();
    gateway.failErase = true;
    await expectLater(service.eraseAll(), throwsStateError);
    expect(events, ['erase']);
  });
}

class _Gateway implements LocalDataGateway {
  _Gateway(this.events);
  final List<String> events;
  String? password;
  bool failErase = false;
  @override
  bool get hasRecoverySafetyCopy => true;

  Future<void> _activate(Future<void> Function() refresh) async {
    events.add('activate');
    await refresh();
    events.add('complete');
  }

  @override
  Future<LocalRestoreResult> restore(
    String filePath, {
    required LocalRestoreMode mode,
    String? password,
    required Future<void> Function() postActivationRefresh,
  }) async {
    this.password = password;
    await _activate(postActivationRefresh);
    return LocalRestoreResult(
      mode: mode,
      restoredRows: 1,
      keptNewerLocalRows: 0,
      restoredEvidence: 0,
    );
  }

  @override
  Future<void> recoverControlledState({
    required Future<void> Function() postActivationRefresh,
  }) => _activate(postActivationRefresh);
  @override
  Future<void> resetControlledRecovery({
    required Future<void> Function() postResetRefresh,
  }) => _activate(postResetRefresh);
  @override
  Future<void> eraseAll() async {
    events.add('erase');
    if (failErase) throw StateError('storage failed');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
