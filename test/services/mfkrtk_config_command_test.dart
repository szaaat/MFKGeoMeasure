import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mfk_geomeasure/models/gnss/mfkrtk_constants.dart';
import 'package:mfk_geomeasure/services/gnss/ble_transport.dart';
import 'package:mfk_geomeasure/services/gnss/mfkrtk_provider.dart';

class _RecordingBle implements BleTransport {
  final StreamController<List<int>> configNotifications =
      StreamController<List<int>>.broadcast(sync: true);
  final List<({String uuid, List<int> bytes, String? serviceUuid})> writes = [];
  bool connected = true;
  bool hasConfigCharacteristic = true;
  Object? writeError;

  @override
  bool get isConnected => connected;

  @override
  bool hasCharacteristic(String uuid, {String? serviceUuid}) =>
      uuid.toLowerCase() == MfkRtkConstants.configUuid &&
      serviceUuid == MfkRtkConstants.serviceUuid &&
      hasConfigCharacteristic;

  @override
  Stream<List<int>> getExtraStream(String charUuid, {String? serviceUuid}) =>
      charUuid.toLowerCase() == MfkRtkConstants.configUuid
          ? configNotifications.stream
          : const Stream<List<int>>.empty();

  @override
  Future<void> writeExtra(String charUuid, List<int> data,
      {bool withoutResponse = false, String? serviceUuid}) async {
    if (!connected) throw StateError('BLE is not connected');
    if (charUuid.toLowerCase() == MfkRtkConstants.configUuid &&
        !hasConfigCharacteristic) {
      throw StateError('CONFIG characteristic was not discovered');
    }
    if (writeError != null) throw writeError!;
    writes.add((uuid: charUuid.toLowerCase(), bytes: List.of(data), serviceUuid: serviceUuid));
  }

  @override
  Stream<List<int>> get dataStream => const Stream<List<int>>.empty();

  @override
  Stream<bool> get connectionStatus => Stream.value(connected);

  @override
  Future<void> connect() async {}

  @override
  Future<void> disconnect() async {
    connected = false;
  }

  @override
  Future<void> write(List<int> data) async {}

  @override
  Future<void> enableExtraNotify(String charUuid, {String? serviceUuid}) async {}

  @override
  int get currentMtu => 23;

  @override
  void dispose() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('MfkRtk CONFIG command transport', () {
    late _RecordingBle transport;
    late MfkRtkProvider provider;

    setUp(() {
      transport = _RecordingBle();
      provider = MfkRtkProvider(transport: transport);
    });

    tearDown(() async {
      await provider.disconnect();
      provider.dispose();
      await transport.configNotifications.close();
    });

    test('provider CONFIG commands route only to CONFIG UUID', () async {
      await provider.setHeading(12.34);
      await provider.restartIns();
      await provider.getRtcmStatus();
      await provider.reconfigureM21();
      await provider.saveM21Config();

      expect(
        transport.writes.map((write) => write.uuid).toList(),
        everyElement(MfkRtkConstants.configUuid),
      );
      expect(
        transport.writes.map((write) => utf8.decode(write.bytes)).toList(),
        [
          'SET_HEADING:12.3',
          'INS_RESTART',
          'GET_RTCM_STATUS',
          'M21_CONFIGURE_INS',
          'M21_SAVE_CONFIG',
        ],
      );
      expect(
        transport.writes.every(
          (write) => write.uuid != MfkRtkConstants.rtcmInputUuid,
        ),
        isTrue,
      );
      expect(
        transport.writes.every(
          (write) => write.serviceUuid == MfkRtkConstants.serviceUuid,
        ),
        isTrue,
      );
    });

    test('RTCM forwarding remains on the separate RTCM characteristic', () async {
      provider.sendCorrectionData([0xD3, 0x00]);
      await Future<void>.delayed(Duration.zero);

      expect(transport.writes, hasLength(1));
      expect(transport.writes.single.uuid, MfkRtkConstants.rtcmInputUuid);
    });

    test('disconnected, missing-characteristic, and write failures surface', () async {
      transport.connected = false;
      await expectLater(
        provider.getRtcmStatus(),
        throwsA(isA<StateError>()),
      );

      transport.connected = true;
      transport.hasConfigCharacteristic = false;
      await expectLater(
        provider.getRtcmStatus(),
        throwsA(isA<StateError>()),
      );

      transport.hasConfigCharacteristic = true;
      transport.writeError = StateError('simulated GATT write failure');
      await expectLater(
        provider.getRtcmStatus(),
        throwsA(isA<StateError>()),
      );
      expect(transport.writes, isEmpty);
    });

    test('missing CONFIG response does not fabricate a success message', () async {
      final messages = <String>[];
      final subscription = provider.configMessageStream.listen(messages.add);
      await provider.getRtcmStatus();
      await Future<void>.delayed(Duration.zero);

      expect(transport.writes, hasLength(1));
      expect(messages, isEmpty);
      await subscription.cancel();
    });

    test('CONFIG response stream emits text and ignores malformed JSON safely', () async {
      final messages = <String>[];
      final subscription = provider.configMessageStream.listen(messages.add);
      await provider.connect();

      transport.configNotifications.add(utf8.encode('DEVICE_READY\r\n'));
      transport.configNotifications.add(utf8.encode('{"malformed":}\r\n'));
      await Future<void>.delayed(Duration.zero);

      expect(messages, ['DEVICE_READY']);
      await subscription.cancel();
    });
  });
}
