import 'package:flutter_test/flutter_test.dart';
import 'package:mfk_geomeasure/models/gnss_fix.dart';
import 'package:mfk_geomeasure/models/gnss/mfkrtk_nav_data.dart';
import 'package:mfk_geomeasure/models/gnss/mfkrtk_readiness.dart';
import 'package:mfk_geomeasure/models/gnss/mfkrtk_status.dart';

void main() {
  final now = DateTime.utc(2026, 10, 21, 12);

  GnssFix fix({
    GnssFixType fixType = GnssFixType.rtk,
    RtkStatus rtkStatus = RtkStatus.fixed,
    String? insStatus = 'INS_SOLUTION_GOOD',
    double? heading = 120,
  }) =>
      GnssFix(
        latitude: 47,
        longitude: 19,
        altitude: 100,
        isEllipsoidal: true,
        fixType: fixType,
        rtkStatus: rtkStatus,
        insStatus: insStatus,
        heading: heading,
        positionSource: 'NARROW_INT',
        source: GnssSource.external,
        connectionType: GnssConnectionType.mfkrtk,
        timestamp: now,
      );

  MfkRtkNavData nav({
    String insAlign = 'INS_SOLUTION_GOOD',
    String posType = 'NARROW_INT',
    bool valid = true,
    bool rtcmOk = true,
    int rtcmAgeMs = 250,
    double? azimuth = 120,
    String? autoInsState,
    String? alignmentMode,
    bool? alignmentTrialRequested,
    bool? alignmentTrialCommandRejected,
    String? autoInsError,
    String? insAlignFull,
    bool? measurementReady,
  }) =>
      MfkRtkNavData(
        valid: valid,
        insAlign: insAlign,
        posType: posType,
        rtcmOk: rtcmOk,
        rtcmAgeMs: rtcmAgeMs,
        azimuth: azimuth,
        autoInsState: autoInsState,
        alignmentMode: alignmentMode,
        alignmentTrialRequested: alignmentTrialRequested,
        alignmentTrialCommandRejected: alignmentTrialCommandRejected,
        autoInsError: autoInsError,
        insAlignFull: insAlignFull,
        measurementReady: measurementReady,
      );

  MfkRtkMeasurementState evaluate({
    MfkRtkNavData? navData,
    DateTime? navAt,
    MfkRtkStatus? status,
    DateTime? statusAt,
    GnssFix? currentFix,
    DateTime? fixAt,
    bool connected = true,
  }) =>
      MfkRtkReadiness.evaluate(
        connected: connected,
        nav: navData,
        navReceivedAt: navAt,
        status: status,
        statusReceivedAt: statusAt,
        fix: currentFix ?? fix(),
        fixReceivedAt: fixAt ?? now,
        now: now,
      );

  group('MFKRTK measurement readiness', () {
    test('requires fresh RTK FIX, RTCM, heading, and INS_SOLUTION_GOOD', () {
      expect(
        evaluate(navData: nav(), navAt: now),
        MfkRtkMeasurementState.readyToMeasure,
      );
    });

    test('rejects a NAV_DATA message older than the freshness window', () {
      expect(
        evaluate(
          navData: nav(),
          navAt: now.subtract(MfkRtkReadiness.maxDataAge + const Duration(milliseconds: 1)),
        ),
        MfkRtkMeasurementState.waitingRtk,
      );
    });

    test('rejects a stale RTK fix even when receiver status remains good', () {
      expect(
        evaluate(
          navData: nav(),
          navAt: now,
          fixAt: now.subtract(MfkRtkReadiness.maxDataAge + const Duration(milliseconds: 1)),
        ),
        MfkRtkMeasurementState.waitingRtk,
      );
    });

    test('requires explicit and recent RTCM correction age', () {
      expect(
        evaluate(navData: nav(rtcmAgeMs: 3001), navAt: now),
        MfkRtkMeasurementState.rtcmLost,
      );
      expect(
        evaluate(navData: nav(rtcmAgeMs: -1), navAt: now),
        MfkRtkMeasurementState.waitingRtk,
      );
    });

    test('keeps alignment complete distinct from fine INS solution', () {
      expect(
        evaluate(navData: nav(insAlign: 'INS_ALIGNMENT_COMPLETE'), navAt: now),
        MfkRtkMeasurementState.insAlignmentComplete,
      );
    });

    test('does not treat a missing heading as zero degrees', () {
      expect(
        evaluate(navData: nav(azimuth: null), navAt: now, currentFix: fix(heading: null)),
        MfkRtkMeasurementState.waitingHeading,
      );
    });

    test('rejects DEVICE_STATUS after it exceeds the freshness window', () {
      final status = MfkRtkStatus(
        firmwareVersion: 'test',
        batteryVoltage: 3.8,
        batteryPercentage: 60,
        bleConnected: true,
        otaState: 'IDLE',
        insAlign: 'INS_SOLUTION_GOOD',
        posType: 'NARROW_INT',
        rtcmOk: true,
        rtcmAgeMs: 10,
      );
      expect(
        evaluate(
          status: status,
          statusAt: now.subtract(
            MfkRtkReadiness.maxDataAge + const Duration(milliseconds: 1),
          ),
        ),
        MfkRtkMeasurementState.waitingRtk,
      );
    });

    test('ALIGN_TRIAL fails closed even when raw INS reports solution good', () {
      expect(
        evaluate(
          navData: nav(
            insAlign: 'ALIGN_TRIAL_UNVERIFIED',
            alignmentMode: 'ALIGN_TRIAL_EXPERIMENTAL',
            insAlignFull: 'INS_SOLUTION_GOOD',
            measurementReady: false,
          ),
          navAt: now,
        ),
        MfkRtkMeasurementState.insSolutionUnverified,
      );
      expect(
        evaluate(
          navData: nav(
            insAlign: 'INS_SOLUTION_GOOD',
            alignmentMode: 'ALIGN_TRIAL_EXPERIMENTAL',
            measurementReady: true,
          ),
          navAt: now,
        ),
        MfkRtkMeasurementState.insSolutionUnverified,
      );
    });

    test('explicit measurement_ready false blocks measurement', () {
      expect(
        evaluate(navData: nav(measurementReady: false), navAt: now),
        MfkRtkMeasurementState.autoInsConfiguring,
      );
    });

    test('receiver error and rejected trial command fail closed', () {
      expect(
        evaluate(navData: nav(autoInsError: 'ALIGNMENT_FAILED'), navAt: now),
        MfkRtkMeasurementState.configurationError,
      );
      expect(
        evaluate(
          navData: nav(alignmentTrialCommandRejected: true),
          navAt: now,
        ),
        MfkRtkMeasurementState.configurationError,
      );
    });

    test('reports automatic initialization while it is running', () {
      expect(
        evaluate(
          navData: nav(
            autoInsState: 'ALIGN_TRIAL_RUNNING',
            insAlign: 'INS_ALIGNING',
          ),
          navAt: now,
        ),
        MfkRtkMeasurementState.autoInsTrial,
      );
      expect(
        evaluate(navData: nav(autoInsState: 'CONFIGURING'), navAt: now),
        MfkRtkMeasurementState.autoInsConfiguring,
      );
    });

    test('parses automatic alignment fields from NAV_DATA JSON', () {
      final parsed = MfkRtkNavData.fromJson({
        'auto_ins_state': 'ALIGN_TRIAL_RUNNING',
        'alignment_mode': 'ALIGN_TRIAL_EXPERIMENTAL',
        'alignment_trial_requested': true,
        'alignment_trial_command_rejected': false,
        'auto_ins_error': '',
        'ins_align': 'ALIGN_TRIAL_UNVERIFIED',
        'ins_align_full': 'INS_SOLUTION_GOOD',
        'measurement_ready': false,
      });

      expect(parsed.autoInsState, 'ALIGN_TRIAL_RUNNING');
      expect(parsed.alignmentMode, 'ALIGN_TRIAL_EXPERIMENTAL');
      expect(parsed.alignmentTrialRequested, isTrue);
      expect(parsed.alignmentTrialCommandRejected, isFalse);
      expect(parsed.autoInsError, '');
      expect(parsed.insAlign, 'ALIGN_TRIAL_UNVERIFIED');
      expect(parsed.insAlignFull, 'INS_SOLUTION_GOOD');
      expect(parsed.measurementReady, isFalse);
    });

    test('requires an RTK fixed solution and valid navigation data', () {
      expect(
        evaluate(navData: nav(), navAt: now, currentFix: fix(rtkStatus: RtkStatus.float)),
        MfkRtkMeasurementState.waitingRtk,
      );
      expect(
        evaluate(navData: nav(valid: false), navAt: now),
        MfkRtkMeasurementState.waitingRtk,
      );
    });

    test('does not retain missing INS and RTCM fields from an older status', () {
      final previous = MfkRtkStatus(
        firmwareVersion: 'test',
        batteryVoltage: 3.8,
        batteryPercentage: 60,
        bleConnected: true,
        otaState: 'IDLE',
        insAlign: 'INS_SOLUTION_GOOD',
        posType: 'NARROW_INT',
        rtcmOk: true,
        rtcmAgeMs: 10,
      );
      final partial = MfkRtkStatus.fromJson(
        {'battery_percent': 59},
        previousStatus: previous,
      );

      expect(partial.batteryPercentage, 59);
      expect(partial.insAlign, isNull);
      expect(partial.posType, isNull);
      expect(partial.rtcmOk, isNull);
      expect(partial.rtcmAgeMs, isNull);
    });
  });
}
