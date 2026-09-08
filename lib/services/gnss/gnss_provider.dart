import '../../models/gnss_fix.dart';
import '../../models/gnss_raw_measurement.dart';

abstract class GnssProvider {
  /// Stream az érkező pozícióadatokról
  Stream<GnssFix> get fixStream;

  /// Stream a nyers műholdas mérésekről (PPK-hoz)
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
