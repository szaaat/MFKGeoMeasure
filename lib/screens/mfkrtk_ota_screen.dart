import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../services/gnss_info_service.dart';
import '../services/gnss/mfkrtk_ota_service.dart';
import '../services/gnss/mfkrtk_provider.dart';

class MfkRtkOtaScreen extends StatefulWidget {
  const MfkRtkOtaScreen({super.key});

  @override
  State<MfkRtkOtaScreen> createState() => _MfkRtkOtaScreenState();
}

class _MfkRtkOtaScreenState extends State<MfkRtkOtaScreen> {
  final _otaService = MfkRtkOtaService();
  final _versionController = TextEditingController(text: '0.2.2');

  @override
  void initState() {
    super.initState();
    _otaService.addListener(_onOtaStateChanged);
  }

  @override
  void dispose() {
    _otaService.removeListener(_onOtaStateChanged);
    _versionController.dispose();
    super.dispose();
  }

  void _onOtaStateChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _pickFile() async {
    try {
      final PlatformFile? result = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['bin'],
      );
      if (!mounted) return;
      if (result == null) return;

      debugPrint('[OTA] FilePicker returned: name=${result.name}, path=${result.path ?? result.uri}');
      final version = _versionController.text.trim();
      if (version.isEmpty) {
        _otaService.reportFailure('FILE_PICK_ERROR', 'Please enter a target version.');
        return;
      }

      await _otaService.prepareFirmware(result, version);
      if (_otaService.state == OtaUpdateState.idle && _otaService.firmwareBytes != null) {
        // Selecting the .bin begins the requested OTA flow; no second start action is required.
        await _otaService.startUpdate();
      }
    } catch (e) {
      debugPrint('[OTA] FILE_PICK_ERROR: $e');
      _otaService.reportFailure('FILE_PICK_ERROR', e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final gnssService = context.watch<GnssInfoService>();
    final isMfkActive = gnssService.activeProvider is MfkRtkProvider;
    
    if (isMfkActive && _otaService.state == OtaUpdateState.idle) {
      _otaService.attach(gnssService.activeProvider as MfkRtkProvider);
    }

    final currentFirmware = gnssService.mfkRtkStatus?.firmwareVersion ?? 'Unknown';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Firmware Update'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('DEVICE', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                    const Divider(),
                    _infoRow('Status:', isMfkActive ? 'CONNECTED' : 'DISCONNECTED', color: isMfkActive ? Colors.green : Colors.red),
                    _infoRow('Current Firmware:', currentFirmware),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _versionController,
                      decoration: const InputDecoration(
                        labelText: 'Target Version (e.g. 0.2.2)',
                        border: OutlineInputBorder(),
                      ),
                      enabled: _otaService.state == OtaUpdateState.idle || _otaService.state == OtaUpdateState.completed || _otaService.state == OtaUpdateState.failed || _otaService.state == OtaUpdateState.cancelled,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: (_otaService.state == OtaUpdateState.idle || _otaService.state == OtaUpdateState.completed || _otaService.state == OtaUpdateState.failed || _otaService.state == OtaUpdateState.cancelled) ? _pickFile : null,
                      icon: const Icon(Icons.folder),
                      label: const Text('SELECT .BIN FILE'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('OTA STATUS', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                    const Divider(),
                    _infoRow('State:', _otaService.state.name.toUpperCase(), color: _getStateColor(_otaService.state)),
                    if (_otaService.errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(_otaService.errorMessage!, style: const TextStyle(color: Colors.red)),
                      ),
                    const SizedBox(height: 8),
                    _infoRow('Target Firmware:', _otaService.firmwareVersion ?? '-'),
                    _infoRow('Reported Firmware:', _otaService.reportedFirmwareVersion ?? '-'),
                    if (_otaService.state == OtaUpdateState.completed)
                      _infoRow('Verification:', 'PASS', color: Colors.green)
                    else if (_otaService.state == OtaUpdateState.failed &&
                        (_otaService.errorMessage?.startsWith('OTA_VERIFY_ERROR:') ?? false))
                      _infoRow('Verification:', 'FAIL', color: Colors.red),
                    const SizedBox(height: 8),
                    _infoRow('File Size:', '${_otaService.firmwareSize} bytes'),
                    _infoRow('SHA-256:', _otaService.sha256Hash ?? '-'),
                    _infoRow('Uploaded:', '${_otaService.uploadedBytes} / ${_otaService.firmwareSize}'),
                    _infoRow('App Progress:', '${(_otaService.progress * 100).toStringAsFixed(1)} %'),
                    _infoRow('Device Progress:', '${_otaService.deviceProgress} %'),
                    _infoRow('Transfer Rate:', '${_otaService.transferRateKbps.toStringAsFixed(1)} kB/s'),
                    _infoRow('MTU:', '${_otaService.currentMtu} bytes'),
                    const SizedBox(height: 16),
                    if (_otaService.state == OtaUpdateState.uploading || _otaService.state == OtaUpdateState.verifying)
                      LinearProgressIndicator(value: _otaService.progress),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ElevatedButton.icon(
                          onPressed: (isMfkActive && _otaService.firmwareBytes != null && _otaService.state == OtaUpdateState.idle) 
                              ? () => _otaService.startUpdate() 
                              : null,
                          icon: const Icon(Icons.system_update_alt),
                          label: const Text('START UPDATE'),
                        ),
                        ElevatedButton.icon(
                          onPressed: (_otaService.state == OtaUpdateState.uploading || _otaService.state == OtaUpdateState.waitingForReady) 
                              ? () => _otaService.cancelUpdate() 
                              : null,
                          icon: const Icon(Icons.cancel),
                          label: const Text('CANCEL'),
                          style: ElevatedButton.styleFrom(foregroundColor: Colors.red),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  'Warning: Do not turn off the device or close the app during the firmware update. '
                  'The device will reboot automatically once the update is successfully finalized.',
                  style: TextStyle(color: Colors.orange, fontStyle: FontStyle.italic),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getStateColor(OtaUpdateState state) {
    switch (state) {
      case OtaUpdateState.idle: return Colors.grey;
      case OtaUpdateState.completed: return Colors.green;
      case OtaUpdateState.failed: return Colors.red;
      case OtaUpdateState.cancelled: return Colors.orange;
      case OtaUpdateState.uploading: return Colors.blue;
      case OtaUpdateState.verifyingVersion: return Colors.orange;
      default: return Colors.black;
    }
  }

  Widget _infoRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 2, child: Text(label, style: const TextStyle(color: Colors.grey))),
          Expanded(
            flex: 3, 
            child: Text(
              value, 
              style: TextStyle(fontWeight: FontWeight.bold, color: color),
              textAlign: TextAlign.right,
            )
          ),
        ],
      ),
    );
  }
}
