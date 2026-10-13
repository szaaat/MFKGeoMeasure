import 'dart:math';
import 'package:flutter/foundation.dart';

class BynavNavSolution {
  final String messageName;
  final double latitude;
  final double longitude;
  final double altitude;
  final double? undulation;
  
  final double? heading;
  final double? pitch;
  final double? roll;
  
  final double? northVelocity;
  final double? eastVelocity;
  final double? upVelocity;
  
  final double? horizontalAccuracy;
  final double? verticalAccuracy;
  
  final int? gpsWeek;
  final double? gpsSeconds;
  
  final String? insStatus;
  final String? posType;
  final int? satellitesUsed;
  final double? correctionAge;

  BynavNavSolution({
    required this.messageName,
    required this.latitude,
    required this.longitude,
    required this.altitude,
    this.undulation,
    this.heading,
    this.pitch,
    this.roll,
    this.northVelocity,
    this.eastVelocity,
    this.upVelocity,
    this.horizontalAccuracy,
    this.verticalAccuracy,
    this.gpsWeek,
    this.gpsSeconds,
    this.insStatus,
    this.posType,
    this.satellitesUsed,
    this.correctionAge,
  });

  bool get isInsGood => insStatus == 'INS_SOLUTION_GOOD';

  @override
  String toString() {
    return 'BynavNavSolution(msg: $messageName, lat: $latitude, lon: $longitude, h: $altitude, ins: $insStatus, posType: $posType, acc: $horizontalAccuracy)';
  }
}

class BynavParser {
  /// Parses a Bynav/NovAtel ASCII line starting with `#` or `%`.
  /// Returns `null` if the line is not a supported Bynav message or if parsing fails.
  BynavNavSolution? parse(String line) {
    try {
      final trimmed = line.trim();
      if (!trimmed.startsWith('#') && !trimmed.startsWith('%')) {
        return null;
      }

      // Remove leading prefix
      final raw = trimmed.substring(1);
      
      // Separate payload and checksum if present
      final payload = raw.contains('*') ? raw.split('*')[0] : raw;
      
      // Separate header and body by ';'
      if (!payload.contains(';')) return null;

      final parts = payload.split(';');
      final headerStr = parts[0];
      final bodyStr = parts[1];

      final headerFields = headerStr.split(',');
      if (headerFields.isEmpty) return null;

      final msgName = headerFields[0].toUpperCase();
      final bodyFields = bodyStr.split(',');

      // Extract GPS week/seconds from header if available
      int? headerGpsWeek;
      double? headerGpsSeconds;
      if (headerFields.length >= 6) {
        headerGpsWeek = int.tryParse(headerFields[headerFields.length - 2]);
        headerGpsSeconds = double.tryParse(headerFields[headerFields.length - 1]);
      }

      switch (msgName) {
        case 'INSPVASA':
        case 'INSPVA':
          return _parseINSPVASA(msgName, headerFields, bodyFields, headerGpsWeek, headerGpsSeconds);
        case 'INSPVAXA':
        case 'INSPVAX':
          return _parseINSPVAXA(msgName, headerFields, bodyFields, headerGpsWeek, headerGpsSeconds);
        case 'BESTPOSA':
          return _parseBESTPOSA(msgName, headerFields, bodyFields, headerGpsWeek, headerGpsSeconds);
        default:
          return null;
      }
    } catch (e) {
      debugPrint('[BYNAV-PARSER] Parse error: $e');
      return null;
    }
  }

  /// Parses Short Header INSPVASA / INSPVA
  /// Body: [week, seconds, lat, lon, height, northVel, eastVel, upVel, roll, pitch, azimuth, insStatus]
  BynavNavSolution? _parseINSPVASA(
    String msgName,
    List<String> header,
    List<String> body,
    int? headerWeek,
    double? headerSec,
  ) {
    if (body.length < 12) return null;

    final week = int.tryParse(body[0]) ?? headerWeek;
    final seconds = double.tryParse(body[1]) ?? headerSec;
    final lat = double.tryParse(body[2]);
    final lon = double.tryParse(body[3]);
    final height = double.tryParse(body[4]);

    if (lat == null || lon == null || height == null) return null;

    final nVel = double.tryParse(body[5]);
    final eVel = double.tryParse(body[6]);
    final uVel = double.tryParse(body[7]);
    final roll = double.tryParse(body[8]);
    final pitch = double.tryParse(body[9]);
    final azimuth = double.tryParse(body[10]);
    final insStatus = body[11].trim();

    return BynavNavSolution(
      messageName: msgName,
      latitude: lat,
      longitude: lon,
      altitude: height,
      heading: azimuth,
      pitch: pitch,
      roll: roll,
      northVelocity: nVel,
      eastVelocity: eVel,
      upVelocity: uVel,
      gpsWeek: week,
      gpsSeconds: seconds,
      insStatus: insStatus,
    );
  }

  /// Parses Extended Header INSPVAXA / INSPVAX
  /// Body: [insStatus, posType, lat, lon, height, undulation, nVel, eVel, uVel, roll, pitch, azimuth, latStd, lonStd, hgtStd, ...]
  BynavNavSolution? _parseINSPVAXA(
    String msgName,
    List<String> header,
    List<String> body,
    int? headerWeek,
    double? headerSec,
  ) {
    if (body.length < 15) return null;

    final insStatus = body[0].trim();
    final posType = body[1].trim();
    final lat = double.tryParse(body[2]);
    final lon = double.tryParse(body[3]);
    final height = double.tryParse(body[4]);

    if (lat == null || lon == null || height == null) return null;

    final undulation = double.tryParse(body[5]);
    final nVel = double.tryParse(body[6]);
    final eVel = double.tryParse(body[7]);
    final uVel = double.tryParse(body[8]);
    final roll = double.tryParse(body[9]);
    final pitch = double.tryParse(body[10]);
    final azimuth = double.tryParse(body[11]);

    final latStd = double.tryParse(body[12]);
    final lonStd = double.tryParse(body[13]);
    final hgtStd = double.tryParse(body[14]);

    double? hAcc;
    if (latStd != null && lonStd != null) {
      hAcc = sqrt(latStd * latStd + lonStd * lonStd);
    }

    return BynavNavSolution(
      messageName: msgName,
      latitude: lat,
      longitude: lon,
      altitude: height,
      undulation: undulation,
      heading: azimuth,
      pitch: pitch,
      roll: roll,
      northVelocity: nVel,
      eastVelocity: eVel,
      upVelocity: uVel,
      horizontalAccuracy: hAcc,
      verticalAccuracy: hgtStd,
      gpsWeek: headerWeek,
      gpsSeconds: headerSec,
      insStatus: insStatus,
      posType: posType,
    );
  }

  /// Parses BESTPOSA
  /// Body: [solStatus, posType, lat, lon, height, undulation, datum, latStd, lonStd, hgtStd, stnId, diffAge, solAge, satsTracked, satsUsed, ...]
  BynavNavSolution? _parseBESTPOSA(
    String msgName,
    List<String> header,
    List<String> body,
    int? headerWeek,
    double? headerSec,
  ) {
    if (body.length < 15) return null;

    final solStatus = body[0].trim();
    final posType = body[1].trim();
    final lat = double.tryParse(body[2]);
    final lon = double.tryParse(body[3]);
    final height = double.tryParse(body[4]);

    if (lat == null || lon == null || height == null) return null;

    final undulation = double.tryParse(body[5]);
    final latStd = double.tryParse(body[7]);
    final lonStd = double.tryParse(body[8]);
    final hgtStd = double.tryParse(body[9]);
    final diffAge = double.tryParse(body[11]);
    final satsUsed = int.tryParse(body[14]);

    double? hAcc;
    if (latStd != null && lonStd != null) {
      hAcc = sqrt(latStd * latStd + lonStd * lonStd);
    }

    return BynavNavSolution(
      messageName: msgName,
      latitude: lat,
      longitude: lon,
      altitude: height,
      undulation: undulation,
      horizontalAccuracy: hAcc,
      verticalAccuracy: hgtStd,
      gpsWeek: headerWeek,
      gpsSeconds: headerSec,
      posType: '$solStatus/$posType',
      satellitesUsed: satsUsed,
      correctionAge: diffAge,
    );
  }
}
