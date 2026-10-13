import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../models/ntrip_source.dart';
import '../../models/ntrip_diagnostics.dart';

enum NtripStatus {
  notConfigured,
  disconnected,
  connecting,
  connected,
  correctionDataActive,
  reconnecting,
  error,
}

enum NtripError {
  none,
  invalidConfig,
  hostNotFound,
  connectionRefused,
  timeout,
  authFailed,
  mountpointNotFound,
  connectionLost,
  noData,
}

class NtripClient {
  final String host;
  final int port;
  final String mountpoint;
  final String? username;
  final String? password;
  final int ggaInterval;
  
  Socket? _socket;
  final _dataController = StreamController<List<int>>.broadcast();
  final _statusController = StreamController<NtripStatus>.broadcast();
  final _diagController = StreamController<NtripDiagnostics>.broadcast();
  
  NtripStatus _status = NtripStatus.disconnected;
  NtripError _lastError = NtripError.none;
  String? _technicalError;

  Timer? _ggaTimer;
  String? _lastGga;
  
  // Diagnostics
  int _bytesReceived = 0;
  DateTime? _lastRtcmReceived;
  DateTime? _lastGgaSent;
  final Stopwatch _correctionStopwatch = Stopwatch();
  Timer? _diagTimer;
  
  bool _manuallyDisconnected = false;

  NtripClient({
    required this.host,
    required this.port,
    required this.mountpoint,
    this.username,
    this.password,
    this.ggaInterval = 10,
  }) {
    if (host.isEmpty || port <= 0 || mountpoint.isEmpty) {
      _status = NtripStatus.notConfigured;
      _lastError = NtripError.invalidConfig;
    }
  }

  Stream<List<int>> get rtcmStream => _dataController.stream;
  Stream<NtripStatus> get statusStream => _statusController.stream;
  Stream<NtripDiagnostics> get diagnosticsStream => _diagController.stream;
  
  NtripStatus get status => _status;
  NtripError get lastError => _lastError;
  String? get technicalError => _technicalError;

  Future<void> connect() async {
    _manuallyDisconnected = false;
    await _doConnect();
  }

  Future<void> _doConnect() async {
    if (_status == NtripStatus.notConfigured) return;
    
    debugPrint('[NTRIP] Connecting to $host:$port');
    _bytesReceived = 0;
    _lastRtcmReceived = null;
    _correctionStopwatch.reset();
    
    _updateStatus(NtripStatus.connecting);
    
    try {
      _socket = await Socket.connect(host, port, timeout: const Duration(seconds: 10));
      
      final auth = (username != null && password != null && username!.isNotEmpty)
          ? base64Encode(utf8.encode('$username:$password'))
          : null;
          
      final request = StringBuffer();
      request.write('GET /$mountpoint HTTP/1.0\r\n');
      request.write('User-Agent: NTRIP MFKgps/1.0\r\n');
      request.write('Accept: */*\r\n');
      request.write('Connection: close\r\n');
      if (auth != null) {
        request.write('Authorization: Basic $auth\r\n');
      }
      request.write('\r\n');
      
      _socket!.write(request.toString());
      
      bool headerFinished = false;
      
      _socket!.listen(
        (Uint8List data) {
          if (!headerFinished) {
            final response = utf8.decode(data, allowMalformed: true);
            if (response.contains('200 OK')) {
              debugPrint('[NTRIP] Connected to mountpoint: $mountpoint');
              headerFinished = true;
              _updateStatus(NtripStatus.connected);
              
              // Immediate feedback for NEAR mountpoints
              if ((mountpoint == 'NEAR' || mountpoint == 'NEAR4') && _lastGga != null && _socket != null) {
                _socket!.write('$_lastGga\r\n');
                _lastGgaSent = DateTime.now();
                debugPrint('[NTRIP] Immediate GGA feedback sent for $mountpoint');
              }
              
              _startGgaFeedback();
              _startDiagnostics();
              
              final bodyIndex = response.indexOf('\r\n\r\n');
              if (bodyIndex != -1 && bodyIndex + 4 < data.length) {
                _handleRtcmData(data.sublist(bodyIndex + 4));
              }
            } else if (response.contains('401')) {
              _handleError(NtripError.authFailed, "401 Unauthorized");
            } else if (response.contains('404')) {
              _handleError(NtripError.mountpointNotFound, "404 Not Found");
            } else if (response.contains('HTTP/') || response.contains('ICY')) {
              _handleError(NtripError.connectionLost, "Server returned: ${response.split('\r\n')[0]}");
            }
          } else {
            _handleRtcmData(data);
          }
        },
        onError: (e) {
          _handleError(NtripError.connectionLost, e.toString());
        },
        onDone: () {
          if (!_manuallyDisconnected && _status != NtripStatus.error) {
             _handleError(NtripError.connectionLost, "Socket closed by server");
          } else {
             disconnect();
          }
        },
      );
      
    } on SocketException catch (e) {
      if (e.osError?.errorCode == 7 || e.message.contains("Failed host lookup")) {
        _handleError(NtripError.hostNotFound, e.toString());
      } else if (e.osError?.errorCode == 111 || e.message.contains("Connection refused")) {
        _handleError(NtripError.connectionRefused, e.toString());
      } else {
        _handleError(NtripError.connectionLost, e.toString());
      }
    } on TimeoutException catch (e) {
      _handleError(NtripError.timeout, e.toString());
    } catch (e) {
      _handleError(NtripError.connectionLost, e.toString());
    }
  }

  void _handleRtcmData(List<int> data) {
    debugPrint('[NTRIP] RTCM packet received: ${data.length} bytes');
    if (_status != NtripStatus.correctionDataActive) {
      _updateStatus(NtripStatus.correctionDataActive);
    }
    _bytesReceived += data.length;
    _lastRtcmReceived = DateTime.now();
    _correctionStopwatch.start();
    _correctionStopwatch.reset();
    _correctionStopwatch.start();
    _dataController.add(data);
  }

  void _handleError(NtripError error, String technical) {
    debugPrint('[NTRIP] Error: $error ($technical)');
    _lastError = error;
    _technicalError = technical;
    _updateStatus(NtripStatus.error);
    _socket?.destroy();
    _socket = null;
    _diagTimer?.cancel();
    _ggaTimer?.cancel();
  }

  void updatePosition(String gga) {
    _lastGga = gga;
  }

  void _startGgaFeedback() {
    _ggaTimer?.cancel();
    if (ggaInterval <= 0) return;
    
    _ggaTimer = Timer.periodic(Duration(seconds: ggaInterval), (timer) {
      if (_status == NtripStatus.correctionDataActive || _status == NtripStatus.connected) {
        if (_lastGga != null && _socket != null) {
          _socket!.write('$_lastGga\r\n');
          _lastGgaSent = DateTime.now();
        }
      }
    });
  }

  void _startDiagnostics() {
    _diagTimer?.cancel();
    int lastBytes = 0;
    _diagTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final currentBytes = _bytesReceived;
      final bitrate = (currentBytes - lastBytes) * 8 / 1024.0; // kbps
      lastBytes = currentBytes;

      _diagController.add(NtripDiagnostics(
        correctionAge: _correctionStopwatch.isRunning ? _correctionStopwatch.elapsed : null,
        bytesReceived: _bytesReceived,
        bitrateKbps: bitrate,
        lastGgaSent: _lastGgaSent,
        lastRtcmReceived: _lastRtcmReceived,
        isConnected: _status == NtripStatus.connected || _status == NtripStatus.correctionDataActive,
      ));
    });
  }

  void disconnect() {
    _manuallyDisconnected = true;
    _ggaTimer?.cancel();
    _diagTimer?.cancel();
    _correctionStopwatch.stop();
    _socket?.destroy();
    _socket = null;
    _updateStatus(NtripStatus.disconnected);
    
    // Final clear diag
    _diagController.add(NtripDiagnostics(isConnected: false));
  }

  void _updateStatus(NtripStatus s) {
    _status = s;
    _statusController.add(s);
  }

  static Future<List<NtripSource>> fetchSourceTable({
    required String host,
    required int port,
    String? username,
    String? password,
  }) async {
    if (host.isEmpty || port <= 0) {
      throw Exception("Invalid host or port");
    }

    Socket? socket;
    try {
      socket = await Socket.connect(host, port, timeout: const Duration(seconds: 10));
      
      final auth = (username != null && password != null && username.isNotEmpty)
          ? base64Encode(utf8.encode('$username:$password'))
          : null;

      final request = StringBuffer();
      request.write('GET / HTTP/1.0\r\n');
      request.write('User-Agent: NTRIP MFKgps/1.0\r\n');
      request.write('Connection: close\r\n');
      if (auth != null) {
        request.write('Authorization: Basic $auth\r\n');
      }
      request.write('\r\n');
      
      socket.write(request.toString());
      
      final completer = Completer<String>();
      final buffer = StringBuffer();
      
      socket.listen(
        (Uint8List data) {
          buffer.write(utf8.decode(data, allowMalformed: true));
        },
        onError: (e) => completer.completeError(e),
        onDone: () => completer.complete(buffer.toString()),
      );
      
      final response = await completer.future.timeout(const Duration(seconds: 15));
      final lines = response.split('\n');
      final List<NtripSource> sources = [];
      
      for (var line in lines) {
        final trimmed = line.trim();
        if (trimmed.startsWith('STR;')) {
          try {
            sources.add(NtripSource.fromCsv(trimmed));
          } catch (e) {
            debugPrint("Error parsing sourcetable line: $e");
          }
        }
      }
      
      return sources;
    } finally {
      socket?.destroy();
    }
  }

  void dispose() {
    disconnect();
    _dataController.close();
    _statusController.close();
    _diagController.close();
  }
}
