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
import 'gnss/rtcm_service.dart';
import 'geoid_service.dart';
import '../models/ntrip_settings.dart';
import '../models/ntrip_profile.dart';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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

class GnssInfoService extends ChangeNotifier {
  GnssStatusData _currentStatus = GnssStatusData();
  StreamSubscription? _rawGnssSubscription;
  StreamSubscription? _fixSubscription;
  StreamSubscription? _ggaSubscription;
  
  // Note: Internal status monitoring for Android still uses RawGnss directly for now
  // until GnssProvider is fully extended for status unification.
  final _rawGnss = RawGnss();
  final RawGnssLogger rawLogger = RawGnssLogger();
  
  GnssProvider? _activeProvider;
  GnssFix? _lastFix;
  
  final _fixStreamController = StreamController<GnssFix>.broadcast();
  final _secureStorage = const FlutterSecureStorage();
  
  NtripSettings _ntripSettings = NtripSettings();
  NtripSettings get ntripSettings => _ntripSettings;

  // Stability logic
  final Stopwatch _rtkStabilityStopwatch = Stopwatch();
  bool _isStableRtkFix = false;
  bool get isStableRtkFix => _isStableRtkFix;
  double get currentFixStabilityDuration => _rtkStabilityStopwatch.elapsedMilliseconds / 1000.0;

  // Getterek
  GnssStatusData get currentStatus => _currentStatus;
  GnssProvider? get activeProvider => _activeProvider;
  GnssFix? get lastFix => _lastFix;
  Stream<GnssFix> get fixStream => _fixStreamController.stream;

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
      if (_ntripSettings.requireStableFix) {
        final wasStable = _isStableRtkFix;
        _isStableRtkFix = _lastFix?.fixType == GnssFixType.rtk && 
                         _lastFix?.rtkStatus == RtkStatus.fixed &&
                         _rtkStabilityStopwatch.elapsed.inSeconds >= _ntripSettings.stabilityThresholdSeconds;
        if (wasStable != _isStableRtkFix) notifyListeners();
      } else {
        _isStableRtkFix = true;
      }
    });
  }

  void setProvider(GnssProvider provider, {RtcmService? rtcmService}) {
    _activeProvider?.dispose();
    _fixSubscription?.cancel();
    _ggaSubscription?.cancel();
    
    _activeProvider = provider;
    _fixSubscription = _activeProvider!.fixStream.listen((fix) {
      _lastFix = fix;
      _updateFromFix(fix);
      _fixStreamController.add(fix);
      notifyListeners();
    });
    
    if (_activeProvider is ExternalGnssProvider) {
      _ggaSubscription = (_activeProvider as ExternalGnssProvider).ggaStream.listen((gga) {
        rtcmService?.updateGga(gga);
      });
      
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
    
    _activeProvider!.connect().catchError((e) {
      debugPrint("Provider connection error: $e");
    });
    
    notifyListeners();
  }

  // --- Profile Management ---

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
    if (_activeProvider is ExternalGnssProvider && _ntripSettings.enabled && rtcmService != null && active != null) {
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

  Future<void> _saveSettings() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/gnss_settings.json');
    await file.writeAsString(jsonEncode(_ntripSettings.toJson()));
  }

  Future<void> _loadSettings() async {
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
    _rawGnssSubscription?.cancel();
    _fixSubscription?.cancel();
    _ggaSubscription?.cancel();
    _activeProvider?.dispose();
    _fixStreamController.close();
    rawLogger.removeListener(notifyListeners);
    super.dispose();
  }
}
