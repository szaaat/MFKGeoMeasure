import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/gnss/mfkrtk_diagnostics_logger.dart';
import '../services/gnss_info_service.dart';

class MfkRtkDiagnosticsScreen extends StatefulWidget {
  const MfkRtkDiagnosticsScreen({super.key});

  @override
  State<MfkRtkDiagnosticsScreen> createState() => _MfkRtkDiagnosticsScreenState();
}

class _MfkRtkDiagnosticsScreenState extends State<MfkRtkDiagnosticsScreen> {
  final _logger = MfkRtkDiagnosticsLogger();
  bool _isPaused = false;
  
  // Throttle updates for UI
  Timer? _uiUpdateTimer;

  @override
  void initState() {
    super.initState();
    _uiUpdateTimer = Timer.periodic(const Duration(milliseconds: 300), (_) {
      if (!_isPaused && mounted) {
        setState(() {}); // trigger rebuild
      }
    });
  }

  @override
  void dispose() {
    _uiUpdateTimer?.cancel();
    super.dispose();
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final state = _logger.state;
    final gnssService = context.watch<GnssInfoService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('MFKRTK Diagnostics'),
        actions: [
          IconButton(
            icon: Icon(_isPaused ? Icons.play_arrow : Icons.pause),
            tooltip: _isPaused ? 'Resume UI' : 'Pause UI',
            onPressed: () {
              setState(() => _isPaused = !_isPaused);
            },
          )
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          _build30sCaptureSection(gnssService),
          const SizedBox(height: 16),
          _buildDeviceSection(state, gnssService),
          const SizedBox(height: 16),
          _buildGnssDataSection(state),
          const SizedBox(height: 16),
          _buildKalmanDiagnosticsSection(gnssService),
          const SizedBox(height: 16),
          _buildRtcmSection(state),
          const SizedBox(height: 16),
          _buildLoggerSection(state),
          const SizedBox(height: 16),
          _buildLastDataSection(state),
        ],
      ),
    );
  }

  Widget _build30sCaptureSection(GnssInfoService gnssService) {
    final summary = gnssService.lastCaptureSummary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('30 SECOND DIAGNOSTIC CAPTURE', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                if (gnssService.is30sCapturing)
                  Text('${gnssService.captureRemainingSeconds}s', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.deepOrange)),
              ],
            ),
            const Divider(),
            if (gnssService.is30sCapturing) ...[
              LinearProgressIndicator(value: (30 - gnssService.captureRemainingSeconds) / 30.0),
              const SizedBox(height: 8),
              Text('Capturing epochs... (${gnssService.capturedEpochs.length} recorded)', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ] else ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => gnssService.start30sCapture(),
                  icon: const Icon(Icons.timer),
                  label: const Text('START 30s CAPTURE'),
                ),
              ),
            ],
            if (summary != null) ...[
              const SizedBox(height: 12),
              const Text('CAPTURE SUMMARY REPORT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const Divider(),
              _infoRow('Total Epochs:', '${summary.totalEpochs}'),
              _infoRow('RTK FIX Epochs:', '${summary.rtkFixEpochs}'),
              _infoRow('Rejected Epochs:', '${summary.rejectedEpochs}'),
              _infoRow('INS Rejected Epochs:', '${summary.insRejectedEpochs}'),
              _infoRow('Mean RAW \u2192 Kalman Shift:', '${summary.meanRawToKalmanShift.toStringAsFixed(4)} m',
                  color: summary.meanRawToKalmanShift < 0.01 ? Colors.green : Colors.orange),
              _infoRow('Max RAW \u2192 Kalman Shift:', '${summary.maxRawToKalmanShift.toStringAsFixed(4)} m'),
              const SizedBox(height: 8),
              const Text('Kalman Shift Decay After FIX:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.blueGrey)),
              _infoRow('  0 s:', '${summary.decayAt0s.toStringAsFixed(4)} m'),
              _infoRow('  5 s:', '${summary.decayAt5s.toStringAsFixed(4)} m'),
              _infoRow(' 10 s:', '${summary.decayAt10s.toStringAsFixed(4)} m'),
              _infoRow(' 20 s:', '${summary.decayAt20s.toStringAsFixed(4)} m'),
              _infoRow(' 30 s:', '${summary.decayAt30s.toStringAsFixed(4)} m'),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildKalmanDiagnosticsSection(GnssInfoService gnssService) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('KALMAN FILTER', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                Switch(
                  value: gnssService.enableKalmanFilter,
                  onChanged: (val) {
                    setState(() => gnssService.enableKalmanFilter = val);
                  },
                )
              ],
            ),
            const Divider(),
            _infoRow('Source:', gnssService.lastRawFix?.source.name.toUpperCase() ?? 'UNKNOWN'),
            _infoRow('Raw GNSS Valid:', gnssService.isPositionValid ? 'TRUE' : 'FALSE', color: gnssService.isPositionValid ? Colors.green : Colors.red),
            if (!gnssService.isPositionValid)
              _infoRow('Status:', 'NO FIX - position rejected', color: Colors.red),
            _infoRow('Raw Fix Type:', gnssService.lastRawFix?.fixType.name.toUpperCase() ?? '-'),
            _infoRow('Raw Data Age:', _formatAge(gnssService.lastRawFix?.timestamp)),
            _infoRow('Kalman Update Age:', _formatAge(gnssService.kalmanLastUpdateTime)),
            const SizedBox(height: 8),
            _infoRow('Raw Lat/Lon:', gnssService.lastRawFix != null 
                ? '${gnssService.lastRawFix!.latitude.toStringAsFixed(7)}, ${gnssService.lastRawFix!.longitude.toStringAsFixed(7)}' 
                : '-'),
            _infoRow('Kalman Output:', gnssService.lastFix != null 
                ? '${gnssService.lastFix!.latitude.toStringAsFixed(7)}, ${gnssService.lastFix!.longitude.toStringAsFixed(7)}' 
                : '-'),
            const SizedBox(height: 8),
            _infoRow('Distance Raw \u2192 Kalman:', '${gnssService.kalmanDistance.toStringAsFixed(3)} m', color: Colors.orange),
            _infoRow('Kalman Initialized:', gnssService.isKalmanInitialized ? 'TRUE' : 'FALSE'),
            _infoRow('Filter Status:', gnssService.enableKalmanFilter ? 'ACTIVE' : 'BYPASSED'),
            if (!gnssService.isPositionValid)
              _infoRow('Status:', 'NO FIX - position rejected', color: Colors.red),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceSection(state, GnssInfoService gnssService) {
    final status = gnssService.mfkRtkStatus;
    final nav = gnssService.mfkRtkNavData;
    final batPct = (status?.batteryPercentage != null && status!.batteryPercentage > 0)
        ? status.batteryPercentage
        : (nav?.batteryPercentage != null && nav!.batteryPercentage! > 0)
            ? nav.batteryPercentage
            : null;
    final batVolt = (status?.batteryVoltage != null && status!.batteryVoltage > 0)
        ? status.batteryVoltage
        : nav?.batteryVoltage;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('DEVICE', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
            const Divider(),
            _infoRow('Device:', state.deviceName),
            _infoRow('BLE Status:', state.isConnected ? 'CONNECTED' : 'DISCONNECTED', 
              color: state.isConnected ? Colors.green : Colors.red),
            _infoRow('Firmware:', status?.firmwareVersion ?? state.firmwareVersion ?? 'Unknown'),
            _infoRow(
              'Battery:',
              batPct != null
                  ? '$batPct% (${(batVolt ?? 0.0).toStringAsFixed(2)} V)'
                  : 'Waiting...',
              color: (batPct ?? 100) <= 20 ? Colors.red : Colors.green,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGnssDataSection(state) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('GNSS DATA (RX)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
            const Divider(),
            _infoRow('RX Rate:', '${_formatBytes(state.rxBytesPerSecond.round())}/s'),
            _infoRow('Total RX:', _formatBytes(state.totalRxBytes)),
            const SizedBox(height: 8),
            _infoRow('NMEA Rate:', '${state.nmeaMessagesPerSecond.toStringAsFixed(1)} msg/s'),
            _infoRow('NMEA Messages:', '${state.nmeaMessages} msg'),
            _infoRow('Binary Bytes:', _formatBytes(state.binaryBytes)),
          ],
        ),
      ),
    );
  }

  Widget _buildRtcmSection(state) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('RTCM (TX)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
            const Divider(),
            _infoRow('TX Total:', _formatBytes(state.rtcmTxBytes)),
            _infoRow('Packets:', '${state.rtcmPacketsSent}'),
            _infoRow('Errors:', '${state.rtcmErrors}'),
          ],
        ),
      ),
    );
  }

  Widget _buildLoggerSection(state) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('RAW LOGGER', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                if (state.isLogging)
                  const Icon(Icons.fiber_manual_record, color: Colors.red, size: 16),
              ],
            ),
            const Divider(),
            if (state.isLogging) ...[
              _infoRow('Elapsed:', _formatDuration(state.logDuration)),
              _infoRow('Size:', _formatBytes(state.logFileSize)),
            ] else ...[
              const Text('Not logging', style: TextStyle(color: Colors.grey)),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: state.isLogging ? null : () => _logger.startLogging(),
                  icon: const Icon(Icons.play_circle),
                  label: const Text('START LOG'),
                ),
                ElevatedButton.icon(
                  onPressed: !state.isLogging ? null : () => _logger.stopLogging(),
                  icon: const Icon(Icons.stop_circle),
                  label: const Text('STOP LOG'),
                ),
                if (!state.isLogging && state.logFilePath != null)
                  ElevatedButton.icon(
                    onPressed: () => _logger.shareLog(),
                    icon: const Icon(Icons.share),
                    label: const Text('SHARE'),
                  ),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildLastDataSection(state) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('RAW MONITOR', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                TextButton(
                  onPressed: () => _logger.clearMonitor(),
                  child: const Text('CLEAR'),
                )
              ],
            ),
            const Divider(),
            const Text('Last NMEA:', style: TextStyle(fontSize: 12, color: Colors.grey)),
            Text(state.lastNmeaSentence ?? '-', style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
            const SizedBox(height: 8),
            const Text('ASCII Preview (last 64 bytes):', style: TextStyle(fontSize: 12, color: Colors.grey)),
            Text(state.lastAsciiPreview ?? '-', style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
            const SizedBox(height: 8),
            const Text('HEX Preview (last 64 bytes):', style: TextStyle(fontSize: 12, color: Colors.grey)),
            Text(state.lastRawHex ?? '-', style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(color: Colors.grey)),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.bold, color: color),
            ),
          ),
        ],
      ),
    );
  }

  String _formatAge(DateTime? time) {
    if (time == null) return '-';
    final ms = DateTime.now().difference(time).inMilliseconds;
    return '$ms ms';
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
  }
}
