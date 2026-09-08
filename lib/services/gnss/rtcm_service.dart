import 'dart:async';
import 'package:flutter/foundation.dart';
import 'ntrip_client.dart';
import 'gnss_provider.dart';
import '../../models/ntrip_diagnostics.dart';

class RtcmService extends ChangeNotifier {
  NtripClient? _ntripClient;
  StreamSubscription? _rtcmSubscription;
  StreamSubscription? _statusSubscription;
  StreamSubscription? _diagSubscription;
  
  NtripStatus _status = NtripStatus.disconnected;
  NtripStatus get status => _status;
  
  NtripDiagnostics _diagnostics = NtripDiagnostics();
  NtripDiagnostics get diagnostics => _diagnostics;
  
  final _diagStreamController = StreamController<NtripDiagnostics>.broadcast();
  Stream<NtripDiagnostics> get diagnosticsStream => _diagStreamController.stream;

  // Reconnect logic
  Timer? _reconnectTimer;
  int _reconnectAttempt = 0;
  static const List<int> _backoffIntervals = [1, 2, 5, 10, 30];

  void startNtrip({
    required String host,
    required int port,
    required String mountpoint,
    String? username,
    String? password,
    int ggaInterval = 10,
    required GnssProvider targetProvider,
  }) {
    _cancelReconnect();
    stopNtrip();

    if (host.isEmpty || port <= 0 || mountpoint.isEmpty) {
      _status = NtripStatus.notConfigured;
      notifyListeners();
      return;
    }
    
    _ntripClient = NtripClient(
      host: host,
      port: port,
      mountpoint: mountpoint,
      username: username,
      password: password,
      ggaInterval: ggaInterval,
    );
    
    _statusSubscription = _ntripClient!.statusStream.listen((s) {
      _status = s;
      if (s == NtripStatus.error) {
        _scheduleReconnect(targetProvider);
      } else if (s == NtripStatus.connected || s == NtripStatus.correctionDataActive) {
        _reconnectAttempt = 0;
      }
      notifyListeners();
    });
    
    _rtcmSubscription = _ntripClient!.rtcmStream.listen((data) {
      if (targetProvider.supportsRtcmInput) {
        targetProvider.sendCorrectionData(data);
      }
    });

    _diagSubscription = _ntripClient!.diagnosticsStream.listen((d) {
      _diagnostics = d;
      _diagStreamController.add(d);
      notifyListeners();
    });
    
    _ntripClient!.connect().catchError((e) {
      debugPrint("NTRIP Connection error: $e");
      // Reconnect will be scheduled by status listener if error
    });
  }

  void _scheduleReconnect(GnssProvider targetProvider) {
    if (_reconnectTimer != null) return;
    
    final delay = _backoffIntervals[(_reconnectAttempt < _backoffIntervals.length) ? _reconnectAttempt : _backoffIntervals.length - 1];
    _reconnectAttempt++;
    
    debugPrint("NTRIP: Scheduling reconnect in $delay seconds (Attempt $_reconnectAttempt)");
    
    _reconnectTimer = Timer(Duration(seconds: delay), () {
      _reconnectTimer = null;
      if (_status == NtripStatus.error) {
         _status = NtripStatus.reconnecting;
         notifyListeners();
         _ntripClient?.connect().catchError((e) {
           debugPrint("NTRIP Reconnect failed: $e");
         });
      }
    });
  }

  void _cancelReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempt = 0;
  }

  void updateGga(String gga) {
    _ntripClient?.updatePosition(gga);
  }

  void stopNtrip() {
    _cancelReconnect();
    _rtcmSubscription?.cancel();
    _statusSubscription?.cancel();
    _diagSubscription?.cancel();
    _ntripClient?.dispose();
    _ntripClient = null;
    _status = NtripStatus.disconnected;
    _diagnostics = NtripDiagnostics();
    _diagStreamController.add(_diagnostics);
    notifyListeners();
  }

  @override
  void dispose() {
    stopNtrip();
    _diagStreamController.close();
    super.dispose();
  }
}
