import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/gnss_fix.dart';
import 'eov_service.dart';
import 'gnss/mfkrtk_provider.dart';

class ControlPointReference {
  final String projectId;
  final String layerId;
  final String layerName;
  final String featureId;
  final String pointId;
  final String pointName;
  final double referenceE;
  final double referenceN;
  final double? referenceHeight;
  final String? heightReference;
  final double latitude;
  final double longitude;
  final String sourceLabel;

  const ControlPointReference({
    required this.projectId,
    required this.layerId,
    required this.layerName,
    required this.featureId,
    required this.pointId,
    required this.pointName,
    required this.referenceE,
    required this.referenceN,
    required this.latitude,
    required this.longitude,
    required this.sourceLabel,
    this.referenceHeight,
    this.heightReference,
  });
}

class ControlPointEpoch {
  final DateTime timestamp;
  final double latitude;
  final double longitude;
  final double easting;
  final double northing;
  final double? ellipsoidalHeight;
  final double? orthometricHeight;
  final bool heightIsEllipsoidal;
  final String rtkStatus;
  final String fixType;
  final String insStatus;
  final String? positionType;
  final int satellites;
  final double horizontalAccuracy;
  final double verticalAccuracy;
  final double? heading;
  final double? roll;
  final double? pitch;

  const ControlPointEpoch({
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    required this.easting,
    required this.northing,
    required this.ellipsoidalHeight,
    this.orthometricHeight,
    required this.heightIsEllipsoidal,
    required this.rtkStatus,
    required this.fixType,
    required this.insStatus,
    required this.satellites,
    required this.horizontalAccuracy,
    required this.verticalAccuracy,
    this.positionType,
    this.heading,
    this.roll,
    this.pitch,
  });

  factory ControlPointEpoch.fromFix(GnssFix fix, EovService eov) {
    final projected = eov.wgsToEov(fix.latitude, fix.longitude);
    return ControlPointEpoch(
      timestamp: fix.timestamp,
      latitude: fix.latitude,
      longitude: fix.longitude,
      easting: projected[0],
      northing: projected[1],
      ellipsoidalHeight: fix.ellipsoidalHeight,
      orthometricHeight: fix.mslAltitude,
      heightIsEllipsoidal: fix.isEllipsoidal,
      rtkStatus: fix.rtkStatus.name.toUpperCase(),
      fixType: fix.fixType.name.toUpperCase(),
      insStatus: fix.insStatus ?? 'UNKNOWN',
      positionType: fix.positionSource,
      satellites: fix.satellitesUsed,
      horizontalAccuracy: fix.horizontalAccuracy,
      verticalAccuracy: fix.verticalAccuracy,
      heading: fix.heading,
      roll: fix.roll,
      pitch: fix.pitch,
    );
  }

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'latitude': latitude,
        'longitude': longitude,
        'easting': easting,
        'northing': northing,
        'ellipsoidalHeight': ellipsoidalHeight,
        'orthometricHeight': orthometricHeight,
        'heightIsEllipsoidal': heightIsEllipsoidal,
        'rtkStatus': rtkStatus,
        'fixType': fixType,
        'insStatus': insStatus,
        'positionType': positionType,
        'satellites': satellites,
        'horizontalAccuracy': horizontalAccuracy,
        'verticalAccuracy': verticalAccuracy,
        'heading': heading,
        'roll': roll,
        'pitch': pitch,
      };

  factory ControlPointEpoch.fromJson(Map<String, dynamic> json) => ControlPointEpoch(
        timestamp: DateTime.parse(json['timestamp'] as String),
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        easting: (json['easting'] as num).toDouble(),
        northing: (json['northing'] as num).toDouble(),
        ellipsoidalHeight: (json['ellipsoidalHeight'] as num?)?.toDouble(),
        orthometricHeight: (json['orthometricHeight'] as num?)?.toDouble(),
        heightIsEllipsoidal: json['heightIsEllipsoidal'] as bool? ?? true,
        rtkStatus: json['rtkStatus']?.toString() ?? 'UNKNOWN',
        fixType: json['fixType']?.toString() ?? 'UNKNOWN',
        insStatus: json['insStatus']?.toString() ?? 'UNKNOWN',
        positionType: json['positionType']?.toString(),
        satellites: (json['satellites'] as num?)?.toInt() ?? 0,
        horizontalAccuracy: (json['horizontalAccuracy'] as num?)?.toDouble() ?? 0,
        verticalAccuracy: (json['verticalAccuracy'] as num?)?.toDouble() ?? 0,
        heading: (json['heading'] as num?)?.toDouble(),
        roll: (json['roll'] as num?)?.toDouble(),
        pitch: (json['pitch'] as num?)?.toDouble(),
      );
}

class ControlPointMetrics {
  final int count;
  final double? meanE;
  final double? meanN;
  final double? medianE;
  final double? medianN;
  final double? meanDeltaE;
  final double? meanDeltaN;
  final double? rmseE;
  final double? rmseN;
  final double? meanError2d;
  final double? medianError2d;
  final double? rmse2d;
  final double? maxError2d;
  final double? percentile95Error2d;
  final double? meanHeight;
  final bool allFixed;
  final String rtkStatus;
  final String insStatus;
  final int meanSatellites;
  final double? meanHorizontalAccuracy;
  final double? meanVerticalAccuracy;

  const ControlPointMetrics({
    required this.count,
    this.meanE,
    this.meanN,
    this.medianE,
    this.medianN,
    this.meanDeltaE,
    this.meanDeltaN,
    this.rmseE,
    this.rmseN,
    this.meanError2d,
    this.medianError2d,
    this.rmse2d,
    this.maxError2d,
    this.percentile95Error2d,
    this.meanHeight,
    this.allFixed = false,
    this.rtkStatus = 'NO DATA',
    this.insStatus = 'NO DATA',
    this.meanSatellites = 0,
    this.meanHorizontalAccuracy,
    this.meanVerticalAccuracy,
  });

  factory ControlPointMetrics.calculate(
    List<ControlPointEpoch> epochs, {
    required double referenceE,
    required double referenceN,
  }) {
    if (epochs.isEmpty) return const ControlPointMetrics(count: 0);
    final es = epochs.map((e) => e.easting).toList();
    final ns = epochs.map((e) => e.northing).toList();
    final de = es.map((v) => v - referenceE).toList();
    final dn = ns.map((v) => v - referenceN).toList();
    final errors = List<double>.generate(epochs.length, (i) => math.sqrt(de[i] * de[i] + dn[i] * dn[i]));
    final fixedCount = epochs.where((e) => e.rtkStatus == 'FIXED').length;
    final goodInsCount = epochs.where((e) => e.insStatus == 'INS_SOLUTION_GOOD' || e.insStatus == 'INS_ALIGNMENT_COMPLETE').length;
    double mean(List<double> values) =>
        values.reduce((a, b) => a + b) / values.length;
    double median(List<double> values) {
      final sorted = List<double>.from(values)..sort();
      final mid = sorted.length ~/ 2;
      return sorted.length.isOdd ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
    }
    final sortedErrors = List<double>.from(errors)..sort();
    final p95Index = ((sortedErrors.length * .95).ceil() - 1).clamp(0, sortedErrors.length - 1);
    final rtk = fixedCount == epochs.length ? 'FIXED' : fixedCount > 0 ? 'MIXED' : epochs.any((e) => e.rtkStatus == 'FLOAT') ? 'FLOAT' : 'SINGLE';
    final ins = goodInsCount == epochs.length ? 'GOOD' : goodInsCount > 0 ? 'MIXED' : epochs.last.insStatus;
    final allFixed = fixedCount == epochs.length && goodInsCount == epochs.length;
    return ControlPointMetrics(
      count: epochs.length,
      meanE: mean(es),
      meanN: mean(ns),
      medianE: median(es),
      medianN: median(ns),
      meanDeltaE: mean(de),
      meanDeltaN: mean(dn),
      rmseE: math.sqrt(de.map((v) => v * v).reduce((a, b) => a + b) / de.length),
      rmseN: math.sqrt(dn.map((v) => v * v).reduce((a, b) => a + b) / dn.length),
      meanError2d: mean(errors),
      medianError2d: median(errors),
      rmse2d: math.sqrt(errors.map((v) => v * v).reduce((a, b) => a + b) / errors.length),
      maxError2d: sortedErrors.last,
      percentile95Error2d: sortedErrors[p95Index],
      meanHeight: mean(epochs.map((e) => e.ellipsoidalHeight).whereType<double>().toList()),
      allFixed: allFixed,
      rtkStatus: rtk,
      insStatus: ins,
      meanSatellites: mean(epochs.map((e) => e.satellites.toDouble()).toList()).round(),
      meanHorizontalAccuracy: mean(epochs.map((e) => e.horizontalAccuracy).toList()),
      meanVerticalAccuracy: mean(epochs.map((e) => e.verticalAccuracy).toList()),
    );
  }
}

class ControlPointMeasurementSession {
  final String id;
  final ControlPointReference reference;
  final DateTime startedAt;
  final DateTime endedAt;
  final int requestedDurationSeconds;
  final List<ControlPointEpoch> epochs;

  const ControlPointMeasurementSession({
    required this.id,
    required this.reference,
    required this.startedAt,
    required this.endedAt,
    required this.requestedDurationSeconds,
    required this.epochs,
  });

  Duration get duration => endedAt.difference(startedAt);
  ControlPointMetrics get metrics => ControlPointMetrics.calculate(
        epochs,
        referenceE: reference.referenceE,
        referenceN: reference.referenceN,
      );

  double? get deltaHeight {
    final referenceHeight = reference.referenceHeight;
    final kind = reference.heightReference;
    if (referenceHeight == null || kind == null || epochs.isEmpty) return null;
    final heights = kind == 'ellipsoidal'
        ? epochs.where((e) => e.heightIsEllipsoidal).map((e) => e.ellipsoidalHeight).whereType<double>().toList()
        : kind == 'orthometric'
            ? epochs.map((e) => e.orthometricHeight).whereType<double>().toList()
            : <double>[];
    if (heights.length != epochs.length) return null;
    final meanHeight = heights.reduce((a, b) => a + b) / heights.length;
    return meanHeight - referenceHeight;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'projectId': reference.projectId,
        'layerId': reference.layerId,
        'layerName': reference.layerName,
        'featureId': reference.featureId,
        'pointId': reference.pointId,
        'pointName': reference.pointName,
        'referenceE': reference.referenceE,
        'referenceN': reference.referenceN,
        'referenceHeight': reference.referenceHeight,
        'heightReference': reference.heightReference,
        'latitude': reference.latitude,
        'longitude': reference.longitude,
        'sourceLabel': reference.sourceLabel,
        'startedAt': startedAt.toIso8601String(),
        'endedAt': endedAt.toIso8601String(),
        'requestedDurationSeconds': requestedDurationSeconds,
        'epochs': epochs.map((e) => e.toJson()).toList(),
      };

  factory ControlPointMeasurementSession.fromJson(Map<String, dynamic> json) {
    final reference = ControlPointReference(
      projectId: json['projectId'] as String,
      layerId: json['layerId'] as String,
      layerName: json['layerName'] as String? ?? '',
      featureId: json['featureId'] as String,
      pointId: json['pointId'] as String,
      pointName: json['pointName'] as String,
      referenceE: (json['referenceE'] as num).toDouble(),
      referenceN: (json['referenceN'] as num).toDouble(),
      referenceHeight: (json['referenceHeight'] as num?)?.toDouble(),
      heightReference: json['heightReference'] as String?,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      sourceLabel: json['sourceLabel'] as String? ?? 'EOV geometry',
    );
    return ControlPointMeasurementSession(
      id: json['id'] as String,
      reference: reference,
      startedAt: DateTime.parse(json['startedAt'] as String),
      endedAt: DateTime.parse(json['endedAt'] as String),
      requestedDurationSeconds: (json['requestedDurationSeconds'] as num).toInt(),
      epochs: (json['epochs'] as List<dynamic>)
          .map((e) => ControlPointEpoch.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }
}

class ControlPointCheckService extends ChangeNotifier {
  final Map<String, List<ControlPointMeasurementSession>> _sessions = {};
  final List<ControlPointEpoch> _activeEpochs = [];
  StreamSubscription<GnssFix>? _fixSubscription;
  Timer? _timer;
  DateTime? _startedAt;
  ControlPointReference? _activeReference;
  int _requestedDurationSeconds = 30;
  bool _loaded = false;
  bool _isMeasuring = false;

  bool get isMeasuring => _isMeasuring;
  DateTime? get startedAt => _startedAt;
  int get requestedDurationSeconds => _requestedDurationSeconds;
  int get epochCount => _activeEpochs.length;
  ControlPointEpoch? get latestEpoch => _activeEpochs.isEmpty ? null : _activeEpochs.last;
  double get remainingSeconds {
    if (_startedAt == null) return 0;
    return math.max(0, _requestedDurationSeconds - DateTime.now().difference(_startedAt!).inMilliseconds / 1000);
  }

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/control_point_measurements.json');
      if (!await file.exists()) return;
      final decoded = jsonDecode(await file.readAsString()) as List<dynamic>;
      for (final value in decoded) {
        final session = ControlPointMeasurementSession.fromJson(Map<String, dynamic>.from(value as Map));
        _sessions.putIfAbsent(_key(session.reference.projectId, session.reference.featureId), () => []).add(session);
      }
    } catch (error) {
      debugPrint('[CONTROL POINT] Could not load saved sessions: $error');
    }
    notifyListeners();
  }

  List<ControlPointMeasurementSession> get allSessions =>
      List.unmodifiable(_sessions.values.expand((sessions) => sessions).toList());

  List<ControlPointMeasurementSession> sessionsFor(String projectId, String featureId) =>
      List.unmodifiable(_sessions[_key(projectId, featureId)] ?? const []);

  ControlPointMetrics metricsFor(ControlPointReference reference) {
    final epochs = sessionsFor(reference.projectId, reference.featureId)
        .expand((session) => session.epochs)
        .toList();
    return ControlPointMetrics.calculate(epochs, referenceE: reference.referenceE, referenceN: reference.referenceN);
  }

  Future<void> startMeasurement({
    required ControlPointReference reference,
    required MfkRtkProvider provider,
    required EovService eovService,
    required int durationSeconds,
  }) async {
    if (_isMeasuring) throw StateError('A measurement is already running.');
    await ensureLoaded();
    _activeEpochs.clear();
    _activeReference = reference;
    _requestedDurationSeconds = durationSeconds;
    _startedAt = DateTime.now();
    _isMeasuring = true;
    _fixSubscription = provider.fixStream.listen((fix) {
      if (!fix.isValidPosition) return;
      try {
        _activeEpochs.add(ControlPointEpoch.fromFix(fix, eovService));
        notifyListeners();
      } catch (error) {
        debugPrint('[CONTROL POINT] Ignored invalid epoch: $error');
      }
    }, onError: (Object error) {
      debugPrint('[CONTROL POINT] GNSS stream error: $error');
    });
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (remainingSeconds <= 0) {
        finishMeasurement();
      } else {
        notifyListeners();
      }
    });
    notifyListeners();
  }

  Future<void> finishMeasurement() async {
    if (!_isMeasuring) return;
    _timer?.cancel();
    _timer = null;
    _isMeasuring = false;
    await _fixSubscription?.cancel();
    _fixSubscription = null;
    final reference = _activeReference!;
    final session = ControlPointMeasurementSession(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      reference: reference,
      startedAt: _startedAt!,
      endedAt: DateTime.now(),
      requestedDurationSeconds: _requestedDurationSeconds,
      epochs: List.unmodifiable(_activeEpochs),
    );
    _sessions.putIfAbsent(_key(reference.projectId, reference.featureId), () => []).add(session);
    _activeReference = null;
    _startedAt = null;
    await _saveSessions();
    notifyListeners();
  }

  Future<void> _saveSessions() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/control_point_measurements.json');
      final all = _sessions.values.expand((sessions) => sessions).map((s) => s.toJson()).toList();
      await file.writeAsString(jsonEncode(all));
    } catch (error) {
      debugPrint('[CONTROL POINT] Could not save sessions: $error');
    }
  }

  static String _key(String projectId, String featureId) => '$projectId/$featureId';

  @override
  void dispose() {
    _timer?.cancel();
    _fixSubscription?.cancel();
    super.dispose();
  }
}
