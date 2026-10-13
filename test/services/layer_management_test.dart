import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mfk_geomeasure/models/geo_feature.dart';
import 'package:mfk_geomeasure/services/project_service.dart';
import 'package:mfk_geomeasure/services/import_service.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockPathProvider extends Fake with MockPlatformInterfaceMixin implements PathProviderPlatform {
  final Directory tempDir = Directory.systemTemp.createTempSync('layer_mgmt_test_');

  @override
  Future<String?> getApplicationDocumentsPath() async => tempDir.path;
  @override
  Future<String?> getTemporaryPath() async => tempDir.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  PathProviderPlatform.instance = MockPathProvider();

  group('Professional Layer Management Tests', () {
    late ProjectService service;

    setUp(() {
      ProjectService.enableSaving = false;
      service = ProjectService();
      service.createProject("Layer Test Project");
    });

    test('Initial state has one layer, visible and active', () {
      expect(service.activeProject!.layers.length, 1);
      expect(service.activeProject!.layers.first.isVisible, isTrue);
      expect(service.activeLayer!.id, service.activeProject!.layers.first.id);
    });

    test('Creating a new layer sets it as active', () {
      service.createLayer("New Layer");
      expect(service.activeProject!.layers.length, 2);
      expect(service.activeLayer!.name, "New Layer");
      expect(service.activeProject!.activeLayerId, service.activeLayer!.id);
    });

    test('Visibility toggle affects visibleFeatures', () {
      service.addPointToGeometry(const LatLng(47, 19), 100);
      service.finishRecording("Point 1", "");
      
      expect(service.visibleFeatures.length, 1);
      
      service.toggleLayerVisibility(service.activeLayer!);
      expect(service.visibleFeatures.length, 0);
      
      service.toggleLayerVisibility(service.activeProject!.layers.first);
      expect(service.visibleFeatures.length, 1);
    });

    test('Deleting a layer', () {
      service.createLayer("Layer to Delete");
      final idToDelete = service.activeLayer!.id;
      
      service.deleteLayer(service.activeProject!.layers.last);
      expect(service.activeProject!.layers.any((l) => l.id == idToDelete), isFalse);
      expect(service.activeProject!.layers.length, 1);
      expect(service.activeLayer, isNotNull);
    });

    test('Multi-layer Import Support', () {
      final imported = [
        ImportedLayer("Roads", [GeoFeature(name: "Road 1", type: FeatureType.line, geometry: [])]),
        ImportedLayer("Points", [GeoFeature(name: "P1", type: FeatureType.point, geometry: [])]),
      ];
      
      service.addImportedLayers(imported);
      
      expect(service.activeProject!.layers.length, 3); // 1 original + 2 imported
      expect(service.activeProject!.layers.any((l) => l.name == "Roads"), isTrue);
      expect(service.activeProject!.layers.any((l) => l.name == "Points"), isTrue);
      
      final roadsLayer = service.activeProject!.layers.firstWhere((l) => l.name == "Roads");
      expect(roadsLayer.features.length, 1);
      expect(roadsLayer.isVisible, isTrue);
    });
  });
}
