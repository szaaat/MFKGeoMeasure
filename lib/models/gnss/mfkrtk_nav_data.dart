class MfkRtkNavData {
  final int version;
  final bool valid;
  final String source;
  final String insAlign;
  final String fix;
  final String posType;
  final int satellites;
  final double? hdop;
  final double? latitude;
  final double? longitude;
  final double? height;
  final double? roll;
  final double? pitch;
  final double? azimuth;
  final int ageMs;
  final int rtcmAgeMs;
  final int rtcmBytes;
  final int rtcmPkts;
  final bool rtcmOk;
  final int? batteryPercentage;
  final double? batteryVoltage;

  const MfkRtkNavData({
    this.version = 0,
    this.valid = false,
    this.source = 'NONE',
    this.insAlign = 'INS_INACTIVE',
    this.fix = 'NONE',
    this.posType = 'NONE',
    this.satellites = 0,
    this.hdop,
    this.latitude,
    this.longitude,
    this.height,
    this.roll,
    this.pitch,
    this.azimuth,
    this.ageMs = -1,
    this.rtcmAgeMs = -1,
    this.rtcmBytes = 0,
    this.rtcmPkts = 0,
    this.rtcmOk = false,
    this.batteryPercentage,
    this.batteryVoltage,
  });

  factory MfkRtkNavData.fromJson(Map<String, dynamic> json) {
    int? batPct = _intValue(json['battery_percent'])
        ?? _intValue(json['battery_percentage'])
        ?? _intValue(json['battery_pct'])
        ?? _intValue(json['bat_percent'])
        ?? _intValue(json['bat_percentage'])
        ?? _intValue(json['bat_pct'])
        ?? _intValue(json['bat_p'])
        ?? _intValue(json['battery_level'])
        ?? _intValue(json['bat_level'])
        ?? _intValue(json['battery'])
        ?? _intValue(json['bat'])
        ?? _intValue(json['soc'])
        ?? _intValue(json['charge'])
        ?? _intValue(json['level']);

    double? batVolt = _doubleValue(json['battery_voltage'])
        ?? _doubleValue(json['battery_v'])
        ?? _doubleValue(json['bat_voltage'])
        ?? _doubleValue(json['bat_v'])
        ?? _doubleValue(json['v_bat'])
        ?? _doubleValue(json['vbat'])
        ?? _doubleValue(json['v_batt'])
        ?? _doubleValue(json['vbatt'])
        ?? _doubleValue(json['voltage'])
        ?? _doubleValue(json['volts']);

    if (batPct == null && batVolt != null && batVolt > 2.5) {
      if (batVolt >= 4.15) {
        batPct = 100;
      } else if (batVolt <= 3.3) {
        batPct = 0;
      } else {
        batPct = (((batVolt - 3.3) / (4.15 - 3.3)) * 100).clamp(0, 100).round();
      }
    }

    return MfkRtkNavData(
      version: _intValue(json['v']) ?? 0,
      valid: json['valid'] == true,
      source: json['source']?.toString() ?? 'NONE',
      insAlign: json['ins_align']?.toString() ?? 'INS_INACTIVE',
      fix: json['fix']?.toString() ?? 'NONE',
      posType: json['pos_type']?.toString() ?? 'NONE',
      satellites: _intValue(json['sat']) ?? 0,
      hdop: _doubleValue(json['hdop']),
      latitude: _doubleValue(json['lat']),
      longitude: _doubleValue(json['lon']),
      height: _doubleValue(json['h']),
      roll: _doubleValue(json['roll']),
      pitch: _doubleValue(json['pitch']),
      azimuth: _doubleValue(json['azimuth']),
      ageMs: _intValue(json['age_ms']) ?? -1,
      rtcmAgeMs: _intValue(json['rtcm_age_ms']) ?? -1,
      rtcmBytes: _intValue(json['rtcm_bytes']) ?? 0,
      rtcmPkts: _intValue(json['rtcm_pkts']) ?? 0,
      rtcmOk: json['rtcm_ok'] == true,
      batteryPercentage: batPct,
      batteryVoltage: batVolt,
    );
  }

  static int? _intValue(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static double? _doubleValue(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }
}

class MfkRtkRtcmStatus {
  final int rtcmPkts;
  final int rtcmBytes;
  final int rtcmAgeMs;
  final bool rtcmOk;

  const MfkRtkRtcmStatus({
    this.rtcmPkts = 0,
    this.rtcmBytes = 0,
    this.rtcmAgeMs = -1,
    this.rtcmOk = false,
  });

  factory MfkRtkRtcmStatus.fromJson(Map<String, dynamic> json) =>
      MfkRtkRtcmStatus(
        rtcmPkts: _intValue(json['rtcm_pkts']) ?? 0,
        rtcmBytes: _intValue(json['rtcm_bytes']) ?? 0,
        rtcmAgeMs: _intValue(json['rtcm_age_ms']) ?? -1,
        rtcmOk: json['rtcm_ok'] == true,
      );

  static int? _intValue(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }
}
