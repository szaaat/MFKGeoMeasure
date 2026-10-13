import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:mfk_geomeasure/models/gnss_fix.dart';
import 'package:mfk_geomeasure/models/gnss_raw_measurement.dart';
import 'package:mfk_geomeasure/services/gnss/gnss_provider.dart';
import 'gnss_transport.dart';
import 'nmea_parser.dart';

class ExternalGnssProvider implements GnssProvider {
  final GnssTransport _transport;
  final NmeaParser _parser = NmeaParser();
  final String _receiverName;
  final GnssConnectionType _connectionType;
  
  final _fixController = StreamController<GnssFix>.broadcast();
  final _ggaController = StreamController<String>.broadcast();
  final _rawController = StreamController<List<int>>.broadcast();
  StreamSubscription? _dataSubscription;
  
  // Buffer for conservative NMEA frame extraction
  final List<int> _byteBuffer = [];

  ExternalGnssProvider({
    required GnssTransport transport,
    String receiverName = "External GNSS",
    required GnssConnectionType connectionType,
  }) : _transport = transport, 
       _receiverName = receiverName,
       _connectionType = connectionType;

  @override
  Stream<GnssFix> get fixStream => _fixController.stream;

  @override
  Stream<List<int>> get rawStream => _rawController.stream;

  @override
  Stream<GnssRawMeasurement> get rawMeasurementStream => const Stream.empty();
  
  /// Stream a beérkező nyers GGA mondatokról (NTRIP feedbackhez)
  Stream<String> get ggaStream => _ggaController.stream;

  @override
  bool get supportsRtcmInput => true; 

  @override
  Future<void> connect() async {
    debugPrint('[GNSS-EXTERNAL] Connecting to $_receiverName via $_connectionType');
    await _transport.connect();
    
    _dataSubscription = _transport.dataStream.listen((data) {
      _processIncomingBytes(data);
    });
  }

  @override
  Future<void> disconnect() async {
    await _dataSubscription?.cancel();
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
    _transport.dispose();
  }

  void _processIncomingBytes(List<int> data) {
    // 1. Forward to raw stream immediately (NEVER discarded)
    _rawController.add(data);

    // 2. Add to buffer for NMEA frame extraction
    _byteBuffer.addAll(data);

    // 3. Conservative NMEA frame extraction
    _extractNmeaFromBuffer();

    // 4. Circular buffer maintenance (prevent memory leaks)
    if (_byteBuffer.length > 8192) {
      _byteBuffer.removeRange(0, _byteBuffer.length - 2048);
    }
  }

  void _extractNmeaFromBuffer() {
    while (true) {
      // Find start of NMEA sentence
      int startIdx = _byteBuffer.indexOf(0x24); // '$'
      if (startIdx == -1) {
        // No '$' found, but we DON'T clear the buffer because it might contain 
        // non-NMEA protocol data (Bynav binary) which we want to preserve in the raw stream.
        // However, for the NMEA extraction logic, we can ignore bytes until the next '$'.
        // Wait, if I clear the buffer here, I might lose the beginning of a binary message.
        // Actually, the raw bytes were ALREADY sent to _rawController.add(data) in step 1.
        // So clearing _byteBuffer only affects the NMEA extractor.
        _byteBuffer.clear(); 
        break;
      }

      if (startIdx > 0) {
        _byteBuffer.removeRange(0, startIdx);
        startIdx = 0;
      }

      // Look for '\r\n' (NMEA line ending)
      int endIdx = -1;
      for (int i = 0; i < _byteBuffer.length - 1; i++) {
        if (_byteBuffer[i] == 0x0D && _byteBuffer[i+1] == 0x0A) {
          endIdx = i;
          break;
        }
      }

      if (endIdx != -1) {
        // Extract candidate frame
        List<int> frame = _byteBuffer.sublist(0, endIdx + 2);
        _byteBuffer.removeRange(0, endIdx + 2);

        try {
          String sentence = utf8.decode(frame, allowMalformed: true).trim();
          if (sentence.startsWith('\$') && sentence.contains('*')) {
             _handleSentence(sentence);
          }
        } catch (e) {
          // Binary data inside what looked like NMEA or decoding error.
        }
      } else {
        // Frame incomplete
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
      connectionType: _connectionType
    );
    
    if (fix != null) {
      _fixController.add(_copyFixWithReceiverName(fix));
    }
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
      receiverName: _receiverName,
      connectionType: _connectionType,
      timestamp: fix.timestamp,
      timestampSource: fix.timestampSource,
      referenceFrame: fix.referenceFrame,
      referenceEpoch: fix.referenceEpoch,
    );
  }
}
