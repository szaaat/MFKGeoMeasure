import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mfk_geomeasure/models/geo_feature.dart';
import 'package:mfk_geomeasure/services/eov_service.dart';
import 'package:mfk_geomeasure/services/geoid_service.dart';
import 'package:mfk_geomeasure/services/project_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockPathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final Directory tempDir =
      Directory.systemTemp.createTempSync('project_service_test_');

  @override
  Future<String?> getApplicationDocumentsPath() async => tempDir.path;
  @override
  Future<String?> getTemporaryPath() async => tempDir.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MockPathProvider mockPathProvider;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockPathProvider = MockPathProvider();
    PathProviderPlatform.instance = mockPathProvider;
  });

  group('Export and Persistence Regression Tests', () {
    late ProjectService projectService;
    late EovService eovService;
    late GeoidCorrectionService geoidService;

    setUp(() async {
      ProjectService.enableSaving = true;
      geoidService = GeoidCorrectionService();
      await geoidService.loadBmeGrid();
      eovService = EovService(geoidService.gridService, false,
          EovInputFrame.unknown, EovTransformMode.bmeAssumed);
      await eovService.loadBmeGrids();

      projectService = ProjectService();
      projectService.updateEovService(eovService);
      projectService.updateGeoidService(geoidService);
      projectService.createProject("Regression Project");
    });

    test('1. EOV_Y and EOV_X attribute mapping in CSV and GeoJSON exports', () {
      final layer = projectService.activeLayer!;
      // Eger benchmark point: (lat: 47.97801236, lon: 20.43002679)
      // Expected EOV: Easting Y = 753218.97 m, Northing X = 293622.26 m
      const lat = 47.97801236;
      const lon = 20.43002679;
      final feature = GeoFeature(
        name: "Eger Benchmark",
        type: FeatureType.point,
        geometry: [const LatLng(lat, lon)],
        altitudes: [233.625],
        properties: {'isEllipsoidal': [true], 'referenceFrame': 'etrf2000'},
      );
      layer.features.add(feature);

      // 1. Verify GeoJSON export properties
      final geoJson = projectService.buildGeoJsonForTest(
        geoidService,
        projectService.activeProject!,
        layer: layer,
      );
      final properties = geoJson['features'][0]['properties'];

      expect(properties['EOV_Y'], closeTo(753218.97, 0.05),
          reason: "EOV_Y in GeoJSON must be Easting (~753,218 m)");
      expect(properties['EOV_X'], closeTo(293622.26, 0.05),
          reason: "EOV_X in GeoJSON must be Northing (~293,622 m)");

      // 2. Verify CSV export column headers and mapped row values
      final csvString = projectService.generateCsvForTest(
        geoidService,
        projectService.activeProject!,
        layer: layer,
      );
      final csvLines = csvString.trim().split('\n');
      expect(csvLines.length, greaterThanOrEqualTo(2));
      final headers = csvLines[0].split(';');
      final dataRow = csvLines[1].split(';');

      final eovYIndex = headers.indexOf('EOV_Y');
      final eovXIndex = headers.indexOf('EOV_X');
      expect(eovYIndex, isNot(-1), reason: "CSV must contain EOV_Y header");
      expect(eovXIndex, isNot(-1), reason: "CSV must contain EOV_X header");

      expect(double.parse(dataRow[eovYIndex]), closeTo(753218.97, 0.05),
          reason: "EOV_Y column in CSV must be Easting (~753,218 m)");
      expect(double.parse(dataRow[eovXIndex]), closeTo(293622.26, 0.05),
          reason: "EOV_X column in CSV must be Northing (~293,622 m)");
    });

    test('2. GeoJSON 3D height semantics (Ellipsoidal vs Baltic Orthometric)', () {
      final layer = projectService.activeLayer!;
      const lat = 47.97801236;
      const lon = 20.43002679;
      const hEllipsoidal = 233.625;

      final feature = GeoFeature(
        name: "Height Test Point",
        type: FeatureType.point,
        geometry: [const LatLng(lat, lon)],
        altitudes: [hEllipsoidal],
        properties: {'isEllipsoidal': [true], 'referenceFrame': 'etrf2000'},
      );
      layer.features.add(feature);

      final geoJson = projectService.buildGeoJsonForTest(
        geoidService,
        projectService.activeProject!,
        layer: layer,
      );

      final featureObj = geoJson['features'][0];
      final List coordinates = featureObj['geometry']['coordinates'];
      final properties = featureObj['properties'];

      // Geometry 3rd coordinate must be ellipsoidal height (RFC 7946)
      expect(coordinates.length, 3);
      expect(coordinates[0], closeTo(lon, 0.000001));
      expect(coordinates[1], closeTo(lat, 0.000001));
      expect(coordinates[2], closeTo(hEllipsoidal, 0.001),
          reason: "3rd GeoJSON coordinate must be WGS84 Ellipsoidal Height");

      // Feature properties must retain Baltic orthometric height (H = h - N = 191.279 m)
      expect(properties['Baltic_Height'], closeTo(191.279, 0.01),
          reason:
              "Baltic_Height property must retain calculated orthometric height");
      expect(properties['Ellipsoidal_Height'], closeTo(hEllipsoidal, 0.001));
    });

    test('3. Rapid consecutive edits execute without race conditions or PathNotFoundException',
        () async {
      final layer = projectService.activeLayer!;
      final feature = GeoFeature(
        name: "Rapid Edit Target",
        type: FeatureType.point,
        geometry: [const LatLng(47, 19)],
      );
      layer.features.add(feature);

      // Perform 50 rapid sequential edits in fast succession
      for (int i = 1; i <= 50; i++) {
        projectService.updateFeatureCustomData(feature.id, {'rapid_counter': i});
      }

      // Flush pending save queue and explicitly assert no save errors occurred
      await projectService.flushPendingSaves();
      expect(projectService.lastSaveError, isNull,
          reason: "Save operations must complete without errors");

      // Verify raw file string on disk
      final appDir = await mockPathProvider.getApplicationDocumentsPath();
      final savedFile = File('$appDir/saved_projects.json');
      expect(await savedFile.exists(), isTrue,
          reason: "saved_projects.json file must exist on disk");
      final content = await savedFile.readAsString();
      expect(content, contains('"rapid_counter":50'),
          reason: "Disk file must contain the 50th edit value");

      // Verify complete model deserialization into a fresh ProjectService instance
      final freshService = ProjectService();
      await freshService.loadProjectsFromDiskForTest();
      freshService.updateEovService(eovService);
      freshService.updateGeoidService(geoidService);
      expect(freshService.activeProject, isNotNull);
      final reloadedFeature = freshService.activeProject!.layers.first.features
          .firstWhere((f) => f.id == feature.id);
      expect(reloadedFeature.customData['rapid_counter'], 50,
          reason:
              "Freshly reloaded model from disk must contain the 50th edit value");
    });
  });
}
