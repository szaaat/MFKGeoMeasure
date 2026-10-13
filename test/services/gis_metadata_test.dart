import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mfk_geomeasure/models/gnss_fix.dart';
import 'package:mfk_geomeasure/models/geo_feature.dart';
import 'package:mfk_geomeasure/services/project_service.dart';
import 'package:mfk_geomeasure/services/eov_service.dart';
import 'package:mfk_geomeasure/services/geoid_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockPathProvider extends Fake with MockPlatformInterfaceMixin implements PathProviderPlatform {
  final Directory tempDir = Directory.systemTemp.createTempSync('gis_meta_test_');

  @override
  Future<String?> getApplicationDocumentsPath() async => tempDir.path;
  @override
  Future<String?> getTemporaryPath() async => tempDir.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  PathProviderPlatform.instance = MockPathProvider();

  group('GIS Metadata Generation Tests', () {
    late ProjectService service;

    setUp(() {
      service = ProjectService();
      service.updateEovService(
          EovService(null, false, EovInputFrame.unknown, EovTransformMode.legacy));
      service.updateGeoidService(GeoidCorrectionService());
      service.createProject("Test Project");
    });

    test('Internal GPS (Phone) Metadata', () {
      final fix = GnssFix(
        latitude: 47.0,
        longitude: 19.0,
        altitude: 100.0,
        ellipsoidalHeight: 100.0,
        isEllipsoidal: true,
        source: GnssSource.internal,
        connectionType: GnssConnectionType.internal,
        timestamp: DateTime.now(),
        horizontalAccuracy: 5.0,
        receiverName: "Internal GPS",
      );

      service.addPointToGeometry(const LatLng(47.0, 19.0), 100.0, fix: fix);
      service.finishRecording("Phone Point", "Test");

      final feature = service.activeLayer!.features.last;
      final stats = feature.calculatedStats;

      expect(stats['Survey Method'], 'PHONE');
      expect(stats['GNSS Source'], 'INTERNAL');
      expect(stats['RTK Status'], 'N/A');
      expect(stats['Receiver'], isNull); // Should be omitted for internal
    });

    test('External RTK FIX Metadata', () {
      final fix = GnssFix(
        latitude: 47.0,
        longitude: 19.0,
        altitude: 100.0,
        ellipsoidalHeight: 100.0,
        isEllipsoidal: true,
        source: GnssSource.external,
        connectionType: GnssConnectionType.bluetoothClassic,
        timestamp: DateTime.now(),
        fixType: GnssFixType.rtk,
        rtkStatus: RtkStatus.fixed,
        receiverName: "ArduSimple",
        correctionAge: 1.2,
        satellitesUsed: 15,
        stationId: "TEST_STATION",
      );

      service.addPointToGeometry(const LatLng(47.0, 19.0), 100.0, fix: fix);
      service.finishRecording("RTK FIX Point", "Test");

      final feature = service.activeLayer!.features.last;
      final stats = feature.calculatedStats;

      expect(stats['Survey Method'], 'RTK');
      expect(stats['RTK Status'], 'FIXED');
      expect(stats['NTRIP Active'], 'YES');
      expect(stats['Receiver'], 'ArduSimple');
      expect(stats['Sats Used'], 15);
      expect(stats['Correction Age'], 1.2);
      expect(stats['Station ID'], 'TEST_STATION');
    });

    test('External RTK FLOAT Metadata', () {
      final fix = GnssFix(
        latitude: 47.0,
        longitude: 19.0,
        altitude: 100.0,
        ellipsoidalHeight: 100.0,
        isEllipsoidal: true,
        source: GnssSource.external,
        connectionType: GnssConnectionType.bluetoothClassic,
        timestamp: DateTime.now(),
        fixType: GnssFixType.rtk,
        rtkStatus: RtkStatus.float,
      );

      service.addPointToGeometry(const LatLng(47.0, 19.0), 100.0, fix: fix);
      service.finishRecording("RTK FLOAT Point", "Test");

      final feature = service.activeLayer!.features.last;
      expect(feature.calculatedStats['Survey Method'], 'RTK');
      expect(feature.calculatedStats['RTK Status'], 'FLOAT');
    });

    test('External GNSS (Non-RTK) Metadata', () {
      final fix = GnssFix(
        latitude: 47.0,
        longitude: 19.0,
        altitude: 100.0,
        ellipsoidalHeight: 100.0,
        isEllipsoidal: true,
        source: GnssSource.external,
        connectionType: GnssConnectionType.bluetoothClassic,
        timestamp: DateTime.now(),
        fixType: GnssFixType.autonomous,
        rtkStatus: RtkStatus.none,
      );

      service.addPointToGeometry(const LatLng(47.0, 19.0), 100.0, fix: fix);
      service.finishRecording("External Autonomous Point", "Test");

      final feature = service.activeLayer!.features.last;
      expect(feature.calculatedStats['Survey Method'], 'EXTERNAL_GNSS');
      expect(feature.calculatedStats['RTK Status'], 'NONE');
    });

    test('Imported GIS Metadata', () async {
      final feature = GeoFeature(
        name: "Imported Point",
        type: FeatureType.point,
        geometry: [const LatLng(47.0, 19.0)],
        calculatedStats: {
          'Survey Method': 'IMPORTED',
          'Imported CRS': 'EOV',
        }
      );
      
      service.activeLayer!.features.add(feature);
      
      final stats = feature.calculatedStats;
      expect(stats['Survey Method'], 'IMPORTED');
      expect(stats['Imported CRS'], 'EOV');
      expect(stats['GNSS Source'], isNull);
    });
  });
}
