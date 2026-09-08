import '../../models/gnss_fix.dart';

abstract class GnssProvider {
  /// Stream az érkező pozícióadatokról
  Stream<GnssFix> get fixStream;

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
