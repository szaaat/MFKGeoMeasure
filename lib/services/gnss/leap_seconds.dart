class LeapSeconds {
  /// GPS time was synced with UTC on Jan 6, 1980.
  /// Since then, leap seconds have been introduced.
  static int getLeapSeconds(DateTime gpsTime) {
    if (gpsTime.isBefore(DateTime.utc(1981, 7, 1))) return 0;
    if (gpsTime.isBefore(DateTime.utc(1982, 7, 1))) return 1;
    if (gpsTime.isBefore(DateTime.utc(1983, 7, 1))) return 2;
    if (gpsTime.isBefore(DateTime.utc(1985, 7, 1))) return 3;
    if (gpsTime.isBefore(DateTime.utc(1988, 1, 1))) return 4;
    if (gpsTime.isBefore(DateTime.utc(1990, 1, 1))) return 5;
    if (gpsTime.isBefore(DateTime.utc(1991, 1, 1))) return 6;
    if (gpsTime.isBefore(DateTime.utc(1992, 7, 1))) return 7;
    if (gpsTime.isBefore(DateTime.utc(1993, 7, 1))) return 8;
    if (gpsTime.isBefore(DateTime.utc(1994, 7, 1))) return 9;
    if (gpsTime.isBefore(DateTime.utc(1996, 1, 1))) return 10;
    if (gpsTime.isBefore(DateTime.utc(1997, 7, 1))) return 11;
    if (gpsTime.isBefore(DateTime.utc(1999, 1, 1))) return 12;
    if (gpsTime.isBefore(DateTime.utc(2006, 1, 1))) return 13;
    if (gpsTime.isBefore(DateTime.utc(2009, 1, 1))) return 14;
    if (gpsTime.isBefore(DateTime.utc(2012, 7, 1))) return 15;
    if (gpsTime.isBefore(DateTime.utc(2015, 7, 1))) return 16;
    if (gpsTime.isBefore(DateTime.utc(2017, 1, 1))) return 17;
    return 18; // Effective from Jan 1, 2017 until at least 2026.
  }
}
