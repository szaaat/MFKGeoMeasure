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
}

enum GnssConnectionType {
  internal,
  bluetoothClassic,
  ble,
  usb,
}

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
  
  final GnssSource source;
  final String? receiverName;
  final GnssConnectionType connectionType;
  
  final DateTime timestamp;

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
    required this.source,
    this.receiverName,
    required this.connectionType,
    required this.timestamp,
  });

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
    'source': source.name,
    'receiverName': receiverName,
    'connectionType': connectionType.name,
    'timestamp': timestamp.toIso8601String(),
  };

  @override
  String toString() {
    return 'GnssFix(lat: $latitude, lon: $longitude, h: $altitude, ellipsoidal: $isEllipsoidal, type: $fixType, rtk: $rtkStatus, src: $source)';
  }
}
