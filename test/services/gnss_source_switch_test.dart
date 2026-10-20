import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mfk_geomeasure/models/gnss_fix.dart';
import 'package:mfk_geomeasure/models/gnss_raw_measurement.dart';
import 'package:mfk_geomeasure/services/gnss/gnss_provider.dart';
import 'package:mfk_geomeasure/services/gnss/internal_gnss_provider.dart';
import 'package:mfk_geomeasure/services/gnss/mfkrtk_provider.dart';
import 'package:mfk_geomeasure/services/gnss/ble_transport.dart';
import 'package:mfk_geomeasure/services/gnss_info_service.dart';
import 'package:mfk_geomeasure/services/geoid_service.dart';

class MockInternalGnssProvider implements GnssProvider {
  final _fixController = StreamController<GnssFix>.broadcast();
  bool isConnected = false;
  int connectCalls = 0;
  int disconnectCalls = 0;

  @override
  Stream<GnssFix> get fixStream => _fixController.stream;

  @override
  Future<void> connect() async {
    connectCalls++;
    isConnected = true;
    _fixController.add(GnssFix(
      latitude: 47.1,
      longitude: 19.1,
      altitude: 100.0,
      isEllipsoidal: false,
      horizontalAccuracy: 5.0,
      source: GnssSource.internal,
      connectionType: GnssConnectionType.internal,
      timestamp: DateTime.now(),
    ));
  }

  @override
  Future<void> disconnect() async {
    disconnectCalls++;
    isConnected = false;
  }

  @override
  void dispose() {
    _fixController.close();
  }

  @override
  Stream<GnssRawMeasurement> get rawMeasurementStream => const Stream.empty();

  @override
  Stream<List<int>> get rawStream => const Stream.empty();

  @override
  void sendCorrectionData(List<int> data) {}

  @override
  bool get supportsRtcmInput => false;
}

class TestMfkProvider extends MfkRtkProvider {
  final StreamController<bool> _connController = StreamController<bool>.broadcast();
  bool isConnected = false;
  bool shouldFailReconnect = false;
  int reconnectAttempts = 0;

  TestMfkProvider() : super(transport: _DummyBle());

  @override
  Stream<bool> get connectionStatus => _connController.stream;

  void emitConnectionLost() {
    if (!_connController.isClosed) _connController.add(false);
  }

  @override
  Future<void> connect() async {
    isConnected = true;
    if (!_connController.isClosed) _connController.add(true);
  }

  @override
  Future<void> disconnect() async {
    isConnected = false;
    if (!_connController.isClosed) _connController.add(false);
  }

  @override
  Future<void> reconnect() async {
    reconnectAttempts++;
    if (shouldFailReconnect) {
      throw Exception('BLE connection lost');
    }
    isConnected = true;
    if (!_connController.isClosed) _connController.add(true);
  }

  @override
  void dispose() {
    _connController.close();
    super.dispose();
  }
}

class _DummyBle implements BleTransport {
  @override
  void dispose() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    const MethodChannel sharedPrefsChannel = MethodChannel('plugins.flutter.io/shared_preferences');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(sharedPrefsChannel, (MethodCall methodCall) async {
      if (methodCall.method == 'getAll') return <String, dynamic>{};
      return null;
    });

    const MethodChannel pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(pathProviderChannel, (MethodCall methodCall) async {
      if (methodCall.method == 'getApplicationDocumentsDirectory') return '/tmp';
      return null;
    });

    const MethodChannel geolocatorChannel = MethodChannel('flutter.baseflow.com/geolocator');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(geolocatorChannel, (MethodCall methodCall) async {
      if (methodCall.method == 'isLocationServiceEnabled') return true;
      if (methodCall.method == 'checkPermission') return 3; // LocationPermission.always
      return null;
    });
  });

  group('Phase 1: GNSS Source Switching and Fallback', () {
    late GnssInfoService infoService;
    late GeoidCorrectionService geoidService;

    setUp(() {
      geoidService = GeoidCorrectionService();
      infoService = GnssInfoService(geoidService);
    });

    tearDown(() {
      infoService.dispose();
    });

    test('Unexpected BLE disconnect triggers fallback to InternalGnssProvider and emits a valid fix', () async {
      final bleProvider = TestMfkProvider();
      bleProvider.shouldFailReconnect = true;

      // Use a custom MockInternalGnssProvider for the fallback so we can test the emission
      // GnssInfoService uses InternalGnssProvider by default, but we will intercept it or
      // verify the stream output from the internal provider after fallback.
      // Wait, fallback creates `InternalGnssProvider(geoidService: _geoidService)`.
      // Since it creates a REAL `InternalGnssProvider` during fallback, we can't inject `MockInternalGnssProvider`.
      // But we CAN listen to the `infoService.fixStream` and see what happens when the real InternalGnssProvider starts.
      // Since we mocked Geolocator, InternalGnssProvider will call Geolocator... wait, Geolocator event stream is not mocked!
      // Mocking Geolocator stream channel:
      const EventChannel geolocatorEventChannel = EventChannel('flutter.baseflow.com/geolocator_updates');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockStreamHandler(geolocatorEventChannel, MockStreamHandler.inline(
        onListen: (Object? arguments, MockStreamHandlerEventSink events) {
          events.success({
            'latitude': 47.5,
            'longitude': 19.5,
            'altitude': 120.0,
            'accuracy': 5.0,
            'heading': 0.0,
            'speed': 0.0,
            'speed_accuracy': 0.0,
            'heading_accuracy': 0.0,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
            'is_mocked': false,
          });
        },
      ));

      List<GnssFix> emittedFixes = [];
      final sub = infoService.fixStream.listen((fix) {
        emittedFixes.add(fix);
      });

      await infoService.setProvider(bleProvider);
      expect(infoService.activeProvider, bleProvider);

      bleProvider.emitConnectionLost();

      await Future.delayed(const Duration(seconds: 15));

      expect(bleProvider.reconnectAttempts, 3);
      expect(infoService.activeProvider, isA<InternalGnssProvider>());

      // Wait a bit for the internal provider to emit the mocked Geolocator event
      await Future.delayed(const Duration(milliseconds: 100));

      expect(emittedFixes.isNotEmpty, isTrue, reason: 'Fallback provider should have emitted a fix');
      final fallbackFix = emittedFixes.last;
      expect(fallbackFix.latitude, 47.5);
      expect(fallbackFix.longitude, 19.5);
      expect(fallbackFix.horizontalAccuracy, 5.0);
      expect(fallbackFix.source, GnssSource.internal);

      await sub.cancel();
    }, timeout: const Timeout(Duration(seconds: 20)));
  });
}
