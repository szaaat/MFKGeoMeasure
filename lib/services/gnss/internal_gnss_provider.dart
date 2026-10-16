import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:raw_gnss/raw_gnss.dart';
import 'package:mfk_geomeasure/models/gnss_fix.dart';
import 'package:mfk_geomeasure/models/gnss_raw_measurement.dart';
import 'package:mfk_geomeasure/services/gnss/gnss_provider.dart';
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
          _fixController.add(_mapNativeIOSLocationToGnssFix(event));
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

  GnssFix _mapNativeIOSLocationToGnssFix(Map<dynamic, dynamic> data) {
    final double latitude = data['latitude'] as double;
    final double longitude = data['longitude'] as double;
    final double altitude = data['altitude'] as double; // iOS MSL
    final double? ellipsoidalAltitude = data['ellipsoidalAltitude'] as double?;
    final double hAccuracy = data['horizontalAccuracy'] as double;
    final double vAccuracy = data['verticalAccuracy'] as double;
    final double timestampMs = data['timestamp'] as double;
    final DateTime timestamp =
        DateTime.fromMillisecondsSinceEpoch(timestampMs.round());

    double ellipsoidalHeight;
    double? mslAltitude;
    double? geoidSeparation;
    bool isEllipsoidal;

    if (ellipsoidalAltitude != null) {
      // iOS 15+ has ellipsoidal altitude
      isEllipsoidal = true;
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
          mslAltitude = altitude;
          geoidSeparation = ellipsoidalHeight - mslAltitude;
        }
      } else {
        mslAltitude = altitude;
        geoidSeparation = ellipsoidalHeight - mslAltitude;
      }
    } else {
      // Prior to iOS 15 or not available, we only have orthometric MSL altitude
      isEllipsoidal = false;
      mslAltitude = altitude;
      ellipsoidalHeight = altitude; // We don't have it, put dummy value
    }

    return GnssFix(
      latitude: latitude,
      longitude: longitude,
      altitude: altitude, // The raw field is altitude (MSL on iOS)
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
    double ellipsoidalHeight = pos.altitude;
    double? mslAltitude;
    double? geoidSeparation;
    bool isEllipsoidal = true;

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

    return GnssFix(
      latitude: pos.latitude,
      longitude: pos.longitude,
      altitude: pos.altitude,
      ellipsoidalHeight: ellipsoidalHeight,
      isEllipsoidal: isEllipsoidal,
      mslAltitude: mslAltitude,
      geoidSeparation: geoidSeparation,
      horizontalAccuracy: pos.accuracy,
      verticalAccuracy: pos.altitudeAccuracy,
      fixType: pos.accuracy < 10 ? GnssFixType.autonomous : GnssFixType.none,
      satellitesUsed: 0,
      source: GnssSource.internal,
      receiverName: "Internal GPS",
      connectionType: GnssConnectionType.internal,
      timestamp: pos.timestamp,
    );
  }
}
