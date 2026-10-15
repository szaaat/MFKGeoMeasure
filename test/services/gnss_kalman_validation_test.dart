import 'package:flutter_test/flutter_test.dart';
import 'package:mfk_geomeasure/models/gnss_fix.dart';
import 'package:mfk_geomeasure/services/gnss/nmea_parser.dart';
import 'package:mfk_geomeasure/services/kalman_service.dart';

void main() {
  group('GGA NO FIX and Kalman Initialization Tests', () {
    late NmeaParser parser;
    late GpsKalmanFilter kalman;

    setUp(() {
      parser = NmeaParser();
      kalman = GpsKalmanFilter();
    });

    test('NO FIX GGA with empty coordinates results in invalid position', () {
      const sentence = '\$GPGGA,123456.00,,,,,0,00,0.0,,,,,,*41';
      // Calculate checksum:
      int checksum = 0;
      for (int i = 1; i < sentence.lastIndexOf('*'); i++) {
        checksum ^= sentence.codeUnitAt(i);
      }
      final validSentence = '\$GPGGA,123456.00,,,,,0,00,0.0,,,,,,*${checksum.toRadixString(16).toUpperCase().padLeft(2, '0')}';

      final fix = parser.parse(validSentence, source: GnssSource.external, connectionType: GnssConnectionType.ble);
      
      expect(fix, isNotNull);
      expect(fix!.fixType, equals(GnssFixType.none));
      expect(fix.isValidPosition, isFalse);
      expect(fix.latitude, equals(0.0));
      expect(fix.longitude, equals(0.0));
    });

    test('Valid external fix initializes Kalman accurately', () {
      const lat = 47.973596;
      const lon = 20.417747;
      const accuracy = 0.05;

      kalman.reset();
      
      final filtered = kalman.filter(lat, lon, accuracy);
      
      expect(filtered[0], equals(lat));
      expect(filtered[1], equals(lon));
      
      // Check next step with identical input
      final filtered2 = kalman.filter(lat, lon, accuracy);
      expect(filtered2[0], equals(lat));
      expect(filtered2[1], equals(lon));
    });

    test('Zero coordinate is marked invalid', () {
      final fix = GnssFix(
        latitude: 0.0,
        longitude: 0.0,
        altitude: 0.0,
        ellipsoidalHeight: 0.0,
        isEllipsoidal: false,
        source: GnssSource.external,
        connectionType: GnssConnectionType.ble,
        timestamp: DateTime.now(),
        fixType: GnssFixType.rtk,
      );

      expect(fix.isValidPosition, isFalse);
    });

    test('NaN coordinate is marked invalid', () {
      final fix = GnssFix(
        latitude: double.nan,
        longitude: 20.0,
        altitude: 0.0,
        ellipsoidalHeight: 0.0,
        isEllipsoidal: false,
        source: GnssSource.external,
        connectionType: GnssConnectionType.ble,
        timestamp: DateTime.now(),
        fixType: GnssFixType.rtk,
      );

      expect(fix.isValidPosition, isFalse);
    });
  });
}
