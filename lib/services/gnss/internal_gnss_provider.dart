import 'dart:async';
import 'dart:io';
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
  StreamSubscription? _rawSubscription;

  final _rawGnss = RawGnss();
  final GeoidCorrectionService? _geoidService;

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

    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 0,
    );

    _positionSubscription =
        Geolocator.getPositionStream(locationSettings: locationSettings)
            .listen((Position position) {
      _fixController.add(_mapPositionToGnssFix(position));
    });

    if (Platform.isAndroid) {
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
    await _rawSubscription?.cancel();
    _positionSubscription = null;
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
