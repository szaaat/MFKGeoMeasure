import 'package:flutter_test/flutter_test.dart';
import 'package:mfk_geomeasure/services/gnss/bynav_parser.dart';

void main() {
  group('BynavParser Tests', () {
    late BynavParser parser;

    setUp(() {
      parser = BynavParser();
    });

    test('Parses short header INSPVASA correctly', () {
      const log = '%INSPVASA,COM1,0,85.0,FINESTEERING,2200,123456.780,00000000,0000,1234;2200,123456.780,47.12345678,18.12345678,150.123,0.01,0.02,0.00,1.23,-0.45,182.50,INS_SOLUTION_GOOD*crc';
      final solution = parser.parse(log);

      expect(solution, isNotNull);
      expect(solution!.messageName, 'INSPVASA');
      expect(solution.latitude, closeTo(47.12345678, 1e-7));
      expect(solution.longitude, closeTo(18.12345678, 1e-7));
      expect(solution.altitude, closeTo(150.123, 1e-3));
      expect(solution.roll, closeTo(1.23, 1e-2));
      expect(solution.pitch, closeTo(-0.45, 1e-2));
      expect(solution.heading, closeTo(182.50, 1e-2));
      expect(solution.insStatus, 'INS_SOLUTION_GOOD');
      expect(solution.isInsGood, isTrue);
      expect(solution.gpsWeek, 2200);
      expect(solution.gpsSeconds, 123456.780);
    });

    test('Parses extended header INSPVAXA with standard deviations', () {
      const log = '#INSPVAXA,COM1,0,85.0,FINESTEERING,2200,123456.780,00000000,0000,1234;INS_SOLUTION_GOOD,INS_RTKFIXED,47.12345678,18.12345678,150.123,43.21,0.01,0.02,0.00,1.23,-0.45,182.50,0.015,0.020,0.035,0.01,0.01,0.01,0.1,0.1,0.2,00000000,0*crc';
      final solution = parser.parse(log);

      expect(solution, isNotNull);
      expect(solution!.messageName, 'INSPVAXA');
      expect(solution.insStatus, 'INS_SOLUTION_GOOD');
      expect(solution.posType, 'INS_RTKFIXED');
      expect(solution.latitude, closeTo(47.12345678, 1e-7));
      expect(solution.longitude, closeTo(18.12345678, 1e-7));
      expect(solution.altitude, closeTo(150.123, 1e-3));
      expect(solution.undulation, closeTo(43.21, 1e-2));
      expect(solution.horizontalAccuracy, closeTo(0.025, 1e-3)); // sqrt(0.015^2 + 0.020^2) = 0.025
      expect(solution.verticalAccuracy, closeTo(0.035, 1e-3));
    });

    test('Parses BESTPOSA GNSS position log correctly', () {
      const log = '#BESTPOSA,COM1,0,85.0,FINESTEERING,2200,123456.780,00000000,0000,1234;SOL_COMPUTED,NARROW_INT,47.12345678,18.12345678,150.123,43.21,WGS84,0.012,0.016,0.025,0000,1.0,0.2,28,24,24,20,0,01,0,0*crc';
      final solution = parser.parse(log);

      expect(solution, isNotNull);
      expect(solution!.messageName, 'BESTPOSA');
      expect(solution.posType, 'SOL_COMPUTED/NARROW_INT');
      expect(solution.latitude, closeTo(47.12345678, 1e-7));
      expect(solution.longitude, closeTo(18.12345678, 1e-7));
      expect(solution.altitude, closeTo(150.123, 1e-3));
      expect(solution.horizontalAccuracy, closeTo(0.020, 1e-3)); // sqrt(0.012^2 + 0.016^2) = 0.020
      expect(solution.satellitesUsed, 24);
      expect(solution.correctionAge, closeTo(1.0, 1e-2));
    });

    test('Returns null on unrecognized / corrupted logs', () {
      expect(parser.parse('\$GPGGA,123456,4712.34,N,01812.34,E,1,08,0.9,150.0,M,43.0,M,,*47'), isNull);
      expect(parser.parse('INVALID_STRING_LOG'), isNull);
      expect(parser.parse('#INSPVASA,corrupted_header_without_semicolon'), isNull);
    });
  });
}
