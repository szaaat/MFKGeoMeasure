import 'package:flutter_test/flutter_test.dart';
import 'package:mfk_geomeasure/models/gnss/mfkrtk_status.dart';

void main() {
  group('MfkRtkStatus Tests', () {
    test('Parses SmartPuck v0.2.0 JSON format correctly', () {
      final json = {
        "device": "SmartPuck",
        "firmware": "0.2.0",
        "battery_voltage": 3.97,
        "battery_percent": 81,
        "position_source": "GNSS",
        "ins_status": "WAITING_AZIMUTH",
        "gnss_fix": "SINGLE",
        "satellites": 20,
        "ble_connected": false,
        "ota": false
      };

      final status = MfkRtkStatus.fromJson(json);

      expect(status.firmwareVersion, '0.2.0');
      expect(status.batteryVoltage, closeTo(3.97, 1e-2));
      expect(status.batteryPercentage, 81);
      expect(status.positionSource, 'GNSS');
      expect(status.insStatus, 'WAITING_AZIMUTH');
      expect(status.gnssFix, 'SINGLE');
      expect(status.satellites, 20);
      expect(status.bleConnected, isFalse);
      expect(status.otaState, 'IDLE');
    });

    test('Parses legacy JSON format as fallback', () {
      final json = {
        "fw_ver": "v0.1.0",
        "bat_v": 3.85,
        "bat_p": 75,
        "ble_conn": true,
        "ota_state": "IDLE",
        "ins_stat": "INS_ALIGNING",
        "pos_src": "INS_RTKFLOAT",
        "sats": 18
      };

      final status = MfkRtkStatus.fromJson(json);

      expect(status.firmwareVersion, 'v0.1.0');
      expect(status.batteryVoltage, closeTo(3.85, 1e-2));
      expect(status.batteryPercentage, 75);
      expect(status.bleConnected, isTrue);
      expect(status.otaState, 'IDLE');
      expect(status.insStatus, 'INS_ALIGNING');
      expect(status.positionSource, 'INS_RTKFLOAT');
      expect(status.satellites, 18);
    });
  });
}
