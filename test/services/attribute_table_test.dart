import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mfk_geomeasure/services/project_service.dart';
import 'package:mfk_geomeasure/models/field_definition.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockPathProvider extends Fake with MockPlatformInterfaceMixin implements PathProviderPlatform {
  final Directory tempDir = Directory.systemTemp.createTempSync('attr_table_test_');

  @override
  Future<String?> getApplicationDocumentsPath() async => tempDir.path;
  @override
  Future<String?> getTemporaryPath() async => tempDir.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  PathProviderPlatform.instance = MockPathProvider();

  group('Professional Attribute Table Logic Tests', () {
    late ProjectService service;

    setUp(() {
      ProjectService.enableSaving = false;
      service = ProjectService();
      service.createProject("Table Test Project");
    });

    test('Type Validation - Integer', () async {
      final layer = service.activeLayer!;
      service.addCustomFieldToLayer(layer, CustomFieldDefinition(
        key: 'test_int',
        label: 'Test Int',
        type: FieldType.integer,
      ));

      service.addPointToGeometry(const LatLng(47, 19), 100);
      service.finishRecording("Point 1", "");
      final featureId = layer.features.last.id;

      // 1. Valid update
      final err1 = await service.updateFeatureAttribute(layer.id, featureId, 'test_int', '123');
      expect(err1, isNull);
      expect(layer.features.last.customData['test_int'], 123);
      expect(layer.features.last.customData['test_int'], isA<int>());

      // 2. Invalid update
      final err2 = await service.updateFeatureAttribute(layer.id, featureId, 'test_int', 'abc');
      expect(err2, isNotNull);
      expect(layer.features.last.customData['test_int'], 123); // Unchanged
    });

    test('Type Validation - Decimal with Comma', () async {
      final layer = service.activeLayer!;
      service.addCustomFieldToLayer(layer, CustomFieldDefinition(
        key: 'test_dec',
        label: 'Test Dec',
        type: FieldType.decimal,
      ));

      service.addPointToGeometry(const LatLng(47, 19), 100);
      service.finishRecording("Point 1", "");
      final featureId = layer.features.last.id;

      // Hungarian style comma input
      final err = await service.updateFeatureAttribute(layer.id, featureId, 'test_dec', '42,67');
      expect(err, isNull);
      expect(layer.features.last.customData['test_dec'], 42.67);
      expect(layer.features.last.customData['test_dec'], isA<double>());
    });

    test('Selection Sync State', () {
      final layerId = service.activeLayer!.id;
      const featureId = "f-123";
      
      service.selectFeature(layerId, featureId);
      
      expect(service.selectedFeature, isNotNull);
      expect(service.selectedFeature!.layerId, layerId);
      expect(service.selectedFeature!.featureId, featureId);
      
      service.selectFeature(null, null);
      expect(service.selectedFeature, isNull);
    });

    test('System Field Read-Only Constraint - logic returns error for invalid keys', () async {
      final err = await service.updateFeatureAttribute(service.activeLayer!.id, "none", "nonexistent", "val");
      expect(err, isNotNull);
    });

   group('Sorting and Formatting Logic', () {
      test('Handles 1000 features', () {
        for(int i=0; i<1000; i++) {
          service.addPointToGeometry(LatLng(47.0 + i/10000, 19.0), 100);
          service.finishRecording("P $i", "");
        }
        expect(service.activeLayer!.features.length, 1000); 
      });
    });
  });
}
