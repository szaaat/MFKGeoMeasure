import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mfk_geomeasure/models/geo_feature.dart';
import 'package:mfk_geomeasure/services/project_service.dart';
import 'package:mfk_geomeasure/models/field_definition.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockPathProvider extends Fake with MockPlatformInterfaceMixin implements PathProviderPlatform {
  final Directory tempDir = Directory.systemTemp.createTempSync('survey_workflow_test_');

  @override
  Future<String?> getApplicationDocumentsPath() async => tempDir.path;
  @override
  Future<String?> getTemporaryPath() async => tempDir.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  PathProviderPlatform.instance = MockPathProvider();

  group('Professional Survey Workflow Integration Tests', () {
    late ProjectService service;

    setUp(() {
      ProjectService.enableSaving = false;
      service = ProjectService();
      service.createProject("Workflow Test");
    });

    test('Multi-selection and Clear logic', () {
      final layerId = service.activeLayer!.id;
      const f1 = "f1";
      const f2 = "f2";
      
      service.selectFeature(layerId, f1, multiSelect: true);
      service.selectFeature(layerId, f2, multiSelect: true);
      
      expect(service.selectedFeatureIds.length, 2);
      expect(service.selectedFeatureIds.contains(f1), isTrue);
      expect(service.selectedFeatureIds.contains(f2), isTrue);
      
      service.selectFeature(layerId, f1, multiSelect: true); // Toggle off
      expect(service.selectedFeatureIds.length, 1);
      expect(service.selectedFeatureIds.contains(f1), isFalse);
      
      service.clearSelection();
      expect(service.selectedFeatureIds.isEmpty, isTrue);
    });

    test('ProjectLayer Metadata - Source and CRS', () {
      final layer = ProjectLayer(
        name: "Imported Data",
        sourceType: 'import',
        crsInfo: 'EPSG:23700',
      );
      
      expect(layer.sourceType, 'import');
      expect(layer.crsInfo, 'EPSG:23700');
    });

    test('ProjectLayer Dynamic containedGeometryTypes', () {
      final layer = service.activeLayer!;
      layer.features.add(GeoFeature(name: "P", type: FeatureType.point, geometry: [const LatLng(0, 0)]));
      layer.features.add(GeoFeature(name: "L", type: FeatureType.line, geometry: [const LatLng(0, 0), const LatLng(1, 1)]));
      
      final types = layer.containedGeometryTypes;
      expect(types.length, 2);
      expect(types.contains(FeatureType.point), isTrue);
      expect(types.contains(FeatureType.line), isTrue);
    });

    test('Type Safe Update - Success and Fail', () async {
      final layer = service.activeLayer!;
      service.addCustomFieldToLayer(layer, CustomFieldDefinition(
        key: 'pop',
        label: 'Population',
        type: FieldType.integer,
      ));
      
      final feature = GeoFeature(name: "City", type: FeatureType.point, geometry: [const LatLng(0, 0)]);
      layer.features.add(feature);
      
      // 1. Success
      final res1 = await service.updateFeatureAttribute(layer.id, feature.id, 'pop', '1000');
      expect(res1, isNull);
      expect(feature.customData['pop'], 1000);

      // 2. Failure
      final res2 = await service.updateFeatureAttribute(layer.id, feature.id, 'pop', 'not a number');
      expect(res2, isNotNull);
      expect(feature.customData['pop'], 1000); // Unchanged
    });
  });
}
