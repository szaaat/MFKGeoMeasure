import 'package:flutter_test/flutter_test.dart';
import 'package:mfk_geomeasure/models/gnss_fix.dart';
import 'package:mfk_geomeasure/services/gnss/nmea_parser.dart';

void main() {
  group('NmeaParser Timestamping', () {
    late NmeaParser parser;

    setUp(() {
      parser = NmeaParser();
    });

    String addChecksum(String sentence) {
      if (!sentence.startsWith(r'$')) return sentence;
      final content = sentence.substring(1);
      int checksum = 0;
      for (int i = 0; i < content.length; i++) {
        checksum ^= content.codeUnitAt(i);
      }
      return '$sentence*${checksum.toRadixString(16).toUpperCase().padLeft(2, '0')}';
    }

    test('Falls back to device time if no RMC date is known', () {
      final gga = addChecksum(r'$GNGGA,123456.00,4753.8921,N,02021.7289,E,1,08,0.9,211.5,M,38.4,M,,');
      final fix = parser.parse(gga, source: GnssSource.external, connectionType: GnssConnectionType.bluetoothClassic);
      
      expect(fix, isNotNull);
      expect(fix!.timestampSource, TimestampSource.device);
    });

    test('Uses GNSS time after RMC provides date', () {
      final rmc = addChecksum(r'$GNRMC,123455.00,A,4753.8921,N,02021.7289,E,0.026,,080926,,,A');
      parser.parse(rmc, source: GnssSource.external, connectionType: GnssConnectionType.bluetoothClassic);

      final gga = addChecksum(r'$GNGGA,123456.00,4753.8921,N,02021.7289,E,1,08,0.9,211.5,M,38.4,M,,');
      final fix = parser.parse(gga, source: GnssSource.external, connectionType: GnssConnectionType.bluetoothClassic);
      
      expect(fix, isNotNull);
      final f = fix!;
      expect(f.timestampSource, TimestampSource.gnss);
      expect(f.timestamp.year, 2026);
      expect(f.timestamp.month, 9);
      expect(f.timestamp.day, 8);
      expect(f.timestamp.hour, 12);
      expect(f.timestamp.minute, 34);
      expect(f.timestamp.second, 56);
    });

    test('Handles midnight rollover correctly', () {
      // RMC at 23:59:59 on Sep 8
      final rmc = addChecksum(r'$GNRMC,235959.00,A,4753.8921,N,02021.7289,E,0.026,,080926,,,A');
      parser.parse(rmc, source: GnssSource.external, connectionType: GnssConnectionType.bluetoothClassic);

      // GGA arrives at 00:00:01 (next day)
      final gga = addChecksum(r'$GNGGA,000001.00,4753.8921,N,02021.7289,E,1,08,0.9,211.5,M,38.4,M,,');
      final fix = parser.parse(gga, source: GnssSource.external, connectionType: GnssConnectionType.bluetoothClassic);
      
      expect(fix, isNotNull);
      final f = fix!;
      expect(f.timestampSource, TimestampSource.gnss);
      expect(f.timestamp.day, 9);
      expect(f.timestamp.hour, 0);
    });

    test('Handles GGA arriving just before RMC at midnight (stale date)', () {
      // Last known RMC was Sep 7, 23:59:59
      final rmcOld = addChecksum(r'$GNRMC,235959.00,A,4753.8921,N,02021.7289,E,0.026,,070926,,,A');
      parser.parse(rmcOld, source: GnssSource.external, connectionType: GnssConnectionType.bluetoothClassic);

      // New GGA arrives at 00:00:01 on Sep 8, but RMC for Sep 8 hasn't arrived yet
      final gga = addChecksum(r'$GNGGA,000001.00,4753.8921,N,02021.7289,E,1,08,0.9,211.5,M,38.4,M,,');
      final fix = parser.parse(gga, source: GnssSource.external, connectionType: GnssConnectionType.bluetoothClassic);

      expect(fix, isNotNull);
      expect(fix!.timestamp.day, 8);
      expect(fix.timestamp.month, 9);
      expect(fix.timestamp.year, 2026);
    });
  });
}
