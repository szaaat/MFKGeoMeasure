import 'package:latlong2/latlong.dart';

enum GnssFixType {
  none,
  autonomous,
  dgps,
  rtk,
}

enum RtkStatus {
  none,
  float,
  fixed,
}

enum GnssSource {
  internal,
  external,
  hybrid,
}

enum TimestampSource {
  device,
  gnss,
}

enum GnssConnectionType {
  internal,
  bluetoothClassic,
  ble,
  usb,
  mfkrtk, // Specialized BLE profile for MFKRTK
}

enum GnssReferenceFrame { unknown, etrf2000 }

class GnssFix {
  final double latitude;
  final double longitude;
  
  /// A forrásból érkező "nyers" magasság.
  final double altitude;
  
  /// Kiszámított vagy megadott ellipszoidi magasság.
  final double ellipsoidalHeight;

  /// Igaz, ha az [altitude] mező már ellipszoidi magasságot tartalmaz.
  final bool isEllipsoidal;
  
  // Opcionális mezők az eredeti NMEA adatokhoz (GGA-ból)
  final double? mslAltitude;
  final double? geoidSeparation;

  final double horizontalAccuracy;
  final double verticalAccuracy;
  
  final GnssFixType fixType;
  final RtkStatus rtkStatus;
  
  final int satellitesUsed;
  final int satellitesInView;
  
  final double? pdop;
  final double? hdop;
  final double? vdop;
  
  final double? correctionAge;
  final String? stationId;
  
  // INS & Bynav specific fields
  final double? heading;
  final double? roll;
  final double? pitch;
  final String? insStatus;
  final String? positionSource;
  
  final GnssSource source;
  final String? receiverName;
  final GnssConnectionType connectionType;
  
  final DateTime timestamp;
  final TimestampSource timestampSource;
  final GnssReferenceFrame referenceFrame;
  final DateTime? referenceEpoch;

  GnssFix({
    required this.latitude,
    required this.longitude,
    required this.altitude,
    required this.ellipsoidalHeight,
    required this.isEllipsoidal,
    this.mslAltitude,
    this.geoidSeparation,
    this.horizontalAccuracy = 0.0,
    this.verticalAccuracy = 0.0,
    this.fixType = GnssFixType.none,
    this.rtkStatus = RtkStatus.none,
    this.satellitesUsed = 0,
    this.satellitesInView = 0,
    this.pdop,
    this.hdop,
    this.vdop,
    this.correctionAge,
    this.stationId,
    this.heading,
    this.roll,
    this.pitch,
    this.insStatus,
    this.positionSource,
    required this.source,
    this.receiverName,
    required this.connectionType,
    required this.timestamp,
    this.timestampSource = TimestampSource.device,
    this.referenceFrame = GnssReferenceFrame.unknown,
    this.referenceEpoch,
  });

  bool get isInsGood => insStatus == 'INS_SOLUTION_GOOD';

  bool get isValidPosition {
    if (latitude.isNaN || longitude.isNaN) return false;
    if (latitude.isInfinite || longitude.isInfinite) return false;
    if (latitude == 0.0 || longitude == 0.0) return false;
    if (fixType == GnssFixType.none && !isInsGood) return false;
    return true;
  }

  GnssFix copyWith({
    double? latitude,
    double? longitude,
  }) {
    return GnssFix(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      altitude: altitude,
      ellipsoidalHeight: ellipsoidalHeight,
      isEllipsoidal: isEllipsoidal,
      mslAltitude: mslAltitude,
      geoidSeparation: geoidSeparation,
      horizontalAccuracy: horizontalAccuracy,
      verticalAccuracy: verticalAccuracy,
      fixType: fixType,
      rtkStatus: rtkStatus,
      satellitesUsed: satellitesUsed,
      satellitesInView: satellitesInView,
      pdop: pdop,
      hdop: hdop,
      vdop: vdop,
      correctionAge: correctionAge,
      stationId: stationId,
      heading: heading,
      roll: roll,
      pitch: pitch,
      insStatus: insStatus,
      positionSource: positionSource,
      source: source,
      receiverName: receiverName,
      connectionType: connectionType,
      timestamp: timestamp,
      timestampSource: timestampSource,
      referenceFrame: referenceFrame,
      referenceEpoch: referenceEpoch,
    );
  }

  LatLng get toLatLng => LatLng(latitude, longitude);

  Map<String, dynamic> toMap() => {
    'latitude': latitude,
    'longitude': longitude,
    'altitude': altitude,
    'ellipsoidalHeight': ellipsoidalHeight,
    'isEllipsoidal': isEllipsoidal,
    'horizontalAccuracy': horizontalAccuracy,
    'verticalAccuracy': verticalAccuracy,
    'fixType': fixType.name,
    'rtkStatus': rtkStatus.name,
    'satellitesUsed': satellitesUsed,
    'satellitesInView': satellitesInView,
    'pdop': pdop,
    'hdop': hdop,
    'vdop': vdop,
    'correctionAge': correctionAge,
    'stationId': stationId,
    'heading': heading,
    'roll': roll,
    'pitch': pitch,
    'insStatus': insStatus,
    'positionSource': positionSource,
    'source': source.name,
    'receiverName': receiverName,
    'connectionType': connectionType.name,
    'timestamp': timestamp.toIso8601String(),
    'timestampSource': timestampSource.name,
    'referenceFrame': referenceFrame.name,
    'referenceEpoch': referenceEpoch?.toIso8601String(),
  };

  @override
  String toString() {
    return 'GnssFix(lat: $latitude, lon: $longitude, h: $altitude, ellipsoidal: $isEllipsoidal, type: $fixType, rtk: $rtkStatus, ins: $insStatus, hdg: $heading, src: $source)';
  }
}
