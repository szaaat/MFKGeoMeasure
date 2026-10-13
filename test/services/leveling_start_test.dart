import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mfk_geomeasure/services/leveling/leveling_calculation_service.dart';
import 'package:mfk_geomeasure/services/leveling/leveling_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockPathProvider extends Fake with MockPlatformInterfaceMixin implements PathProviderPlatform {
  final Directory tempDir = Directory.systemTemp.createTempSync('leveling_start_test_');

  @override
  Future<String?> getApplicationDocumentsPath() async => tempDir.path;
  @override
  Future<String?> getTemporaryPath() async => tempDir.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  PathProviderPlatform.instance = MockPathProvider();

  group('Leveling Service Start Tests', () {
    late LevelingService levelingService;

    setUp(() {
      levelingService = LevelingService(LevelingCalculationService());
    });

    test('startNewProject initializes project and station correctly', () {
      levelingService.startNewProject(
        id: 'test-leveling-1',
        name: 'Vonal szintezés 1',
        startPointId: 'P1',
        startHeight: 120.450,
        isPrecision: false,
      );

      expect(levelingService.activeProject, isNotNull);
      expect(levelingService.activeProject!.name, 'Vonal szintezés 1');
      expect(levelingService.activeProject!.startPointId, 'P1');
      expect(levelingService.activeProject!.startHeight, 120.450);

      levelingService.addStation('P1');
      expect(levelingService.currentStation, isNotNull);
      expect(levelingService.currentStation!.backsightPointId, 'P1');
    });

    test('startNewProject accepts 0.0 startHeight for unknown benchmark points', () {
      levelingService.startNewProject(
        id: 'test-leveling-2',
        name: 'Relatív szintezés',
        startPointId: 'P0',
        startHeight: 0.0,
        isPrecision: false,
      );

      expect(levelingService.activeProject, isNotNull);
      expect(levelingService.activeProject!.startHeight, 0.0);
    });
  });
}
