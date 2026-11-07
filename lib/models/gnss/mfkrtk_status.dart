class MfkRtkStatus {
  final String firmwareVersion;
  final double batteryVoltage;
  final int batteryPercentage;
  final bool bleConnected;
  final String otaState;

  // Future geodetic fields (nullable)
  final String? gnssFix;
  final String? rtkStatus;
  final int? satellites;
  final double? hdop;
  final double? latitude;
  final double? longitude;
  final double? altitude;
  final String? insStatus;
  final String? positionSource;
  final double? roll;
  final double? pitch;
  final double? heading;
  final double? correctionAge;
  final String? insAlign;
  final String? posType;
  final bool? rtcmOk;
  final int? rtcmAgeMs;
  final int? rtcmBytes;
  final int? rtcmPkts;
  final String? autoInsState;
  final String? alignmentMode;
  final bool? alignmentTrialRequested;
  final bool? alignmentTrialCommandRejected;
  final String? autoInsError;
  final String? insAlignFull;
  final bool? measurementReady;

  MfkRtkStatus({
    required this.firmwareVersion,
    required this.batteryVoltage,
    required this.batteryPercentage,
    required this.bleConnected,
    required this.otaState,
    this.gnssFix,
    this.rtkStatus,
    this.satellites,
    this.hdop,
    this.latitude,
    this.longitude,
    this.altitude,
    this.insStatus,
    this.positionSource,
    this.roll,
    this.pitch,
    this.heading,
    this.correctionAge,
    this.insAlign,
    this.posType,
    this.rtcmOk,
    this.rtcmAgeMs,
    this.rtcmBytes,
    this.rtcmPkts,
    this.autoInsState,
    this.alignmentMode,
    this.alignmentTrialRequested,
    this.alignmentTrialCommandRejected,
    this.autoInsError,
    this.insAlignFull,
    this.measurementReady,
  });

  factory MfkRtkStatus.fromJson(Map<String, dynamic> json, {MfkRtkStatus? previousStatus}) {
    // OTA field parsing (can be boolean false/true or string)
    String parsedOta = previousStatus?.otaState ?? 'IDLE';
    if (json.containsKey('ota')) {
      final o = json['ota'];
      if (o is bool) {
        parsedOta = o ? 'UPDATING' : 'IDLE';
      } else if (o is String) {
        parsedOta = o;
      }
    } else if (json.containsKey('ota_state')) {
      parsedOta = json['ota_state']?.toString() ?? 'IDLE';
    }

    double voltage = (json['battery_voltage'] as num?)?.toDouble() 
        ?? (json['battery_v'] as num?)?.toDouble() 
        ?? (json['bat_voltage'] as num?)?.toDouble()
        ?? (json['bat_v'] as num?)?.toDouble() 
        ?? (json['v_bat'] as num?)?.toDouble()
        ?? (json['vbat'] as num?)?.toDouble()
        ?? (json['v_batt'] as num?)?.toDouble()
        ?? (json['vbatt'] as num?)?.toDouble()
        ?? (json['voltage'] as num?)?.toDouble()
        ?? (json['volts'] as num?)?.toDouble()
        ?? 0.0;

    int? rawPct = _intValue(json['battery_percent']) 
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

    int pct = rawPct ?? 0;
    if (rawPct == null && voltage > 2.5) {
      if (voltage >= 4.15) {
        pct = 100;
      } else if (voltage <= 3.3) {
        pct = 0;
      } else {
        pct = (((voltage - 3.3) / (4.15 - 3.3)) * 100).clamp(0, 100).round();
      }
    } else if (pct > 0 && voltage == 0.0) {
      voltage = 3.3 + (pct / 100.0) * 0.85;
    }

    // Preserve previous battery state if missing in current JSON chunk
    if (pct == 0 && previousStatus != null && previousStatus.batteryPercentage > 0) {
      pct = previousStatus.batteryPercentage;
    }
    if (voltage == 0.0 && previousStatus != null && previousStatus.batteryVoltage > 0.0) {
      voltage = previousStatus.batteryVoltage;
    }

    final fw = json['firmware']?.toString() ?? json['fw_ver']?.toString() ?? json['fw']?.toString();

    return MfkRtkStatus(
      firmwareVersion: fw ?? previousStatus?.firmwareVersion ?? 'Unknown',
      batteryVoltage: voltage,
      batteryPercentage: pct,
      bleConnected: json['ble_connected'] as bool? ?? json['ble_conn'] as bool? ?? previousStatus?.bleConnected ?? false,
      otaState: parsedOta,
      gnssFix: json['gnss_fix']?.toString() ?? json['gnss_fix_type']?.toString(),
      rtkStatus: json['rtk_stat']?.toString() ?? json['rtk_status']?.toString(),
      satellites: _intValue(json['satellites']) ?? _intValue(json['sats']) ?? previousStatus?.satellites,
      hdop: (json['hdop'] as num?)?.toDouble() ?? previousStatus?.hdop,
      latitude: (json['latitude'] as num?)?.toDouble() ?? (json['lat'] as num?)?.toDouble() ?? previousStatus?.latitude,
      longitude: (json['longitude'] as num?)?.toDouble() ?? (json['lon'] as num?)?.toDouble() ?? previousStatus?.longitude,
      altitude: (json['altitude'] as num?)?.toDouble() ?? (json['alt'] as num?)?.toDouble() ?? previousStatus?.altitude,
      insStatus: json['ins_align']?.toString() ?? json['ins_status']?.toString() ?? json['ins_stat']?.toString(),
      insAlign: json['ins_align']?.toString() ?? json['ins_status']?.toString() ?? json['ins_stat']?.toString(),
      positionSource: json['position_source']?.toString() ?? json['pos_src']?.toString(),
      posType: json['pos_type']?.toString(),
      rtcmOk: json['rtcm_ok'] as bool?,
      rtcmAgeMs: _intValue(json['rtcm_age_ms']),
      rtcmBytes: _intValue(json['rtcm_bytes']),
      rtcmPkts: _intValue(json['rtcm_pkts']),
      roll: (json['roll'] as num?)?.toDouble(),
      pitch: (json['pitch'] as num?)?.toDouble(),
      heading: (json['heading'] as num?)?.toDouble() ?? (json['hdg'] as num?)?.toDouble(),
      correctionAge: (json['correction_age'] as num?)?.toDouble() ?? (json['corr_age'] as num?)?.toDouble(),
      autoInsState: json['auto_ins_state']?.toString(),
      alignmentMode: json['alignment_mode']?.toString(),
      alignmentTrialRequested: _boolValue(json['alignment_trial_requested']),
      alignmentTrialCommandRejected:
          _boolValue(json['alignment_trial_command_rejected']),
      autoInsError: json['auto_ins_error']?.toString(),
      insAlignFull: json['ins_align_full']?.toString(),
      measurementReady: _boolValue(json['measurement_ready']),
    );
  }

  static bool? _boolValue(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      switch (value.trim().toLowerCase()) {
        case 'true':
        case '1':
        case 'yes':
          return true;
        case 'false':
        case '0':
        case 'no':
          return false;
      }
    }
    return null;
  }

  static int? _intValue(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  @override
  String toString() {
    return 'MfkRtkStatus(fw: $firmwareVersion, bat: $batteryPercentage%, ble: $bleConnected)';
  }
}
