import 'package:flutter_test/flutter_test.dart';
import 'package:mfk_geomeasure/services/bme_grid_service.dart';
import 'package:mfk_geomeasure/services/geoid_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GeoidCorrectionService Height Management', () {
    late BmeGridService bmeGridService;
    late GeoidCorrectionService geoidService;

    setUp(() async {
      bmeGridService = BmeGridService();
      await bmeGridService.load();
      geoidService = GeoidCorrectionService(bmeGridService);
      // await geoidService.loadGeoidFile(); // Not needed if inside BME grid
    });

    test('Ellipsoidal height inside BME grid, unknown frame -> uses BME with assumed status', () {
      // 47.5, 19.0 is inside Hungary
      final result = geoidService.getOrthoHeight(47.5, 19.0, 150.0, isEllipsoidal: true, referenceFrame: GeoidInputFrame.unknown);

      expect(result, isNotNull);
      expect(result!.gridName, 'BME_geoid2014');
      // gpsAlt - undulation (undulation is around 40m in Hungary)
      expect(result.value, lessThan(150.0));
      expect(result.value, greaterThan(100.0));
    });

    test('Ellipsoidal height inside BME grid, etrf2000 frame -> uses BME', () {
      final result = geoidService.getOrthoHeight(47.5, 19.0, 150.0, isEllipsoidal: true, referenceFrame: GeoidInputFrame.etrf2000);

      expect(result, isNotNull);
      expect(result!.gridName, 'BME_geoid2014');
    });

    test('Already orthometric height -> returns null (no correction applied)', () {
      final result = geoidService.getOrthoHeight(47.5, 19.0, 105.0, isEllipsoidal: false, referenceFrame: GeoidInputFrame.unknown);

      expect(result, isNull);
    });
  });
}
