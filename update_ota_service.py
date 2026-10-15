import re

with open('lib/services/gnss/mfkrtk_ota_service.dart', 'r') as f:
    content = f.read()

# Add reportedFirmwareVersion to state
content = content.replace(
    'String? get firmwareVersion => _firmwareVersion;',
    'String? get firmwareVersion => _firmwareVersion;\n\n  String? _reportedFirmwareVersion;\n  String? get reportedFirmwareVersion => _reportedFirmwareVersion;'
)

# Add verifyingVersion to enum
content = content.replace(
    'reconnecting,\n  completed',
    'reconnecting,\n  verifyingVersion,\n  completed'
)

# Add MfkRtkProvider getter
content = content.replace(
    'MfkRtkProvider? _provider;',
    'MfkRtkProvider? _provider;\n  MfkRtkProvider? get provider => _provider;'
)

# Add _connSub 
content = content.replace(
    'StreamSubscription? _configSub;',
    'StreamSubscription? _configSub;\n  StreamSubscription? _connSub;'
)

# Replace attach
old_attach = '''  void attach(MfkRtkProvider provider) {
    _provider = provider;
  }'''

new_attach = '''  void attach(MfkRtkProvider provider) {
    if (_provider == provider) return;

    _configSub?.cancel();
    _connSub?.cancel();
    _provider = provider;

    if (_state == OtaUpdateState.rebooting || _state == OtaUpdateState.reconnecting) {
      _setState(OtaUpdateState.reconnecting);
      
      _configSub = _provider!.transport.getExtraStream(MfkRtkConstants.configUuid).listen(_onConfigNotify);

      Future.delayed(const Duration(seconds: 2), () {
        if (_state == OtaUpdateState.reconnecting && _provider != null) {
          _verifyVersionAfterReconnect();
        }
      });
    }
  }'''
content = content.replace(old_attach, new_attach)

# Replace detach
old_detach = '''  void detach() {
    if (_state != OtaUpdateState.idle && _state != OtaUpdateState.completed && _state != OtaUpdateState.failed && _state != OtaUpdateState.cancelled) {
       cancelUpdate();
    }
    _provider = null;
    _configSub?.cancel();
  }'''

new_detach = '''  void detach() {
    if (_state != OtaUpdateState.idle && _state != OtaUpdateState.completed && _state != OtaUpdateState.failed && _state != OtaUpdateState.cancelled) {
       cancelUpdate();
    }
    _provider = null;
    _configSub?.cancel();
    _connSub?.cancel();
  }'''
content = content.replace(old_detach, new_detach)

# Replace startUpdate logic
old_start = '''    _setState(OtaUpdateState.beginRequested);
    _uploadedBytes = 0;
    _deviceProgress = 0.0;
    _isUploading = false;'''

new_start = '''    _setState(OtaUpdateState.beginRequested);
    _uploadedBytes = 0;
    _deviceProgress = 0.0;
    _reportedFirmwareVersion = null;
    _isUploading = false;'''
content = content.replace(old_start, new_start)

# Replace _onConfigNotify
old_on_config = '''      } else if (msg == 'OTA_SUCCESS') {
        _rateTimer?.cancel();
        _setState(OtaUpdateState.rebooting);
        // We expect disconnect shortly. The app will reconnect automatically via GnssInfoService
        // Once reconnected, the provider will change and we can verify version.
        // For now, mark completed.
        Future.delayed(const Duration(seconds: 2), () {
            _setState(OtaUpdateState.completed);
        });
      } else if (msg.startsWith('OTA_ERROR:')) {'''

new_on_config = '''      } else if (msg == 'OTA_SUCCESS') {
        _rateTimer?.cancel();
        _isUploading = false;
        _setState(OtaUpdateState.rebooting);
        
        _connSub?.cancel();
        _connSub = _provider!.transport.connectionStatus.listen((connected) {
          if (!connected && _state == OtaUpdateState.rebooting) {
            _setState(OtaUpdateState.reconnecting);
          }
        });
      } else if (_state == OtaUpdateState.verifyingVersion) {
        if (msg.isNotEmpty && !msg.startsWith('OTA_')) {
          _reportedFirmwareVersion = msg;
          if (_reportedFirmwareVersion == _firmwareVersion) {
            _setState(OtaUpdateState.completed);
          } else {
            _setState(OtaUpdateState.failed, error: 'VERSION MISMATCH');
          }
        }
      } else if (msg.startsWith('OTA_ERROR:')) {'''
content = content.replace(old_on_config, new_on_config)

# Add _verifyVersionAfterReconnect
verify_func = '''  void _verifyVersionAfterReconnect() async {
    _setState(OtaUpdateState.verifyingVersion);
    try {
      await _provider!.transport.writeExtra(MfkRtkConstants.configUuid, utf8.encode('GET_VERSION'));
      
      Future.delayed(const Duration(seconds: 5), () {
        if (_state == OtaUpdateState.verifyingVersion) {
          _setState(OtaUpdateState.failed, error: 'Timeout waiting for GET_VERSION response');
        }
      });
    } catch (e) {
      _setState(OtaUpdateState.failed, error: 'Failed to request version: $e');
    }
  }

  Future<void> cancelUpdate() async {'''
content = content.replace('  Future<void> cancelUpdate() async {', verify_func)

# Replace reset
old_reset = '''    _sha256Hash = null;
    _deviceProgress = 0.0;'''

new_reset = '''    _reportedFirmwareVersion = null;
    _sha256Hash = null;
    _deviceProgress = 0.0;'''
content = content.replace(old_reset, new_reset)

with open('lib/services/gnss/mfkrtk_ota_service.dart', 'w') as f:
    f.write(content)
