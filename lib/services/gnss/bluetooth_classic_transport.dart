import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'gnss_transport.dart';

class BluetoothClassicTransport implements GnssTransport {
  final String deviceAddress;
  BluetoothConnection? _connection;
  
  final _dataController = StreamController<List<int>>.broadcast();
  final _statusController = StreamController<bool>.broadcast();
  
  bool _isConnecting = false;

  BluetoothClassicTransport({required this.deviceAddress});

  @override
  Stream<List<int>> get dataStream => _dataController.stream;

  @override
  Stream<bool> get connectionStatus => _statusController.stream;

  @override
  Future<void> connect() async {
    if (!Platform.isAndroid) throw Exception("Bluetooth Classic is only supported on Android.");
    if (_isConnecting || (_connection?.isConnected ?? false)) return;

    _isConnecting = true;
    try {
      _connection = await BluetoothConnection.toAddress(deviceAddress);
      _statusController.add(true);
      
      _connection!.input?.listen((Uint8List data) {
        _dataController.add(data);
      }, onDone: () {
        _statusController.add(false);
        _connection = null;
      }, onError: (e) {
        _statusController.add(false);
      });
    } catch (e) {
      _statusController.add(false);
      rethrow;
    } finally {
      _isConnecting = false;
    }
  }

  @override
  Future<void> disconnect() async {
    await _connection?.close();
    _connection = null;
    _statusController.add(false);
  }

  @override
  Future<void> write(List<int> data) async {
    if (_connection?.isConnected ?? false) {
      _connection!.output.add(Uint8List.fromList(data));
      await _connection!.output.allSent;
    }
  }

  @override
  void dispose() {
    disconnect();
    _dataController.close();
    _statusController.close();
  }
}
