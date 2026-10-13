import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../models/gnss_fix.dart';
import '../../models/gnss_raw_measurement.dart';
import '../../models/gnss/mfkrtk_constants.dart';
import '../../models/gnss/mfkrtk_status.dart';
import 'gnss_provider.dart';
import 'ble_transport.dart';
import 'nmea_parser.dart';

class MfkRtkProvider implements GnssProvider {
  final BleTransport _transport;
  final NmeaParser _parser = NmeaParser();
  
  final _fixController = StreamController<GnssFix>.broadcast();
  final _ggaController = StreamController<String>.broadcast();
  final _rawController = StreamController<List<int>>.broadcast();
  final _statusController = StreamController<MfkRtkStatus>.broadcast();
  
  StreamSubscription? _dataSubscription;
  StreamSubscription? _statusSubscription;
  
  final List<int> _nmeaBuffer = [];
  MfkRtkStatus? _lastStatus;

  MfkRtkProvider({required BleTransport transport}) : _transport = transport;

  @override
  Stream<GnssFix> get fixStream => _fixController.stream;

  @override
  Stream<List<int>> get rawStream => _rawController.stream;

  @override
  Stream<GnssRawMeasurement> get rawMeasurementStream => const Stream.empty();
  
  Stream<MfkRtkStatus> get statusStream => _statusController.stream;
  MfkRtkStatus? get lastStatus => _lastStatus;

  /// Stream a beérkező nyers GGA mondatokról (NTRIP feedbackhez)
  Stream<String> get ggaStream => _ggaController.stream;

  @override
  bool get supportsRtcmInput => true;

  @override
  Future<void> connect() async {
    debugPrint('[MFKRTK] Connecting via BLE...');
    
    // Subscribe to status characteristic BEFORE connecting
    _statusSubscription = _transport.getExtraStream(MfkRtkConstants.deviceStatusUuid).listen((bytes) {
      _processStatusBytes(bytes);
    });

    await _transport.connect();
    
    _dataSubscription = _transport.dataStream.listen((data) {
      _processIncomingBytes(data);
    });
  }

  @override
  Future<void> disconnect() async {
    await _dataSubscription?.cancel();
    await _statusSubscription?.cancel();
    await _transport.disconnect();
  }

  @override
  void sendCorrectionData(List<int> data) {
    _transport.write(data);
  }

  @override
  void dispose() {
    disconnect();
    _fixController.close();
    _ggaController.close();
    _rawController.close();
    _statusController.close();
    _transport.dispose();
  }

  void _processIncomingBytes(List<int> data) {
    // Forward everything to raw stream immediately
    _rawController.add(data);

    // Extract NMEA frames
    _nmeaBuffer.addAll(data);
    _extractNmea();
    
    if (_nmeaBuffer.length > 8192) {
      _nmeaBuffer.removeRange(0, _nmeaBuffer.length - 2048);
    }
  }

  void _extractNmea() {
    while (true) {
      int startIdx = _nmeaBuffer.indexOf(0x24); // '$'
      if (startIdx == -1) {
        _nmeaBuffer.clear();
        break;
      }
      if (startIdx > 0) {
        _nmeaBuffer.removeRange(0, startIdx);
        startIdx = 0;
      }

      int endIdx = -1;
      for (int i = 0; i < _nmeaBuffer.length - 1; i++) {
        if (_nmeaBuffer[i] == 0x0D && _nmeaBuffer[i+1] == 0x0A) {
          endIdx = i;
          break;
        }
      }

      if (endIdx != -1) {
        List<int> frame = _nmeaBuffer.sublist(0, endIdx + 2);
        _nmeaBuffer.removeRange(0, endIdx + 2);

        try {
          String sentence = utf8.decode(frame, allowMalformed: true).trim();
          if (sentence.startsWith('$') && sentence.contains('*')) {
             _handleSentence(sentence);
          }
        } catch (_) {}
      } else {
        break;
      }
    }
  }

  void _handleSentence(String sentence) {
    if (sentence.contains('GGA')) {
      _ggaController.add(sentence);
    }
    
    final fix = _parser.parse(
      sentence, 
      source: GnssSource.external, 
      connectionType: GnssConnectionType.ble
    );
    
    if (fix != null) {
      _fixController.add(_copyFixWithReceiverName(fix));
    }
  }

  void _processStatusBytes(List<int> bytes) {
    try {
      final String jsonStr = utf8.decode(bytes);
      final Map<String, dynamic> data = jsonDecode(jsonStr);
      _lastStatus = MfkRtkStatus.fromJson(data);
      _statusController.add(_lastStatus!);
      notifyFixStatusIfPresent();
    } catch (e) {
      debugPrint('[MFKRTK] Status parse error: $e');
    }
  }

  void notifyFixStatusIfPresent() {
    // If the status JSON contains position/fix data, we could inject it here
    // but the Bynav raw stream is the primary source.
  }

  GnssFix _copyFixWithReceiverName(GnssFix fix) {
    return GnssFix(
      latitude: fix.latitude,
      longitude: fix.longitude,
      altitude: fix.altitude,
      ellipsoidalHeight: fix.ellipsoidalHeight,
      isEllipsoidal: fix.isEllipsoidal,
      mslAltitude: fix.mslAltitude,
      geoidSeparation: fix.geoidSeparation,
      horizontalAccuracy: fix.horizontalAccuracy,
      verticalAccuracy: fix.verticalAccuracy,
      fixType: fix.fixType,
      rtkStatus: fix.rtkStatus,
      satellitesUsed: fix.satellitesUsed,
      satellitesInView: fix.satellitesInView,
      pdop: fix.pdop,
      hdop: fix.hdop,
      vdop: fix.vdop,
      correctionAge: fix.correctionAge,
      stationId: fix.stationId,
      source: fix.source,
      receiverName: "MFKRTK",
      connectionType: GnssConnectionType.ble,
      timestamp: fix.timestamp,
      timestampSource: fix.timestampSource,
    );
  }
}
