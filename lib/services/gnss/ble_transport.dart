import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'gnss_transport.dart';

class BleTransport implements GnssTransport {
  final String deviceId;
  final String? serviceUuid;
  final String? rxCharacteristicUuid;
  final String? txCharacteristicUuid;

  BluetoothDevice? _device;
  BluetoothCharacteristic? _rxCharacteristic;
  BluetoothCharacteristic? _txCharacteristic;

  final _dataController = StreamController<List<int>>.broadcast();
  final _statusController = StreamController<bool>.broadcast();
  StreamSubscription? _notifySubscription;

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

  @override
  Future<void> connect() async {
    _device = BluetoothDevice.fromId(deviceId);

    await _device!.connect();
    _statusController.add(true);

    List<BluetoothService> services = await _device!.discoverServices();
    
    // Keressünk UART-szerű szervizt és karakterisztikát
    for (var service in services) {
      for (var char in service.characteristics) {
        if (char.properties.notify || char.properties.indicate) {
          _rxCharacteristic = char;
        }
        if (char.properties.write || char.properties.writeWithoutResponse) {
          _txCharacteristic = char;
        }
      }
    }

    if (_rxCharacteristic != null) {
      await _rxCharacteristic!.setNotifyValue(true);
      _notifySubscription = _rxCharacteristic!.lastValueStream.listen((value) {
        _dataController.add(value);
      });
    }

    _device!.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected) {
        _statusController.add(false);
      }
    });
  }

  @override
  Future<void> disconnect() async {
    await _notifySubscription?.cancel();
    await _device?.disconnect();
    _statusController.add(false);
  }

  @override
  Future<void> write(List<int> data) async {
    if (_txCharacteristic != null) {
      await _txCharacteristic!.write(data, withoutResponse: true);
    }
  }

  @override
  void dispose() {
    disconnect();
    _dataController.close();
    _statusController.close();
  }
}
