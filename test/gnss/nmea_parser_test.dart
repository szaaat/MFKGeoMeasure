import 'package:flutter_test/flutter_test.dart';
import 'package:mfk_geomeasure/services/gnss/nmea_parser.dart';
import 'package:mfk_geomeasure/models/gnss_fix.dart';

void main() {
  group('NmeaParser Tests', () {
    late NmeaParser parser;

    setUp(() {
      parser = NmeaParser();
    });

    String withChecksum(String sentence) {
      int calculated = 0;
      for (int i = 0; i < sentence.length; i++) {
        calculated ^= sentence.codeUnitAt(i);
      }
      return '\$$sentence*${calculated.toRadixString(16).toUpperCase().padLeft(2, '0')}';
    }

    test('Valid GGA parsing - Autonomous', () {
      final gga = withChecksum('GPGGA,123519,4807.038,N,01131.000,E,1,08,0.9,545.4,M,46.9,M,,');
      final fix = parser.parse(gga, source: GnssSource.external, connectionType: GnssConnectionType.bluetoothClassic);
      
      expect(fix, isNotNull);
      expect(fix!.latitude, closeTo(48.1173, 0.0001));
      expect(fix.longitude, closeTo(11.5166, 0.0001));
      expect(fix.fixType, GnssFixType.autonomous);
      expect(fix.satellitesUsed, 8);
      expect(fix.hdop, 0.9);
      expect(fix.mslAltitude, 545.4);
      expect(fix.geoidSeparation, 46.9);
      expect(fix.ellipsoidalHeight, 545.4 + 46.9);
      expect(fix.isEllipsoidal, false);
    });

    test('RTK FIX GGA parsing', () {
      // Quality = 4 (RTK Fixed)
      final gga = withChecksum('GNGGA,172814.00,4714.439,N,01904.857,E,4,24,0.6,120.5,M,43.2,M,,');
      final fix = parser.parse(gga, source: GnssSource.external, connectionType: GnssConnectionType.ble);
      
      expect(fix, isNotNull);
      expect(fix!.fixType, GnssFixType.rtk);
      expect(fix.rtkStatus, RtkStatus.fixed);
      expect(fix.mslAltitude, 120.5);
      expect(fix.geoidSeparation, 43.2);
      expect(fix.ellipsoidalHeight, 120.5 + 43.2);
    });

    test('RTK FLOAT GGA parsing', () {
      // Quality = 5 (RTK Float)
      final gga = withChecksum('GNGGA,172814.00,4714.439,N,01904.857,E,5,18,0.8,120.5,M,43.2,M,,');
      final fix = parser.parse(gga, source: GnssSource.external, connectionType: GnssConnectionType.ble);
      
      expect(fix, isNotNull);
      expect(fix!.fixType, GnssFixType.rtk);
      expect(fix.rtkStatus, RtkStatus.float);
    });

    test('Invalid checksum', () {
      const gga = r'$GPGGA,123519,4807.038,N,01131.000,E,1,08,0.9,545.4,M,46.9,M,,*00';
      final fix = parser.parse(gga, source: GnssSource.external, connectionType: GnssConnectionType.usb);
      expect(fix, isNull);
    });

    test('GSA / GSV state management', () {
      final gsa = withChecksum('GPGSA,A,3,01,02,03,04,05,06,07,08,,,,,1.2,0.7,1.0');
      final gsv = withChecksum('GPGSV,3,1,11,01,40,090,40,02,19,045,35,03,58,214,,04,39,310,40');
      final gga = withChecksum('GPGGA,123519,4807.038,N,01131.000,E,1,08,0.9,545.4,M,46.9,M,,');

      parser.parse(gsa, source: GnssSource.external, connectionType: GnssConnectionType.usb);
      parser.parse(gsv, source: GnssSource.external, connectionType: GnssConnectionType.usb);
      final fix = parser.parse(gga, source: GnssSource.external, connectionType: GnssConnectionType.usb);

      expect(fix, isNotNull);
      expect(fix!.pdop, 1.2);
      expect(fix.vdop, 1.0);
      expect(fix.satellitesInView, 11);
    });
  });
}
