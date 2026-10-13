import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../models/gnss_fix.dart';
import '../../models/gnss_raw_measurement.dart';
import '../../models/gnss/mfkrtk_constants.dart';
import '../../models/gnss/mfkrtk_status.dart';
import '../../models/gnss/mfkrtk_nav_data.dart';
import 'gnss_provider.dart';
import 'ble_transport.dart';
import 'nmea_parser.dart';
import 'bynav_parser.dart';

class MfkRtkProvider implements GnssProvider {
  final BleTransport _transport;
  final NmeaParser _nmeaParser = NmeaParser();
  final BynavParser _bynavParser = BynavParser();

  final _fixController = StreamController<GnssFix>.broadcast();
  final _ggaController = StreamController<String>.broadcast();
  final _rawController = StreamController<List<int>>.broadcast();
  final _statusController = StreamController<MfkRtkStatus>.broadcast();
  final _navDataController = StreamController<MfkRtkNavData>.broadcast();
  final _configMessageController = StreamController<String>.broadcast();
  final _diagnosticEventController = StreamController<Map<String, dynamic>>.broadcast();
  final Map<int, _M21LogChunkBuffer> _m21LogChunks = {};

  StreamSubscription? _dataSubscription;
  StreamSubscription? _statusSubscription;
  StreamSubscription? _navDataSubscription;
  StreamSubscription? _configSubscription;

  final List<int> _rxBuffer = [];
  String _statusStringBuffer = '';
  String _navStringBuffer = '';
  String _configStringBuffer = '';
  MfkRtkStatus? _lastStatus;
  MfkRtkNavData? _lastNavData;
  MfkRtkRtcmStatus? _lastRtcmStatus;
  bool _rtcmForwardingPausedForOta = false;

  // Metadata cache from Bynav high-rate and enrichment logs
  double? _lastHorizAcc;
  double? _lastVertAcc;
  String? _lastPosType;
  String? _lastInsStatus;
  double? _lastHeading;
  double? _lastPitch;
  double? _lastRoll;
  int? _lastSatsUsed;
  double? _lastCorrectionAge;

  // GPS epoch deduplication tracking
  int? _lastEmittedWeek;
  double? _lastEmittedSeconds;

  MfkRtkProvider({required BleTransport transport}) : _transport = transport;

  BleTransport get transport => _transport;

  @override
  Stream<GnssFix> get fixStream => _fixController.stream;

  @override
  Stream<List<int>> get rawStream => _rawController.stream;

  @override
  Stream<GnssRawMeasurement> get rawMeasurementStream => const Stream.empty();

  Stream<MfkRtkStatus> get statusStream => _statusController.stream;
  Stream<MfkRtkNavData> get navDataStream => _navDataController.stream;
  Stream<String> get configMessageStream => _configMessageController.stream;
  Stream<Map<String, dynamic>> get diagnosticEventStream =>
      _diagnosticEventController.stream;
  Stream<bool> get connectionStatus => _transport.connectionStatus;
  MfkRtkStatus? get lastStatus => _lastStatus;
  MfkRtkNavData? get lastNavData => _lastNavData;
  MfkRtkRtcmStatus? get lastRtcmStatus => _lastRtcmStatus;

  /// Stream a beérkező nyers GGA mondatokról (NTRIP feedbackhez)
  Stream<String> get ggaStream => _ggaController.stream;

  @override
  bool get supportsRtcmInput => true;

  @override
  Future<void> connect() async {
    debugPrint('[MFKRTK] Connecting via BLE...');
    await _dataSubscription?.cancel();
    await _statusSubscription?.cancel();
    await _navDataSubscription?.cancel();
    await _configSubscription?.cancel();

    // 🔴 1. csatlakozunk ELŐBB
    await _transport.connect();

    // 🔴 csatlakozás UTÁN iratkozunk fel a karakterisztikákra
    _dataSubscription = _transport.dataStream.listen(_processIncomingBytes);
    _statusSubscription = _transport
        .getExtraStream(
          MfkRtkConstants.deviceStatusUuid,
          serviceUuid: MfkRtkConstants.serviceUuid,
        )
        .listen(_processStatusBytes);
    _navDataSubscription = _transport
        .getExtraStream(
          MfkRtkConstants.navDataUuid,
          serviceUuid: MfkRtkConstants.serviceUuid,
        )
        .listen(_processNavDataBytes);
    _configSubscription = _transport
        .getExtraStream(
          MfkRtkConstants.configUuid,
          serviceUuid: MfkRtkConstants.serviceUuid,
        )
        .listen(_processConfigBytes);
  }

  /// Re-establishes the BLE link after the receiver reboots at the end of OTA.
  Future<void> reconnectForOta() async {
    await _dataSubscription?.cancel();
    _dataSubscription = null;
    await _statusSubscription?.cancel();
    _statusSubscription = null;
    await _navDataSubscription?.cancel();
    _navDataSubscription = null;
    await _configSubscription?.cancel();
    _configSubscription = null;
    await _transport.disconnect();
    await connect();
  }

  Future<void> reconnect() async {
    await disconnect();
    await connect();
  }

  void setRtcmForwardingPausedForOta(bool paused) {
    _rtcmForwardingPausedForOta = paused;
    debugPrint(
        '[MFKRTK] RTCM forwarding ${paused ? 'paused' : 'resumed'} for OTA');
  }

  @override
  Future<void> disconnect() async {
    await _dataSubscription?.cancel();
    await _statusSubscription?.cancel();
    await _navDataSubscription?.cancel();
    await _configSubscription?.cancel();
    await _transport.disconnect();
  }

  // 🟢 6. sendConfigCommand() — TX log
  Future<void> sendConfigCommand(String command) async {
    debugPrint('[MFKRTK] TX CONFIG: $command');
    _diagnosticEventController.add({
      'event': 'config_tx',
      'command': command,
    });
    await _transport.writeExtra(
      MfkRtkConstants.configUuid,
      utf8.encode(command),
      serviceUuid: MfkRtkConstants.serviceUuid,
    );
  }

  // 🟢 5. setHeading() — validáció + log
  Future<void> setHeading(double degrees) async {
    if (!degrees.isFinite) {
      throw ArgumentError('Heading must be finite');
    }
    if (degrees < 0 || degrees > 360) {
      throw RangeError.range(degrees, 0, 360, 'degrees');
    }
    final cmd = 'SET_HEADING:${degrees.toStringAsFixed(1)}';
    debugPrint('[MFKRTK] TX CONFIG: $cmd');
    await sendConfigCommand(cmd);
  }

  Future<void> restartIns() {
    debugPrint('[MFKRTK] TX CONFIG: INS_RESTART');
    return sendConfigCommand('INS_RESTART');
  }

  Future<void> getRtcmStatus() {
    debugPrint('[MFKRTK] TX CONFIG: GET_RTCM_STATUS');
    return sendConfigCommand('GET_RTCM_STATUS');
  }

  Future<void> reconfigureM21() {
    debugPrint('[MFKRTK] TX CONFIG: M21_CONFIGURE_INS');
    return sendConfigCommand('M21_CONFIGURE_INS');
  }

  Future<void> saveM21Config() {
    debugPrint('[MFKRTK] TX CONFIG: M21_SAVE_CONFIG');
    return sendConfigCommand('M21_SAVE_CONFIG');
  }

  // 🔴 2. sendCorrectionData() — explicit RTCM UUID + withoutResponse
  @override
  void sendCorrectionData(List<int> data) {
    if (_rtcmForwardingPausedForOta || !_transport.isConnected) return;
    _diagnosticEventController.add({
      'event': 'rtcm_tx',
      'bytes': data.length,
      'data_base64': base64Encode(data),
    });
    _transport.writeExtra(
      MfkRtkConstants.rtcmInputUuid,
      data,
      withoutResponse: true,
      serviceUuid: MfkRtkConstants.serviceUuid,
    );
  }

  @override
  void dispose() {
    disconnect();
    _configStringBuffer = '';
    _statusStringBuffer = '';
    _navStringBuffer = '';
    _fixController.close();
    _ggaController.close();
    _rawController.close();
    _statusController.close();
    _navDataController.close();
    _configMessageController.close();
    _diagnosticEventController.close();
    _m21LogChunks.clear();
    _transport.dispose();
  }

  void _processIncomingBytes(List<int> data) {
    // 1. Forward everything to raw stream immediately
    _rawController.add(data);

    // 2. Add to RX buffer and extract complete frames
    _rxBuffer.addAll(data);
    _extractFrames();

    if (_rxBuffer.length > 8192) {
      _rxBuffer.removeRange(0, _rxBuffer.length - 2048);
    }
  }

  void _extractFrames() {
    while (true) {
      // Find start of frame: '$' (NMEA), '#' (Bynav long/ext header), '%' (Bynav short header)
      int startIdx = -1;
      for (int i = 0; i < _rxBuffer.length; i++) {
        final b = _rxBuffer[i];
        if (b == 0x24 || b == 0x23 || b == 0x25) {
          // '$', '#', '%'
          startIdx = i;
          break;
        }
      }

      if (startIdx == -1) {
        _rxBuffer.clear();
        break;
      }

      if (startIdx > 0) {
        _rxBuffer.removeRange(0, startIdx);
        startIdx = 0;
      }

      // Find line ending: '\r\n' or '\n'
      int endIdx = -1;
      int lineEndLength = 1;
      for (int i = 0; i < _rxBuffer.length; i++) {
        if (_rxBuffer[i] == 0x0A) {
          // '\n'
          if (i > 0 && _rxBuffer[i - 1] == 0x0D) {
            // '\r\n'
            endIdx = i - 1;
            lineEndLength = 2;
          } else {
            endIdx = i;
            lineEndLength = 1;
          }
          break;
        }
      }

      if (endIdx != -1) {
        List<int> frame = _rxBuffer.sublist(0, endIdx);
        _rxBuffer.removeRange(0, endIdx + lineEndLength);

        try {
          String line = utf8.decode(frame, allowMalformed: true).trim();
          if (line.isNotEmpty) {
            _processLine(line);
          }
        } catch (_) {}
      } else {
        break;
      }
    }
  }

  void _processLine(String line) {
    if (line.startsWith('#') || line.startsWith('%')) {
      final solution = _bynavParser.parse(line);
      if (solution != null) {
        _handleBynavSolution(solution);
      }
    } else if (line.startsWith('\$')) {
      _handleNmeaSentence(line);
    } else if (line.startsWith('{')) {
      try {
        final decoded = jsonDecode(line);
        if (decoded is Map<String, dynamic>) {
          if (decoded.containsKey('battery_percent') ||
              decoded.containsKey('battery_percentage') ||
              decoded.containsKey('bat_p') ||
              decoded.containsKey('bat_pct') ||
              decoded.containsKey('battery_pct') ||
              decoded.containsKey('battery_level') ||
              decoded.containsKey('bat_level') ||
              decoded.containsKey('bat') ||
              decoded.containsKey('battery') ||
              decoded.containsKey('soc') ||
              decoded.containsKey('charge') ||
              decoded.containsKey('level') ||
              decoded.containsKey('battery_voltage') ||
              decoded.containsKey('battery_v') ||
              decoded.containsKey('bat_v') ||
              decoded.containsKey('v_bat') ||
              decoded.containsKey('vbat') ||
              decoded.containsKey('v_batt') ||
              decoded.containsKey('voltage') ||
              decoded.containsKey('volts') ||
              decoded.containsKey('firmware') ||
              decoded.containsKey('fw_ver') ||
              decoded.containsKey('fw')) {
            _lastStatus =
                MfkRtkStatus.fromJson(decoded, previousStatus: _lastStatus);
            _statusController.add(_lastStatus!);
          } else if (decoded.containsKey('v') ||
              decoded.containsKey('ins_align') ||
              decoded.containsKey('pos_type')) {
            _lastNavData = MfkRtkNavData.fromJson(decoded);
            _navDataController.add(_lastNavData!);
          }
        }
      } catch (e) {
        debugPrint('[MFKRTK] JSON line parse error: $e');
      }
    }
  }

  void _handleBynavSolution(BynavNavSolution sol) {
    // 1. Always update metadata caches from Bynav messages
    if (sol.heading != null) _lastHeading = sol.heading;
    if (sol.pitch != null) _lastPitch = sol.pitch;
    if (sol.roll != null) _lastRoll = sol.roll;
    if (sol.insStatus != null) _lastInsStatus = sol.insStatus;
    if (sol.posType != null) _lastPosType = sol.posType;
    if (sol.satellitesUsed != null) _lastSatsUsed = sol.satellitesUsed;
    if (sol.correctionAge != null) _lastCorrectionAge = sol.correctionAge;

    // 2. Update accuracy cache if available (e.g. from INSPVAXA or BESTPOSA)
    if (sol.horizontalAccuracy != null) _lastHorizAcc = sol.horizontalAccuracy;
    if (sol.verticalAccuracy != null) _lastVertAcc = sol.verticalAccuracy;

    // Check epoch deduplication
    final bool isSameEpoch = (sol.gpsWeek != null &&
        sol.gpsSeconds != null &&
        sol.gpsWeek == _lastEmittedWeek &&
        (sol.gpsSeconds! - (_lastEmittedSeconds ?? -1.0)).abs() < 0.01);

    if (isSameEpoch) return;

    if (sol.latitude == 0.0 && sol.longitude == 0.0) return;

    final isEllipsoidal = sol.isEllipsoidalHeight;
    final ellipsoidalHeight =
        isEllipsoidal ? sol.altitude : sol.altitude + (sol.undulation ?? 0.0);
    final fix = GnssFix(
      latitude: sol.latitude,
      longitude: sol.longitude,
      altitude: sol.altitude,
      ellipsoidalHeight: ellipsoidalHeight,
      isEllipsoidal: isEllipsoidal,
      geoidSeparation: sol.undulation,
      mslAltitude: isEllipsoidal && sol.undulation != null
          ? sol.altitude - sol.undulation!
          : sol.altitude,
      horizontalAccuracy: sol.horizontalAccuracy ?? _lastHorizAcc ?? 0.0,
      verticalAccuracy: sol.verticalAccuracy ?? _lastVertAcc ?? 0.0,
      fixType: _mapPosTypeToFixType(sol.posType ?? _lastPosType),
      rtkStatus: _mapPosTypeToRtkStatus(sol.posType ?? _lastPosType),
      satellitesUsed: sol.satellitesUsed ?? _lastSatsUsed ?? 0,
      correctionAge: sol.correctionAge ?? _lastCorrectionAge,
      heading: sol.heading ?? _lastHeading,
      pitch: sol.pitch ?? _lastPitch,
      roll: sol.roll ?? _lastRoll,
      insStatus: sol.insStatus ?? _lastInsStatus,
      positionSource: sol.posType ?? _lastPosType ?? sol.messageName,
      source: GnssSource.external,
      receiverName: "MFKRTK",
      connectionType: GnssConnectionType.ble,
      timestamp: DateTime.now(),
      referenceFrame: GnssReferenceFrame.unknown,
    );

    _lastEmittedWeek = sol.gpsWeek;
    _lastEmittedSeconds = sol.gpsSeconds;
    _fixController.add(fix);
  }

  void _handleNmeaSentence(String sentence) {
    if (sentence.contains('GGA')) {
      _ggaController.add(sentence);
    }

    // If INS is GOOD or BESTPOSA fix was already emitted, don't emit tertiary NMEA position fix
    if (_lastInsStatus == 'INS_SOLUTION_GOOD') return;

    final fix = _nmeaParser.parse(sentence,
        source: GnssSource.external, connectionType: GnssConnectionType.ble);

    if (fix != null) {
      final enrichedFix = GnssFix(
        latitude: fix.latitude,
        longitude: fix.longitude,
        altitude: fix.altitude,
        ellipsoidalHeight: fix.ellipsoidalHeight,
        isEllipsoidal: fix.isEllipsoidal,
        mslAltitude: fix.mslAltitude,
        geoidSeparation: fix.geoidSeparation,
        horizontalAccuracy: _lastHorizAcc ?? fix.horizontalAccuracy,
        verticalAccuracy: _lastVertAcc ?? fix.verticalAccuracy,
        fixType: fix.fixType,
        rtkStatus: fix.rtkStatus,
        satellitesUsed:
            fix.satellitesUsed > 0 ? fix.satellitesUsed : (_lastSatsUsed ?? 0),
        satellitesInView: fix.satellitesInView,
        pdop: fix.pdop,
        hdop: fix.hdop,
        vdop: fix.vdop,
        correctionAge: fix.correctionAge ?? _lastCorrectionAge,
        stationId: fix.stationId,
        heading: _lastHeading,
        pitch: _lastPitch,
        roll: _lastRoll,
        insStatus: _lastInsStatus,
        positionSource: _lastPosType ?? 'NMEA',
        source: fix.source,
        receiverName: "MFKRTK",
        connectionType: GnssConnectionType.ble,
        timestamp: fix.timestamp,
        timestampSource: fix.timestampSource,
        referenceFrame: fix.referenceFrame,
        referenceEpoch: fix.referenceEpoch,
      );
      _fixController.add(enrichedFix);
    }
  }

  void _processNavDataBytes(List<int> bytes) {
    try {
      _navStringBuffer += utf8.decode(bytes, allowMalformed: true);
      while (true) {
        final start = _navStringBuffer.indexOf('{');
        if (start < 0) {
          _navStringBuffer = '';
          return;
        }
        if (start > 0) _navStringBuffer = _navStringBuffer.substring(start);
        var depth = 0;
        var end = -1;
        for (var i = 0; i < _navStringBuffer.length; i++) {
          if (_navStringBuffer[i] == '{') depth++;
          if (_navStringBuffer[i] == '}') {
            depth--;
            if (depth == 0) {
              end = i;
              break;
            }
          }
        }
        if (end < 0) break;
        final candidate = _navStringBuffer.substring(0, end + 1);
        _navStringBuffer = _navStringBuffer.substring(end + 1);
        final decoded = jsonDecode(candidate);
        if (decoded is Map<String, dynamic>) {
          _lastNavData = MfkRtkNavData.fromJson(decoded);
          _navDataController.add(_lastNavData!);

          if (_lastNavData!.batteryPercentage != null &&
              _lastNavData!.batteryPercentage! > 0) {
            _lastStatus = MfkRtkStatus(
              firmwareVersion: _lastStatus?.firmwareVersion ?? 'Unknown',
              batteryVoltage: _lastNavData!.batteryVoltage ??
                  _lastStatus?.batteryVoltage ??
                  0.0,
              batteryPercentage: _lastNavData!.batteryPercentage!,
              bleConnected: true,
              otaState: _lastStatus?.otaState ?? 'IDLE',
              insAlign: _lastNavData!.insAlign,
              posType: _lastNavData!.posType,
              rtcmOk: _lastNavData!.rtcmOk,
              rtcmAgeMs: _lastNavData!.rtcmAgeMs,
              rtcmBytes: _lastNavData!.rtcmBytes,
              rtcmPkts: _lastNavData!.rtcmPkts,
            );
            _statusController.add(_lastStatus!);
          }
        }
      }
      if (_navStringBuffer.length > 8192) _navStringBuffer = '';
    } catch (error) {
      debugPrint('[MFKRTK] NAV_DATA parse error: $error');
      _navStringBuffer = '';
    }
  }

  // 🟡 3. _processConfigBytes() — brace-counting buffer
  void _processConfigBytes(List<int> bytes) {
    _configStringBuffer += utf8.decode(bytes, allowMalformed: true);

    while (true) {
      final startIdx = _configStringBuffer.indexOf('{');
      if (startIdx < 0) {
        // Nem-JSON — soronként küldd tovább
        final lines = _configStringBuffer.split(RegExp(r'[\r\n]+'));
        if (lines.length > 1) {
          for (var i = 0; i < lines.length - 1; i++) {
            final msg = lines[i].trim();
            if (msg.isEmpty) continue;
            debugPrint('[MFKRTK] CONFIG RX: $msg');
            _configMessageController.add(msg);
          }
          _configStringBuffer = lines.last;
        }
        break;
      }

      if (startIdx > 0) {
        final prefix = _configStringBuffer.substring(0, startIdx);
        for (final line in prefix.split(RegExp(r'[\r\n]+'))) {
          final msg = line.trim();
          if (msg.isEmpty) continue;
          debugPrint('[MFKRTK] CONFIG RX: $msg');
          _configMessageController.add(msg);
        }
        _configStringBuffer = _configStringBuffer.substring(startIdx);
      }

      final endIdx = _findJsonEnd(_configStringBuffer);
      if (endIdx < 0) break;

      final jsonStr = _configStringBuffer.substring(0, endIdx + 1);
      _configStringBuffer = _configStringBuffer.substring(endIdx + 1);

      try {
        _handleConfigJson(jsonDecode(jsonStr));
      } catch (e) {
        debugPrint('[MFKRTK] CONFIG JSON parse error: $e');
      }
    }
  }

  int _findJsonEnd(String value) {
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var i = 0; i < value.length; i++) {
      final char = value[i];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (char == '\\' && inString) {
        escaped = true;
        continue;
      }
      if (char == '"') {
        inString = !inString;
        continue;
      }
      if (inString) continue;
      if (char == '{') {
        depth++;
      } else if (char == '}' && --depth == 0) {
        return i;
      }
    }
    return -1;
  }

  void _handleConfigJson(dynamic decoded) {
    if (decoded is! Map<String, dynamic>) return;
    final type = decoded['type']?.toString();

    if (type == 'm21_rx_chunk') {
      final messageId = (decoded['message_id'] as num?)?.toInt();
      final chunk = (decoded['chunk'] as num?)?.toInt();
      final total = (decoded['total'] as num?)?.toInt();
      final data = decoded['data']?.toString();
      if (messageId == null ||
          chunk == null ||
          total == null ||
          data == null ||
          total <= 0 ||
          chunk < 0 ||
          chunk >= total) {
        return;
      }
      final buffer = _m21LogChunks.putIfAbsent(
        messageId,
        () => _M21LogChunkBuffer(total),
      );
      buffer.parts[chunk] = data;
      if (buffer.parts.length == total) {
        final reconstructed =
            List.generate(total, (index) => buffer.parts[index]!).join();
        _m21LogChunks.remove(messageId);
        _handleConfigJson(jsonDecode(reconstructed));
      }
      return;
    }

    if (type == 'm21_rx' || type == 'm21_tx' || type == 'm21_rx_stats') {
      final message = decoded['line']?.toString() ??
          decoded['command']?.toString() ??
          jsonEncode(decoded);
      debugPrint('[MFKRTK][DIAGNOSTIC] $message');
      _configMessageController.add(message);
      return;
    }

    if (type == 'm21_response_logging') {
      _configMessageController.add(jsonEncode(decoded));
      return;
    }

    if (decoded.containsKey('rtcm_ok') ||
        decoded.containsKey('rtcm_age_ms') ||
        decoded.containsKey('rtcm_bytes')) {
      _lastRtcmStatus = MfkRtkRtcmStatus.fromJson(decoded);
      debugPrint('[MFKRTK] CONFIG RTCM status: $decoded');
    } else {
      _configMessageController.add(jsonEncode(decoded));
    }
  }

  void _processStatusBytes(List<int> bytes) {
    try {
      final chunk = utf8.decode(bytes, allowMalformed: true);
      _statusStringBuffer += chunk;

      while (_statusStringBuffer.contains('{')) {
        int startIdx = _statusStringBuffer.indexOf('{');
        if (startIdx > 0) {
          _statusStringBuffer = _statusStringBuffer.substring(startIdx);
        }

        int endIdx = _statusStringBuffer.indexOf('}');
        if (endIdx == -1) {
          // JSON payload incomplete, wait for next BLE notification
          break;
        }

        String jsonCandidate = _statusStringBuffer.substring(0, endIdx + 1);

        try {
          final Map<String, dynamic> data = jsonDecode(jsonCandidate);
          _statusStringBuffer = _statusStringBuffer.substring(endIdx + 1);

          _lastStatus =
              MfkRtkStatus.fromJson(data, previousStatus: _lastStatus);
          _statusController.add(_lastStatus!);

          _lastInsStatus =
              _lastStatus!.insAlign ?? _lastStatus!.insStatus ?? _lastInsStatus;
          _lastPosType = _lastStatus!.posType ??
              _lastStatus!.positionSource ??
              _lastPosType;
        } catch (_) {
          int nextEndIdx = _statusStringBuffer.indexOf('}', endIdx + 1);
          if (nextEndIdx != -1) {
            jsonCandidate = _statusStringBuffer.substring(0, nextEndIdx + 1);
            try {
              final Map<String, dynamic> data = jsonDecode(jsonCandidate);
              _statusStringBuffer =
                  _statusStringBuffer.substring(nextEndIdx + 1);

              _lastStatus =
                  MfkRtkStatus.fromJson(data, previousStatus: _lastStatus);
              _statusController.add(_lastStatus!);

              _lastInsStatus = _lastStatus!.insAlign ??
                  _lastStatus!.insStatus ??
                  _lastInsStatus;
              _lastPosType = _lastStatus!.posType ??
                  _lastStatus!.positionSource ??
                  _lastPosType;
            } catch (_) {
              _statusStringBuffer = _statusStringBuffer.substring(1);
            }
          } else {
            break;
          }
        }
      }

      if (_statusStringBuffer.length > 4096) {
        _statusStringBuffer = '';
      }
    } catch (e) {
      debugPrint('[MFKRTK] Status parse error: $e');
    }
  }

  GnssFixType _mapPosTypeToFixType(String? posType) {
    if (posType == null) return GnssFixType.autonomous;
    final upper = posType.toUpperCase();
    if (upper.contains('RTK') ||
        upper.contains('NARROW') ||
        upper.contains('WIDE')) {
      return GnssFixType.rtk;
    }
    if (upper.contains('DIFF') || upper.contains('PSRDIFF')) {
      return GnssFixType.dgps;
    }
    if (upper.contains('SINGLE') || upper.contains('SOL_COMPUTED')) {
      return GnssFixType.autonomous;
    }
    return GnssFixType.none;
  }

  RtkStatus _mapPosTypeToRtkStatus(String? posType) {
    if (posType == null) return RtkStatus.none;
    final upper = posType.toUpperCase();
    if (upper.contains('FIXED') ||
        upper.contains('NARROW_INT') ||
        upper.contains('WIDE_INT')) {
      return RtkStatus.fixed;
    }
    if (upper.contains('FLOAT') ||
        upper.contains('NARROW_FLOAT') ||
        upper.contains('L1_FLOAT')) {
      return RtkStatus.float;
    }
    return RtkStatus.none;
  }
}

class _M21LogChunkBuffer {
  final int total;
  final Map<int, String> parts = {};

  _M21LogChunkBuffer(this.total);
}
