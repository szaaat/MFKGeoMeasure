import 'package:mfk_geomeasure/models/gnss_fix.dart';
import 'package:mfk_geomeasure/models/gnss_raw_measurement.dart';

abstract class GnssProvider {
  /// Stream az érkező pozícióadatokról (feldolgozott)
  Stream<GnssFix> get fixStream;

  /// Stream a nyers byte-folyamról (diagnosztikához, egyedi protokollokhoz)
  Stream<List<int>> get rawStream;

  /// Stream a nyers műholdas mérésekről (PPK-hoz, ha a hardver támogatja)
  Stream<GnssRawMeasurement> get rawMeasurementStream;

  /// Támogatja-e a korrekciós adatok fogadását (RTCM)
  bool get supportsRtcmInput;

  /// Kapcsolódás a forráshoz (pl. Bluetooth párosítás, engedélyek kérése)
  Future<void> connect();

  /// Kapcsolat bontása
  Future<void> disconnect();

  /// Korrekciós adatok (RTCM) küldése a vevőnek
  void sendCorrectionData(List<int> data);
  
  /// Megszüntetés
  void dispose();
}
