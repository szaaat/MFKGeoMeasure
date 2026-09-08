import 'dart:async';
import '../../models/gnss_fix.dart';
import '../../models/gnss_raw_measurement.dart';
import 'gnss_provider.dart';

/// Architectural skeleton for a Hybrid GNSS Provider.
/// Capable of managing multiple sources (Internal + External) and
/// implementing fallback/merging logic.
class HybridGnssProvider implements GnssProvider {
  final GnssProvider internal;
  final GnssProvider external;

  final _fixController = StreamController<GnssFix>.broadcast();
  final _rawController = StreamController<GnssRawMeasurement>.broadcast();
  
  StreamSubscription? _internalSub;
  StreamSubscription? _externalSub;
  StreamSubscription? _internalRawSub;
  StreamSubscription? _externalRawSub;

  GnssSource _activeSource = GnssSource.internal;
  final bool _preferExternal = true;

  HybridGnssProvider({
    required this.internal,
    required this.external,
  });

  @override
  Stream<GnssFix> get fixStream => _fixController.stream;

  @override
  Stream<GnssRawMeasurement> get rawMeasurementStream => _rawController.stream;

  @override
  bool get supportsRtcmInput => external.supportsRtcmInput;

  @override
  Future<void> connect() async {
    // Note: For now, this is just a skeleton. 
    // In a real hybrid scenario, we would manage both connections.
    await internal.connect();
    await external.connect();

    _internalSub = internal.fixStream.listen((fix) {
      if (_activeSource == GnssSource.internal) {
        _fixController.add(_mapToHybrid(fix));
      }
    });

    _externalSub = external.fixStream.listen((fix) {
      // Future logic: if external is high quality (RTK FIX), switch to it
      if (_preferExternal && (fix.fixType == GnssFixType.rtk)) {
        _activeSource = GnssSource.external;
      }
      
      if (_activeSource == GnssSource.external) {
        _fixController.add(_mapToHybrid(fix));
      }
    });
    
    _internalRawSub = internal.rawMeasurementStream.listen((m) => _rawController.add(m));
    _externalRawSub = external.rawMeasurementStream.listen((m) => _rawController.add(m));
  }

  @override
  Future<void> disconnect() async {
    await _internalSub?.cancel();
    await _externalSub?.cancel();
    await _internalRawSub?.cancel();
    await _externalRawSub?.cancel();
    await internal.disconnect();
    await external.disconnect();
  }

  @override
  void sendCorrectionData(List<int> data) {
    external.sendCorrectionData(data);
  }

  @override
  void dispose() {
    disconnect();
    _fixController.close();
    _rawController.close();
  }

  GnssFix _mapToHybrid(GnssFix fix) {
    // Maintain identical geodetic data but mark as hybrid source
    return GnssFix(
      latitude: fix.latitude,
      longitude: fix.longitude,
      altitude: fix.altitude,
      ellipsoidalHeight: fix.ellipsoidalHeight,
      isEllipsoidal: fix.isEllipsoidal,
      mslAltitude: fix.mslAltitude,
      geoidSeparation: fix.geoidSeparation,
      horizontalAccuracy: fix.horizontalAccuracy,
      verticalAccuracy: fix.verticalAccuracy,
      fixType: fix.fixType,
      rtkStatus: fix.rtkStatus,
      satellitesUsed: fix.satellitesUsed,
      satellitesInView: fix.satellitesInView,
      pdop: fix.pdop,
      hdop: fix.hdop,
      vdop: fix.vdop,
      correctionAge: fix.correctionAge,
      stationId: fix.stationId,
      source: GnssSource.hybrid, // Mark as hybrid
      receiverName: fix.receiverName,
      connectionType: fix.connectionType,
      timestamp: fix.timestamp,
      timestampSource: fix.timestampSource,
    );
  }
}
