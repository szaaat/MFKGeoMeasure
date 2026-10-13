import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../../models/gnss/mfkrtk_constants.dart';
import 'gnss_transport.dart';

class BleTransport implements GnssTransport {
  final String deviceId;
  final String? serviceUuid;
  final String? rxCharacteristicUuid;
  final String? txCharacteristicUuid;
  
  // Optional extra notify characteristics (e.g. for status)
  final Map<String, StreamController<List<int>>> _extraNotifyControllers = {};

  BluetoothDevice? _device;
  BluetoothCharacteristic? _rxCharacteristic;
  BluetoothCharacteristic? _txCharacteristic;

  final _dataController = StreamController<List<int>>.broadcast();
  final _statusController = StreamController<bool>.broadcast();
  final List<StreamSubscription> _notifySubscriptions = [];
  final Set<String> _enabledExtraNotifies = {};
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  bool _isConnected = false;

  BleTransport({
    required this.deviceId,
    this.serviceUuid,
    this.rxCharacteristicUuid,
    this.txCharacteristicUuid,
  });

  @override
  Stream<List<int>> get dataStream => _dataController.stream;

  @override
  Stream<bool> get connectionStatus => _statusController.stream;
  bool get isConnected => _isConnected && (_device?.isConnected ?? false);

  /// Returns a stream for an extra characteristic (e.g. DEVICE_STATUS)
  Stream<List<int>> getExtraStream(String charUuid, {String? serviceUuid}) {
    final key = charUuid.toLowerCase();
    final controller = _extraNotifyControllers.putIfAbsent(
      key, 
      () => StreamController<List<int>>.broadcast()
    );
    if (_isConnected) {
      unawaited(enableExtraNotify(key, serviceUuid: serviceUuid)
          .catchError((e) => debugPrint('[BLE] enableExtraNotify failed for $key: $e')));
    }
    return controller.stream;
  }

  @override
  Future<void> connect() async {
    _isConnected = false;
    // Never carry characteristic handles across a reboot/reconnect. A fresh
    // BluetoothDevice instance and service discovery repopulate these handles.
    _rxCharacteristic = null;
    _txCharacteristic = null;
    _enabledExtraNotifies.clear();
    _device = BluetoothDevice.fromId(deviceId);

    await _device!.connect();
    
    // Attempt to negotiate a higher MTU. 
    try {
      await _device!.requestMtu(512);
    } catch (e) {
      debugPrint('[BLE-TRANSPORT] MTU request failed or not supported: $e');
    }

    List<BluetoothService> services = await _device!.discoverServices();
    _findCharacteristics(services);

    if (_rxCharacteristic != null) {
      await _rxCharacteristic!.setNotifyValue(true);
      _notifySubscriptions.add(_rxCharacteristic!.lastValueStream.listen((value) {
        if (value.isNotEmpty) _dataController.add(value);
      }));
    }

    // Connect extra listeners requested before or during the BLE session.
    _isConnected = true;
    for (final charUuid in _extraNotifyControllers.keys.toList()) {
      await enableExtraNotify(charUuid);
    }

    // Standard GATT Battery Level characteristic (0x2A19) fallback
    final batteryChar = _findCharacteristicInServices(services, '2a19');
    if (batteryChar != null) {
      try {
        void emitGattBattery(List<int> val) {
          if (val.isNotEmpty) {
            final statusController = _extraNotifyControllers[MfkRtkConstants.deviceStatusUuid.toLowerCase()];
            if (statusController != null) {
              final jsonStr = utf8.encode(jsonEncode({'battery_percent': val[0]}));
              statusController.add(jsonStr);
            }
          }
        }

        if (batteryChar.properties.notify || batteryChar.properties.indicate) {
          await batteryChar.setNotifyValue(true);
          _notifySubscriptions.add(batteryChar.lastValueStream.listen((value) {
            emitGattBattery(value);
          }));
        }
        if (batteryChar.properties.read) {
          final val = await batteryChar.read();
          emitGattBattery(val);
        }
      } catch (e) {
        debugPrint('[BLE-TRANSPORT] Error reading GATT battery service: $e');
      }
    }

    _statusController.add(true);
    await _connectionSubscription?.cancel();
    _connectionSubscription = _device!.connectionState.listen((state) {
      final connected = state == BluetoothConnectionState.connected;
      if (_isConnected != connected) {
        _isConnected = connected;
        _statusController.add(connected);
      }
    });
  }

  BluetoothCharacteristic? _findCharacteristicInServices(
    List<BluetoothService> services,
    String uuid, {
    String? serviceUuid,
  }) {
    for (final service in services) {
      if (serviceUuid != null &&
          service.uuid.toString().toLowerCase() != serviceUuid.toLowerCase()) {
        continue;
      }
      for (final characteristic in service.characteristics) {
        if (characteristic.uuid.toString().toLowerCase() == uuid.toLowerCase()) {
          return characteristic;
        }
      }
    }
    return null;
  }

  bool hasCharacteristic(String uuid, {String? serviceUuid}) {
    final device = _device;
    if (!_isConnected || device == null) return false;
    return _findCharacteristicInServices(
          device.servicesList,
          uuid,
          serviceUuid: serviceUuid,
        ) !=
        null;
  }

  Future<void> enableExtraNotify(String charUuid, {String? serviceUuid}) async {
    final key = charUuid.toLowerCase();
    final controller = _extraNotifyControllers.putIfAbsent(
      key,
      () => StreamController<List<int>>.broadcast(),
    );
    if (_enabledExtraNotifies.contains(key)) return;

    final device = _device;
    if (!_isConnected || device == null) {
      debugPrint('[BLE-TRANSPORT] BLE is not connected; cannot enable notify for $charUuid');
      return;
    }
    final characteristic = _findCharacteristicInServices(
      device.servicesList,
      charUuid,
      serviceUuid: serviceUuid,
    );
    if (characteristic == null) {
      debugPrint('[BLE-TRANSPORT] Characteristic $charUuid was not discovered');
      return;
    }
    if (!characteristic.properties.notify && !characteristic.properties.indicate) {
      debugPrint('[BLE-TRANSPORT] Characteristic $charUuid does not support notify or indicate');
      return;
    }

    try {
      await characteristic.setNotifyValue(true);
      _notifySubscriptions.add(characteristic.lastValueStream.listen((value) {
        if (value.isNotEmpty) controller.add(value);
      }));
      _enabledExtraNotifies.add(key);

      if (characteristic.properties.read) {
        try {
          final initialValue = await characteristic.read();
          if (initialValue.isNotEmpty) controller.add(initialValue);
        } catch (e) {
          debugPrint('[BLE-TRANSPORT] Initial read for $charUuid failed: $e');
        }
      }
    } catch (e) {
      debugPrint('[BLE-TRANSPORT] Error enabling notify for $charUuid: $e');
    }
  }

  void _findCharacteristics(List<BluetoothService> services) {
    if (serviceUuid != null && rxCharacteristicUuid != null && txCharacteristicUuid != null) {
      for (var service in services) {
        if (service.uuid.toString().toLowerCase() == serviceUuid!.toLowerCase()) {
          for (var char in service.characteristics) {
            if (char.uuid.toString().toLowerCase() == rxCharacteristicUuid!.toLowerCase()) {
              _rxCharacteristic = char;
            }
            if (char.uuid.toString().toLowerCase() == txCharacteristicUuid!.toLowerCase()) {
              _txCharacteristic = char;
            }
          }
        }
      }
    } else {
      // Generic fallback (UART)
      for (var service in services) {
        for (var char in service.characteristics) {
          if (char.properties.notify || char.properties.indicate) {
            _rxCharacteristic ??= char;
          }
          if (char.properties.write || char.properties.writeWithoutResponse) {
            _txCharacteristic ??= char;
          }
        }
      }
    }
  }

  Future<void> waitUntilDisconnected({required Duration timeout}) async {
    final device = _device;
    if (device == null || !_isConnected) return;
    await device.connectionState
        .firstWhere((state) => state == BluetoothConnectionState.disconnected)
        .timeout(timeout);
  }

  @override
  Future<void> disconnect() async {
    for (var sub in _notifySubscriptions) {
      await sub.cancel();
    }
    _notifySubscriptions.clear();
    await _connectionSubscription?.cancel();
    _connectionSubscription = null;
    _enabledExtraNotifies.clear();
    final device = _device;
    await device?.disconnect();
    if (_isConnected) {
      _isConnected = false;
      _statusController.add(false);
    }
    // Drop all characteristic references once the connection is torn down.
    _rxCharacteristic = null;
    _txCharacteristic = null;
  }

  @override
  Future<void> write(List<int> data) async {
    if (_txCharacteristic == null || _device == null) return;

    // Use negotiated MTU. Payload = MTU - 3.
    final int mtu = _device!.mtuNow;
    final int maxPayload = max(20, mtu - 3);

    if (data.length <= maxPayload) {
      await _txCharacteristic!.write(data, withoutResponse: true);
    } else {
      for (int i = 0; i < data.length; i += maxPayload) {
        int end = min(i + maxPayload, data.length);
        await _txCharacteristic!.write(data.sublist(i, end), withoutResponse: true);
      }
    }
  }

  Future<void> writeExtra(
    String charUuid,
    List<int> data, {
    bool withoutResponse = false,
    String? serviceUuid,
  }) async {
    final device = _device;
    if (!_isConnected || device == null) {
      throw StateError('BLE is not connected; cannot write $charUuid');
    }
    final characteristic = _findCharacteristicInServices(
      device.servicesList,
      charUuid,
      serviceUuid: serviceUuid,
    );
    if (characteristic == null) {
      throw StateError('Characteristic $charUuid was not discovered');
    }
    
    final bool canWriteNoResp = characteristic.properties.writeWithoutResponse;
    final bool canWriteWithResp = characteristic.properties.write;

    if (!canWriteNoResp && !canWriteWithResp) {
      throw StateError('Characteristic $charUuid does not support writes');
    }

    final bool useWithoutResponse = withoutResponse
        ? canWriteNoResp
        : (!canWriteWithResp && canWriteNoResp);

    final int maxPayload = max(20, device.mtuNow - 3);
    for (int offset = 0; offset < data.length; offset += maxPayload) {
      final end = min(offset + maxPayload, data.length);
      await characteristic.write(
        data.sublist(offset, end),
        withoutResponse: useWithoutResponse,
      );
    }
  }

  int get currentMtu => _device?.mtuNow ?? 23;

  @override
  void dispose() {
    disconnect();
    _dataController.close();
    _statusController.close();
    for (var controller in _extraNotifyControllers.values) {
      controller.close();
    }
  }
}
