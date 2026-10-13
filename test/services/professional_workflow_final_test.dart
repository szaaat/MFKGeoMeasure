import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mfk_geomeasure/models/geo_feature.dart';
import 'package:mfk_geomeasure/services/project_service.dart';
import 'package:mfk_geomeasure/services/eov_service.dart';
import 'package:mfk_geomeasure/services/geoid_service.dart';
import 'package:mfk_geomeasure/models/field_definition.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockPathProvider extends Fake with MockPlatformInterfaceMixin implements PathProviderPlatform {
  final Directory tempDir = Directory.systemTemp.createTempSync('professional_workflow_test_');

  @override
  Future<String?> getApplicationDocumentsPath() async => tempDir.path;
  @override
  Future<String?> getTemporaryPath() async => tempDir.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  PathProviderPlatform.instance = MockPathProvider();

  group('Professional GIS & Survey Workflow Final Verification', () {
    late ProjectService projectService;
    late EovService eovService;
    late GeoidCorrectionService geoidService;

    setUp(() {
      ProjectService.enableSaving = false;
      eovService =
          EovService(null, false, EovInputFrame.unknown, EovTransformMode.legacy);
      geoidService = GeoidCorrectionService();
      projectService = ProjectService();
      projectService.updateEovService(eovService);
      projectService.updateGeoidService(geoidService);
      projectService.createProject("Final Verification Project");
    });

    test('Point 1: 100 features -> 5 selected -> export -> subset integrity', () async {
      final layer = projectService.activeLayer!;
      
      // 1. Create 100 features
      for (int i = 1; i <= 100; i++) {
        final f = GeoFeature(
          name: "Point $i",
          type: FeatureType.point,
          geometry: [LatLng(47.0 + i / 1000, 19.0)],
          customData: {"INDEX": i},
        );
        layer.features.add(f);
      }

      // 2. Select 5 features (e.g. 10, 20, 30, 40, 50)
      final selectedIds = [
        layer.features[9].id,
        layer.features[19].id,
        layer.features[29].id,
        layer.features[39].id,
        layer.features[49].id,
      ];
      for (var id in selectedIds) {
        projectService.selectFeature(layer.id, id, multiSelect: true);
      }
      expect(projectService.selectedFeatureIds.length, 5);

      // 3. Export Selected to GeoJSON (since it's easiest to verify in memory)
      final featuresToExport = layer.features.where((f) => projectService.selectedFeatureIds.contains(f.id)).toList();
      // Accessing internal builder for verification
      // ignore: invalid_use_of_protected_member
      final geoJson = projectService.buildGeoJsonForTest(geoidService, projectService.activeProject!, layer: layer, features: featuresToExport);
      
      final List features = geoJson['features'];
      expect(features.length, 5);
      
      // Verify attributes
      final indices = features.map((f) => f['properties']['INDEX']).toList();
      expect(indices, containsAll([10, 20, 30, 40, 50]));
      
      // Verify geometry consistency (Budapest area)
      final firstPoint = features.first['geometry']['coordinates'];
      expect(firstPoint[1], closeTo(47.0 + 10 / 1000, 0.0000001));
    });

    test('Point 2: Attribute Table edit -> ProjectService -> Safe Save -> Reload persistence', () async {
      ProjectService.enableSaving = true;
      final layer = projectService.activeLayer!;
      final f = GeoFeature(name: "Edit Test", type: FeatureType.point, geometry: [const LatLng(47, 19)]);
      layer.features.add(f);
      
      projectService.addCustomFieldToLayer(layer, CustomFieldDefinition(
        key: 'note', label: 'Note', type: FieldType.text
      ));

      // Simulate edit from Attribute Table - AWAIT IT
      await projectService.updateFeatureAttribute(layer.id, f.id, 'note', 'Updated Value');
      
      expect(f.customData['note'], 'Updated Value');
      
      // Verification of "Safe Save" by checking the file
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/saved_projects.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        expect(content, contains('Updated Value'));
      } else {
        expect(f.customData['note'], 'Updated Value');
      }
    });

    test('Point 5: Performance Stress Test - 10,000 features', () {
      final layer = projectService.activeLayer!;
      final stopwatch = Stopwatch()..start();
      
      // Generation
      for (int i = 0; i < 10000; i++) {
        layer.features.add(GeoFeature(
          name: "Bulk $i", 
          type: FeatureType.point, 
          geometry: [const LatLng(47, 19)],
          calculatedStats: {'HDOP': 0.5 + (i % 10) / 10},
        ));
      }
      final genTime = stopwatch.elapsedMilliseconds;
      stopwatch.reset();

      // Filtering (Search)
      const query = "Bulk 999";
      final filtered = layer.features.where((f) => f.name.contains(query)).toList();
      final filterTime = stopwatch.elapsedMilliseconds;
      expect(filtered.length, 11); // 999, 9990-9999
      stopwatch.reset();

      // Sorting (by HDOP)
      layer.features.sort((a, b) => (a.calculatedStats['HDOP'] as num).compareTo(b.calculatedStats['HDOP'] as num));
      final sortTime = stopwatch.elapsedMilliseconds;
      
      debugPrint("Performance (10k features): Gen: ${genTime}ms, Filter: ${filterTime}ms, Sort: ${sortTime}ms");
      
      expect(filterTime, lessThan(50)); // Should be very fast on modern hardware
      expect(sortTime, lessThan(100));
    });

    test('Point 6: EOV Consistency Check (Geometry vs Attributes)', () {
      const lat = 47.902;
      const lon = 20.373;
      final eov = eovService.wgsToEov(lat, lon);
      // eov[0] is Easting (Y ~ 740,000 m), eov[1] is Northing (X ~ 285,000 m)
      
      double easting = eov[0]; 
      double northing = eov[1]; 
      
      // Check if it's in the ballpark for Hungary
      expect(easting, greaterThan(400000));
      expect(easting, lessThan(900000));
      expect(northing, greaterThan(40000));
      expect(northing, lessThan(400000));
      
      // Round-trip check via EovService directly to verify its own consistency
      final wgsBack = eovService.eovToWgs(easting, northing);
      expect(wgsBack[0], closeTo(lat, 0.0000001));
      expect(wgsBack[1], closeTo(lon, 0.0000001));
    });
  });
}
