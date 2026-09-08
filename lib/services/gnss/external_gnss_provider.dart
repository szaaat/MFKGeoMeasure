import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../models/gnss_fix.dart';
import '../../models/gnss_raw_measurement.dart';
import 'gnss_provider.dart';
import 'gnss_transport.dart';
import 'nmea_parser.dart';

class ExternalGnssProvider implements GnssProvider {
  final GnssTransport _transport;
  final NmeaParser _parser = NmeaParser();
  final String _receiverName;
  final GnssConnectionType _connectionType;
  
  final _fixController = StreamController<GnssFix>.broadcast();
  final _ggaController = StreamController<String>.broadcast();
  StreamSubscription? _dataSubscription;
  
  // Buffer a töredékes NMEA mondatokhoz
  String _buffer = "";

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
  Stream<GnssRawMeasurement> get rawMeasurementStream => const Stream.empty();
  
  /// Stream a beérkező nyers GGA mondatokról (NTRIP feedbackhez)
  Stream<String> get ggaStream => _ggaController.stream;

  @override
  bool get supportsRtcmInput => true; // Külső vevők jellemzően támogatják

  @override
  Future<void> connect() async {
    debugPrint('[GNSS-EXTERNAL] Connecting to $_receiverName via $_connectionType');
    await _transport.connect();
    
    _dataSubscription = _transport.dataStream.listen((data) {
      _processRawData(data);
    });
  }

  @override
  Future<void> disconnect() async {
    await _dataSubscription?.cancel();
    await _transport.disconnect();
  }

  @override
  void sendCorrectionData(List<int> data) {
    debugPrint('[RTCM] Forwarding ${data.length} bytes to receiver');
    _transport.write(data);
  }

  @override
  void dispose() {
    disconnect();
    _fixController.close();
    _ggaController.close();
    _transport.dispose();
  }

  void _processRawData(List<int> data) {
    debugPrint('[GNSS-EXTERNAL] Bytes received: ${data.length}');
    _buffer += utf8.decode(data, allowMalformed: true);
    
    // NMEA mondatok szétszedése (sorvégjelek mentén)
    while (_buffer.contains('\n')) {
      int index = _buffer.indexOf('\n');
      String sentence = _buffer.substring(0, index).trim();
      _buffer = _buffer.substring(index + 1);
      
      if (sentence.isNotEmpty) {
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
    }
  }

  GnssFix _copyFixWithReceiverName(GnssFix fix) {
    // A parser nem tudja a vevő nevét, itt adjuk hozzá
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
    );
  }
}
