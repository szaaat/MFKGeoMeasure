import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:raw_gnss/raw_gnss.dart';
import 'package:raw_gnss/gnss_status_model.dart';
import 'raw_gnss_logger.dart';
import '../models/gnss_fix.dart';
import 'gnss/gnss_provider.dart';
import 'gnss/internal_gnss_provider.dart';
import 'gnss/external_gnss_provider.dart';
import 'gnss/mfkrtk_provider.dart';
import 'gnss/mfkrtk_diagnostics_logger.dart';
import 'gnss/rtcm_service.dart';
import '../models/gnss/mfkrtk_status.dart';
import '../models/gnss/mfkrtk_nav_data.dart';
import 'gnss/mfkrtk_ota_service.dart';
import 'geoid_service.dart';
import '../models/ntrip_settings.dart';
import '../models/ntrip_profile.dart';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'kalman_service.dart';
import 'eov_service.dart';
import 'package:latlong2/latlong.dart';

enum MfkRtkMeasurementState {
  waitingRtk,
  waitingInsAlign,
  readyToMeasure,
  rtcmLost,
}

class GnssStatusData {
  final int satellitesInView;
  final int satellitesUsedInFix;
  final double? pdop;
  final double qualityScore; // 0-100%
  final List<Status> satellites;

  GnssStatusData({
    this.satellitesInView = 0,
    this.satellitesUsedInFix = 0,
    this.pdop,
    this.qualityScore = 0.0,
    this.satellites = const [],
  });
}

class DiagnosticEpochRecord {
  final int epochId;
  final DateTime timestamp;
  final String source;
  final double rawLat;
  final double rawLon;
  final double rawAlt;
  final double hAcc;
  final double vAcc;
  final String fixType;
  final String rtkStatus;
  final int satsUsed;
  final String insStatus;
  final bool accepted;
  final String rejectReason;
  final bool kalmanEnabled;
  final bool kalmanInitialized;
  final double kalmanInputLat;
  final double kalmanInputLon;
  final double kalmanOutputLat;
  final double kalmanOutputLon;
  final double kalmanDistance;
  final double rawEovY;
  final double rawEovX;
  final double kalmanEovY;
  final double kalmanEovX;
  final Map<String, dynamic>? kalmanDiagnostic;

  DiagnosticEpochRecord({
    required this.epochId,
    required this.timestamp,
    required this.source,
    required this.rawLat,
    required this.rawLon,
    required this.rawAlt,
    required this.hAcc,
    required this.vAcc,
    required this.fixType,
    required this.rtkStatus,
    required this.satsUsed,
    required this.insStatus,
    required this.accepted,
    required this.rejectReason,
    required this.kalmanEnabled,
    required this.kalmanInitialized,
    required this.kalmanInputLat,
    required this.kalmanInputLon,
    required this.kalmanOutputLat,
    required this.kalmanOutputLon,
    required this.kalmanDistance,
    required this.rawEovY,
    required this.rawEovX,
    required this.kalmanEovY,
    required this.kalmanEovX,
    this.kalmanDiagnostic,
  });

  Map<String, dynamic> toJson() => {
    'epoch_id': epochId,
    'timestamp': timestamp.toIso8601String(),
    'source': source,
    'raw_lat': rawLat,
    'raw_lon': rawLon,
    'raw_alt': rawAlt,
    'h_acc': hAcc,
    'v_acc': vAcc,
    'fix_type': fixType,
    'rtk_status': rtkStatus,
    'sats_used': satsUsed,
    'ins_status': insStatus,
    'accepted': accepted,
    'reject_reason': rejectReason,
    'kalman_enabled': kalmanEnabled,
    'kalman_initialized': kalmanInitialized,
    'kalman_input_lat': kalmanInputLat,
    'kalman_input_lon': kalmanInputLon,
    'kalman_output_lat': kalmanOutputLat,
    'kalman_output_lon': kalmanOutputLon,
    'kalman_distance_m': kalmanDistance,
    'raw_eov_y': rawEovY,
    'raw_eov_x': rawEovX,
    'kalman_eov_y': kalmanEovY,
    'kalman_eov_x': kalmanEovX,
    'kalman_diagnostic': kalmanDiagnostic,
  };

  String toCsvRow() =>
      '${timestamp.toIso8601String()},$epochId,$source,$rawLat,$rawLon,$rawAlt,$hAcc,$vAcc,'
      '$fixType,$rtkStatus,$satsUsed,$insStatus,$accepted,"$rejectReason",$kalmanEnabled,'
      '$kalmanInitialized,$kalmanInputLat,$kalmanInputLon,$kalmanOutputLat,$kalmanOutputLon,'
      '${kalmanDistance.toStringAsFixed(4)},${rawEovY.toStringAsFixed(3)},${rawEovX.toStringAsFixed(3)},'
      '${kalmanEovY.toStringAsFixed(3)},${kalmanEovX.toStringAsFixed(3)}';
}

class DiagnosticCaptureSummary {
  final int totalEpochs;
  final int rtkFixEpochs;
  final int rejectedEpochs;
  final int insRejectedEpochs;
  final double meanRawToKalmanShift;
  final double maxRawToKalmanShift;
  final double decayAt0s;
  final double decayAt5s;
  final double decayAt10s;
  final double decayAt20s;
  final double decayAt30s;
  final String csvPath;
  final String jsonPath;

  DiagnosticCaptureSummary({
    required this.totalEpochs,
    required this.rtkFixEpochs,
    required this.rejectedEpochs,
    required this.insRejectedEpochs,
    required this.meanRawToKalmanShift,
    required this.maxRawToKalmanShift,
    required this.decayAt0s,
    required this.decayAt5s,
    required this.decayAt10s,
    required this.decayAt20s,
    required this.decayAt30s,
    required this.csvPath,
    required this.jsonPath,
  });
}

class GnssInfoService extends ChangeNotifier {
  GnssStatusData _currentStatus = GnssStatusData();
  StreamSubscription? _rawGnssSubscription;
  StreamSubscription? _fixSubscription;
  StreamSubscription? _ggaSubscription;
  StreamSubscription? _mfkStatusSubscription;
  StreamSubscription? _mfkNavSubscription;
  StreamSubscription? _mfkConfigSubscription;
  StreamSubscription? _mfkConnectionSubscription;
  Timer? _mfkReconnectTimer;
  bool _mfkReconnectInProgress = false;
  int _mfkReconnectAttempt = 0;
  bool _mfkConnected = false;
  MfkRtkStatus? _lastMfkRtkStatus;
  MfkRtkNavData? _lastMfkNavData;
  String? _rtcmAlert;
  String? _lastMfkConfigMessage;
  bool _rtcmAlertDismissed = false;
  
  // Note: Internal status monitoring for Android still uses RawGnss directly for now
  // until GnssProvider is fully extended for status unification.
  final _rawGnss = RawGnss();
  final RawGnssLogger rawLogger = RawGnssLogger();
  final EovService _eovService =
      EovService(null, false, EovInputFrame.unknown, EovTransformMode.bmeAssumed);
  
  GnssProvider? _activeProvider;
  GnssFix? _lastFix;
  GnssFix? _lastRawFix;
  double _kalmanDistance = 0.0;
  GnssSource? _lastSource;
  DateTime? _kalmanLastUpdateTime;
  bool _positionValid = false;
  bool _kalmanInitialized = false;

  int _epochSequence = 0;
  RtkStatus? _lastRtkStatus;

  // 30s Capture State
  bool _is30sCapturing = false;
  int _captureRemainingSeconds = 0;
  Timer? _captureTimer;
  final List<DiagnosticEpochRecord> _capturedEpochs = [];
  DiagnosticCaptureSummary? _lastCaptureSummary;

  bool get is30sCapturing => _is30sCapturing;
  int get captureRemainingSeconds => _captureRemainingSeconds;
  List<DiagnosticEpochRecord> get capturedEpochs => List.unmodifiable(_capturedEpochs);
  DiagnosticCaptureSummary? get lastCaptureSummary => _lastCaptureSummary;
  
  // Developer diagnostics (Bypassed for production, RAW M21 used directly)
  bool enableKalmanFilter = false;
  final GpsKalmanFilter _kalmanFilter = GpsKalmanFilter();
  
  final _fixStreamController = StreamController<GnssFix>.broadcast();
  final _secureStorage = const FlutterSecureStorage();
  
  NtripSettings _ntripSettings = NtripSettings();
  NtripSettings get ntripSettings => _ntripSettings;

  // Stability logic
  final Stopwatch _rtkStabilityStopwatch = Stopwatch();
  bool _isStableRtkFix = false;
  int _providerGeneration = 0;
  bool get isStableRtkFix => _isStableRtkFix;
  double get currentFixStabilityDuration => _rtkStabilityStopwatch.elapsedMilliseconds / 1000.0;

  // Getterek
  GnssStatusData get currentStatus => _currentStatus;
  GnssProvider? get activeProvider => _activeProvider;
  GnssFix? get lastFix => _lastFix;
  GnssFix? get lastRawFix => _lastRawFix;
  double get kalmanDistance => _kalmanDistance;
  DateTime? get kalmanLastUpdateTime => _kalmanLastUpdateTime;
  bool get isPositionValid => _positionValid;
  bool get isKalmanInitialized => _kalmanInitialized;
  MfkRtkStatus? get mfkRtkStatus => _lastMfkRtkStatus ?? (_activeProvider is MfkRtkProvider ? (_activeProvider as MfkRtkProvider).lastStatus : null);
  MfkRtkNavData? get mfkRtkNavData => _lastMfkNavData ?? (_activeProvider is MfkRtkProvider ? (_activeProvider as MfkRtkProvider).lastNavData : null);
  MfkRtkRtcmStatus? get mfkRtkRtcmStatus => _activeProvider is MfkRtkProvider ? (_activeProvider as MfkRtkProvider).lastRtcmStatus : null;
  String? get rtcmAlert => _rtcmAlertDismissed ? null : _rtcmAlert;
  String? get lastMfkConfigMessage => _lastMfkConfigMessage;
  bool get isMfkRtkActive => _activeProvider is MfkRtkProvider;
  bool get isMfkRtkConnected => !isMfkRtkActive || _mfkConnected;
  Stream<GnssFix> get fixStream => _fixStreamController.stream;

  MfkRtkMeasurementState get mfkRtkMeasurementState {
    if (!isMfkRtkActive) return MfkRtkMeasurementState.readyToMeasure;
    if (!_mfkConnected) return MfkRtkMeasurementState.waitingRtk;
    final nav = mfkRtkNavData;
    final status = mfkRtkStatus;
    if (nav == null && status == null) return MfkRtkMeasurementState.waitingRtk;

    final rtcmOk = nav?.rtcmOk ?? status?.rtcmOk ?? false;
    if (!rtcmOk) return MfkRtkMeasurementState.rtcmLost;

    final posType = (nav?.posType ?? status?.posType ?? _lastFix?.positionSource ?? '').toUpperCase();
    if (posType != 'NARROW_INT') return MfkRtkMeasurementState.waitingRtk;

    if (nav != null && !nav.valid) return MfkRtkMeasurementState.waitingRtk;
    final alignment = (nav?.insAlign ?? status?.insAlign ?? _lastFix?.insStatus ?? '').toUpperCase();
    if (alignment == 'INS_SOLUTION_GOOD' || alignment == 'INS_ALIGNMENT_COMPLETE') {
      return MfkRtkMeasurementState.readyToMeasure;
    }
    if (alignment == 'WAITING_AZIMUTH' || alignment == 'WAITING_INITIALPOS') {
      return MfkRtkMeasurementState.waitingInsAlign;
    }
    return MfkRtkMeasurementState.waitingRtk;
  }

  void dismissRtcmAlert() {
    _rtcmAlertDismissed = true;
    notifyListeners();
  }

  GnssInfoService(GeoidCorrectionService geoidService) {
    _loadSettings();
    // Alapértelmezett a belső GPS
    setProvider(InternalGnssProvider(geoidService: geoidService));
    
    if (Platform.isAndroid) {
      _initRawGnssListener();
    }
    rawLogger.addListener(notifyListeners);
    
    // Stability checker loop
    Timer.periodic(const Duration(milliseconds: 500), (timer) {
      final bool requirementActive = _ntripSettings.requireStableFix && _activeProvider is! InternalGnssProvider;
      
      if (requirementActive) {
        final wasStable = _isStableRtkFix;
        _isStableRtkFix = _lastFix?.fixType == GnssFixType.rtk && 
                         _lastFix?.rtkStatus == RtkStatus.fixed &&
                         _rtkStabilityStopwatch.elapsed.inSeconds >= _ntripSettings.stabilityThresholdSeconds;
        if (wasStable != _isStableRtkFix) notifyListeners();
      } else {
        if (!_isStableRtkFix) {
          _isStableRtkFix = true;
          notifyListeners();
        }
      }
    });
  }

  Future<void> setProvider(GnssProvider provider,
      {RtcmService? rtcmService}) async {
    final generation = ++_providerGeneration;
    final previousProvider = _activeProvider;

    // Stop the previous source completely before allowing a new source to
    // publish fixes. This prevents stale async callbacks during rapid
    // receiver switching.
    await _fixSubscription?.cancel();
    await _ggaSubscription?.cancel();
    await _mfkStatusSubscription?.cancel();
    await _mfkNavSubscription?.cancel();
    await _mfkConfigSubscription?.cancel();
    await _mfkConnectionSubscription?.cancel();
    _mfkReconnectTimer?.cancel();
    _mfkReconnectTimer = null;
    _mfkReconnectInProgress = false;
    _mfkReconnectAttempt = 0;
    _fixSubscription = null;
    _ggaSubscription = null;
    _mfkStatusSubscription = null;
    _mfkNavSubscription = null;
    _mfkConfigSubscription = null;
    await previousProvider?.disconnect();
    previousProvider?.dispose();
    if (generation != _providerGeneration) {
      provider.dispose();
      return;
    }

    _lastMfkRtkStatus = null;
    _lastMfkNavData = null;
    _lastRtkStatus = null;
    _rtcmAlert = null;
    _rtcmAlertDismissed = false;
    
    // Explicitly wipe out all old states to prevent cross-source leakage 
    // and guarantee the new source starts completely fresh.
    _lastFix = null;
    _lastRawFix = null;
    _lastSource = null;
    _kalmanFilter.reset();
    _kalmanLastUpdateTime = null;
    _positionValid = false;
    _kalmanInitialized = false;
    debugPrint('[MFKRTK][KALMAN] event=RESET');
    
    // Detach logger
    MfkRtkDiagnosticsLogger().detach();
    
    _rtkStabilityStopwatch.stop();
    _rtkStabilityStopwatch.reset();
    _isStableRtkFix = false; 
    
    _activeProvider = provider;
    _mfkConnected = provider is! MfkRtkProvider;
    
    // Attach logger and OTA service if MFKRTK
    if (_activeProvider is MfkRtkProvider) {
       final mfkProvider = _activeProvider as MfkRtkProvider;
       MfkRtkDiagnosticsLogger().attach(mfkProvider);
       MfkRtkOtaService().attach(mfkProvider);
    } else {
       MfkRtkOtaService().detach();
    }
    
    _fixSubscription = provider.fixStream.listen((fix) {
      if (generation != _providerGeneration ||
          !identical(_activeProvider, provider)) {
        return;
      }
      _epochSequence++;
      final currentEpochId = _epochSequence;
      final now = DateTime.now();

      // Track RTK status transitions
      if (_lastRtkStatus != fix.rtkStatus) {
        debugPrint('[MFKRTK][RTK STATE CHANGE] previous=${_lastRtkStatus?.name} current=${fix.rtkStatus.name}');
        if (_lastRtkStatus != RtkStatus.fixed && fix.rtkStatus == RtkStatus.fixed) {
          final distToPrev = _lastFix != null
              ? const Distance().as(LengthUnit.Meter, LatLng(fix.latitude, fix.longitude), LatLng(_lastFix!.latitude, _lastFix!.longitude))
              : 0.0;
          debugPrint('[MFKRTK][FIX ACQUIRED] epoch=$currentEpochId raw_lat=${fix.latitude} raw_lon=${fix.longitude} kalman_lat_before=${_lastFix?.latitude} kalman_lon_before=${_lastFix?.longitude} dist_raw_to_prev_kalman=${distToPrev.toStringAsFixed(4)}m kalman_initialized=$_kalmanInitialized source=${fix.source.name}');
        }
        _lastRtkStatus = fix.rtkStatus;
      }

      _lastRawFix = fix;

      if (_lastSource != fix.source) {
        _kalmanFilter.reset();
        _lastSource = fix.source;
        _positionValid = false;
        _kalmanInitialized = false;
        debugPrint('[MFKRTK][KALMAN] event=RESET source_changed');
      }

      final bool isValid = fix.isValidPosition;
      final String rejectReason = isValid ? '' : 'NO_FIX';

      if (!isValid) {
        debugPrint('[MFKRTK][REJECT] epoch=$currentEpochId reason=NO_FIX');
        _positionValid = false;
      } else {
        _positionValid = true;
      }

      double outputLat = fix.latitude;
      double outputLon = fix.longitude;

      if (isValid && enableKalmanFilter) {
        if (!_kalmanInitialized) {
          debugPrint('[MFKRTK][KALMAN] event=INITIALIZED epoch=$currentEpochId lat=${fix.latitude} lon=${fix.longitude}');
          _kalmanInitialized = true;
        }

        _kalmanLastUpdateTime = now;
        final filtered = _kalmanFilter.filter(fix.latitude, fix.longitude, fix.horizontalAccuracy);
        outputLat = filtered[0];
        outputLon = filtered[1];

        const distanceCalc = Distance();
        _kalmanDistance = distanceCalc.as(LengthUnit.Meter, LatLng(fix.latitude, fix.longitude), LatLng(outputLat, outputLon));
      } else {
        _kalmanDistance = 0.0;
      }

      // Authoritative position in production is ALWAYS the RAW M21 fix directly
      _lastFix = fix;

      // Compute EOV coordinates for RAW vs KALMAN
      final frame = fix.referenceFrame == GnssReferenceFrame.etrf2000
          ? EovInputFrame.etrf2000
          : EovInputFrame.unknown;
      final rawEov = _eovService.transformWgsToEov(
        fix.latitude,
        fix.longitude,
        sourceFrame: frame,
      );
      final kalmanEov = _eovService.transformWgsToEov(
        outputLat,
        outputLon,
        sourceFrame: frame,
      );
      MfkRtkDiagnosticsLogger().recordEvent('app_fix_calculation', {
        'source': fix.source.name,
        'latitude': fix.latitude,
        'longitude': fix.longitude,
        'source_altitude': fix.altitude,
        'ellipsoidal_height': fix.ellipsoidalHeight,
        'is_ellipsoidal': fix.isEllipsoidal,
        'reference_frame': fix.referenceFrame.name,
        'fix_type': fix.fixType.name,
        'rtk_status': fix.rtkStatus.name,
        'ins_status': fix.insStatus,
        'satellites': fix.satellitesUsed,
        'raw_eov_status': rawEov.status.name,
        'raw_eov': rawEov.coordinates,
        'kalman_eov_status': kalmanEov.status.name,
        'kalman_eov': kalmanEov.coordinates,
      });

      // Detailed Pipeline Log for every M21 epoch
      if (_kalmanFilter.lastDiagnostic != null) {
        final latDiag = _kalmanFilter.lastDiagnostic!.latStep;
        final lonDiag = _kalmanFilter.lastDiagnostic!.lonStep;
        debugPrint('[PIPELINE_EPOCH #$currentEpochId] RAW=(${fix.latitude}, ${fix.longitude}) KALMAN=($outputLat, $outputLon) SHIFT=${_kalmanDistance.toStringAsFixed(4)}m RAW_EOV=${rawEov.coordinates ?? rawEov.status.name} KALMAN_EOV=${kalmanEov.coordinates ?? kalmanEov.status.name} K_LAT=${latDiag.kalmanGain.toStringAsFixed(6)} K_LON=${lonDiag.kalmanGain.toStringAsFixed(6)}');
      }

      // Record to 30s capture list if capturing
      if (_is30sCapturing) {
        _capturedEpochs.add(DiagnosticEpochRecord(
          epochId: currentEpochId,
          timestamp: now,
          source: fix.source.name,
          rawLat: fix.latitude,
          rawLon: fix.longitude,
          rawAlt: fix.altitude,
          hAcc: fix.horizontalAccuracy,
          vAcc: fix.verticalAccuracy,
          fixType: fix.fixType.name,
          rtkStatus: fix.rtkStatus.name,
          satsUsed: fix.satellitesUsed,
          insStatus: fix.insStatus ?? 'N/A',
          accepted: isValid,
          rejectReason: rejectReason,
          kalmanEnabled: enableKalmanFilter,
          kalmanInitialized: _kalmanInitialized,
          kalmanInputLat: fix.latitude,
          kalmanInputLon: fix.longitude,
          kalmanOutputLat: outputLat,
          kalmanOutputLon: outputLon,
          kalmanDistance: _kalmanDistance,
          rawEovY: rawEov.coordinates?[0] ?? 0.0,
          rawEovX: rawEov.coordinates?[1] ?? 0.0,
          kalmanEovY: kalmanEov.coordinates?[0] ?? 0.0,
          kalmanEovX: kalmanEov.coordinates?[1] ?? 0.0,
          kalmanDiagnostic: _kalmanFilter.lastDiagnostic?.toJson(),
        ));
      }

      if (isValid) {
        _updateFromFix(_lastFix!);
        _fixStreamController.add(_lastFix!);
      }

      notifyListeners();
    });
    
    if (_activeProvider is ExternalGnssProvider) {
      _ggaSubscription = (_activeProvider as ExternalGnssProvider).ggaStream.listen((gga) {
        rtcmService?.updateGga(gga);
      });
    } else if (_activeProvider is MfkRtkProvider) {
      final mfk = _activeProvider as MfkRtkProvider;
      _ggaSubscription = mfk.ggaStream.listen((gga) {
        rtcmService?.updateGga(gga);
      });
      _mfkStatusSubscription = mfk.statusStream.listen((status) {
        _lastMfkRtkStatus = status;
        notifyListeners();
      });
      _mfkNavSubscription = mfk.navDataStream.listen((nav) {
        _lastMfkNavData = nav;
        notifyListeners();
      });
      _mfkConfigSubscription = mfk.configMessageStream.listen(_handleMfkConfigMessage);
      _mfkConnectionSubscription = mfk.connectionStatus.listen((connected) {
        if (generation != _providerGeneration ||
            !identical(_activeProvider, provider)) {
          return;
        }
        if (connected) {
          _mfkConnected = true;
          _mfkReconnectTimer?.cancel();
          _mfkReconnectTimer = null;
          _mfkReconnectInProgress = false;
          _mfkReconnectAttempt = 0;
          notifyListeners();
        } else {
          _mfkConnected = false;
          _handleMfkConnectionLost(mfk, generation);
        }
      });
    }

    if (_activeProvider is ExternalGnssProvider || _activeProvider is MfkRtkProvider) {
      final active = _ntripSettings.activeProfile;
      if (_ntripSettings.enabled && active != null && rtcmService != null) {
        if (active.host.isNotEmpty && active.port > 0 && active.mountpoint.isNotEmpty) {
          _secureStorage.read(key: 'ntrip_pwd_${active.id}').then((pwd) {
            rtcmService.startNtrip(
              host: active.host,
              port: active.port,
              mountpoint: active.mountpoint,
              username: active.username,
              password: pwd,
              ggaInterval: active.ggaInterval,
              targetProvider: _activeProvider!,
            );
          });
        }
      }
    } else {
      rtcmService?.stopNtrip();
    }
    
    try {
      await provider.connect();
      if (!identical(_activeProvider, provider)) {
        await provider.disconnect();
      }
    } catch (e) {
      if (identical(_activeProvider, provider)) {
        debugPrint("Provider connection error: $e");
      }
    }
    
    notifyListeners();
  }

  // --- Profile Management ---

  Future<void> start30sCapture() async {
    if (_is30sCapturing) return;
    _is30sCapturing = true;
    _captureRemainingSeconds = 30;
    _capturedEpochs.clear();
    _lastCaptureSummary = null;
    notifyListeners();

    _captureTimer?.cancel();
    _captureTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      _captureRemainingSeconds--;
      notifyListeners();

      if (_captureRemainingSeconds <= 0) {
        _captureTimer?.cancel();
        _is30sCapturing = false;
        await _finish30sCapture();
        notifyListeners();
      }
    });
  }

  Future<void> _finish30sCapture() async {
    if (_capturedEpochs.isEmpty) return;

    final now = DateTime.now();
    final timeStr = "${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}";

    final dir = await getApplicationDocumentsDirectory();
    final csvPath = '${dir.path}/MFKRTK_DIAGNOSTIC_$timeStr.csv';
    final jsonPath = '${dir.path}/MFKRTK_DIAGNOSTIC_$timeStr.json';

    final csvBuffer = StringBuffer();
    csvBuffer.writeln('timestamp,epoch_id,source,raw_lat,raw_lon,raw_alt,h_acc,v_acc,fix_type,rtk_status,sats_used,ins_status,accepted,reject_reason,kalman_enabled,kalman_initialized,kalman_input_lat,kalman_input_lon,kalman_output_lat,kalman_output_lon,kalman_distance_m,raw_eov_y,raw_eov_x,kalman_eov_y,kalman_eov_x');

    for (var rec in _capturedEpochs) {
      csvBuffer.writeln(rec.toCsvRow());
    }

    await File(csvPath).writeAsString(csvBuffer.toString());
    await File(jsonPath).writeAsString(jsonEncode(_capturedEpochs.map((e) => e.toJson()).toList()));

    final rtkFixEpochs = _capturedEpochs.where((e) => e.rtkStatus.toLowerCase() == 'fixed').length;
    final rejectedEpochs = _capturedEpochs.where((e) => !e.accepted).length;
    final insRejectedEpochs = _capturedEpochs.where((e) => e.insStatus.toUpperCase().contains('NOT') || e.insStatus.toUpperCase().contains('ALIGN') || e.insStatus.toUpperCase().contains('WAITING')).length;

    final shifts = _capturedEpochs.map((e) => e.kalmanDistance).toList();
    final meanShift = shifts.isNotEmpty ? shifts.reduce((a, b) => a + b) / shifts.length : 0.0;
    final maxShift = shifts.isNotEmpty ? shifts.reduce((a, b) => a > b ? a : b) : 0.0;

    double getShiftAtSec(int sec) {
      if (_capturedEpochs.isEmpty) return 0.0;
      final targetTime = _capturedEpochs.first.timestamp.add(Duration(seconds: sec));
      final rec = _capturedEpochs.firstWhere(
        (e) => e.timestamp.isAfter(targetTime) || e.timestamp.isAtSameMomentAs(targetTime),
        orElse: () => _capturedEpochs.last,
      );
      return rec.kalmanDistance;
    }

    _lastCaptureSummary = DiagnosticCaptureSummary(
      totalEpochs: _capturedEpochs.length,
      rtkFixEpochs: rtkFixEpochs,
      rejectedEpochs: rejectedEpochs,
      insRejectedEpochs: insRejectedEpochs,
      meanRawToKalmanShift: meanShift,
      maxRawToKalmanShift: maxShift,
      decayAt0s: getShiftAtSec(0),
      decayAt5s: getShiftAtSec(5),
      decayAt10s: getShiftAtSec(10),
      decayAt20s: getShiftAtSec(20),
      decayAt30s: getShiftAtSec(30),
      csvPath: csvPath,
      jsonPath: jsonPath,
    );

    try {
      await Share.shareXFiles([XFile(csvPath), XFile(jsonPath)], text: 'MFKRTK 30s Diagnostic Capture Data');
    } catch (e) {
      debugPrint('[MFKRTK] Share diagnostic files failed: $e');
    }
  }

  Future<void> saveProfile(NtripProfile profile, String? password) async {
    final index = _ntripSettings.profiles.indexWhere((p) => p.id == profile.id);
    if (index != -1) {
      _ntripSettings.profiles[index] = profile;
    } else {
      _ntripSettings.profiles = [..._ntripSettings.profiles, profile];
    }
    
    if (password != null) {
      await _secureStorage.write(key: 'ntrip_pwd_${profile.id}', value: password);
    }
    
    await _saveSettings();
    notifyListeners();
  }

  Future<void> deleteProfile(String profileId) async {
    _ntripSettings.profiles.removeWhere((p) => p.id == profileId);
    if (_ntripSettings.activeProfileId == profileId) {
      _ntripSettings.activeProfileId = null;
    }
    await _secureStorage.delete(key: 'ntrip_pwd_$profileId');
    await _saveSettings();
    notifyListeners();
  }

  void setActiveProfile(String? profileId, {RtcmService? rtcmService}) {
    _ntripSettings.activeProfileId = profileId;
    _saveSettings();
    
    if (rtcmService != null) {
       updateNtripSettings(_ntripSettings, rtcmService: rtcmService);
    } else {
       notifyListeners();
    }
  }

  void updateNtripSettings(NtripSettings settings, {RtcmService? rtcmService}) {
    _ntripSettings = settings;
    _saveSettings();
    
    final active = _ntripSettings.activeProfile;
    final isExternal = _activeProvider is ExternalGnssProvider || _activeProvider is MfkRtkProvider;
    if (isExternal && _ntripSettings.enabled && rtcmService != null && active != null) {
      if (active.host.isNotEmpty && active.port > 0 && active.mountpoint.isNotEmpty) {
         _secureStorage.read(key: 'ntrip_pwd_${active.id}').then((pwd) {
            rtcmService.startNtrip(
              host: active.host,
              port: active.port,
              mountpoint: active.mountpoint,
              username: active.username,
              password: pwd,
              ggaInterval: active.ggaInterval,
              targetProvider: _activeProvider!,
            );
         });
      }
    } else {
      rtcmService?.stopNtrip();
    }
    notifyListeners();
  }

  void _handleMfkConnectionLost(
    MfkRtkProvider provider,
    int generation,
  ) {
    _lastFix = null;
    _lastRawFix = null;
    _positionValid = false;
    _kalmanFilter.reset();
    _kalmanInitialized = false;
    _rtkStabilityStopwatch.stop();
    _isStableRtkFix = false;
    _lastMfkConfigMessage = 'M21 BLE kapcsolat megszakadt';
    notifyListeners();

    if (_mfkReconnectTimer != null || _mfkReconnectInProgress) return;
    final delaySeconds = (2 * (1 << _mfkReconnectAttempt.clamp(0, 4)))
        .clamp(2, 30)
        .toInt();
    _mfkReconnectTimer = Timer(Duration(seconds: delaySeconds), () async {
      _mfkReconnectTimer = null;
      if (generation != _providerGeneration ||
          !identical(_activeProvider, provider)) {
        return;
      }
      _mfkReconnectInProgress = true;
      _mfkReconnectAttempt++;
      try {
        await provider.reconnect();
        if (generation == _providerGeneration &&
            identical(_activeProvider, provider)) {
          debugPrint(
              '[MFKRTK] BLE reconnect succeeded after attempt $_mfkReconnectAttempt');
        }
      } catch (e) {
        debugPrint(
            '[MFKRTK] BLE reconnect failed on attempt $_mfkReconnectAttempt: $e');
        _mfkReconnectInProgress = false;
        _handleMfkConnectionLost(provider, generation);
        return;
      }
      _mfkReconnectInProgress = false;
    });
  }

  void _handleMfkConfigMessage(String message) {
    _lastMfkConfigMessage = message;
    if (message == 'RTCM_TIMEOUT') {
      _rtcmAlert = 'RTK korrekció megszakadt! Ellenőrizd az NTRIP kapcsolatot.';
      _rtcmAlertDismissed = false;
    } else if (message == 'RTCM_RECOVERED') {
      _rtcmAlert = null;
      _rtcmAlertDismissed = false;
    }
    notifyListeners();
  }

  bool get allowFloatSave => _ntripSettings.allowFloatSave;

  Future<void> setAllowFloatSave(bool value) async {
    _ntripSettings.allowFloatSave = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('allowFloatSave', value);
    } catch (e) {
      debugPrint("Error saving allowFloatSave to SharedPreferences: $e");
    }
    await _saveSettings();
  }

  Future<void> _saveSettings() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/gnss_settings.json');
    await file.writeAsString(jsonEncode(_ntripSettings.toJson()));
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.containsKey('allowFloatSave')) {
        _ntripSettings.allowFloatSave = prefs.getBool('allowFloatSave') ?? true;
      }
    } catch (e) {
      debugPrint("Error loading SharedPreferences allowFloatSave: $e");
    }

    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/gnss_settings.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        _ntripSettings = NtripSettings.fromJson(jsonDecode(content));
        
        // Handle legacy single password migration if needed
        final legacyPwd = await _secureStorage.read(key: 'ntrip_password');
        if (legacyPwd != null && _ntripSettings.activeProfileId == 'default_legacy') {
           await _secureStorage.write(key: 'ntrip_pwd_default_legacy', value: legacyPwd);
           await _secureStorage.delete(key: 'ntrip_password');
        }
        
        notifyListeners();
      }
    } catch (e) {
      debugPrint("Error loading GNSS settings: $e");
    }
  }

  void _updateFromFix(GnssFix fix) {
    // Stability tracking
    if (fix.fixType == GnssFixType.rtk && fix.rtkStatus == RtkStatus.fixed) {
      if (!_rtkStabilityStopwatch.isRunning) _rtkStabilityStopwatch.start();
    } else {
      _rtkStabilityStopwatch.stop();
      _rtkStabilityStopwatch.reset();
    }

    if (fix.source == GnssSource.external) {
       _currentStatus = GnssStatusData(
        satellitesInView: fix.satellitesInView,
        satellitesUsedInFix: fix.satellitesUsed,
        pdop: fix.pdop,
        qualityScore: _calculateQuality(fix.horizontalAccuracy, 0.0, fix.satellitesUsed),
        satellites: _currentStatus.satellites,
      );
    } else {
      _currentStatus = GnssStatusData(
        satellitesInView: _currentStatus.satellitesInView,
        satellitesUsedInFix: _currentStatus.satellitesUsedInFix,
        pdop: _currentStatus.pdop,
        qualityScore: _calculateQuality(fix.horizontalAccuracy, 0.0, _currentStatus.satellitesUsedInFix),
        satellites: _currentStatus.satellites,
      );
    }
  }

  double _calculateQuality(double accuracy, double speed, int sats) {
    double score = 0;
    score += max(0, 40 - (accuracy * 4));
    score += min(40, max(0, (sats - 4) * 5));
    score += max(0, 20 - (speed * 10));
    return score.clamp(0.0, 100.0);
  }

  void updateQuality(double accuracy, double speed) {
    _currentStatus = GnssStatusData(
      satellitesInView: _currentStatus.satellitesInView,
      satellitesUsedInFix: _currentStatus.satellitesUsedInFix,
      pdop: _currentStatus.pdop,
      qualityScore: _calculateQuality(accuracy, speed, _currentStatus.satellitesUsedInFix),
      satellites: _currentStatus.satellites,
    );
    notifyListeners();
  }

  void _initRawGnssListener() {
    try {
      _rawGnssSubscription = _rawGnss.gnssStatusEvents.listen((GnssStatusModel model) {
        if (model.status != null) {
          int inView = model.status!.length;
          int used = model.status!.where((sat) => sat.usedInFix == true).length;
          
          _currentStatus = GnssStatusData(
            satellitesInView: inView,
            satellitesUsedInFix: used,
            pdop: _currentStatus.pdop,
            qualityScore: _currentStatus.qualityScore,
            satellites: model.status!,
          );
          notifyListeners();
        }
      }, onError: (e) {
        debugPrint("Error in GNSS listener: $e");
      });
    } catch (e) {
      debugPrint("Failed to initialize GNSS diagnostics: $e");
    }
  }

  @override
  void dispose() {
    _mfkReconnectTimer?.cancel();
    _rawGnssSubscription?.cancel();
    _fixSubscription?.cancel();
    _ggaSubscription?.cancel();
    _mfkStatusSubscription?.cancel();
    _mfkNavSubscription?.cancel();
    _mfkConfigSubscription?.cancel();
    _mfkConnectionSubscription?.cancel();
    _activeProvider?.dispose();
    _fixStreamController.close();
    rawLogger.removeListener(notifyListeners);
    super.dispose();
  }
}
