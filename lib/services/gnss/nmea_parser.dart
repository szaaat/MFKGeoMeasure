import 'package:flutter/foundation.dart';
import '../../models/gnss_fix.dart';

class NmeaParser {
  // Állapotmegőrzés a mondatok között (pl. GSA/GSV adatok összevárása)
  double? _lastPdop;
  double? _lastHdop;
  double? _lastVdop;
  int _satellitesInView = 0;
  int _satellitesUsed = 0;
  
  // RMC-ből jövő dátum/idő
  DateTime? _lastDateTime;

  /// Feldolgoz egyetlen NMEA mondatot és visszaad egy [GnssFix]-et, ha a mondat pozíciót tartalmazott.
  GnssFix? parse(String sentence, {required GnssSource source, required GnssConnectionType connectionType}) {
    if (!isValid(sentence)) return null;

    final parts = sentence.split('*')[0].split(',');
    if (parts.isEmpty) return null;

    final type = parts[0].substring(3);
    
    if (type == 'GGA') {
      debugPrint('[NMEA-PARSER] Sentence: $sentence');
    }

    switch (type) {
      case 'GGA':
        return _parseGGA(parts, source, connectionType);
      case 'RMC':
        _parseRMC(parts);
        break;
      case 'GSA':
        _parseGSA(parts);
        break;
      case 'GSV':
        _parseGSV(parts);
        break;
    }

    return null;
  }

  bool isValid(String sentence) {
    if (!sentence.startsWith(r'$') || !sentence.contains('*')) return false;
    
    final content = sentence.substring(1, sentence.lastIndexOf('*'));
    final providedChecksum = sentence.substring(sentence.lastIndexOf('*') + 1);
    
    int calculated = 0;
    for (int i = 0; i < content.length; i++) {
      calculated ^= content.codeUnitAt(i);
    }
    
    final hexChecksum = calculated.toRadixString(16).toUpperCase().padLeft(2, '0');
    return hexChecksum == providedChecksum.toUpperCase();
  }

  GnssFix? _parseGGA(List<String> parts, GnssSource source, GnssConnectionType connectionType) {
    if (parts.length < 15) return null;

    // Lat/Lon parsing
    double? lat = _parseDegrees(parts[2], parts[3]);
    double? lon = _parseDegrees(parts[4], parts[5]);
    if (lat == null || lon == null) return null;

    // Quality
    int quality = int.tryParse(parts[6]) ?? 0;
    GnssFixType fixType = GnssFixType.none;
    RtkStatus rtkStatus = RtkStatus.none;

    switch (quality) {
      case 1: fixType = GnssFixType.autonomous; break;
      case 2: fixType = GnssFixType.dgps; break;
      case 4: fixType = GnssFixType.rtk; rtkStatus = RtkStatus.fixed; break;
      case 5: fixType = GnssFixType.rtk; rtkStatus = RtkStatus.float; break;
    }

    // Satellites
    _satellitesUsed = int.tryParse(parts[7]) ?? 0;
    _lastHdop = double.tryParse(parts[8]);

    // Altitude
    double mslAlt = double.tryParse(parts[9]) ?? 0.0;
    double geoidSep = double.tryParse(parts[11]) ?? 0.0;
    
    // Konvenció: ellipsoidal height = MSL altitude + geoid separation
    double ellipsoidalHeight = mslAlt + geoidSep;

    double? age = double.tryParse(parts[13]);
    String? station = parts[14];

    debugPrint('[NMEA-PARSER] Quality: $quality (Fix: ${fixType.name}, RTK: ${rtkStatus.name}), Sats: $_satellitesUsed, Age: $age');

    return GnssFix(
      latitude: lat,
      longitude: lon,
      altitude: mslAlt, // NMEA GGA-ban az "altitude" mező az MSL
      ellipsoidalHeight: ellipsoidalHeight,
      isEllipsoidal: false, // Jelezzük, hogy az 'altitude' mező MSL
      mslAltitude: mslAlt,
      geoidSeparation: geoidSep,
      fixType: fixType,
      rtkStatus: rtkStatus,
      satellitesUsed: _satellitesUsed,
      satellitesInView: _satellitesInView,
      hdop: _lastHdop,
      pdop: _lastPdop,
      vdop: _lastVdop,
      correctionAge: age,
      stationId: station,
      source: source,
      connectionType: connectionType,
      timestamp: _lastDateTime ?? DateTime.now(),
    );
  }

  void _parseRMC(List<String> parts) {
    if (parts.length < 10) return;
    // RMC dátum/idő frissítése a pontos timestamphez
    // parts[1]: time (HHMMSS.ss)
    // parts[9]: date (DDMMYY)
    // Egyelőre csak a DateTime.now()-t használjuk a komplexitás csökkentésére, 
    // de a helyes implementáció ezt parse-olná.
  }

  void _parseGSA(List<String> parts) {
    if (parts.length < 18) return;
    _lastPdop = double.tryParse(parts[15]);
    _lastHdop = double.tryParse(parts[16]);
    _lastVdop = double.tryParse(parts[17]);
  }

  void _parseGSV(List<String> parts) {
    if (parts.length < 4) return;
    _satellitesInView = int.tryParse(parts[3]) ?? 0;
  }

  double? _parseDegrees(String val, String dir) {
    if (val.isEmpty) return null;
    try {
      int degLen = (val.contains('.')) ? val.indexOf('.') - 2 : val.length - 2;
      double deg = double.parse(val.substring(0, degLen));
      double min = double.parse(val.substring(degLen));
      double res = deg + (min / 60.0);
      if (dir == 'S' || dir == 'W') res = -res;
      return res;
    } catch (e) {
      return null;
    }
  }
}
