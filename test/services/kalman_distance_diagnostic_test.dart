import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mfk_geomeasure/models/gnss_fix.dart';
import 'package:mfk_geomeasure/models/gnss_raw_measurement.dart';
import 'package:mfk_geomeasure/services/gnss/gnss_provider.dart';
import 'package:mfk_geomeasure/services/gnss_info_service.dart';
import 'package:mfk_geomeasure/services/geoid_service.dart';

class MockGnssProvider implements GnssProvider {
  final _fixController = StreamController<GnssFix>.broadcast();

  @override
  Stream<GnssFix> get fixStream => _fixController.stream;

  @override
  Future<void> connect() async {}

  @override
  Future<void> disconnect() async {}

  @override
  void dispose() {
    _fixController.close();
  }

  @override
  Stream<GnssRawMeasurement> get rawMeasurementStream => const Stream.empty();

  @override
  Stream<List<int>> get rawStream => const Stream.empty();

  @override
  void sendCorrectionData(List<int> data) {}

  @override
  bool get supportsRtcmInput => false;

  void emitFix(GnssFix fix) {
    _fixController.add(fix);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Kalman Distance Diagnostic Tests', () {
    late GnssInfoService infoService;
    late MockGnssProvider mockProvider;

    setUp(() async {
      infoService = GnssInfoService(GeoidCorrectionService());
      mockProvider = MockGnssProvider();
      await infoService.setProvider(mockProvider);
    });

    tearDown(() {
      infoService.dispose();
      mockProvider.dispose();
    });

    test('kalman_distance_m matches the calculated horizontal distance between raw and filtered coordinates', () async {
      // 1. Enable Kalman filter and start capturing
      infoService.enableKalmanFilter = true;
      await infoService.start30sCapture();

      // 2. Emit an initial fix to initialize Kalman
      final fix1 = GnssFix(
        latitude: 47.0,
        longitude: 19.0,
        altitude: 100.0,
        ellipsoidalHeight: 100.0,
        isEllipsoidal: true,
        horizontalAccuracy: 1.0,
        verticalAccuracy: 1.0,
        fixType: GnssFixType.rtk,
        rtkStatus: RtkStatus.fixed,
        source: GnssSource.external,
        connectionType: GnssConnectionType.ble,
        timestamp: DateTime.now(),
      );
      mockProvider.emitFix(fix1);

      // Give it a tiny delay to process stream
      await Future.delayed(const Duration(milliseconds: 50));

      // 3. Emit a second fix that is slightly shifted to force Kalman to produce a different output than raw
      final fix2 = GnssFix(
        latitude: 47.0001,
        longitude: 19.0001,
        altitude: 100.0,
        ellipsoidalHeight: 100.0,
        isEllipsoidal: true,
        horizontalAccuracy: 1.0,
        verticalAccuracy: 1.0,
        fixType: GnssFixType.rtk,
        rtkStatus: RtkStatus.fixed,
        source: GnssSource.external,
        connectionType: GnssConnectionType.ble,
        timestamp: DateTime.now(),
      );
      mockProvider.emitFix(fix2);

      await Future.delayed(const Duration(milliseconds: 50));

      // 4. Verify the captured epoch record
      final epochs = infoService.capturedEpochs;
      expect(epochs.length, greaterThanOrEqualTo(2));

      final lastEpoch = epochs.last;

      // Calculate expected distance directly using the same Distance() logic
      const distanceCalc = Distance();
      final expectedDistance = distanceCalc.distance(
        LatLng(lastEpoch.rawLat, lastEpoch.rawLon),
        LatLng(lastEpoch.kalmanOutputLat, lastEpoch.kalmanOutputLon)
      );

      // Verify that raw and kalman output actually differ
      expect(lastEpoch.rawLat != lastEpoch.kalmanOutputLat || lastEpoch.rawLon != lastEpoch.kalmanOutputLon, isTrue, reason: 'Raw and Kalman output should differ for a meaningful test');

      // Verify recorded distance matches mathematical distance
      expect(lastEpoch.kalmanDistance, closeTo(expectedDistance, 0.0001));

      // 5. Verify CSV / JSON representation maps it correctly
      final csvRow = lastEpoch.toCsvRow();
      final jsonMap = lastEpoch.toJson();

      // Check CSV format: Ensure it's correctly formatted as string
      expect(csvRow.contains(lastEpoch.kalmanDistance.toStringAsFixed(4)), isTrue);
      // Check JSON format
      expect(jsonMap['kalman_distance_m'], lastEpoch.kalmanDistance);
    });
  });
}
