import 'package:flutter_test/flutter_test.dart';
import 'package:mfk_geomeasure/services/gnss/bynav_parser.dart';

void main() {
  group('Phase 2: BynavParser Integrity Tests', () {
    final parser = BynavParser();

    test('BESTPOSA horizontal accuracy calculation matches formula', () {
      // BESTPOSA body: solStatus, posType, lat, lon, height, undulation, datum, latStd, lonStd, hgtStd
      // Here: latStd = 0.03, lonStd = 0.04
      // hAcc = sqrt(latStd^2 + lonStd^2) = sqrt(0.0009 + 0.0016) = sqrt(0.0025) = 0.05
      const msg = '#BESTPOSA,COM1,0,85.0,FINESTEERING,2234,123456.000,02000000,0000,0;SOL_COMPUTED,NARROW_INT,47.0,19.0,150.0,40.0,WGS84,0.03,0.04,0.08,stnId,1.0,1.0,20,18*12345678';
      final sol = parser.parse(msg);

      expect(sol, isNotNull);
      expect(sol!.messageName, 'BESTPOSA');
      expect(sol.latitude, 47.0);
      expect(sol.longitude, 19.0);
      expect(sol.altitude, 150.0);
      expect(sol.undulation, 40.0);
      expect(sol.horizontalAccuracy, closeTo(0.05, 0.001));
      expect(sol.verticalAccuracy, 0.08);
      expect(sol.satellitesUsed, 18);
      expect(sol.correctionAge, 1.0);
      expect(sol.posType, 'SOL_COMPUTED/NARROW_INT');

      // BESTPOS means isEllipsoidalHeight should be FALSE (orthometric)
      expect(sol.isEllipsoidalHeight, isFalse);
    });

    test('BESTPOSA with blank position type preserves status without fabricating a type', () {
      const msg = '#BESTPOSA,COM1,0,85.0,FINESTEERING,2234,123456.000,02000000,0000,0;SOL_COMPUTED,,47.0,19.0,150.0,40.0,WGS84,0.03,0.04,0.08,stnId,1.0,1.0,20,18*12345678';
      final sol = parser.parse(msg);

      expect(sol, isNotNull);
      expect(sol!.solutionStatus, 'SOL_COMPUTED');
      expect(sol.posType, isNull);
      expect(sol.posType, isNot(contains('null')));
    });

    test('INSPVAXA horizontal accuracy calculation matches formula', () {
      // INSPVAXA body: insStatus, posType, lat, lon, height, undulation, nVel, eVel, uVel, roll, pitch, azimuth, latStd, lonStd, hgtStd
      const msg = '#INSPVAXA,COM1,0,85.0,FINESTEERING,2234,123456.000,02000000,0000,0;INS_SOLUTION_GOOD,INS_RTKFIXED,47.0,19.0,190.0,-40.0,0.1,0.2,0.3,1.0,2.0,3.0,0.06,0.08,0.1*12345678';
      final sol = parser.parse(msg);

      expect(sol, isNotNull);
      expect(sol!.messageName, 'INSPVAXA');
      expect(sol.altitude, 190.0); // This is WGS84 according to NovAtel format
      expect(sol.undulation, -40.0);

      // hAcc = sqrt(0.06^2 + 0.08^2) = sqrt(0.0036 + 0.0064) = sqrt(0.01) = 0.1
      expect(sol.horizontalAccuracy, closeTo(0.1, 0.001));
      expect(sol.verticalAccuracy, 0.1);

      expect(sol.insStatus, 'INS_SOLUTION_GOOD');
      expect(sol.posType, 'INS_RTKFIXED');

      // INSPVAX means isEllipsoidalHeight should be TRUE
      expect(sol.isEllipsoidalHeight, isTrue);
    });

    test('Invalid or truncated messages return null', () {
      const truncatedMsg = '#BESTPOSA,COM1,0,85.0,FINESTEERING,2234,123456.000,02000000,0000,0;SOL_COMPUTED,NARROW_INT,47.0,19.0';
      final sol = parser.parse(truncatedMsg);
      expect(sol, isNull);
    });
  });
}
