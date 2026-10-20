import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mfk_geomeasure/models/gnss/mfkrtk_constants.dart';
import 'package:mfk_geomeasure/services/gnss/ble_transport.dart';
import 'package:mfk_geomeasure/services/gnss/mfkrtk_ota_service.dart';
import 'package:mfk_geomeasure/services/gnss/mfkrtk_provider.dart';

class _OtaWrite {
  _OtaWrite(this.uuid, this.bytes, this.withoutResponse, this.serviceUuid);
  final String uuid;
  final List<int> bytes;
  final bool withoutResponse;
  final String? serviceUuid;
  String get text => utf8.decode(bytes, allowMalformed: true);
}

class _FakeOtaTransport implements BleTransport {
  final notifications = StreamController<List<int>>.broadcast(sync: true);
  final writes = <_OtaWrite>[];
  bool connected = true;
  bool configAvailable = true;
  bool firmwareAvailable = true;
  Object? writeError;
  int mtu = 8;

  void notifyText(String text) => notifications.add(utf8.encode(text));

  @override
  bool get isConnected => connected;

  @override
  bool hasCharacteristic(String uuid, {String? serviceUuid}) {
    if (!connected || serviceUuid != MfkRtkConstants.serviceUuid) return false;
    if (uuid.toLowerCase() == MfkRtkConstants.configUuid) return configAvailable;
    if (uuid.toLowerCase() == MfkRtkConstants.firmwareUpdateUuid) return firmwareAvailable;
    return uuid.toLowerCase() == MfkRtkConstants.rtcmInputUuid;
  }

  @override
  Stream<List<int>> getExtraStream(String charUuid, {String? serviceUuid}) =>
      charUuid.toLowerCase() == MfkRtkConstants.configUuid
          ? notifications.stream
          : const Stream<List<int>>.empty();

  @override
  Future<void> writeExtra(String charUuid, List<int> data,
      {bool withoutResponse = false, String? serviceUuid}) async {
    if (!connected) throw StateError('BLE disconnected');
    if (serviceUuid != MfkRtkConstants.serviceUuid) throw StateError('Unexpected service UUID');
    if (!hasCharacteristic(charUuid, serviceUuid: serviceUuid)) {
      throw StateError('Characteristic not discovered: $charUuid');
    }
    if (writeError != null) throw writeError!;
    writes.add(_OtaWrite(charUuid.toLowerCase(), List<int>.of(data), withoutResponse, serviceUuid));
  }

  @override
  Stream<List<int>> get dataStream => const Stream<List<int>>.empty();
  @override
  Stream<bool> get connectionStatus => Stream<bool>.value(connected);
  @override
  Future<void> connect() async => connected = true;
  @override
  Future<void> disconnect() async => connected = false;
  @override
  Future<void> waitUntilDisconnected({required Duration timeout}) async {}
  @override
  Future<void> write(List<int> data) async {}
  @override
  Future<void> enableExtraNotify(String charUuid, {String? serviceUuid}) async {
    if (!connected || !hasCharacteristic(charUuid, serviceUuid: serviceUuid)) {
      throw StateError('Cannot enable notify for $charUuid');
    }
  }
  @override
  int get currentMtu => mtu;
  @override
  void dispose() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MfkRtkOtaService isolated transport tests', () {
    late MfkRtkOtaService service;
    late _FakeOtaTransport transport;
    late MfkRtkProvider provider;
    late Directory tempDirectory;

    setUp(() async {
      service = MfkRtkOtaService();
      service.detach();
      await Future<void>.delayed(Duration.zero);
      service.reset();
      transport = _FakeOtaTransport();
      provider = MfkRtkProvider(transport: transport);
      await provider.connect();
      service.attach(provider);
      tempDirectory = await Directory.systemTemp.createTemp('mfkrtk_ota_test_');
    });

    tearDown(() async {
      service.detach();
      await Future<void>.delayed(Duration.zero);
      await provider.disconnect();
      provider.dispose();
      await transport.notifications.close();
      await tempDirectory.delete(recursive: true);
    });

    Future<void> prepare(List<int> bytes, {String name = 'firmware.bin'}) async {
      final file = File('${tempDirectory.path}/$name');
      await file.writeAsBytes(bytes);
      await service.prepareFirmwareFromFile(file, '1.0.0');
    }

    Future<void> uploadToVersionQuery() async {
      await service.startUpdate();
      transport.notifyText('OTA_READY');
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(service.state, OtaUpdateState.finalizing);
      transport.notifyText('OTA_SUCCESS');
      await Future<void>.delayed(const Duration(milliseconds: 2200));
      expect(service.state, OtaUpdateState.verifyingVersion);
      expect(transport.writes.last.uuid, MfkRtkConstants.configUuid);
      expect(transport.writes.last.text, 'GET_VERSION');
    }

    test('valid file records exact size and lowercase SHA-256; empty/unreadable files fail', () async {
      final bytes = <int>[0xde, 0xad, 0xbe, 0xef, 0, 1, 2, 3, 4];
      await prepare(bytes);
      expect(service.firmwareSize, bytes.length);
      expect(service.firmwareBytes, orderedEquals(bytes));
      expect(service.sha256Hash, sha256.convert(bytes).toString().toLowerCase());
      expect(service.state, OtaUpdateState.idle);

      await prepare(const [], name: 'empty.bin');
      expect(service.state, OtaUpdateState.failed);
      expect(service.errorMessage, contains('FILE_READ_ERROR'));
      await service.prepareFirmwareFromFile(File('${tempDirectory.path}/missing.bin'), '1.0.0');
      expect(service.state, OtaUpdateState.failed);
      expect(service.errorMessage, contains('FILE_READ_ERROR'));
      await prepare([1], name: 'firmware.txt');
      expect(service.state, OtaUpdateState.failed);
      expect(service.errorMessage, contains('FILE_PICK_ERROR'));
    });

    test('upload uses exact CONFIG/FIRMWARE UUIDs, MTU chunks, bytes, hash and version confirmation', () async {
      final bytes = List<int>.generate(12, (index) => index + 1);
      await prepare(bytes);
      await service.startUpdate();
      expect(service.state, OtaUpdateState.waitingForReady);
      expect(transport.writes.single.uuid, MfkRtkConstants.configUuid);
      expect(transport.writes.single.text, 'OTA_BEGIN:12:1.0.0');

      provider.sendCorrectionData([0xd3, 0, 1]);
      expect(transport.writes, hasLength(1));
      transport.notifyText('OTA_READY');
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(service.state, OtaUpdateState.finalizing);

      final firmwareWrites = transport.writes
          .where((write) => write.uuid == MfkRtkConstants.firmwareUpdateUuid)
          .toList();
      expect(firmwareWrites.map((write) => write.bytes).toList(), [
        [1, 2, 3, 4, 5],
        [6, 7, 8, 9, 10],
        [11, 12],
      ]);
      expect(firmwareWrites.every((write) => write.withoutResponse), isTrue);
      expect(firmwareWrites.every((write) => write.serviceUuid == MfkRtkConstants.serviceUuid), isTrue);
      expect(service.uploadedBytes, bytes.length);

      transport.notifyText('OTA_PROGRESS:42.5');
      transport.notifyText('OTA_PROGRESS:NaN');
      transport.notifyText('OTA_PROGRESS:Infinity');
      await Future<void>.delayed(Duration.zero);
      expect(service.deviceProgress, 42.5);

      final end = transport.writes.last;
      expect(end.uuid, MfkRtkConstants.configUuid);
      expect(end.text, 'OTA_END:${sha256.convert(bytes).toString().toLowerCase()}');

      transport.notifyText('OTA_SUCCESS');
      await Future<void>.delayed(const Duration(milliseconds: 2200));
      expect(service.state, OtaUpdateState.verifyingVersion);
      expect(transport.writes.last.uuid, MfkRtkConstants.configUuid);
      expect(transport.writes.last.text, 'GET_VERSION');
      transport.notifyText('v1.0.0');
      await Future<void>.delayed(Duration.zero);
      expect(service.state, OtaUpdateState.completed);

      provider.sendCorrectionData([0xd3, 1]);
      await Future<void>.delayed(Duration.zero);
      expect(transport.writes.last.uuid, MfkRtkConstants.rtcmInputUuid);
      expect(transport.writes.last.bytes, [0xd3, 1]);
      expect(transport.writes.every((write) =>
          write.uuid == MfkRtkConstants.configUuid ||
          write.uuid == MfkRtkConstants.firmwareUpdateUuid ||
          write.uuid == MfkRtkConstants.rtcmInputUuid), isTrue);
    });

    test('OTA_ERROR, OTA_ABORTED and explicit cancel produce non-success states', () async {
      await prepare([1, 2]);
      await service.startUpdate();
      transport.notifyText('OTA_ERROR:BAD_IMAGE');
      await Future<void>.delayed(Duration.zero);
      expect(service.state, OtaUpdateState.failed);
      expect(service.errorMessage, contains('OTA_WRITE_ERROR'));

      service.reset();
      await prepare([1, 2], name: 'cancel.bin');
      await service.startUpdate();
      transport.notifyText('OTA_ABORTED');
      await Future<void>.delayed(Duration.zero);
      expect(service.state, OtaUpdateState.cancelled);

      service.reset();
      await prepare([1, 2], name: 'explicit-cancel.bin');
      await service.startUpdate();
      await service.cancelUpdate();
      expect(service.state, OtaUpdateState.cancelled);
      expect(transport.writes.last.text, 'OTA_ABORT');
      expect(transport.writes.last.uuid, MfkRtkConstants.configUuid);
    });

    test('disconnected, missing-characteristic, and failed writes are handled', () async {
      await prepare([1]);
      transport.connected = false;
      await service.startUpdate();
      expect(service.state, OtaUpdateState.failed);
      expect(service.errorMessage, contains('OTA_BEGIN_ERROR'));
      expect(transport.writes, isEmpty);

      service.reset();
      transport.connected = true;
      transport.firmwareAvailable = false;
      await service.startUpdate();
      expect(service.state, OtaUpdateState.failed);
      expect(transport.writes, isEmpty);

      service.reset();
      transport.firmwareAvailable = true;
      transport.writeError = StateError('simulated GATT write failure');
      await service.startUpdate();
      expect(service.state, OtaUpdateState.failed);
      expect(service.errorMessage, contains('OTA_BEGIN_ERROR'));
      expect(transport.writes, isEmpty);
    });

    test('OTA_READY timeout is terminal and resumes RTCM', () async {
      await prepare([1]);
      fakeAsync((async) {
        unawaited(service.startUpdate());
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 10));
        async.flushMicrotasks();
        expect(service.state, OtaUpdateState.failed);
        expect(service.errorMessage, contains('OTA_READY_TIMEOUT'));
      });
      provider.sendCorrectionData([0xd3]);
      await Future<void>.delayed(Duration.zero);
      expect(transport.writes.last.uuid, MfkRtkConstants.rtcmInputUuid);
    });

    test('OTA_SUCCESS timeout fails after OTA_END', () async {
      await prepare([1]);
      fakeAsync((async) {
        unawaited(service.startUpdate());
        async.flushMicrotasks();
        transport.notifyText('OTA_READY');
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 10));
        async.flushMicrotasks();
        expect(service.state, OtaUpdateState.finalizing);
        async.elapse(const Duration(seconds: 30));
        async.flushMicrotasks();
        expect(service.state, OtaUpdateState.failed);
        expect(service.errorMessage, contains('OTA_END_ERROR'));
      });
    });

    test('version mismatch and GET_VERSION timeout never report completion', () async {
      await prepare([9]);
      await uploadToVersionQuery();
      transport.notifyText('0.9.9');
      await Future<void>.delayed(Duration.zero);
      expect(service.state, OtaUpdateState.failed);
      expect(service.errorMessage, contains('VERSION MISMATCH'));

      service.reset();
      await prepare([9], name: 'version-timeout.bin');
      await uploadToVersionQuery();
      await Future<void>.delayed(const Duration(seconds: 10));
      expect(service.state, OtaUpdateState.failed);
      expect(service.errorMessage, contains('GET_VERSION timeout'));
    });

    test('detach while OTA is active resumes RTCM on the original provider', () async {
      await prepare([1]);
      await service.startUpdate();
      service.detach();
      await Future<void>.delayed(Duration.zero);
      expect(service.state, OtaUpdateState.cancelled);
      provider.sendCorrectionData([0xd3, 0x7]);
      await Future<void>.delayed(Duration.zero);
      expect(transport.writes.last.uuid, MfkRtkConstants.rtcmInputUuid);
      expect(transport.writes.last.bytes, [0xd3, 0x7]);
    });
  });
}
