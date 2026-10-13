import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mfk_geomeasure/models/geo_feature.dart';
import 'package:mfk_geomeasure/services/shp_export_service.dart';
import 'package:mfk_geomeasure/services/eov_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockPathProvider extends Fake with MockPlatformInterfaceMixin implements PathProviderPlatform {
  final Directory tempDir = Directory.systemTemp.createTempSync('gis_roundtrip_test_');

  @override
  Future<String?> getApplicationDocumentsPath() async => tempDir.path;
  @override
  Future<String?> getTemporaryPath() async => tempDir.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  PathProviderPlatform.instance = MockPathProvider();

  group('GIS Professional Round-trip Tests (EOV ↔ WGS84)', () {
    late EovService eovService;

    setUp(() {
      eovService =
          EovService(null, false, EovInputFrame.unknown, EovTransformMode.legacy);
    });

    test('EOV Point Round-trip Accuracy and Metadata', () async {
      // 1. INPUT: EOV Coordinates (Eger, Hungary area)
      // Y is Easting (~723km), X is Northing (~283km) in Hungarian standard
      const double originalEovY = 723456.78;
      const double originalEovX = 283456.78;
      
      // 2. INTERNAL: Convert to WGS84 for storage
      final wgs = eovService.eovToWgs(originalEovY, originalEovX);
      final LatLng storedPoint = LatLng(wgs[0], wgs[1]);

      final feature = GeoFeature(
        name: "Roundtrip Point",
        type: FeatureType.point,
        geometry: [storedPoint],
        customData: {"TEST_ATTR": "Verified", "NUM_VAL": 42.0},
        calculatedStats: {
          'Survey Method': 'RTK',
          'GNSS Source': 'EXTERNAL',
          'RTK Status': 'FIXED',
        }
      );

      final layer = ProjectLayer(name: "Test Layer", features: [feature]);

      // 3. EXPORT: Save as EOV Shapefile
      final tempDir = Directory.systemTemp.createTempSync();
      final shpFiles = await ShpExportService.generateShapefile(
        tempDir.path, 
        "roundtrip", 
        layer,
        eovService: eovService,
        useEov: true, // Force EOV export
      );

      final shpFile = shpFiles.firstWhere((f) => f.path.endsWith('.shp'));
      final prjFile = shpFiles.firstWhere((f) => f.path.endsWith('.prj'));
      
      // 4. VERIFY EXPORTED BINARY
      final exportData = await shpFile.readAsBytes();
      final view = exportData.buffer.asByteData();
      
      // SHP Point: Header(100) + RecordHeader(8) + Type(4) = 112 offset
      final xInFile = view.getFloat64(112, Endian.little); // SHP X (Easting in projected)
      final yInFile = view.getFloat64(120, Endian.little); // SHP Y (Northing in projected)

      // EOV Ordering: SHP X is Easting (EOV Y), SHP Y is Northing (EOV X)
      expect(xInFile, closeTo(originalEovY, 0.001), reason: "Exported Easting (Y) deviation too high");
      expect(yInFile, closeTo(originalEovX, 0.001), reason: "Exported Northing (X) deviation too high");

      // Verify PRJ contains EOV identifier
      final prjContent = await prjFile.readAsString();
      expect(prjContent, contains("23700"));

      // 5. IMPORT: Simulate loading it back
      // Since ImportService._parseShp requires BuildContext, we verify the transformation function directly
      final reWgsList = eovService.eovToWgs(xInFile, yInFile);
      final LatLng reImportedWgs = LatLng(reWgsList[0], reWgsList[1]);
      
      // Geodetic precision check
      expect(reImportedWgs.latitude, closeTo(storedPoint.latitude, 0.0000001));
      expect(reImportedWgs.longitude, closeTo(storedPoint.longitude, 0.0000001));

      // Cleanup
      tempDir.deleteSync(recursive: true);
    });

    test('WGS84 Round-trip Integrity', () async {
      const originalWgs = LatLng(47.4979, 19.0402); // Budapest
      
      final feature = GeoFeature(
        name: "Budapest WGS",
        type: FeatureType.point,
        geometry: [originalWgs],
      );
      final layer = ProjectLayer(name: "WGS Layer", features: [feature]);

      final tempDir = Directory.systemTemp.createTempSync();
      final shpFiles = await ShpExportService.generateShapefile(
        tempDir.path, 
        "wgs_test", 
        layer,
        useEov: false, // Export as WGS84
      );

      final shpFile = shpFiles.firstWhere((f) => f.path.endsWith('.shp'));
      final exportData = await shpFile.readAsBytes();
      final view = exportData.buffer.asByteData();
      
      // Longitude/Latitude order in WGS84 SHP
      final lonInFile = view.getFloat64(112, Endian.little);
      final latInFile = view.getFloat64(120, Endian.little);

      expect(lonInFile, closeTo(originalWgs.longitude, 0.0000001));
      expect(latInFile, closeTo(originalWgs.latitude, 0.0000001));

      tempDir.deleteSync(recursive: true);
    });

    test('EOV LineString Round-trip Accuracy', () async {
      final p1 = eovService.eovToWgs(723000, 283000);
      final p2 = eovService.eovToWgs(723100, 283100);
      final feature = GeoFeature(
        name: "Test Line",
        type: FeatureType.line,
        geometry: [LatLng(p1[0], p1[1]), LatLng(p2[0], p2[1])],
      );
      final layer = ProjectLayer(name: "Line Layer", features: [feature]);
      final tempDir = Directory.systemTemp.createTempSync();
      final shpFiles = await ShpExportService.generateShapefile(
        tempDir.path, "line_roundtrip", layer, eovService: eovService, useEov: true,
      );
      final exportData = await shpFiles.firstWhere((f) => f.path.endsWith('.shp')).readAsBytes();
      final view = exportData.buffer.asByteData();
      final x1InFile = view.getFloat64(156, Endian.little);
      final y1InFile = view.getFloat64(156 + 8, Endian.little);
      expect(x1InFile, closeTo(723000, 0.001));
      expect(y1InFile, closeTo(283000, 0.001));
      tempDir.deleteSync(recursive: true);
    });

    test('EOV Polygon Round-trip Accuracy', () async {
      final p1 = eovService.eovToWgs(723000, 283000);
      final p2 = eovService.eovToWgs(723100, 283000);
      final p3 = eovService.eovToWgs(723050, 283100);
      final feature = GeoFeature(
        name: "Test Polygon",
        type: FeatureType.polygon,
        geometry: [LatLng(p1[0], p1[1]), LatLng(p2[0], p2[1]), LatLng(p3[0], p3[1])],
      );
      final layer = ProjectLayer(name: "Poly Layer", features: [feature]);
      final tempDir = Directory.systemTemp.createTempSync();
      final shpFiles = await ShpExportService.generateShapefile(
        tempDir.path, "poly_roundtrip", layer, eovService: eovService, useEov: true,
      );
      final exportData = await shpFiles.firstWhere((f) => f.path.endsWith('.shp')).readAsBytes();
      final view = exportData.buffer.asByteData();
      final numPoints = view.getInt32(148, Endian.little);
      expect(numPoints, 4); 
      final x1InFile = view.getFloat64(156, Endian.little);
      expect(x1InFile, closeTo(723000, 0.001));
      tempDir.deleteSync(recursive: true);
    });
  });
}
