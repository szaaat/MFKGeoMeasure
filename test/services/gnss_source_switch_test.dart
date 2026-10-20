import 'dart:async';
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

    test('Intentional switch: Old provider disconnects, new connects', () async {
      final oldProvider = MockInternalGnssProvider();
      final newProvider = TestMfkProvider();

      await infoService.setProvider(oldProvider);
      expect(oldProvider.connectCalls, 1);
      expect(oldProvider.isConnected, true);

      await infoService.setProvider(newProvider);

      expect(oldProvider.disconnectCalls, 1);
      expect(oldProvider.isConnected, false);
      expect(newProvider.isConnected, true);
    });

    test('Unexpected BLE disconnect with failed reconnect triggers fallback to InternalGnssProvider', () async {
      final bleProvider = TestMfkProvider();
      bleProvider.shouldFailReconnect = true;

      await infoService.setProvider(bleProvider);
      expect(infoService.activeProvider, bleProvider);

      bleProvider.emitConnectionLost();

      await Future.delayed(const Duration(seconds: 15));

      expect(bleProvider.reconnectAttempts, 3);
      expect(infoService.activeProvider, isA<InternalGnssProvider>());
    }, timeout: const Timeout(Duration(seconds: 20)));
  });
}
