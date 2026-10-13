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
  final double? roll;
  final double? pitch;
  final double? heading;
  final double? correctionAge;

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
    this.roll,
    this.pitch,
    this.heading,
    this.correctionAge,
  });

  factory MfkRtkStatus.fromJson(Map<String, dynamic> json) {
    return MfkRtkStatus(
      firmwareVersion: json['fw_ver'] ?? 'Unknown',
      batteryVoltage: (json['bat_v'] as num?)?.toDouble() ?? 0.0,
      batteryPercentage: json['bat_p'] as int? ?? 0,
      bleConnected: json['ble_conn'] as bool? ?? false,
      otaState: json['ota_state'] ?? 'IDLE',
      gnssFix: json['gnss_fix'],
      rtkStatus: json['rtk_stat'],
      satellites: json['sats'] as int?,
      hdop: (json['hdop'] as num?)?.toDouble(),
      latitude: (json['lat'] as num?)?.toDouble(),
      longitude: (json['lon'] as num?)?.toDouble(),
      altitude: (json['alt'] as num?)?.toDouble(),
      insStatus: json['ins_stat'],
      roll: (json['roll'] as num?)?.toDouble(),
      pitch: (json['pitch'] as num?)?.toDouble(),
      heading: (json['hdg'] as num?)?.toDouble(),
      correctionAge: (json['corr_age'] as num?)?.toDouble(),
    );
  }

  @override
  String toString() {
    return 'MfkRtkStatus(fw: $firmwareVersion, bat: $batteryPercentage%, ble: $bleConnected)';
  }
}
