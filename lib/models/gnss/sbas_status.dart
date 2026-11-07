import 'package:raw_gnss/gnss_status_model.dart';

enum SbasState {
  /// Inaktív (iOS, külső M21 vevő, vagy nincs Android GNSS Status)
  unavailable,

  /// Belső Android GPS aktív, de 0 SBAS műhold van a látómezőben (constellationType == 2)
  notDetected,

  /// Legalább 1 SBAS műhold látható (constellationType == 2), de usedInFix == false
  detected,

  /// Legalább 1 SBAS műholdnál constellationType == 2 ÉS usedInFix == true
  usedInFix,
}

class SbasStatusData {
  final SbasState state;
  final int sbasInViewCount;
  final int sbasUsedInFixCount;
  final List<Status> sbasSatellites;

  // Diagnosztikai mezők a navigációs üzenetek vételére
  final bool hasNavigationMessages;
  final DateTime? lastNavMessageTimestamp;
  final int? lastNavSvid;
  final bool hasKnownEgnosPrn; // True, ha PRN 123, 126, 136, 138 észlelhető

  const SbasStatusData({
    this.state = SbasState.unavailable,
    this.sbasInViewCount = 0,
    this.sbasUsedInFixCount = 0,
    this.sbasSatellites = const [],
    this.hasNavigationMessages = false,
    this.lastNavMessageTimestamp,
    this.lastNavSvid,
    this.hasKnownEgnosPrn = false,
  });

  bool get isActive => state != SbasState.unavailable;
  bool get isUsedInFix => state == SbasState.usedInFix;
}
