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
  DateTime? _lastGnsDateTime;

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
    if (parts.length < 10) return null;

    // Lat/Lon parsing
    double lat = (parts.length > 3) ? _parseDegrees(parts[2], parts[3]) ?? 0.0 : 0.0;
    double lon = (parts.length > 5) ? _parseDegrees(parts[4], parts[5]) ?? 0.0 : 0.0;

    // Quality
    int quality = (parts.length > 6) ? int.tryParse(parts[6]) ?? 0 : 0;
    GnssFixType fixType = GnssFixType.none;
    RtkStatus rtkStatus = RtkStatus.none;

    switch (quality) {
      case 1: fixType = GnssFixType.autonomous; break;
      case 2: fixType = GnssFixType.dgps; break;
      case 4: fixType = GnssFixType.rtk; rtkStatus = RtkStatus.fixed; break;
      case 5: fixType = GnssFixType.rtk; rtkStatus = RtkStatus.float; break;
    }

    if (quality == 0) {
      fixType = GnssFixType.none;
    }

    // Satellites
    _satellitesUsed = (parts.length > 7) ? int.tryParse(parts[7]) ?? 0 : 0;
    _lastHdop = (parts.length > 8) ? double.tryParse(parts[8]) : null;

    // Altitude
    double mslAlt = (parts.length > 9) ? double.tryParse(parts[9]) ?? 0.0 : 0.0;
    double geoidSep = (parts.length > 11) ? double.tryParse(parts[11]) ?? 0.0 : 0.0;
    
    // Konvenció: ellipsoidal height = MSL altitude + geoid separation
    double ellipsoidalHeight = mslAlt + geoidSep;

    double? age = (parts.length > 13) ? double.tryParse(parts[13]) : null;
    String? station = (parts.length > 14) ? parts[14] : null;

    // Timestamp parsing
    DateTime timestamp = DateTime.now();
    TimestampSource tsSource = TimestampSource.device;

    final ggaTime = parts[1];
    if (ggaTime.isNotEmpty && _lastGnsDateTime != null) {
      final parsed = _combineDateAndTime(_lastGnsDateTime!, ggaTime);
      if (parsed != null) {
        timestamp = parsed;
        tsSource = TimestampSource.gnss;
      }
    }

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
      timestamp: timestamp,
      timestampSource: tsSource,
    );
  }

  void _parseRMC(List<String> parts) {
    if (parts.length < 10) return;
    
    final timeStr = parts[1];
    final dateStr = parts[9];
    
    if (timeStr.isNotEmpty && dateStr.isNotEmpty) {
      final parsed = _parseRmcDateTime(dateStr, timeStr);
      if (parsed != null) {
        _lastGnsDateTime = parsed;
      }
    }
  }

  DateTime? _parseRmcDateTime(String datePart, String timePart) {
    if (datePart.length != 6 || timePart.length < 6) return null;
    try {
      int day = int.parse(datePart.substring(0, 2));
      int month = int.parse(datePart.substring(2, 4));
      int year = int.parse(datePart.substring(4, 6)) + 2000;
      
      int hour = int.parse(timePart.substring(0, 2));
      int minute = int.parse(timePart.substring(2, 4));
      int second = int.parse(timePart.substring(4, 6));
      int millis = 0;
      if (timePart.contains('.')) {
        double sub = double.parse('0${timePart.substring(timePart.indexOf('.'))}');
        millis = (sub * 1000).round();
      }
      
      return DateTime.utc(year, month, day, hour, minute, second, millis);
    } catch (e) {
      return null;
    }
  }

  DateTime? _combineDateAndTime(DateTime lastDate, String ggaTime) {
    if (ggaTime.length < 6) return null;
    try {
      int hour = int.parse(ggaTime.substring(0, 2));
      int minute = int.parse(ggaTime.substring(2, 4));
      int second = int.parse(ggaTime.substring(4, 6));
      int millis = 0;
      if (ggaTime.contains('.')) {
        double sub = double.parse('0${ggaTime.substring(ggaTime.indexOf('.'))}');
        millis = (sub * 1000).round();
      }

      // Midnight rollover check
      // If GGA hour is 0 and RMC hour was 23, we should probably increment the date.
      // But typically RMC and GGA arrive within seconds.
      DateTime dt = DateTime.utc(lastDate.year, lastDate.month, lastDate.day, hour, minute, second, millis);
      
      // If the difference is huge (e.g. > 12h), adjust date
      if (dt.difference(lastDate).inHours.abs() > 12) {
         if (hour < 12 && lastDate.hour > 12) {
           dt = dt.add(const Duration(days: 1));
         } else if (hour > 12 && lastDate.hour < 12) {
           dt = dt.subtract(const Duration(days: 1));
         }
      }
      
      return dt;
    } catch (e) {
      return null;
    }
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
      if (degLen <= 0) return 0.0;
      double deg = double.parse(val.substring(0, degLen));
      double min = double.parse(val.substring(degLen));
      double res = deg + (min / 60.0);
      if (dir == 'S' || dir == 'W') res = -res;
      return res;
    } catch (e) {
      return 0.0;
    }
  }
}
