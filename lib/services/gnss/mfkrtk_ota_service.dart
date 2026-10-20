import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../../models/gnss/mfkrtk_constants.dart';
import 'mfkrtk_provider.dart';

enum OtaUpdateState {
  idle, selecting, preparing, beginRequested, waitingForReady, uploading,
  verifying, finalizing, rebooting, reconnecting, verifyingVersion,
  completed, failed, cancelled
}

class MfkRtkOtaService extends ChangeNotifier {
  static final MfkRtkOtaService _instance = MfkRtkOtaService._internal();
  factory MfkRtkOtaService() => _instance;
  MfkRtkOtaService._internal();

  OtaUpdateState _state = OtaUpdateState.idle;
  OtaUpdateState get state => _state;
  String? _errorMessage;
  String? get errorMessage => _errorMessage;
  String? _firmwareVersion;
  String? get firmwareVersion => _firmwareVersion;
  String? _reportedFirmwareVersion;
  String? get reportedFirmwareVersion => _reportedFirmwareVersion;
  int _firmwareSize = 0;
  int get firmwareSize => _firmwareSize;
  int _uploadedBytes = 0;
  int get uploadedBytes => _uploadedBytes;
  String? _sha256Hash;
  String? get sha256Hash => _sha256Hash;
  double get progress => _firmwareSize == 0 ? 0.0 : _uploadedBytes / _firmwareSize;
  double _deviceProgress = 0.0;
  double get deviceProgress => _deviceProgress;
  Uint8List? _firmwareBytes;
  Uint8List? get firmwareBytes => _firmwareBytes;
  MfkRtkProvider? _provider;
  MfkRtkProvider? _rtcmPausedProvider;
  MfkRtkProvider? get provider => _provider;
  StreamSubscription? _configSub;
  Timer? _protocolTimer;
  Timer? _reconnectTimer;
  Timer? _rateTimer;
  int _mtu = 23;
  int get currentMtu => _mtu;
  double _transferRateKbps = 0.0;
  double get transferRateKbps => _transferRateKbps;
  int _bytesSinceLastTick = 0;
  bool _isUploading = false;
  bool _reconnectInProgress = false;
  int _reconnectAttempts = 0;

  void attach(MfkRtkProvider provider) {
    if (_provider == provider) return;
    final configSub = _configSub;
    _configSub = null;
    configSub?.cancel();
    _provider = provider;
    if (_state == OtaUpdateState.rebooting || _state == OtaUpdateState.reconnecting) {
      _setState(OtaUpdateState.reconnecting);
      _configSub = provider.transport.getExtraStream(MfkRtkConstants.configUuid).listen(_onConfigNotify);
      _scheduleReconnect();
    }
  }

  void detach() {
    if (_state != OtaUpdateState.idle && _state != OtaUpdateState.completed &&
        _state != OtaUpdateState.failed && _state != OtaUpdateState.cancelled) {
      cancelUpdate();
    }
    _provider = null;
    final configSub = _configSub;
    _configSub = null;
    configSub?.cancel();
  }

  void _setState(OtaUpdateState state, {String? error}) {
    _state = state;
    if (error != null) _errorMessage = error;
    if (state == OtaUpdateState.completed ||
        state == OtaUpdateState.failed ||
        state == OtaUpdateState.cancelled) {
      _rtcmPausedProvider?.setRtcmForwardingPausedForOta(false);
      _rtcmPausedProvider = null;
    }
    notifyListeners();
  }

  void reportFailure(String code, String details) {
    _setState(OtaUpdateState.failed, error: '$code: $details');
  }

  Future<void> prepareFirmware(PlatformFile file, String version) async {
    if (!RegExp(r'\.bin$', caseSensitive: false).hasMatch(file.name)) {
      reportFailure('FILE_PICK_ERROR', 'Please select a .bin file.');
      return;
    }
    _resetOperationState();
    _setState(OtaUpdateState.preparing);
    debugPrint('[OTA] Selected file: ${file.name}');
    debugPrint('[OTA] File path: ${file.path ?? file.uri}');
    debugPrint('[OTA] PlatformFile.bytes == null: file_picker 12 exposes bytes through readAsBytes()');

    try {
      Uint8List bytes;
      final path = file.path;
      if (path != null && path.isNotEmpty) {
        try {
          bytes = await File(path).readAsBytes();
        } catch (e) {
          debugPrint('[OTA] Path read failed; falling back to PlatformFile.readAsBytes(): $e');
          bytes = await file.readAsBytes();
        }
      } else {
        bytes = await file.readAsBytes();
      }
      _firmwareBytes = Uint8List.fromList(bytes);
      _firmwareSize = _firmwareBytes!.length;
      if (_firmwareSize == 0) throw const FormatException('Selected firmware file is empty');

      _firmwareVersion = version;
      _sha256Hash = sha256.convert(_firmwareBytes!).toString().toLowerCase();
      debugPrint('[OTA] Firmware byte size: $_firmwareSize');
      debugPrint('[OTA] SHA256: $_sha256Hash');
      debugPrint('[OTA] Target firmware version: $_firmwareVersion');
      _setState(OtaUpdateState.idle);
    } catch (e) {
      debugPrint('[OTA] FILE_READ_ERROR: $e');
      _setState(OtaUpdateState.failed, error: 'FILE_READ_ERROR: $e');
    }
  }

  Future<void> prepareFirmwareFromFile(File file, String version) async {
    final fileName = file.uri.pathSegments.last;
    if (!RegExp(r'\.bin$', caseSensitive: false).hasMatch(fileName)) {
      reportFailure('FILE_PICK_ERROR', 'Please select a .bin file.');
      return;
    }
    _resetOperationState();
    _setState(OtaUpdateState.preparing);
    debugPrint('[OTA] Selected file: $fileName');
    debugPrint('[OTA] File path: ${file.path}');
    debugPrint('[OTA] PlatformFile.bytes == null: not applicable to File input; reading raw file bytes');

    try {
      _firmwareBytes = Uint8List.fromList(await file.readAsBytes());
      _firmwareSize = _firmwareBytes!.length;
      if (_firmwareSize == 0) throw const FormatException('Selected firmware file is empty');
      _firmwareVersion = version;
      _sha256Hash = sha256.convert(_firmwareBytes!).toString().toLowerCase();
      debugPrint('[OTA] Firmware byte size: $_firmwareSize');
      debugPrint('[OTA] SHA256: $_sha256Hash');
      debugPrint('[OTA] Target firmware version: $_firmwareVersion');
      _setState(OtaUpdateState.idle);
    } catch (e) {
      debugPrint('[OTA] FILE_READ_ERROR: $e');
      _setState(OtaUpdateState.failed, error: 'FILE_READ_ERROR: $e');
    }
  }

  Future<void> startUpdate() async {
    final provider = _provider;
    final bytes = _firmwareBytes;
    final hash = _sha256Hash;
    if (provider == null || bytes == null || hash == null) {
      _setState(OtaUpdateState.failed, error: 'OTA_BEGIN_ERROR: firmware/provider unavailable');
      return;
    }

    provider.setRtcmForwardingPausedForOta(true);
    _rtcmPausedProvider = provider;
    final transport = provider.transport;
    const serviceUuid = MfkRtkConstants.serviceUuid;
    const configUuid = MfkRtkConstants.configUuid;
    const firmwareUuid = MfkRtkConstants.firmwareUpdateUuid;
    final command = 'OTA_BEGIN:$_firmwareSize:$_firmwareVersion';
    debugPrint('[OTA] CONFIG UUID: $configUuid');
    debugPrint('[OTA] FIRMWARE_UPDATE UUID: $firmwareUuid');
    debugPrint('[OTA] OTA_BEGIN content: $command');

    try {
      if (!transport.isConnected) throw StateError('BLE connection is not active');
      if (!transport.hasCharacteristic(configUuid, serviceUuid: serviceUuid)) {
        throw StateError('CONFIG not discovered in service $serviceUuid');
      }
      if (!transport.hasCharacteristic(firmwareUuid, serviceUuid: serviceUuid)) {
        throw StateError('FIRMWARE_UPDATE not discovered in service $serviceUuid');
      }
      await _configSub?.cancel();
      _configSub = transport.getExtraStream(configUuid).listen(_onConfigNotify);
      await transport.enableExtraNotify(configUuid, serviceUuid: serviceUuid);

      _uploadedBytes = 0;
      _deviceProgress = 0;
      _reportedFirmwareVersion = null;
      _isUploading = false;
      _mtu = transport.currentMtu;
      debugPrint(
        '[OTA] BLE connected=$transport.isConnected, service discovery=complete, '
        'CONFIG notify=enabled, MTU=$_mtu',
      );

      _setState(OtaUpdateState.waitingForReady);
      await transport.writeExtra(configUuid, Uint8List.fromList(utf8.encode(command)), serviceUuid: serviceUuid);
      debugPrint('[OTA] OTA_BEGIN sent');
      _protocolTimer?.cancel();
      _protocolTimer = Timer(const Duration(seconds: 10), () {
        if (_state == OtaUpdateState.waitingForReady) {
          _setState(OtaUpdateState.failed, error: 'OTA_READY_TIMEOUT: no OTA_READY within 10 seconds');
          _configSub?.cancel();
        }
      });
    } catch (e) {
      debugPrint('[OTA] OTA_BEGIN_ERROR: $e');
      _setState(OtaUpdateState.failed, error: 'OTA_BEGIN_ERROR: $e');
    }
  }

  void _onConfigNotify(List<int> data) {
    try {
      // CONFIG carries text responses only; firmware bytes are never decoded.
      final msg = utf8.decode(data, allowMalformed: true).trim();
      if (msg.isEmpty) return;
      debugPrint('[OTA] CONFIG RX: $msg');

      if (_state == OtaUpdateState.waitingForReady && msg == 'OTA_READY') {
        _protocolTimer?.cancel();
        debugPrint('[OTA] OTA_READY received; starting raw binary upload');
        unawaited(_startUploading());
        return;
      }
      if (msg.startsWith('OTA_PROGRESS:')) {
        final progress = double.tryParse(msg.substring('OTA_PROGRESS:'.length));
        if (progress != null && progress.isFinite) {
          _deviceProgress = progress.clamp(0.0, 100.0);
          notifyListeners();
        }
        return;
      }
      if (msg == 'OTA_SUCCESS' && _state == OtaUpdateState.finalizing) {
        _protocolTimer?.cancel();
        _rateTimer?.cancel();
        _isUploading = false;
        _setState(OtaUpdateState.rebooting);
        debugPrint('[OTA] OTA_SUCCESS received; waiting for BLE disconnect and ESP32 reboot');
        unawaited(_waitForRebootAndReconnect());
        return;
      }
      if (msg.startsWith('OTA_ERROR:')) {
        _protocolTimer?.cancel();
        _rateTimer?.cancel();
        _isUploading = false;
        final code = _state == OtaUpdateState.finalizing ? 'OTA_END_ERROR' : 'OTA_WRITE_ERROR';
        _setState(OtaUpdateState.failed, error: '$code: $msg');
        return;
      }
      if (msg == 'OTA_ABORTED') {
        _protocolTimer?.cancel();
        _rateTimer?.cancel();
        _isUploading = false;
        _setState(OtaUpdateState.cancelled);
        return;
      }
      if (_state == OtaUpdateState.verifyingVersion && !msg.startsWith('OTA_')) {
        _reportedFirmwareVersion = msg;
        final target = _normalizeVersion(_firmwareVersion);
        final reported = _normalizeVersion(msg);
        debugPrint('[OTA] Version verification: Target=$target Reported=$reported');
        if (reported == target) {
          _setState(OtaUpdateState.completed);
          debugPrint('[OTA] OTA VERIFY: PASS Target=$target Reported=$reported');
        } else {
          _setState(OtaUpdateState.failed,
              error: 'OTA_VERIFY_ERROR: VERSION MISMATCH (Target=$target, Reported=$reported)');
          debugPrint('[OTA] OTA VERIFY: FAIL Target=$target Reported=$reported');
        }
      }
    } catch (e) {
      debugPrint('[OTA] CONFIG response parse error: $e');
    }
  }

  Future<void> _startUploading() async {
    final provider = _provider;
    final bytes = _firmwareBytes;
    if (provider == null || bytes == null) {
      _setState(OtaUpdateState.failed, error: 'OTA_WRITE_ERROR: provider or bytes unavailable');
      return;
    }

    _setState(OtaUpdateState.uploading);
    _isUploading = true;
    _bytesSinceLastTick = 0;
    _rateTimer?.cancel();
    _rateTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _transferRateKbps = _bytesSinceLastTick / 1024.0;
      _bytesSinceLastTick = 0;
      notifyListeners();
    });

    final mtu = provider.transport.currentMtu;
    final maxPayload = max(1, mtu - 3);
    _mtu = mtu;
    debugPrint('[OTA] Raw upload: MTU=$mtu, max payload=$maxPayload, bytes=${bytes.length}');

    try {
      for (int offset = 0; offset < bytes.length; offset += maxPayload) {
        if (!_isUploading || _state != OtaUpdateState.uploading) return;
        final end = min(offset + maxPayload, bytes.length);
        final Uint8List chunk = Uint8List.sublistView(bytes, offset, end);
        await provider.transport.writeExtra(
          MfkRtkConstants.firmwareUpdateUuid,
          chunk,
          withoutResponse: true,
          serviceUuid: MfkRtkConstants.serviceUuid,
        );
        _uploadedBytes += chunk.length;
        _bytesSinceLastTick += chunk.length;
        if (_uploadedBytes == chunk.length || _uploadedBytes % (maxPayload * 10) < chunk.length) {
          debugPrint('[OTA] Chunk sent: ${chunk.length} bytes; uploaded=$_uploadedBytes/$_firmwareSize');
          notifyListeners();
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      }
      if (_uploadedBytes != _firmwareSize) {
        throw StateError('uploadedBytes=$_uploadedBytes differs from firmwareSize=$_firmwareSize');
      }

      _isUploading = false;
      _rateTimer?.cancel();
      _setState(OtaUpdateState.finalizing);
      final endCommand = 'OTA_END:${_sha256Hash ?? ''}';
      debugPrint('[OTA] Upload complete: uploadedBytes=$_uploadedBytes firmwareSize=$_firmwareSize');
      debugPrint('[OTA] OTA_END content: $endCommand');
      try {
        await provider.transport.writeExtra(
          MfkRtkConstants.configUuid,
          Uint8List.fromList(utf8.encode(endCommand)),
          serviceUuid: MfkRtkConstants.serviceUuid,
        );
      } catch (e) {
        _setState(OtaUpdateState.failed, error: 'OTA_END_ERROR: $e');
        return;
      }
      _protocolTimer?.cancel();
      _protocolTimer = Timer(const Duration(seconds: 30), () {
        if (_state == OtaUpdateState.finalizing) {
          _setState(OtaUpdateState.failed, error: 'OTA_END_ERROR: no OTA_SUCCESS within 30 seconds');
        }
      });
    } catch (e) {
      _isUploading = false;
      _rateTimer?.cancel();
      debugPrint('[OTA] OTA_WRITE_ERROR: $e');
      _setState(OtaUpdateState.failed, error: 'OTA_WRITE_ERROR: $e');
    }
  }

  Future<void> _waitForRebootAndReconnect() async {
    final provider = _provider;
    if (provider == null) {
      _setState(OtaUpdateState.failed, error: 'OTA_VERIFY_ERROR: provider unavailable after OTA_SUCCESS');
      return;
    }

    try {
      debugPrint('[OTA] Waiting for ESP32 BLE disconnect');
      await provider.transport.waitUntilDisconnected(timeout: const Duration(seconds: 12));
      debugPrint('[OTA] ESP32 BLE disconnect observed');
    } on TimeoutException {
      // A successful OTA can reboot without delivering a clean disconnect callback.
      // Force a complete teardown before reconnecting so no old characteristics survive.
      debugPrint('[OTA] BLE disconnect event timed out; forcing transport teardown');
      await provider.transport.disconnect();
    } catch (e) {
      debugPrint('[OTA] BLE disconnect wait failed; forcing transport teardown: $e');
      await provider.transport.disconnect();
    }

    // Allow the bootloader/application to finish restarting after the link drops.
    await Future<void>.delayed(const Duration(seconds: 2));
    _scheduleReconnect(delay: Duration.zero);
  }

  void _scheduleReconnect({Duration delay = const Duration(seconds: 2)}) {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () => unawaited(_reconnectAndVerify()));
  }

  Future<void> _reconnectAndVerify() async {
    if (_reconnectInProgress ||
        (_state != OtaUpdateState.rebooting && _state != OtaUpdateState.reconnecting)) {
      return;
    }
    final provider = _provider;
    if (provider == null) {
      _setState(OtaUpdateState.failed, error: 'OTA_VERIFY_ERROR: provider unavailable after reboot');
      return;
    }
    _reconnectInProgress = true;
    _setState(OtaUpdateState.reconnecting);
    try {
      debugPrint('[OTA] Reconnecting after reboot, attempt ${_reconnectAttempts + 1}');
      await provider.reconnectForOta();
      final transport = provider.transport;
      if (!transport.isConnected) {
        throw StateError('BLE reconnect did not become active');
      }
      if (!transport.hasCharacteristic(
        MfkRtkConstants.configUuid,
        serviceUuid: MfkRtkConstants.serviceUuid,
      )) {
        throw StateError('CONFIG characteristic missing after service rediscovery');
      }
      debugPrint('[OTA] Service rediscovery complete; CONFIG characteristic found');
      await _configSub?.cancel();
      _configSub = transport.getExtraStream(MfkRtkConstants.configUuid).listen(_onConfigNotify);
      await transport.enableExtraNotify(
        MfkRtkConstants.configUuid,
        serviceUuid: MfkRtkConstants.serviceUuid,
      );
      debugPrint('[OTA] CONFIG notify enabled after reconnect');
      await _verifyVersionAfterReconnect();
      _reconnectAttempts = 0;
    } catch (e) {
      _reconnectAttempts++;
      debugPrint('[OTA] Reconnect attempt failed: $e');
      if (_reconnectAttempts < 6) {
        _scheduleReconnect(delay: const Duration(seconds: 2));
      } else {
        _setState(OtaUpdateState.failed, error: 'OTA_VERIFY_ERROR: reconnect failed: $e');
      }
    } finally {
      _reconnectInProgress = false;
    }
  }

  Future<void> _verifyVersionAfterReconnect() async {
    final provider = _provider;
    if (provider == null) {
      _setState(OtaUpdateState.failed, error: 'OTA_VERIFY_ERROR: provider unavailable');
      return;
    }
    _setState(OtaUpdateState.verifyingVersion);
    _protocolTimer?.cancel();
    _protocolTimer = Timer(const Duration(seconds: 10), () {
      if (_state == OtaUpdateState.verifyingVersion) {
        _setState(OtaUpdateState.failed, error: 'OTA_VERIFY_ERROR: GET_VERSION timeout');
      }
    });
    try {
      await provider.transport.writeExtra(
        MfkRtkConstants.configUuid,
        Uint8List.fromList(utf8.encode('GET_VERSION')),
        serviceUuid: MfkRtkConstants.serviceUuid,
      );
      debugPrint('[OTA] GET_VERSION sent');
    } catch (e) {
      _setState(OtaUpdateState.failed, error: 'OTA_VERIFY_ERROR: GET_VERSION write failed: $e');
    }
  }

  String _normalizeVersion(String? version) =>
      (version ?? '').trim().replaceFirst(RegExp(r'^[vV]'), '');

  Future<void> cancelUpdate() async {
    _isUploading = false;
    _protocolTimer?.cancel();
    _reconnectTimer?.cancel();
    _rateTimer?.cancel();
    final provider = _provider;
    if (provider != null && provider.transport.isConnected) {
      try {
        await provider.transport.writeExtra(
          MfkRtkConstants.configUuid,
          Uint8List.fromList(utf8.encode('OTA_ABORT')),
          serviceUuid: MfkRtkConstants.serviceUuid,
        );
      } catch (_) {}
    }
    _setState(OtaUpdateState.cancelled);
  }

  void _resetOperationState() {
    _protocolTimer?.cancel();
    _reconnectTimer?.cancel();
    _rateTimer?.cancel();
    _errorMessage = null;
    _firmwareVersion = null;
    _firmwareSize = 0;
    _firmwareBytes = null;
    _uploadedBytes = 0;
    _reportedFirmwareVersion = null;
    _sha256Hash = null;
    _deviceProgress = 0.0;
    _reconnectAttempts = 0;
    _transferRateKbps = 0.0;
  }

  void reset() {
    _resetOperationState();
    _state = OtaUpdateState.idle;
    notifyListeners();
  }
}
