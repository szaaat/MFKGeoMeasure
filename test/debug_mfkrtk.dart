import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mfk_geomeasure/services/gnss/mfkrtk_provider.dart';
import 'package:mfk_geomeasure/services/gnss/ble_transport.dart';

class _DummyBle implements BleTransport {
  final _dataController = StreamController<List<int>>.broadcast();
  @override Stream<List<int>> get dataStream => _dataController.stream;
  @override Stream<bool> get connectionStatus => Stream.value(true);
  @override Future<void> connect() async {}
  @override Future<void> disconnect() async {}
  @override Future<void> write(List<int> data) async {}
  void simulateData(List<int> data) { _dataController.add(data); }
  @override void dispose() {}
  Stream<List<int>> getExtraStream(String charUuid, {String? serviceUuid}) => const Stream.empty();
  Future<void> writeExtra(String charUuid, List<int> data, {bool withoutResponse = false, String? serviceUuid}) async {}
  @override dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('debug', () async {
    final dummyBle = _DummyBle();
    final provider = MfkRtkProvider(transport: dummyBle);
    final fixes = [];
    provider.fixStream.listen((fix) { print('Got fix: $fix'); fixes.add(fix); });
    await provider.connect();

    dummyBle.simulateData('#BESTPOSA,COM1,0,85.0,FINESTEERING,2234,123456.000,02000000,0000,0;SOL_COMPUTED,NARROW_INT,47.0,19.0,150.0,40.0,WGS84,0.03,0.04,0.08,stnId,1.0,1.0,20,18*12345678\r\n'.codeUnits);
    await Future.delayed(Duration(milliseconds: 100));
    print('Fixes length: ${fixes.length}');
  });
}
