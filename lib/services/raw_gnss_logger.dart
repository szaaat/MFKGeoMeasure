import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:latlong2/latlong.dart';
import '../models/gnss_raw_measurement.dart';

class RawGnssLogSession {
  final String id;
  final String name;
  final DateTime startTime;
  DateTime? endTime;
  double antennaHeight;
  LatLng? approximatePosition;
  String? notes;

  RawGnssLogSession({
    required this.id,
    required this.name,
    required this.startTime,
    this.antennaHeight = 0.0,
    this.approximatePosition,
    this.notes,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'startTime': startTime.toIso8601String(),
    'endTime': endTime?.toIso8601String(),
    'antennaHeight': antennaHeight,
    'approxLat': approximatePosition?.latitude,
    'approxLon': approximatePosition?.longitude,
    'notes': notes,
  };
}

class RawGnssLogger extends ChangeNotifier {
  StreamSubscription? _measurementSub;
  File? _logFile;
  File? _metaFile;
  RawGnssLogSession? _currentSession;
  bool _isLogging = false;

  bool get isLogging => _isLogging;
  RawGnssLogSession? get currentSession => _currentSession;

  Future<void> startSession({
    required String name,
    required double antennaHeight,
    required Stream<GnssRawMeasurement> rawStream,
    LatLng? approxPosition,
    String? notes,
  }) async {
    if (_isLogging) await stopSession();

    final now = DateTime.now();
    final sessionId = "ppk_${now.millisecondsSinceEpoch}";

    _currentSession = RawGnssLogSession(
      id: sessionId,
      name: name,
      startTime: now,
      antennaHeight: antennaHeight,
      approximatePosition: approxPosition,
      notes: notes,
    );

    final dir = await getApplicationDocumentsDirectory();
    final basePath = '${dir.path}/ppk_logs/$sessionId';

    await Directory(basePath).create(recursive: true);

    _logFile = File('$basePath/raw_observations.log');
    _metaFile = File('$basePath/session_meta.json');

    // Fejléc
    await _logFile!.writeAsString(
      '# PPK Raw GNSS Log\n'
      '# Session: $sessionId\n'
      '# Start: ${now.toIso8601String()}\n'
      'timestamp,svid,constellation,accumulatedDeltaRangeMeters,accumulatedDeltaRangeState,'
      'receivedSvTimeNanos,cn0DbHz,carrierFrequencyHz,timeOffsetNanos,multipathIndicator\n',
    );

    // Metaadat mentése
    await _metaFile!.writeAsString(jsonEncode(_currentSession!.toJson()));

    _measurementSub = rawStream.listen((m) {
      final ts = m.timestamp.toIso8601String();

      final line = '$ts,${m.svid},${m.constellationType},${m.accumulatedDeltaRangeMeters ?? ""},'
          '${m.accumulatedDeltaRangeState ?? ""},${m.receivedSvTimeNanos ?? ""},${m.cn0DbHz ?? ""},'
          '${m.carrierFrequencyHz ?? ""},${m.timeOffsetNanos ?? ""},${m.multipathIndicator ?? ""}\n';
      
      _logFile!.writeAsString(line, mode: FileMode.append);
    });

    _isLogging = true;
    notifyListeners();
  }

  Future<void> stopSession() async {
    await _measurementSub?.cancel();
    if (_currentSession != null) {
      _currentSession!.endTime = DateTime.now();
      await _metaFile?.writeAsString(jsonEncode(_currentSession!.toJson()));
    }
    _isLogging = false;
    notifyListeners();
  }

  Future<List<Directory>> getAllLogFolders() async {
    final dir = await getApplicationDocumentsDirectory();
    final ppkDir = Directory('${dir.path}/ppk_logs');
    if (!await ppkDir.exists()) return [];
    return ppkDir.listSync().whereType<Directory>().toList();
  }
}
