import 'package:flutter_test/flutter_test.dart';
import 'package:mfk_geomeasure/models/gnss_fix.dart';
import 'package:mfk_geomeasure/services/gnss/internal_gnss_provider.dart';

void main() {
  group('InternalGnssProvider iOS mapping', () {
    test('Maps orthometric only data correctly (verticalAccuracy > 0)', () {
      final provider = InternalGnssProvider();

      final data = {
        'latitude': 47.0,
        'longitude': 19.0,
        'altitude': 105.0,
        'horizontalAccuracy': 5.0,
        'verticalAccuracy': 4.0,
        'timestamp': 1600000000000.0,
      };

      // Access private method for testing via reflection or dynamic
      final fix = (provider as dynamic).mapNativeIOSLocationToGnssFix(data) as GnssFix;

      expect(fix.latitude, 47.0);
      expect(fix.longitude, 19.0);
      expect(fix.altitude, 105.0); // Raw MSL altitude
      expect(fix.mslAltitude, 105.0);
      expect(fix.isEllipsoidal, isFalse);
      expect(fix.ellipsoidalHeight.isNaN, isTrue); // No ellipsoidal height provided
    });

    test('Maps iOS 15+ ellipsoidal data correctly (verticalAccuracy > 0)', () {
      final provider = InternalGnssProvider();

      final data = {
        'latitude': 47.0,
        'longitude': 19.0,
        'altitude': 105.0, // iOS provided MSL
        'ellipsoidalAltitude': 145.0, // iOS provided ellipsoidal
        'horizontalAccuracy': 5.0,
        'verticalAccuracy': 4.0,
        'timestamp': 1600000000000.0,
      };

      final fix = (provider as dynamic).mapNativeIOSLocationToGnssFix(data) as GnssFix;

      expect(fix.latitude, 47.0);
      expect(fix.longitude, 19.0);
      expect(fix.altitude, 145.0); // Now raw altitude maps to ellipsoidal
      expect(fix.ellipsoidalHeight, 145.0);
      expect(fix.mslAltitude, 105.0); // Preserved iOS MSL (no BME geoid here)
      expect(fix.isEllipsoidal, isTrue);
    });

    test('Maps invalid altitude (verticalAccuracy <= 0)', () {
      final provider = InternalGnssProvider();

      final data = {
        'latitude': 47.0,
        'longitude': 19.0,
        'altitude': 105.0,
        'ellipsoidalAltitude': 145.0,
        'horizontalAccuracy': 5.0,
        'verticalAccuracy': -1.0,
        'timestamp': 1600000000000.0,
      };

      final fix = (provider as dynamic).mapNativeIOSLocationToGnssFix(data) as GnssFix;

      expect(fix.altitude.isNaN, isTrue);
      expect(fix.ellipsoidalHeight.isNaN, isTrue);
      expect(fix.mslAltitude, isNull);
      expect(fix.isEllipsoidal, isFalse);
    });
  });
}
