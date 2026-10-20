import 'dart:async';
import 'package:fake_async/fake_async.dart';
import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mfk_geomeasure/models/gnss_fix.dart';
import 'package:mfk_geomeasure/services/gnss/mfkrtk_provider.dart';
import 'package:mfk_geomeasure/services/gnss/ble_transport.dart';

class _DummyBle implements BleTransport {
  final _dataController = StreamController<List<int>>.broadcast(sync: true);

  @override
  Stream<List<int>> get dataStream => _dataController.stream;

  @override
  Stream<bool> get connectionStatus => Stream.value(true);

  @override
  Future<void> connect() async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> write(List<int> data) async {}

  void simulateData(List<int> data) {
    _dataController.add(data);
  }

  @override
  void dispose() {}
  @override
  Stream<List<int>> getExtraStream(String charUuid, {String? serviceUuid}) => const Stream.empty();
  @override
  Future<void> writeExtra(String charUuid, List<int> data, {bool withoutResponse = false, String? serviceUuid}) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('Phase 3: MfkRtkProvider Data Integrity Tests', () {
    late MfkRtkProvider provider;
    late _DummyBle dummyBle;
    late List<GnssFix> emittedFixes;
    StreamSubscription<GnssFix>? sub;

    setUp(() async {
      dummyBle = _DummyBle();
      provider = MfkRtkProvider(transport: dummyBle);
      emittedFixes = [];
    });

    tearDown(() async {
      await sub?.cancel();
      await provider.disconnect();
      provider.dispose();
      sub = null;
    });

    void startProvider(FakeAsync async) {
      sub = provider.fixStream.listen(emittedFixes.add);
      unawaited(provider.connect());
      async.flushMicrotasks();
    }

    test('Epoch deduplication tracks message types correctly: BESTPOSA -> INSPVAXA -> BESTPOSA', () {
      fakeAsync((async) {
        final start = DateTime.utc(2026, 1, 1);
        withClock(Clock(() => start.add(async.elapsed)), () {
          startProvider(async);
          dummyBle.simulateData('#BESTPOSA,COM1,0,85.0,FINESTEERING,2234,123456.000,02000000,0000,0;SOL_COMPUTED,NARROW_INT,47.0,19.0,150.0,40.0,WGS84,0.03,0.04,0.08,stnId,1.0,1.0,20,18*12345678\r\n'.codeUnits);
          async.elapse(const Duration(milliseconds: 10));
          expect(emittedFixes.length, 1);

          dummyBle.simulateData('#INSPVAXA,COM1,0,85.0,FINESTEERING,2234,123456.000,02000000,0000,0;INS_SOLUTION_GOOD,INS_RTKFIXED,47.0,19.0,190.0,-40.0,0.1,0.2,0.3,1.0,2.0,3.0,0.06,0.08,0.1*12345678\r\n'.codeUnits);
          async.elapse(const Duration(milliseconds: 10));
          expect(emittedFixes.length, 2, reason: 'INSPVAXA should be emitted as it complements BESTPOSA');

          dummyBle.simulateData('#BESTPOSA,COM1,0,85.0,FINESTEERING,2234,123456.000,02000000,0000,0;SOL_COMPUTED,NARROW_INT,47.0,19.0,150.0,40.0,WGS84,0.03,0.04,0.08,stnId,1.0,1.0,20,18*12345678\r\n'.codeUnits);
          async.elapse(const Duration(milliseconds: 10));
          expect(emittedFixes.length, 2, reason: 'Duplicate BESTPOSA in same epoch should be dropped');

          dummyBle.simulateData('#BESTPOSA,COM1,0,85.0,FINESTEERING,2234,123457.000,02000000,0000,0;SOL_COMPUTED,NARROW_INT,47.0,19.0,150.0,40.0,WGS84,0.03,0.04,0.08,stnId,1.0,1.0,20,18*12345678\r\n'.codeUnits);
          async.elapse(const Duration(milliseconds: 10));
          expect(emittedFixes.length, 3, reason: 'BESTPOSA in new epoch should be emitted');
        });
      });
    });

    test('Blank BESTPOSA type uses solution status without inheriting stale RTK classification', () {
      fakeAsync((async) {
        final start = DateTime.utc(2026, 1, 1);
        withClock(Clock(() => start.add(async.elapsed)), () {
          startProvider(async);
          dummyBle.simulateData('#INSPVAXA,COM1,0,85.0,FINESTEERING,2234,123450.000,02000000,0000,0;INS_SOLUTION_GOOD,INS_RTKFIXED,47.0,19.0,190.0,-40.0,0.1,0.2,0.3,1.0,2.0,3.0,0.06,0.08,0.1*12345678\r\n'.codeUnits);
          async.flushMicrotasks();
          expect(emittedFixes.last.fixType, GnssFixType.rtk);

          dummyBle.simulateData('#BESTPOSA,COM1,0,85.0,FINESTEERING,2234,123451.000,02000000,0000,0;SOL_COMPUTED,,47.0,19.0,150.0,40.0,WGS84,0.03,0.04,0.08,stnId,1.0,1.0,20,18*12345678\r\n'.codeUnits);
          async.flushMicrotasks();
          final fix = emittedFixes.last;
          expect(fix.fixType, GnssFixType.none);
          expect(fix.rtkStatus, RtkStatus.none);
          expect(fix.positionSource, 'SOL_COMPUTED');
        });
      });
    });

    test('Deterministic cache expiration: independent fields expire precisely at 2000 ms', () {
      fakeAsync((async) {
        final start = DateTime.utc(2026, 1, 1);
        withClock(Clock(() => start.add(async.elapsed)), () {
          startProvider(async);
          // Time = 0
          dummyBle.simulateData('#INSPVAXA,COM1,0,85.0,FINESTEERING,2234,123450.000,02000000,0000,0;INS_SOLUTION_GOOD,INS_RTKFIXED,47.0,19.0,190.0,-40.0,0.1,0.2,0.3,1.0,2.0,3.0,0.06,0.08,0.1*12345678\r\n'.codeUnits);
          async.elapse(const Duration(milliseconds: 1)); // t=1
          expect(emittedFixes.last.insStatus, 'INS_SOLUTION_GOOD');

          async.elapse(const Duration(milliseconds: 1499)); // t=1500

          dummyBle.simulateData('#BESTPOSA,COM1,0,85.0,FINESTEERING,2234,123451.500,02000000,0000,0;SOL_COMPUTED,NARROW_INT,47.0,19.0,150.0,40.0,WGS84,0.01,0.01,0.02,stnId,1.0,1.0,24,20*12345678\r\n'.codeUnits);
          async.elapse(const Duration(milliseconds: 1)); // t=1501
          expect(emittedFixes.last.satellitesUsed, 20);
          expect(emittedFixes.last.insStatus, 'INS_SOLUTION_GOOD', reason: 'INS status should still be valid (< 2s)');

          // Move to exactly 1999 ms since t=0. We are at t=1501. Wait 498 ms.
          async.elapse(const Duration(milliseconds: 498)); // t=1999
          dummyBle.simulateData('#BESTPOSA,COM1,0,85.0,FINESTEERING,2234,123452.000,02000000,0000,0;SOL_COMPUTED,NARROW_INT,47.0,19.0,150.0,40.0,WGS84,0.01,0.01,0.02,stnId,1.0,1.0,24,20*12345678\r\n'.codeUnits);
          async.elapse(const Duration(milliseconds: 0));
          expect(emittedFixes.last.insStatus, 'INS_SOLUTION_GOOD', reason: 'At 1999 ms, INS status is still valid');

          // Move to exactly 2000 ms. Wait 1 ms.
          async.elapse(const Duration(milliseconds: 1)); // t=2000
          dummyBle.simulateData('#BESTPOSA,COM1,0,85.0,FINESTEERING,2234,123452.020,02000000,0000,0;SOL_COMPUTED,NARROW_INT,47.0,19.0,150.0,40.0,WGS84,0.01,0.01,0.02,stnId,1.0,1.0,24,20*12345678\r\n'.codeUnits);
          async.elapse(const Duration(milliseconds: 0));
          expect(emittedFixes.last.insStatus, isNull, reason: 'At exactly 2000 ms, INS status expires');

          // Move to 2001 ms. Wait 1 ms.
          async.elapse(const Duration(milliseconds: 1)); // t=2001
          dummyBle.simulateData('#BESTPOSA,COM1,0,85.0,FINESTEERING,2234,123452.040,02000000,0000,0;SOL_COMPUTED,NARROW_INT,47.0,19.0,150.0,40.0,WGS84,0.01,0.01,0.02,stnId,1.0,1.0,24,20*12345678\r\n'.codeUnits);
          async.elapse(const Duration(milliseconds: 0));
          expect(emittedFixes.last.insStatus, isNull, reason: 'At 2001 ms, INS status remains expired');
        });
      });
    });

    test('Missing accuracy fields result in 99.9 fallback instead of 0.0', () {
      fakeAsync((async) {
        final start = DateTime.utc(2026, 1, 1);
        withClock(Clock(() => start.add(async.elapsed)), () {
          startProvider(async);
          dummyBle.simulateData('#INSPVAXA,COM1,0,85.0,FINESTEERING,2234,123459.000,02000000,0000,0;INS_SOLUTION_GOOD,INS_RTKFIXED,47.0,19.0,190.0,-40.0,0.1,0.2,0.3,1.0,2.0,3.0,,,0.2*12345678\r\n'.codeUnits);
          async.elapse(const Duration(milliseconds: 10));
          final fix = emittedFixes.last;
          expect(fix.horizontalAccuracy, 99.9, reason: 'Missing horizontal accuracy should be 99.9');
        });
      });
    });

    test('Timestamp translates from GPS week and seconds to UTC with leap seconds', () {
      fakeAsync((async) {
        final start = DateTime.utc(2026, 1, 1);
        withClock(Clock(() => start.add(async.elapsed)), () {
          startProvider(async);
          // Reference 1: Week 2234, Sec 123456
          // GPS Time: 2022-10-31 10:17:36
          // UTC Time: 2022-10-31 10:17:18 (18 leap seconds)
          dummyBle.simulateData('#BESTPOSA,COM1,0,85.0,FINESTEERING,2234,123456.000,02000000,0000,0;SOL_COMPUTED,NARROW_INT,47.0,19.0,150.0,40.0,WGS84,0.01,0.01,0.02,stnId,1.0,1.0,24,20*12345678\r\n'.codeUnits);
          async.elapse(const Duration(milliseconds: 10));

          var fix = emittedFixes.last;
          expect(fix.timestampSource, TimestampSource.gnss);
          expect(fix.timestamp, DateTime.utc(2022, 10, 31, 10, 17, 18));

          // Reference 2: Week 1900, Sec 345600
          // GPS Time: 2016-06-09 00:00:00
          // UTC Time: 2016-06-08 23:59:43 (17 leap seconds)
          dummyBle.simulateData('#BESTPOSA,COM1,0,85.0,FINESTEERING,1900,345600.000,02000000,0000,0;SOL_COMPUTED,NARROW_INT,47.0,19.0,150.0,40.0,WGS84,0.01,0.01,0.02,stnId,1.0,1.0,24,20*12345678\r\n'.codeUnits);
          async.elapse(const Duration(milliseconds: 10));

          fix = emittedFixes.last;
          expect(fix.timestampSource, TimestampSource.gnss);
          expect(fix.timestamp, DateTime.utc(2016, 6, 8, 23, 59, 43));
        });
      });
    });

    test('Invalid GPS week or seconds use device time without throwing', () {
      const invalidTimes = <(String, String)>[
        ('NaN', '123456.0'),
        ('Infinity', '123456.0'),
        ('-1', '123456.0'),
        ('2234', 'NaN'),
        ('2234', 'Infinity'),
        ('2234', '-0.001'),
        ('2234', '604800.0'),
        ('10000', '0.0'),
      ];

      fakeAsync((async) {
        final start = DateTime.utc(2026, 1, 1);
        withClock(Clock(() => start.add(async.elapsed)), () {
          startProvider(async);
          for (final (week, seconds) in invalidTimes) {
            final line =
                '#BESTPOSA,COM1,0,85.0,FINESTEERING,$week,$seconds,02000000,0000,0;SOL_COMPUTED,NARROW_INT,47.0,19.0,150.0,40.0,WGS84,0.01,0.01,0.02,stnId,1.0,1.0,24,20*12345678\r\n';
            expect(() => dummyBle.simulateData(line.codeUnits), returnsNormally);
            async.flushMicrotasks();
            expect(emittedFixes, isNotEmpty);
            final fix = emittedFixes.last;
            expect(fix.timestampSource, TimestampSource.device);
            expect(fix.timestamp, start);
          }
        });
      });
    });

    test('Metadata caches expire independently at the two-second boundary', () {
      fakeAsync((async) {
        final start = DateTime.utc(2026, 1, 1);
        withClock(Clock(() => start.add(async.elapsed)), () {
          startProvider(async);
          dummyBle.simulateData('#BESTPOSA,COM1,0,85.0,FINESTEERING,2234,123450.000,02000000,0000,0;SOL_COMPUTED,NARROW_INT,47.0,19.0,150.0,40.0,WGS84,0.03,0.04,0.08,stnId,1.0,1.0,20,18*12345678\r\n'.codeUnits);
          dummyBle.simulateData('#INSPVAXA,COM1,0,85.0,FINESTEERING,2234,123450.000,02000000,0000,0;INS_SOLUTION_GOOD,INS_RTKFIXED,47.0,19.0,190.0,-40.0,0.1,0.2,0.3,1.0,2.0,3.0,0.06,0.08,0.1*12345678\r\n'.codeUnits);
          async.flushMicrotasks();
          expect(emittedFixes.last.heading, 3.0);
          expect(emittedFixes.last.pitch, 2.0);
          expect(emittedFixes.last.roll, 1.0);
          expect(emittedFixes.last.insStatus, 'INS_SOLUTION_GOOD');

          async.elapse(const Duration(milliseconds: 1999));
          dummyBle.simulateData('%INSPVASA,2234,123452.000;2234,123452.000,47.0,19.0,190.0,0.1,0.2,0.3,4.0,5.0,6.0,INS_SOLUTION_GOOD\r\n'.codeUnits);
          async.flushMicrotasks();
          expect(emittedFixes.last.heading, 6.0);
          expect(emittedFixes.last.horizontalAccuracy, closeTo(0.1, 1e-9));
          expect(emittedFixes.last.positionSource, 'INS_RTKFIXED');
          expect(emittedFixes.last.satellitesUsed, 18);
          expect(emittedFixes.last.correctionAge, 1.0);

          async.elapse(const Duration(milliseconds: 1));
          dummyBle.simulateData('%INSPVASA,2234,123452.020;2234,123452.020,47.0,19.0,190.0,0.1,0.2,0.3,4.0,5.0,6.0,INS_SOLUTION_GOOD\r\n'.codeUnits);
          async.flushMicrotasks();
          final expiredFix = emittedFixes.last;
          expect(expiredFix.horizontalAccuracy, 99.9);
          expect(expiredFix.verticalAccuracy, 99.9);
          expect(expiredFix.positionSource, 'INSPVASA');
          expect(expiredFix.satellitesUsed, 0);
          expect(expiredFix.correctionAge, isNull);
          expect(expiredFix.heading, 6.0);
          expect(expiredFix.pitch, 5.0);
          expect(expiredFix.roll, 4.0);
          expect(expiredFix.insStatus, 'INS_SOLUTION_GOOD');

          async.elapse(const Duration(milliseconds: 2000));
          dummyBle.simulateData('#BESTPOSA,COM1,0,85.0,FINESTEERING,2234,123454.001,02000000,0000,0;SOL_COMPUTED,NARROW_INT,47.0,19.0,150.0,40.0,WGS84,0.03,0.04,0.08,stnId,1.0,1.0,20,18*12345678\r\n'.codeUnits);
          async.flushMicrotasks();
          expect(emittedFixes.last.heading, isNull);
          expect(emittedFixes.last.pitch, isNull);
          expect(emittedFixes.last.roll, isNull);
          expect(emittedFixes.last.insStatus, isNull);
        });
      });
    });
  });
}
