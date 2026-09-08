class NtripDiagnostics {
  final Duration? correctionAge;
  final int bytesReceived;
  final double bitrateKbps;
  final DateTime? lastGgaSent;
  final DateTime? lastRtcmReceived;
  final bool isConnected;

  NtripDiagnostics({
    this.correctionAge,
    this.bytesReceived = 0,
    this.bitrateKbps = 0.0,
    this.lastGgaSent,
    this.lastRtcmReceived,
    this.isConnected = false,
  });

  bool get hasData => correctionAge != null;

  String get correctionAgeString {
    if (correctionAge == null) return 'NO DATA';
    return '${(correctionAge!.inMilliseconds / 1000.0).toStringAsFixed(1)} s';
  }

  // Thresholds for professional use
  static const Duration goodThreshold = Duration(seconds: 3);
  static const Duration warningThreshold = Duration(seconds: 10);

  NtripDataStatus get status {
    if (correctionAge == null) return NtripDataStatus.noData;
    if (correctionAge! <= goodThreshold) return NtripDataStatus.good;
    if (correctionAge! <= warningThreshold) return NtripDataStatus.warning;
    return NtripDataStatus.poor;
  }
}

enum NtripDataStatus {
  good,
  warning,
  poor,
  noData,
}
