/// Unified model for raw GNSS satellite observations.
/// Initially supports fields required for Android PPK logging.
class GnssRawMeasurement {
  final DateTime timestamp;
  final int svid;
  final int constellationType;
  final double? accumulatedDeltaRangeMeters;
  final int? accumulatedDeltaRangeState;
  final int? receivedSvTimeNanos;
  final double? cn0DbHz;
  final double? carrierFrequencyHz;
  final int? timeOffsetNanos;
  final int? multipathIndicator;

  GnssRawMeasurement({
    required this.timestamp,
    required this.svid,
    required this.constellationType,
    this.accumulatedDeltaRangeMeters,
    this.accumulatedDeltaRangeState,
    this.receivedSvTimeNanos,
    this.cn0DbHz,
    this.carrierFrequencyHz,
    this.timeOffsetNanos,
    this.multipathIndicator,
  });

  Map<String, dynamic> toMap() => {
    'timestamp': timestamp.toIso8601String(),
    'svid': svid,
    'constellationType': constellationType,
    'accumulatedDeltaRangeMeters': accumulatedDeltaRangeMeters,
    'accumulatedDeltaRangeState': accumulatedDeltaRangeState,
    'receivedSvTimeNanos': receivedSvTimeNanos,
    'cn0DbHz': cn0DbHz,
    'carrierFrequencyHz': carrierFrequencyHz,
    'timeOffsetNanos': timeOffsetNanos,
    'multipathIndicator': multipathIndicator,
  };
}
