import 'package:flutter_test/flutter_test.dart';
import 'package:mfk_geomeasure/services/bme_grid_service.dart';
import 'package:mfk_geomeasure/services/eov_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('EovService Fallback Removal', () {
    late BmeGridService gridService;
    late EovService eovService;

    setUp(() async {
      gridService = BmeGridService();
      await gridService.load();
      eovService = EovService(gridService, false, EovInputFrame.etrf2000, EovTransformMode.bmeEtrf2000);
    });

    test('eovToWgs throws StateError outside grid (no automatic legacy fallback)', () {
      // Very far coordinate outside Hungary BME grid
      expect(() => eovService.eovToWgs(100000.0, 10000.0), throwsStateError);
    });

    test('transformEovToWgs returns outsideGrid status instead of falling back', () {
      final result = eovService.transformEovToWgs(100000.0, 10000.0);
      expect(result.coordinates, isNull);
      expect(result.status, EovTransformStatus.outsideGrid);
    });

    test('Legacy transformation is only used if explicitly requested', () {
      final legacyService = EovService(gridService, false, EovInputFrame.unknown, EovTransformMode.legacy);
      final result = legacyService.transformEovToWgs(100000.0, 10000.0);
      expect(result.coordinates, isNotNull);
      expect(result.status, EovTransformStatus.legacy);
    });
  });
}
