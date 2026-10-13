import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mfk_geomeasure/models/geo_feature.dart';
import 'package:mfk_geomeasure/services/project_service.dart';
import 'package:mfk_geomeasure/services/eov_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockPathProvider extends Fake with MockPlatformInterfaceMixin implements PathProviderPlatform {
  final Directory tempDir = Directory.systemTemp.createTempSync('vertex_dist_test_');

  @override
  Future<String?> getApplicationDocumentsPath() async => tempDir.path;
  @override
  Future<String?> getTemporaryPath() async => tempDir.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  PathProviderPlatform.instance = MockPathProvider();

  group('Vertex Editing and Offset/Distance Tests', () {
    late ProjectService projectService;
    late EovService eovService;

    setUp(() {
      eovService =
          EovService(null, false, EovInputFrame.unknown, EovTransformMode.legacy);
      projectService = ProjectService();
      projectService.updateEovService(eovService);
      projectService.createProject('Vertex Test Project');
    });

    test('recalculateFeatureStats updates EOV X and EOV Y correctly', () {
      final feature = GeoFeature(
        name: 'Point 1',
        type: FeatureType.point,
        geometry: [const LatLng(47.4979, 19.0402)], // Budapest
      );

      projectService.recalculateFeatureStats(feature);

      expect(feature.calculatedStats['EOV Y'], isNotNull);
      expect(feature.calculatedStats['EOV X'], isNotNull);
      expect(feature.calculatedStats['EOV Y'], greaterThan(640000));
      expect(feature.calculatedStats['EOV X'], greaterThan(230000));
    });

    test('insertFeatureVertex inserts a vertex and updates stats', () {
      final feature = GeoFeature(
        name: 'Line 1',
        type: FeatureType.line,
        geometry: [const LatLng(47.0, 19.0), const LatLng(47.1, 19.1)],
      );

      projectService.insertFeatureVertex(feature, 1, const LatLng(47.05, 19.05));

      expect(feature.geometry.length, 3);
      expect(feature.geometry[1], const LatLng(47.05, 19.05));
      expect(feature.calculatedStats['Hossz'], isNotNull);
    });

    test('deleteFeatureVertex removes a vertex and enforces min points', () {
      final line = GeoFeature(
        name: 'Line 1',
        type: FeatureType.line,
        geometry: [const LatLng(47.0, 19.0), const LatLng(47.05, 19.05), const LatLng(47.1, 19.1)],
      );

      projectService.deleteFeatureVertex(line, 1);
      expect(line.geometry.length, 2);

      // Attempting to delete when only 2 points remain should throw
      expect(() => projectService.deleteFeatureVertex(line, 0), throwsA(isA<Exception>()));
    });

    test('createOffsetFeature generates parallel offset with valid geometry', () {
      final line = GeoFeature(
        name: 'Source Line',
        type: FeatureType.line,
        geometry: [const LatLng(47.4979, 19.0402), const LatLng(47.5000, 19.0500)],
      );
      projectService.activeLayer!.features.add(line);

      projectService.createOffsetFeature(line, 10.0);

      expect(projectService.activeLayer!.features.length, 2);
      final offsetFeature = projectService.activeLayer!.features.last;
      expect(offsetFeature.name, contains('eltolás'));
      expect(offsetFeature.geometry.length, 2);
      expect(offsetFeature.calculatedStats['Hossz'], isNotNull);
    });
  });
}
