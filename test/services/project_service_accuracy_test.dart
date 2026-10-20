import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mfk_geomeasure/models/gnss_fix.dart';
import 'package:mfk_geomeasure/services/project_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    const sharedPrefsChannel =
        MethodChannel('plugins.flutter.io/shared_preferences');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sharedPrefsChannel, (methodCall) async {
      if (methodCall.method == 'getAll') return <String, dynamic>{};
      return null;
    });

    const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (methodCall) async {
      if (methodCall.method == 'getApplicationDocumentsDirectory') {
        return '/tmp';
      }
      return null;
    });
  });

  group('Phase 3: ProjectService accuracy validation', () {
    late ProjectService service;

    setUp(() {
      service = ProjectService();
    });

    GnssFix createFix({
      required double latitude,
      required double longitude,
      required double altitude,
      required double accuracy,
    }) {
      return GnssFix(
        latitude: latitude,
        longitude: longitude,
        altitude: altitude,
        isEllipsoidal: true,
        horizontalAccuracy: accuracy,
        source: GnssSource.external,
        connectionType: GnssConnectionType.ble,
        timestamp: DateTime.utc(2026, 1, 1),
      );
    }

    test('Does not save geometry when every sample has invalid accuracy',
        () async {
      final controller = StreamController<GnssFix>(sync: true);
      final averaging =
          service.startAveraging(controller.stream, maxDurationSeconds: 30);

      controller
        ..add(createFix(
            latitude: 47, longitude: 19, altitude: 100, accuracy: 99.9))
        ..add(createFix(
            latitude: 48, longitude: 20, altitude: 110, accuracy: double.nan))
        ..add(createFix(
            latitude: 49, longitude: 21, altitude: 120, accuracy: 0))
        ..add(createFix(
            latitude: 50, longitude: 22, altitude: 130, accuracy: -1));
      await controller.close();
      await averaging;

      expect(service.isAveraging, isFalse);
      expect(service.currentGeometry, isEmpty);
      expect(service.currentAltitudes, isEmpty);
      expect(service.currentFixes, isEmpty);
    });

    test('Saves the accuracy-weighted coordinate and altitude', () async {
      final controller = StreamController<GnssFix>(sync: true);
      final averaging =
          service.startAveraging(controller.stream, maxDurationSeconds: 30);

      controller
        ..add(createFix(
            latitude: 47, longitude: 19, altitude: 100, accuracy: 2))
        ..add(createFix(
            latitude: 49, longitude: 23, altitude: 140, accuracy: 4));
      await controller.close();
      await averaging;

      expect(service.currentGeometry, hasLength(1));
      expect(service.currentGeometry.single.latitude, closeTo(47.4, 1e-9));
      expect(service.currentGeometry.single.longitude, closeTo(19.8, 1e-9));
      expect(service.currentAltitudes.single, closeTo(108, 1e-9));
      expect(service.currentIsEllipsoidal.single, isTrue);
      expect(service.currentFixes.single.horizontalAccuracy, 2);
    });
  });
}
