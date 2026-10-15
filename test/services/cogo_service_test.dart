import 'package:flutter_test/flutter_test.dart';
import 'package:mfk_geomeasure/services/cogo_service.dart';
import 'package:mfk_geomeasure/services/eov_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('COGO Inverse Bearing Quadrant Tests', () {
    late CogoService cogoService;

    setUp(() {
      final eovService = EovService();
      cogoService = CogoService(eovService);
    });

    test('Quadrant I: dY > 0, dX > 0 (NE -> 45 deg)', () {
      final report = cogoService.generateEovInverseReport(1000, 1000, 1100, 1100);
      expect(report.results['bearing'], closeTo(45.0, 0.001));
    });

    test('Quadrant II: dY > 0, dX < 0 (SE -> 135 deg)', () {
      final report = cogoService.generateEovInverseReport(1000, 1000, 1100, 900);
      expect(report.results['bearing'], closeTo(135.0, 0.001));
    });

    test('Quadrant III: dY < 0, dX < 0 (SW -> 225 deg)', () {
      final report = cogoService.generateEovInverseReport(1000, 1000, 900, 900);
      expect(report.results['bearing'], closeTo(225.0, 0.001));
    });

    test('Quadrant IV: dY < 0, dX > 0 (NW -> 315 deg)', () {
      final report = cogoService.generateEovInverseReport(1000, 1000, 900, 1100);
      expect(report.results['bearing'], closeTo(315.0, 0.001));
    });

    test('Exact Cardinal Directions (N=0, E=90, S=180, W=270)', () {
      // Due North: dY = 0, dX = 100 -> 0 deg
      expect(cogoService.generateEovInverseReport(1000, 1000, 1000, 1100).results['bearing'], closeTo(0.0, 0.001));
      // Due East: dY = 100, dX = 0 -> 90 deg
      expect(cogoService.generateEovInverseReport(1000, 1000, 1100, 1000).results['bearing'], closeTo(90.0, 0.001));
      // Due South: dY = 0, dX = -100 -> 180 deg
      expect(cogoService.generateEovInverseReport(1000, 1000, 1000, 900).results['bearing'], closeTo(180.0, 0.001));
      // Due West: dY = -100, dX = 0 -> 270 deg
      expect(cogoService.generateEovInverseReport(1000, 1000, 900, 1000).results['bearing'], closeTo(270.0, 0.001));
    });
  });
}
