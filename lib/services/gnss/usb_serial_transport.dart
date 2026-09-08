import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:usb_serial/usb_serial.dart';
import 'gnss_transport.dart';

class UsbSerialTransport implements GnssTransport {
  final UsbDevice device;
  final int baudRate;
  
  UsbPort? _port;
  final _dataController = StreamController<List<int>>.broadcast();
  final _statusController = StreamController<bool>.broadcast();
  StreamSubscription? _inputSubscription;

  UsbSerialTransport({required this.device, this.baudRate = 115200});

  @override
  Stream<List<int>> get dataStream => _dataController.stream;

  @override
  Stream<bool> get connectionStatus => _statusController.stream;

  @override
  Future<void> connect() async {
    if (!Platform.isAndroid) throw Exception("USB Serial is only supported on Android.");
    
    _port = await device.create();
    if (!await _port!.open()) {
      _statusController.add(false);
      throw Exception("Failed to open USB port");
    }

    await _port!.setDTR(true);
    await _port!.setRTS(true);
    await _port!.setPortParameters(baudRate, UsbPort.DATABITS_8, UsbPort.STOPBITS_1, UsbPort.PARITY_NONE);

    _statusController.add(true);

    _inputSubscription = _port!.inputStream?.listen((Uint8List data) {
      _dataController.add(data);
    }, onDone: () {
      _statusController.add(false);
    }, onError: (e) {
      _statusController.add(false);
    });
  }

  @override
  Future<void> disconnect() async {
    await _inputSubscription?.cancel();
    await _port?.close();
    _port = null;
    _statusController.add(false);
  }

  @override
  Future<void> write(List<int> data) async {
    if (_port != null) {
      await _port!.write(Uint8List.fromList(data));
    }
  }

  @override
  void dispose() {
    disconnect();
    _dataController.close();
    _statusController.close();
  }
}
