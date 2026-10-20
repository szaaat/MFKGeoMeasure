import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:raw_gnss/raw_gnss.dart';
import 'package:mfk_geomeasure/models/gnss_fix.dart';
import 'package:mfk_geomeasure/models/gnss_raw_measurement.dart';
import 'package:mfk_geomeasure/services/gnss/gnss_provider.dart';
import 'package:flutter/foundation.dart';
import '../geoid_service.dart';

class InternalGnssProvider implements GnssProvider {
  final _fixController = StreamController<GnssFix>.broadcast();
  final _rawMeasurementController =
      StreamController<GnssRawMeasurement>.broadcast();
  final _rawByteController = StreamController<List<int>>.broadcast();
  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<dynamic>? _nativeLocationSubscription;
  StreamSubscription? _rawSubscription;

  final _rawGnss = RawGnss();
  final GeoidCorrectionService? _geoidService;

  static const _nativeLocationChannel =
      EventChannel('hu.uni.miskolc.mfkGeomeasure/native_location');

  InternalGnssProvider({GeoidCorrectionService? geoidService})
      : _geoidService = geoidService;

  @override
  Stream<GnssFix> get fixStream => _fixController.stream;

  @override
  Stream<List<int>> get rawStream => _rawByteController.stream;

  @override
  Stream<GnssRawMeasurement> get rawMeasurementStream =>
      _rawMeasurementController.stream;

  @override
  bool get supportsRtcmInput => false;

  @override
  Future<void> connect() async {
    // Biztosítjuk, hogy ne legyenek beragadt stream-ek, ha többször hívják meg a connect-et.
    await disconnect();

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception("Location services are disabled.");
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception("Location permissions are denied.");
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception("Location permissions are permanently denied.");
    }

    if (Platform.isIOS) {
      _nativeLocationSubscription = _nativeLocationChannel
          .receiveBroadcastStream()
          .listen((dynamic event) {
        if (event is Map) {
          _fixController.add(mapNativeIOSLocationToGnssFix(event));
        }
      });
    } else {
      const locationSettings = LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 0,
      );

      _positionSubscription =
          Geolocator.getPositionStream(locationSettings: locationSettings)
              .listen((Position position) {
        _fixController.add(_mapPositionToGnssFix(position));
      });

      _rawSubscription = _rawGnss.gnssMeasurementEvents.listen((model) {
        final now = DateTime.now();
        for (var m in (model.measurements ?? [])) {
          _rawMeasurementController.add(GnssRawMeasurement(
            timestamp: now,
            svid: (m.svid as num?)?.toInt() ?? 0,
            constellationType:
                (m.constellationType as num?)?.toInt() ?? 0,
            accumulatedDeltaRangeMeters:
                (m.accumulatedDeltaRangeMeters as num?)?.toDouble(),
            accumulatedDeltaRangeState:
                (m.accumulatedDeltaRangeState as num?)?.toInt(),
            receivedSvTimeNanos:
                (m.receivedSvTimeNanos as num?)?.toInt(),
            cn0DbHz: (m.cn0DbHz as num?)?.toDouble(),
            carrierFrequencyHz: (m.carrierFrequencyHz as num?)?.toDouble(),
            timeOffsetNanos: (m.timeOffsetNanos as num?)?.toInt(),
            multipathIndicator:
                (m.multipathIndicator as num?)?.toInt(),
          ));
        }
      });
    }
  }

  @override
  Future<void> disconnect() async {
    await _positionSubscription?.cancel();
    await _nativeLocationSubscription?.cancel();
    await _rawSubscription?.cancel();
    _positionSubscription = null;
    _nativeLocationSubscription = null;
    _rawSubscription = null;
  }

  @override
  void sendCorrectionData(List<int> data) {
    // Nem támogatott belső GPS esetén
  }

  @override
  void dispose() {
    disconnect();
    _fixController.close();
    _rawMeasurementController.close();
    _rawByteController.close();
  }

  @visibleForTesting
  GnssFix mapNativeIOSLocationToGnssFix(Map<dynamic, dynamic> data) {
    final double latitude = data['latitude'] as double;
    final double longitude = data['longitude'] as double;
    double altitude = data['altitude'] as double; // Default to iOS MSL
    final double? ellipsoidalAltitude = data['ellipsoidalAltitude'] as double?;
    final double hAccuracy = data['horizontalAccuracy'] as double;
    final double vAccuracy = data['verticalAccuracy'] as double;
    final double timestampMs = data['timestamp'] as double;
    final DateTime timestamp =
        DateTime.fromMillisecondsSinceEpoch(timestampMs.round());

    double ellipsoidalHeight = double.nan;
    double? mslAltitude;
    double? geoidSeparation;
    bool isEllipsoidal = false;

    // Check if height is valid
    if (vAccuracy <= 0) {
      altitude = double.nan;
      ellipsoidalHeight = double.nan;
      mslAltitude = null;
      isEllipsoidal = false;
    } else {
      if (ellipsoidalAltitude != null) {
        // iOS 15+ has ellipsoidal altitude
        isEllipsoidal = true;
        altitude = ellipsoidalAltitude; // Ensure GnssFix.altitude matches isEllipsoidal
        ellipsoidalHeight = ellipsoidalAltitude;

        // Recompute BME undulation if possible
        if (_geoidService != null) {
          final geoidResult = _geoidService!.getUndulation(
            latitude,
            longitude,
            referenceFrame: GeoidInputFrame.assumed,
          );
          if (geoidResult != null) {
            geoidSeparation = geoidResult.value;
            mslAltitude = ellipsoidalHeight - geoidSeparation;
          } else {
            // If outside BME, rely on iOS's orthometric height
            mslAltitude = data['altitude'] as double;
            geoidSeparation = ellipsoidalHeight - mslAltitude;
          }
        } else {
          mslAltitude = data['altitude'] as double;
          geoidSeparation = ellipsoidalHeight - mslAltitude;
        }
      } else {
        // Prior to iOS 15 or not available, we only have orthometric MSL altitude
        isEllipsoidal = false;
        altitude = data['altitude'] as double; // Ensure GnssFix.altitude is MSL
        mslAltitude = altitude;
        ellipsoidalHeight = double.nan; // We explicitly don't have ellipsoidal height
      }
    }

    return GnssFix(
      latitude: latitude,
      longitude: longitude,
      altitude: altitude, // Matches isEllipsoidal meaning
      ellipsoidalHeight: ellipsoidalHeight,
      isEllipsoidal: isEllipsoidal,
      mslAltitude: mslAltitude,
      geoidSeparation: geoidSeparation,
      horizontalAccuracy: hAccuracy,
      verticalAccuracy: vAccuracy,
      fixType: hAccuracy < 10 && hAccuracy > 0 ? GnssFixType.autonomous : GnssFixType.none,
      satellitesUsed: 0,
      source: GnssSource.internal,
      receiverName: "Internal GPS (iOS)",
      connectionType: GnssConnectionType.internal,
      timestamp: timestamp,
    );
  }

  GnssFix _mapPositionToGnssFix(Position pos) {
    double altitude = pos.altitude;
    double ellipsoidalHeight = double.nan;
    double? mslAltitude;
    double? geoidSeparation;
    bool isEllipsoidal = true; // Assuming Android geolocator always returns WGS84 ellipsoidal height

    if (pos.altitudeAccuracy <= 0) {
      altitude = double.nan;
      ellipsoidalHeight = double.nan;
      mslAltitude = null;
      isEllipsoidal = false;
    } else {
      ellipsoidalHeight = altitude;
      if (_geoidService != null) {
        final geoidResult = _geoidService!.getUndulation(
          pos.latitude,
          pos.longitude,
          referenceFrame: GeoidInputFrame.assumed,
        );
        if (geoidResult != null) {
          geoidSeparation = geoidResult.value;
          mslAltitude = ellipsoidalHeight - geoidSeparation;
        }
      }
    }

    return GnssFix(
      latitude: pos.latitude,
      longitude: pos.longitude,
      altitude: altitude,
      ellipsoidalHeight: ellipsoidalHeight,
      isEllipsoidal: isEllipsoidal,
      mslAltitude: mslAltitude,
      geoidSeparation: geoidSeparation,
      horizontalAccuracy: pos.accuracy,
      verticalAccuracy: pos.altitudeAccuracy,
      fixType: pos.accuracy < 10 && pos.accuracy > 0 ? GnssFixType.autonomous : GnssFixType.none,
      satellitesUsed: 0,
      source: GnssSource.internal,
      receiverName: "Internal GPS",
      connectionType: GnssConnectionType.internal,
      timestamp: pos.timestamp,
    );
  }
}
