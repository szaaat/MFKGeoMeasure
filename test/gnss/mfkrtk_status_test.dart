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

    test('Parses alternative battery keys correctly', () {
      final json1 = {"battery_pct": 92, "v_bat": 4.12};
      final status1 = MfkRtkStatus.fromJson(json1);
      expect(status1.batteryPercentage, 92);
      expect(status1.batteryVoltage, closeTo(4.12, 1e-2));

      final json2 = {"bat_pct": 65, "battery_v": 3.78};
      final status2 = MfkRtkStatus.fromJson(json2);
      expect(status2.batteryPercentage, 65);
      expect(status2.batteryVoltage, closeTo(3.78, 1e-2));

      final json3 = {"battery_level": 40, "voltage": 3.60};
      final status3 = MfkRtkStatus.fromJson(json3);
      expect(status3.batteryPercentage, 40);
      expect(status3.batteryVoltage, closeTo(3.60, 1e-2));

      final json4 = {"soc": 88, "vbat": 4.05};
      final status4 = MfkRtkStatus.fromJson(json4);
      expect(status4.batteryPercentage, 88);
      expect(status4.batteryVoltage, closeTo(4.05, 1e-2));
    });

    test('Retains previous battery state when new status JSON omits battery fields', () {
      final initialJson = {"battery_percent": 85, "battery_voltage": 4.00};
      final initialStatus = MfkRtkStatus.fromJson(initialJson);
      expect(initialStatus.batteryPercentage, 85);

      final updateJson = {"ins_align": "FINESTEERING", "rtcm_ok": true};
      final updatedStatus = MfkRtkStatus.fromJson(updateJson, previousStatus: initialStatus);

      expect(updatedStatus.batteryPercentage, 85);
      expect(updatedStatus.batteryVoltage, closeTo(4.00, 1e-2));
      expect(updatedStatus.insAlign, "FINESTEERING");
      expect(updatedStatus.rtcmOk, isTrue);
    });

    test('Calculates battery percentage from voltage when raw percentage is absent', () {
      final json = {"v_bat": 3.97};
      final status = MfkRtkStatus.fromJson(json);

      expect(status.batteryVoltage, closeTo(3.97, 1e-2));
      expect(status.batteryPercentage, greaterThan(70));
    });
  });
}
