import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mfk_geomeasure/services/gnss/internal_gnss_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const geolocatorChannel = MethodChannel('flutter.baseflow.com/geolocator');
  var locationServicesEnabled = true;
  var permissionStatus = 0;
  var requestedPermissionStatus = 0;
  var permissionRequests = 0;
  var checkedPermission = false;

  setUp(() {
    locationServicesEnabled = true;
    permissionStatus = 0;
    requestedPermissionStatus = 0;
    permissionRequests = 0;
    checkedPermission = false;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(geolocatorChannel, (call) async {
      switch (call.method) {
        case 'isLocationServiceEnabled':
          return locationServicesEnabled;
        case 'checkPermission':
          checkedPermission = true;
          return permissionStatus;
        case 'requestPermission':
          permissionRequests++;
          return requestedPermissionStatus;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(geolocatorChannel, null);
  });

  test('requests permission on first connection and reports a denial cleanly',
      () async {
    final provider = InternalGnssProvider();

    await expectLater(
      provider.connect(),
      throwsA(
        isA<InternalGnssException>().having(
          (error) => error.error,
          'error',
          InternalGnssError.permissionDenied,
        ),
      ),
    );

    expect(permissionRequests, 1);
    expect(provider.fixStream, isNotNull);
    provider.dispose();
  });

  test('does not repeatedly request permission after permanent denial',
      () async {
    permissionStatus = LocationPermission.deniedForever.index;
    final provider = InternalGnssProvider();

    await expectLater(
      provider.connect(),
      throwsA(
        isA<InternalGnssException>().having(
          (error) => error.error,
          'error',
          InternalGnssError.permissionDeniedForever,
        ),
      ),
    );

    expect(permissionRequests, 0);
    provider.dispose();
  });

  test('reports disabled location services before requesting permission',
      () async {
    locationServicesEnabled = false;
    final provider = InternalGnssProvider();

    await expectLater(
      provider.connect(),
      throwsA(
        isA<InternalGnssException>().having(
          (error) => error.error,
          'error',
          InternalGnssError.locationServicesDisabled,
        ),
      ),
    );

    expect(checkedPermission, isFalse);
    expect(permissionRequests, 0);
    provider.dispose();
  });
}
