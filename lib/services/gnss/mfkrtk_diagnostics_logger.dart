import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/gnss/mfkrtk_diagnostics.dart';
import 'mfkrtk_provider.dart';

class MfkRtkDiagnosticsLogger extends ChangeNotifier {
  static final MfkRtkDiagnosticsLogger _instance = MfkRtkDiagnosticsLogger._internal();
  factory MfkRtkDiagnosticsLogger() => _instance;

  MfkRtkDiagnosticsLogger._internal() {
    _startPeriodicTimer();
  }

  MfkRtkProvider? _provider;
  StreamSubscription? _rawSubscription;
  StreamSubscription? _statusSubscription;
  StreamSubscription? _navSubscription;
  StreamSubscription? _configSubscription;
  StreamSubscription? _connectionSubscription;
  StreamSubscription? _diagnosticSubscription;

  MfkRtkDiagnostics _state = MfkRtkDiagnostics();
  MfkRtkDiagnostics get state => _state;

  // Internal counters for stats
  int _rxBytesSinceLastTick = 0;
  int _nmeaMessagesSinceLastTick = 0;
  Timer? _statsTimer;
  DateTime? _logStartTime;

  // File logging
  File? _logFile;
  IOSink? _logSink;
  
  // Buffers for parsing classification
  final List<int> _rxBuffer = [];
  
  // Recent raw data for UI (last 2KB max)
  final List<int> _recentRawBytes = [];

  List<int> get recentRawBytes => _recentRawBytes;

  void attach(MfkRtkProvider provider) {
    detach();
    _provider = provider;
    _state = _state.copyWith(isConnected: true);
    
    _rawSubscription = _provider!.rawStream.listen(_onRawData);
    
    // Status stream if needed
    _statusSubscription = _provider!.statusStream.listen((status) {
       _state = _state.copyWith(firmwareVersion: status.firmwareVersion);
       recordEvent('m21_status', {'value': _statusToJson(status)});
       notifyListeners();
    });
    _navSubscription = _provider!.navDataStream.listen((nav) {
      recordEvent('m21_nav_data', {
        'value': {
          'version': nav.version,
          'valid': nav.valid,
          'source': nav.source,
          'ins_align': nav.insAlign,
          'fix': nav.fix,
          'pos_type': nav.posType,
          'satellites': nav.satellites,
          'latitude': nav.latitude,
          'longitude': nav.longitude,
          'height': nav.height,
          'roll': nav.roll,
          'pitch': nav.pitch,
          'azimuth': nav.azimuth,
          'age_ms': nav.ageMs,
          'rtcm_age_ms': nav.rtcmAgeMs,
          'rtcm_bytes': nav.rtcmBytes,
          'rtcm_packets': nav.rtcmPkts,
          'rtcm_ok': nav.rtcmOk,
        },
      });
    });
    _configSubscription = _provider!.configMessageStream.listen((message) {
      recordEvent('m21_config_rx', {'message': message});
    });
    _connectionSubscription = _provider!.connectionStatus.listen((connected) {
      recordEvent('ble_connection', {'connected': connected});
    });
    _diagnosticSubscription = _provider!.diagnosticEventStream.listen((event) {
      recordEvent(event['event']?.toString() ?? 'm21_event', event);
    });

    notifyListeners();
  }

  void detach() {
    _rawSubscription?.cancel();
    _rawSubscription = null;
    _statusSubscription?.cancel();
    _statusSubscription = null;
    _navSubscription?.cancel();
    _navSubscription = null;
    _configSubscription?.cancel();
    _configSubscription = null;
    _connectionSubscription?.cancel();
    _connectionSubscription = null;
    _diagnosticSubscription?.cancel();
    _diagnosticSubscription = null;
    _provider = null;
    _state = _state.copyWith(isConnected: false);
    
    if (_state.isLogging) {
       stopLogging();
    }
    
    notifyListeners();
  }

  Future<void> startLogging() async {
    if (_state.isLogging) return;

    try {
      final dir = await getApplicationDocumentsDirectory();
      final now = DateTime.now();
      final formatter = DateFormat('yyyy-MM-dd_HHmmss');
      final fileName = 'MFKRTK_${formatter.format(now)}.m21log';
      _logFile = File('${dir.path}/$fileName');
      
      _logSink = _logFile!.openWrite(mode: FileMode.append);
      
      // Write header
      final header = {
        'ts': now.toIso8601String(),
        'type': 'metadata',
        'app': 'GeoMeasure',
        'platform': Platform.operatingSystem,
        'firmware': _state.firmwareVersion ?? 'unknown',
      };
      _logSink!.writeln(jsonEncode(header));
      
      _logStartTime = now;
      _state = _state.copyWith(
        isLogging: true,
        logFilePath: _logFile!.path,
        logFileSize: 0,
        logDuration: Duration.zero,
      );
      
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to start logging: $e');
    }
  }

  Future<void> stopLogging() async {
    if (!_state.isLogging) return;

    try {
      await _logSink?.flush();
      await _logSink?.close();
    } catch (e) {
      debugPrint('Error closing log sink: $e');
    } finally {
      _logSink = null;
      _state = _state.copyWith(isLogging: false);
      notifyListeners();
    }
  }

  Future<void> shareLog() async {
    if (_state.logFilePath != null) {
      final file = File(_state.logFilePath!);
      if (await file.exists()) {
        await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], text: 'MFKRTK Raw Log'));
      }
    }
  }

  void recordEvent(String type, Map<String, dynamic> fields) {
    if (!_state.isLogging || _logSink == null) return;
    final entry = <String, dynamic>{
      'ts': DateTime.now().toUtc().toIso8601String(),
      'type': type,
      ...fields,
    };
    _logSink!.writeln(jsonEncode(entry));
  }

  Map<String, dynamic> _statusToJson(dynamic status) => {
        'firmware': status.firmwareVersion,
        'battery_voltage': status.batteryVoltage,
        'battery_percentage': status.batteryPercentage,
        'ble_connected': status.bleConnected,
        'ins_status': status.insStatus,
        'pos_type': status.posType,
        'rtcm_ok': status.rtcmOk,
        'rtcm_age_ms': status.rtcmAgeMs,
        'rtcm_bytes': status.rtcmBytes,
        'rtcm_packets': status.rtcmPkts,
      };

  void clearMonitor() {
    _recentRawBytes.clear();
    _state = _state.copyWith(
      lastAsciiPreview: '',
      lastRawHex: '',
      lastNmeaSentence: '',
    );
    notifyListeners();
  }

  @visibleForTesting
  void processRawDataForTest(List<int> data) {
    _onRawData(data);
  }

  @visibleForTesting
  void resetStatsForTest() {
    _state = MfkRtkDiagnostics();
    _rxBuffer.clear();
    _recentRawBytes.clear();
  }

  void _onRawData(List<int> data) {
    if (data.isEmpty) return;

    final now = DateTime.now();
    
    // 1. Statistics
    _state = _state.copyWith(
      totalRxBytes: _state.totalRxBytes + data.length,
      lastMessageTime: now,
    );
    _rxBytesSinceLastTick += data.length;

    // 2. Logging
    if (_state.isLogging && _logSink != null) {
      final entry = {
        'ts': now.toUtc().toIso8601String(),
        'direction': 'RX',
        'source': 'M21',
        'data_base64': base64Encode(data),
      };
      _logSink!.writeln(jsonEncode(entry));
      
      // Update file size occasionally (done in timer to avoid IO overhead, but we can approximate)
      _state = _state.copyWith(
        logFileSize: _state.logFileSize + data.length + 100 // approximation of json overhead
      );
    }

    // 3. UI Monitor buffer (keep last 2048 bytes)
    _recentRawBytes.addAll(data);
    if (_recentRawBytes.length > 2048) {
      _recentRawBytes.removeRange(0, _recentRawBytes.length - 2048);
    }

    // Hex and ASCII update (limit to last 64 bytes for quick preview)
    final previewBytes = data.length > 64 ? data.sublist(data.length - 64) : data;
    final hexStr = previewBytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
    
    String asciiStr = '';
    for (var b in previewBytes) {
      if (b >= 32 && b <= 126) {
        asciiStr += String.fromCharCode(b);
      } else {
        asciiStr += '.';
      }
    }

    _state = _state.copyWith(
      lastRawHex: hexStr,
      lastAsciiPreview: asciiStr,
    );

    // 4. Classification (NMEA vs Binary)
    _classifyData(data);
  }

  void _classifyData(List<int> data) {
    _rxBuffer.addAll(data);
    
    while (true) {
      int startIdx = -1;
      for (int i = 0; i < _rxBuffer.length; i++) {
        final b = _rxBuffer[i];
        if (b == 0x24) { // '$'
          startIdx = i;
          break;
        }
      }

      if (startIdx == -1) {
        // No NMEA start found, consider all as binary/unknown
        _state = _state.copyWith(
          binaryBytes: _state.binaryBytes + _rxBuffer.length
        );
        _rxBuffer.clear();
        break;
      }

      if (startIdx > 0) {
        // Data before '$' is binary
        _state = _state.copyWith(
          binaryBytes: _state.binaryBytes + startIdx
        );
        _rxBuffer.removeRange(0, startIdx);
        startIdx = 0;
      }

      int endIdx = -1;
      int lineEndLength = 1;
      for (int i = 0; i < _rxBuffer.length; i++) {
        if (_rxBuffer[i] == 0x0A) { // '\n'
          if (i > 0 && _rxBuffer[i - 1] == 0x0D) { // '\r\n'
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

        // NMEA sentence found
        try {
          String line = utf8.decode(frame, allowMalformed: true).trim();
          if (line.isNotEmpty) {
            _nmeaMessagesSinceLastTick++;
            _state = _state.copyWith(
              nmeaMessages: _state.nmeaMessages + 1,
              lastNmeaSentence: line,
            );
          }
        } catch (_) {}
      } else {
        break; // Wait for more data
      }
    }
  }

  void _startPeriodicTimer() {
    _statsTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (_provider == null && !_state.isLogging) return;

      double rxSpeed = (_rxBytesSinceLastTick / 0.5); // bytes per sec
      double nmeaSpeed = (_nmeaMessagesSinceLastTick / 0.5);
      
      _rxBytesSinceLastTick = 0;
      _nmeaMessagesSinceLastTick = 0;
      
      Duration logDur = _state.logDuration;
      if (_state.isLogging && _logStartTime != null) {
        logDur = DateTime.now().difference(_logStartTime!);
        // update actual file size occasionally
        if (_logFile != null && _logFile!.existsSync()) {
           _state = _state.copyWith(logFileSize: _logFile!.lengthSync());
        }
      }

      _state = _state.copyWith(
        rxBytesPerSecond: rxSpeed,
        nmeaMessagesPerSecond: nmeaSpeed,
        logDuration: logDur,
      );

      // Throttled UI update
      notifyListeners();
    });
  }

  // Not exact, but we can hook this up to the provider later if needed
  void recordRtcmTx(int length) {
    _state = _state.copyWith(
      rtcmTxBytes: _state.rtcmTxBytes + length,
      rtcmPacketsSent: _state.rtcmPacketsSent + 1,
    );
  }

  @override
  void dispose() {
    _statsTimer?.cancel();
    detach();
    super.dispose();
  }
}
