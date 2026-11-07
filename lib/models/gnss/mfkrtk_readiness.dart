import '../gnss_fix.dart';
import 'mfkrtk_nav_data.dart';
import 'mfkrtk_status.dart';

enum MfkRtkMeasurementState {
  configurationError,
  autoInsConfiguring,
  waitingRtk,
  rtcmLost,
  waitingHeading,
  autoInsTrial,
  insSolutionUnverified,
  waitingInsAlign,
  insAlignmentComplete,
  readyToMeasure,
}

/// Computes measurement readiness from fresh, timestamped receiver data.
///
/// The diagnostic ALIGN_TRIAL firmware mode is always fail-closed. A raw
/// INSPVA solution cannot override the trial mode or receiver readiness flag.
class MfkRtkReadiness {
  static const Duration maxDataAge = Duration(seconds: 3);

  static MfkRtkMeasurementState evaluate({
    required bool connected,
    required MfkRtkNavData? nav,
    required DateTime? navReceivedAt,
    required MfkRtkStatus? status,
    required DateTime? statusReceivedAt,
    required GnssFix? fix,
    required DateTime? fixReceivedAt,
    required DateTime now,
  }) {
    if (!connected) return MfkRtkMeasurementState.waitingRtk;

    final freshNav = _isFresh(navReceivedAt, now) ? nav : null;
    final freshStatus = _isFresh(statusReceivedAt, now) ? status : null;
    final freshFix = _isFresh(fixReceivedAt, now) ? fix : null;

    final autoInsState = _first(freshNav?.autoInsState, freshStatus?.autoInsState)
        ?.trim()
        .toUpperCase();
    final autoInsError = _first(freshNav?.autoInsError, freshStatus?.autoInsError)
        ?.trim();
    final trialRejected = freshNav?.alignmentTrialCommandRejected == true ||
        freshStatus?.alignmentTrialCommandRejected == true;
    if (trialRejected || _hasReceiverError(autoInsError) ||
        (autoInsState != null &&
            (autoInsState.contains('ERROR') ||
                autoInsState.contains('FAILED') ||
                autoInsState.contains('REJECTED')))) {
      return MfkRtkMeasurementState.configurationError;
    }

    final rawInsAlign = _first(
      freshNav?.insAlign,
      freshStatus?.insAlign,
      freshFix?.insStatus,
    )?.trim().toUpperCase();
    final fullInsAlign = _first(
      freshNav?.insAlignFull,
      freshStatus?.insAlignFull,
    )?.trim().toUpperCase();
    final insAlign = fullInsAlign ?? rawInsAlign;
    final alignmentMode = _first(
      freshNav?.alignmentMode,
      freshStatus?.alignmentMode,
    )?.trim().toUpperCase();
    final trialRequested = freshNav?.alignmentTrialRequested == true ||
        freshStatus?.alignmentTrialRequested == true;
    final trialMode = alignmentMode == 'ALIGN_TRIAL_EXPERIMENTAL' ||
        rawInsAlign == 'ALIGN_TRIAL_UNVERIFIED' ||
        trialRequested ||
        (autoInsState?.contains('TRIAL') ?? false);
    if (trialMode) {
      if (insAlign == 'INS_SOLUTION_GOOD') {
        return MfkRtkMeasurementState.insSolutionUnverified;
      }
      return MfkRtkMeasurementState.autoInsTrial;
    }

    final receiverReady = freshNav?.measurementReady ??
        freshStatus?.measurementReady;
    if (receiverReady == false) {
      return MfkRtkMeasurementState.autoInsConfiguring;
    }
    if (autoInsState != null &&
        (autoInsState.contains('CONFIGURING') ||
            autoInsState.contains('INITIALIZING') ||
            autoInsState.contains('STARTING'))) {
      return MfkRtkMeasurementState.autoInsConfiguring;
    }

    if (freshFix == null ||
        !freshFix.isValidPosition ||
        freshFix.fixType != GnssFixType.rtk ||
        freshFix.rtkStatus != RtkStatus.fixed) {
      return MfkRtkMeasurementState.waitingRtk;
    }

    final rtcmOk = freshNav?.rtcmOk ?? freshStatus?.rtcmOk;
    final rtcmAgeMs = freshNav?.rtcmAgeMs ?? freshStatus?.rtcmAgeMs;
    if (rtcmOk == false ||
        (rtcmAgeMs != null &&
            rtcmAgeMs >= 0 &&
            rtcmAgeMs > maxDataAge.inMilliseconds)) {
      return MfkRtkMeasurementState.rtcmLost;
    }
    if (rtcmOk != true || rtcmAgeMs == null || rtcmAgeMs < 0) {
      return MfkRtkMeasurementState.waitingRtk;
    }

    final positionType = (freshNav?.posType ??
            freshStatus?.posType ??
            freshFix.positionSource ??
            '')
        .trim()
        .toUpperCase();
    if (positionType != 'NARROW_INT') {
      return MfkRtkMeasurementState.waitingRtk;
    }
    if (freshNav != null && !freshNav.valid) {
      return MfkRtkMeasurementState.waitingRtk;
    }

    if (insAlign == 'INS_ALIGNMENT_COMPLETE') {
      return MfkRtkMeasurementState.insAlignmentComplete;
    }

    final navHeading = freshNav?.azimuth;
    final fixHeading = freshFix.heading;
    final hasValidHeading =
        (navHeading != null && navHeading.isFinite) ||
        (fixHeading != null && fixHeading.isFinite);
    if (!hasValidHeading) {
      return MfkRtkMeasurementState.waitingHeading;
    }

    if (insAlign == 'INS_SOLUTION_GOOD' && receiverReady != false) {
      return MfkRtkMeasurementState.readyToMeasure;
    }
    return MfkRtkMeasurementState.waitingInsAlign;
  }

  static String? _first(String? a, [String? b, String? c, String? d, String? e]) {
    for (final value in [a, b, c, d, e]) {
      if (value != null && value.trim().isNotEmpty) return value;
    }
    return null;
  }

  static bool _hasReceiverError(String? error) {
    if (error == null || error.isEmpty) return false;
    final normalized = error.toUpperCase();
    return normalized != 'NONE' && normalized != 'NO_ERROR' && normalized != '0';
  }

  static bool _isFresh(DateTime? receivedAt, DateTime now) {
    if (receivedAt == null) return false;
    final age = now.difference(receivedAt);
    return !age.isNegative && age <= maxDataAge;
  }
}
