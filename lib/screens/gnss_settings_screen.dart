import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:provider/provider.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart' as btc;
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as ble;
import 'package:usb_serial/usb_serial.dart' as usb;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:intl/intl.dart';
import '../services/gnss_info_service.dart';
import '../services/gnss/internal_gnss_provider.dart';
import '../services/gnss/external_gnss_provider.dart';
import '../services/gnss/bluetooth_classic_transport.dart';
import '../services/gnss/ble_transport.dart';
import '../services/gnss/usb_serial_transport.dart';
import '../services/gnss/mfkrtk_provider.dart';
import '../services/gnss/rtcm_service.dart';
import '../services/gnss/ntrip_client.dart';
import '../models/gnss_fix.dart';
import '../models/gnss/mfkrtk_constants.dart';
import '../models/ntrip_profile.dart';
import '../models/ntrip_source.dart';
import '../models/ntrip_diagnostics.dart';
import '../l10n/app_localizations.dart';
import 'mfkrtk_diagnostics_screen.dart';
import 'mfkrtk_ota_screen.dart' as hu;
import '../services/geoid_service.dart';

class GnssSettingsScreen extends StatefulWidget {
  const GnssSettingsScreen({super.key});

  @override
  State<GnssSettingsScreen> createState() => _GnssSettingsScreenState();
}

class _GnssSettingsScreenState extends State<GnssSettingsScreen> {
  GnssConnectionType _selectedConnectionType = GnssConnectionType.mfkrtk;
  
  List<dynamic> _discoveredDevices = [];
  bool _isScanning = false;
  bool _autoConnectInProgress = false;
  bool _sendingMfkCommand = false;
  double _headingDegrees = 0;
  StreamSubscription? _bleScanSubscription;
  String? _savedMfkDeviceId;

  @override
  void initState() {
    super.initState();
    _loadSavedMfkDevice();
  }

  Future<void> _loadSavedMfkDevice() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _savedMfkDeviceId = prefs.getString('last_mfk_device_id');
      });
    } catch (error) {
      debugPrint('Saved MFKRTK device could not be loaded: $error');
    }
  }

  @override
  void dispose() {
    _bleScanSubscription?.cancel();
    super.dispose();
  }

  Future<void> _runMfkCommand(
    GnssInfoService gnssService,
    String label,
    Future<void> Function(MfkRtkProvider provider) command,
  ) async {
    final provider = gnssService.activeProvider;
    if (provider is! MfkRtkProvider || _sendingMfkCommand) return;
    setState(() => _sendingMfkCommand = true);
    try {
      await command(provider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$label elküldve a vevőnek.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$label sikertelen: $error'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _sendingMfkCommand = false);
    }
  }

  Future<void> _readPhoneHeading() async {
    try {
      final event = await FlutterCompass.events?.first.timeout(const Duration(seconds: 3));
      final heading = event?.heading;
      if (heading != null && heading.isFinite && mounted) {
        setState(() => _headingDegrees = (heading % 360 + 360) % 360);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Az iránytű nem érhető el: $error')),
      );
    }
  }

  void _startScan() async {
    setState(() {
      _isScanning = true;
      _discoveredDevices = [];
      _autoConnectInProgress = false;
    });

    try {
      if (_selectedConnectionType == GnssConnectionType.bluetoothClassic && Platform.isAndroid) {
        final devices = await btc.FlutterBluetoothSerial.instance.getBondedDevices();
        if (!mounted) return;
        setState(() => _discoveredDevices = devices);
      } else if (_selectedConnectionType == GnssConnectionType.ble ||
          _selectedConnectionType == GnssConnectionType.mfkrtk) {
        await _bleScanSubscription?.cancel();
        _bleScanSubscription = ble.FlutterBluePlus.scanResults.listen((results) {
          if (!mounted) return;

          if (_selectedConnectionType == GnssConnectionType.mfkrtk) {
            final matchingDevices = results.where(_isEkoxRtkDevice).toList();
            if (_savedMfkDeviceId != null) {
              matchingDevices.sort((a, b) {
                final aSaved = a.device.remoteId.str == _savedMfkDeviceId;
                final bSaved = b.device.remoteId.str == _savedMfkDeviceId;
                return aSaved == bSaved ? 0 : (aSaved ? -1 : 1);
              });
            }
            setState(() => _discoveredDevices = matchingDevices);
            if (matchingDevices.isNotEmpty && !_autoConnectInProgress) {
              _autoConnectInProgress = true;
              debugPrint('[BLE] EKOX RTK found; stopping scan and connecting');
              unawaited(ble.FlutterBluePlus.stopScan().then((_) {
                if (mounted) _connectToDevice(matchingDevices.first);
              }));
            }
          } else {
            setState(() => _discoveredDevices = results.toList());
          }
        });
        await ble.FlutterBluePlus.startScan(timeout: const Duration(seconds: 8));
      } else if (_selectedConnectionType == GnssConnectionType.usb && Platform.isAndroid) {
        final devices = await usb.UsbSerial.listDevices();
        if (!mounted) return;
        setState(() => _discoveredDevices = devices);
      }
    } catch (e) {
      debugPrint("Scan error: $e");
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  bool _isEkoxRtkDevice(ble.ScanResult result) {
    final advName = result.advertisementData.advName.toLowerCase();
    final platformName = result.device.platformName.toLowerCase();
    final nameMatch = MfkRtkConstants.deviceNameFilters.any(
      (filter) => advName.contains(filter) || platformName.contains(filter),
    );
    final serviceMatch = result.advertisementData.serviceUuids.any(
      (uuid) => uuid.toString().toLowerCase() == MfkRtkConstants.serviceUuid.toLowerCase(),
    );
    return nameMatch || serviceMatch;
  }

  void _connectToDevice(dynamic deviceItem) {
    final gnssService = context.read<GnssInfoService>();
    final geoidService = context.read<GeoidCorrectionService>();
    final rtcmService = context.read<RtcmService>();
    
    final dynamic device = deviceItem is ble.ScanResult ? deviceItem.device : deviceItem;

    if (_selectedConnectionType == GnssConnectionType.mfkrtk &&
        device is ble.BluetoothDevice) {
      SharedPreferences.getInstance().then((prefs) async {
        await prefs.setString('last_mfk_device_id', device.remoteId.str);
      }).catchError((error) {
        debugPrint('MFKRTK device could not be saved: $error');
      });
    }

    if (_selectedConnectionType == GnssConnectionType.internal) {
      gnssService.setProvider(InternalGnssProvider(geoidService: geoidService), rtcmService: rtcmService);
    } else if (_selectedConnectionType == GnssConnectionType.bluetoothClassic) {
      final transport = BluetoothClassicTransport(deviceAddress: (device as btc.BluetoothDevice).address);
      gnssService.setProvider(ExternalGnssProvider(
        transport: transport,
        connectionType: GnssConnectionType.bluetoothClassic,
        receiverName: device.name ?? "BT Classic GNSS",
      ), rtcmService: rtcmService);
    } else if (_selectedConnectionType == GnssConnectionType.ble) {
      final bleDev = device as ble.BluetoothDevice;
      final name = bleDev.platformName.isNotEmpty 
          ? bleDev.platformName 
          : (deviceItem is ble.ScanResult && deviceItem.advertisementData.advName.isNotEmpty 
              ? deviceItem.advertisementData.advName 
              : "BLE GNSS");
      final transport = BleTransport(deviceId: bleDev.remoteId.str);
      gnssService.setProvider(ExternalGnssProvider(
        transport: transport,
        connectionType: GnssConnectionType.ble,
        receiverName: name,
      ), rtcmService: rtcmService);
    } else if (_selectedConnectionType == GnssConnectionType.mfkrtk) {
      final bleDev = device as ble.BluetoothDevice;
      final transport = BleTransport(
        deviceId: bleDev.remoteId.str,
        serviceUuid: MfkRtkConstants.serviceUuid,
        rxCharacteristicUuid: MfkRtkConstants.gnssDataUuid,
        txCharacteristicUuid: MfkRtkConstants.rtcmInputUuid,
      );
      gnssService.setProvider(MfkRtkProvider(transport: transport), rtcmService: rtcmService);
    } else if (_selectedConnectionType == GnssConnectionType.usb) {
      final transport = UsbSerialTransport(device: device as usb.UsbDevice);
      gnssService.setProvider(ExternalGnssProvider(
        transport: transport,
        connectionType: GnssConnectionType.usb,
        receiverName: "USB GNSS",
      ), rtcmService: rtcmService);
    }
    
    if (device != null) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    
    return Scaffold(
      appBar: AppBar(title: Text(l10n.gnssSource)),
      body: SingleChildScrollView(
        child: Column(
          children: [
            ListTile(
              title: Text(l10n.internalGps),
              leading: const Icon(Icons.phone_android),
              trailing: _selectedConnectionType == GnssConnectionType.internal ? const Icon(Icons.check, color: Colors.green) : null,
              onTap: () {
                setState(() => _selectedConnectionType = GnssConnectionType.internal);
                _connectToDevice(null);
              },
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                children: [
                  Expanded(
                    child: DropdownButton<GnssConnectionType>(
                      value: _selectedConnectionType == GnssConnectionType.internal ? GnssConnectionType.bluetoothClassic : _selectedConnectionType,
                      isExpanded: true,
                      items: [
                        if (Platform.isAndroid)
                          DropdownMenuItem(value: GnssConnectionType.bluetoothClassic, child: Text(l10n.bluetoothClassic)),
                        DropdownMenuItem(value: GnssConnectionType.ble, child: Text(l10n.bluetoothBle)),
                        const DropdownMenuItem(value: GnssConnectionType.mfkrtk, child: Text("EKOX RTK")),
                        if (Platform.isAndroid)
                          DropdownMenuItem(value: GnssConnectionType.usb, child: Text(l10n.usbSerial)),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedConnectionType = val);
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: _isScanning ? null : _startScan,
                    child: Text(_isScanning ? "..." : "Scan"),
                  ),
                ],
              ),
            ),
            if (_discoveredDevices.isNotEmpty) ...[
              const Divider(),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _discoveredDevices.length,
                itemBuilder: (ctx, i) {
                  final dev = _discoveredDevices[i];
                  String name = "Unknown";
                  String address = "";
                  
                  if (dev is btc.BluetoothDevice) {
                    name = dev.name ?? "Unknown BT";
                    address = dev.address;
                  } else if (dev is ble.ScanResult) {
                    name = _selectedConnectionType == GnssConnectionType.mfkrtk && _isEkoxRtkDevice(dev)
                        ? "EKOX RTK"
                        : (dev.advertisementData.advName.isNotEmpty
                            ? dev.advertisementData.advName
                            : (dev.device.platformName.isNotEmpty ? dev.device.platformName : "BLE Device"));
                    address = dev.device.remoteId.str;
                  } else if (dev is ble.BluetoothDevice) {
                    name = dev.platformName.isNotEmpty ? dev.platformName : "Unknown BLE";
                    address = dev.remoteId.str;
                  } else if (dev is usb.UsbDevice) {
                    name = "USB Device ${dev.vid}:${dev.pid}";
                    address = dev.deviceName;
                  }
                  
                  return ListTile(
                    title: Text(name),
                    subtitle: Text(l10n.deviceAddress(address)),
                    onTap: () => _connectToDevice(dev),
                  );
                },
              ),
            ],
            const Divider(),
            _buildMfkRtkStatusCard(context.watch<GnssInfoService>()),
            _buildNtripSection(l10n),
          ],
        ),
      ),
    );
  }

  Widget _buildMfkRtkStatusCard(GnssInfoService gnssService) {
    final l10n = AppLocalizations.of(context)!;
    final status = gnssService.mfkRtkStatus;
    final nav = gnssService.mfkRtkNavData;
    final lastFix = gnssService.lastFix;
    final isMfkActive = gnssService.activeProvider is MfkRtkProvider;
    final insAlign = nav?.insAlign ?? status?.insAlign ?? lastFix?.insStatus ?? 'INS_INACTIVE';
    final posType = nav?.posType ?? status?.posType ?? lastFix?.positionSource ?? 'NONE';
    final rtcmOk = nav?.rtcmOk ?? status?.rtcmOk ?? false;
    final rtcmAgeMs = nav?.rtcmAgeMs ?? status?.rtcmAgeMs ?? -1;
    final rtcmPkts = nav?.rtcmPkts ?? status?.rtcmPkts ?? 0;
    final rtcmBytes = nav?.rtcmBytes ?? status?.rtcmBytes ?? 0;

    if (!isMfkActive) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.tune, color: Colors.blue),
                  const SizedBox(width: 8),
                  const Text("MFKRTK / SmartPuck Status", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const Spacer(),
                  (() {
                    final batPct = (status?.batteryPercentage != null && status!.batteryPercentage > 0)
                        ? status.batteryPercentage
                        : (nav?.batteryPercentage != null && nav!.batteryPercentage! > 0)
                            ? nav.batteryPercentage
                            : null;
                    if (batPct != null && batPct > 0) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          color: batPct > 20 ? Colors.green.shade50 : Colors.red.shade50,
                          border: Border.all(color: batPct > 20 ? Colors.green : Colors.red, width: 1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              batPct > 50
                                  ? Icons.battery_full
                                  : batPct > 20
                                      ? Icons.battery_4_bar
                                      : Icons.battery_alert,
                              size: 14,
                              color: batPct > 20 ? Colors.green.shade800 : Colors.red.shade800,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              "$batPct%",
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: batPct > 20 ? Colors.green.shade900 : Colors.red.shade900,
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  })(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: status?.bleConnected == true ? Colors.green.shade100 : Colors.orange.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      status?.bleConnected == true ? "BLE OK" : "CONNECTED",
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: status?.bleConnected == true ? Colors.green.shade900 : Colors.orange.shade900,
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(),
              _diagRow(
                l10n.battery,
                (status?.batteryPercentage != null && status!.batteryPercentage > 0)
                    ? "${status.batteryPercentage}% (${status.batteryVoltage.toStringAsFixed(2)} V)"
                    : (nav?.batteryPercentage != null && nav!.batteryPercentage! > 0)
                        ? "${nav.batteryPercentage}% (${nav.batteryVoltage?.toStringAsFixed(2) ?? '--'} V)"
                        : l10n.searching,
                color: ((status?.batteryPercentage != null && status!.batteryPercentage > 0)
                        ? status.batteryPercentage
                        : nav?.batteryPercentage ?? 100) <= 20
                    ? Colors.red
                    : null,
              ),
              if (status != null)
                _diagRow(l10n.firmwareVersion, status.firmwareVersion),
              if (lastFix != null) ...[
                _diagRow(l10n.positionSource, lastFix.positionSource ?? "N/A"),
                _diagRow(l10n.insStatus, lastFix.insStatus ?? "N/A", color: lastFix.isInsGood ? Colors.green : Colors.orange),
                _diagRow(l10n.rtkStatusLabel, lastFix.rtkStatus.name.toUpperCase(), color: lastFix.rtkStatus == RtkStatus.fixed ? Colors.green : Colors.orange),
                if (lastFix.heading != null) _diagRow("Heading (M21)", "${lastFix.heading!.toStringAsFixed(1)}°"),
                if (lastFix.pitch != null && lastFix.roll != null)
                  _diagRow("Tilt (Roll / Pitch)", "${lastFix.roll!.toStringAsFixed(1)}° / ${lastFix.pitch!.toStringAsFixed(1)}°"),
              ],
              const SizedBox(height: 8),
              Card(
                color: Colors.blueGrey.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.insAlignment, style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      _diagRow(l10n.insState, insAlign, color: _insAlignmentColor(insAlign)),
                      _diagRow(l10n.m21Position, posType, color: _posTypeColor(posType)),
                      const SizedBox(height: 4),
                      Text('RTCM: ${rtcmOk ? 'OK' : (rtcmAgeMs < 0 ? l10n.noData : 'Timeout')}'
                          ' · ${l10n.age} ${rtcmAgeMs < 0 ? '—' : '${(rtcmAgeMs / 1000).toStringAsFixed(1)} s'}'),
                      Text('${l10n.packets} $rtcmPkts · ${l10n.bytes} $rtcmBytes'),
                      Slider(
                        value: _headingDegrees.clamp(0, 360),
                        min: 0,
                        max: 360,
                        divisions: 360,
                        label: '${_headingDegrees.toStringAsFixed(0)}°',
                        onChanged: (value) => setState(() => _headingDegrees = value),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text('${_headingDegrees.toStringAsFixed(1)}°', style: const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      const Text(
                        'A CONFIG-parancsok BLE-írása csak az elküldést igazolja. '
                        'A SET_HEADING, INS_RESTART, GET_RTCM_STATUS, '
                        'M21_CONFIGURE_INS és M21_SAVE_CONFIG firmware-támogatása '
                        'még ellenőrizendő.',
                        style: TextStyle(fontSize: 12, color: Colors.deepOrange),
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          TextButton.icon(
                            onPressed: _readPhoneHeading,
                            icon: const Icon(Icons.explore),
                            label: Text(l10n.compass),
                          ),
                          FilledButton.icon(
                            onPressed: !_sendingMfkCommand
                                ? () => _runMfkCommand(gnssService, 'SET HEADING', (provider) => provider.setHeading(_headingDegrees))
                                : null,
                            icon: const Icon(Icons.explore_outlined),
                            label: const Text('SET HEADING'),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: _sendingMfkCommand
                                ? null
                                : () => _runMfkCommand(gnssService, 'INS RESTART', (provider) => provider.restartIns()),
                            icon: const Icon(Icons.restart_alt),
                            label: const Text('INS RESTART'),
                            style: FilledButton.styleFrom(foregroundColor: Colors.deepOrange),
                          ),
                        ],
                      ),
                      Wrap(
                        spacing: 8,
                        children: [
                          TextButton(
                            onPressed: _sendingMfkCommand ? null : () => _runMfkCommand(gnssService, 'RTCM státusz', (provider) => provider.getRtcmStatus()),
                            child: Text(l10n.rtcmRefresh),
                          ),
                          TextButton(
                            onPressed: _sendingMfkCommand ? null : () => _runMfkCommand(gnssService, 'M21 konfigurálás', (provider) => provider.reconfigureM21()),
                            child: Text(l10n.m21Configure),
                          ),
                          TextButton(
                            onPressed: _sendingMfkCommand ? null : () => _runMfkCommand(gnssService, 'Konfiguráció mentése', (provider) => provider.saveM21Config()),
                            child: Text(l10n.saveM21Config),
                          ),
                        ],
                      ),
                      if (gnssService.lastMfkConfigMessage != null)
                        Text(
                          l10n.receiverResponse(gnssService.lastMfkConfigMessage!),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11, color: Colors.blueGrey),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const MfkRtkDiagnosticsScreen()),
                    );
                  },
                  icon: const Icon(Icons.bug_report),
                  label: Text(l10n.rawDiagnosticsLogger),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const hu.MfkRtkOtaScreen()),
                    );
                  },
                  icon: const Icon(Icons.system_update_alt),
                  label: Text(l10n.firmwareUpdateOta),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }


  Widget _buildNtripSection(AppLocalizations l10n) {
    final gnssService = context.watch<GnssInfoService>();
    final rtcmService = context.watch<RtcmService>();
    final settings = gnssService.ntripSettings;
    
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(l10n.ntripSettings, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Switch(
                value: settings.enabled,
                onChanged: (val) {
                  settings.enabled = val;
                  gnssService.updateNtripSettings(settings, rtcmService: rtcmService);
                },
              ),
            ],
          ),
          
          if (settings.enabled) ...[
            _buildStatusCard(rtcmService, l10n),
            const SizedBox(height: 16),
            
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(l10n.profiles, style: const TextStyle(fontWeight: FontWeight.bold)),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline, color: Colors.blue),
                  onPressed: () => _showProfileDialog(null),
                )
              ],
            ),
            
            RadioGroup<String>(
              groupValue: settings.activeProfileId,
              onChanged: (value) {
                if (value != null) {
                  gnssService.setActiveProfile(value, rtcmService: rtcmService);
                }
              },
              child: Column(
                children: settings.profiles.map((p) => ListTile(
                  title: Text(p.name, style: TextStyle(fontWeight: p.id == settings.activeProfileId ? FontWeight.bold : FontWeight.normal)),
                  subtitle: Text("${p.host}:${p.port} • ${p.mountpoint.isEmpty ? 'no mountpoint' : p.mountpoint}"),
                  leading: Radio<String>(value: p.id),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(icon: const Icon(Icons.edit, size: 20), onPressed: () => _showProfileDialog(p)),
                      IconButton(icon: const Icon(Icons.delete, size: 20, color: Colors.red), onPressed: () => gnssService.deleteProfile(p.id)),
                    ],
                  ),
                  onTap: () => gnssService.setActiveProfile(p.id, rtcmService: rtcmService),
                )).toList(),
              ),
            ),
            
            const Divider(),
            
            SwitchListTile(
              title: Text(l10n.requireStableFix, style: const TextStyle(fontSize: 14)),
              subtitle: Text("${l10n.stabilityThreshold}: ${settings.stabilityThresholdSeconds}s"),
              value: settings.requireStableFix,
              onChanged: (val) {
                settings.requireStableFix = val;
                gnssService.updateNtripSettings(settings);
              },
            ),
            
            if (settings.requireStableFix)
              Slider(
                value: settings.stabilityThresholdSeconds.toDouble(),
                min: 1, max: 30, divisions: 29,
                label: "${settings.stabilityThresholdSeconds}s",
                onChanged: (val) {
                  setState(() => settings.stabilityThresholdSeconds = val.round());
                  gnssService.updateNtripSettings(settings);
                },
              ),

            const Divider(),

            SwitchListTile(
              title: Text(l10n.allowFloatSave, style: const TextStyle(fontSize: 14)),
              subtitle: Text(l10n.allowFloatSaveSub, style: const TextStyle(fontSize: 12)),
              value: gnssService.allowFloatSave,
              onChanged: (val) {
                gnssService.setAllowFloatSave(val);
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusCard(RtcmService rtcmService, AppLocalizations l10n) {
    final s = rtcmService.status;
    final diag = rtcmService.diagnostics;
    
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 12, height: 12,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: _getStatusColor(s)),
                ),
                const SizedBox(width: 10),
                Text(_getFriendlyStatus(s, l10n), style: const TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                if (s != NtripStatus.disconnected && s != NtripStatus.notConfigured)
                  TextButton(onPressed: () => rtcmService.stopNtrip(), child: Text(l10n.close))
                else
                  TextButton(
                    onPressed: s == NtripStatus.notConfigured ? null : () {
                      final gnss = context.read<GnssInfoService>();
                      gnss.updateNtripSettings(gnss.ntripSettings, rtcmService: rtcmService);
                    }, 
                    child: const Text("Connect")
                  ),
              ],
            ),
            if (s == NtripStatus.correctionDataActive || s == NtripStatus.connected) ...[
              const Divider(),
              _diagRow(l10n.bitrate, "${diag.bitrateKbps.toStringAsFixed(1)} kbps"),
              _diagRow("Correction Age", diag.correctionAgeString, color: _getCorrectionAgeColor(diag.status)),
              _diagRow(l10n.lastGgaSent, diag.lastGgaSent != null ? DateFormat('HH:mm:ss').format(diag.lastGgaSent!) : "Never"),
            ]
          ],
        ),
      ),
    );
  }

  Color _insAlignmentColor(String alignment) {
    switch (alignment.toUpperCase()) {
      case 'INS_SOLUTION_GOOD':
      case 'INS_ALIGNMENT_COMPLETE':
        return Colors.green;
      case 'WAITING_AZIMUTH':
      case 'WAITING_INITIALPOS':
        return Colors.orange;
      case 'INS_INACTIVE':
        return Colors.grey;
      default:
        return Colors.red;
    }
  }

  Color _posTypeColor(String posType) {
    switch (posType.toUpperCase()) {
      case 'NARROW_INT':
        return Colors.green;
      case 'NARROW_FLOAT':
        return Colors.amber.shade800;
      case 'SINGLE':
      case 'COARSE':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  Widget _diagRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  void _showProfileDialog(NtripProfile? existing) {
    final gnssService = context.read<GnssInfoService>();
    final l10n = AppLocalizations.of(context)!;
    
    final nameCtrl = TextEditingController(text: existing?.name ?? "");
    final hostCtrl = TextEditingController(text: existing?.host ?? "");
    final portCtrl = TextEditingController(text: existing?.port.toString() ?? "2101");
    final mountCtrl = TextEditingController(text: existing?.mountpoint ?? "");
    final userCtrl = TextEditingController(text: existing?.username ?? "");
    final pwdCtrl = TextEditingController(); // Always empty for editing, only set if changed
    final ggaCtrl = TextEditingController(text: existing?.ggaInterval.toString() ?? "10");
    
    String selectedProvider = existing?.provider ?? "custom";

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing == null ? l10n.addProfile : l10n.editProfile),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selectedProvider,
                  decoration: InputDecoration(labelText: l10n.ntripProvider),
                  items: [
                    DropdownMenuItem(value: "custom", child: Text(l10n.providerCustom)),
                    DropdownMenuItem(value: "centipede", child: Text(l10n.providerCentipede)),
                    DropdownMenuItem(value: "gnssnet", child: Text(l10n.providerGnssNet)),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setDialogState(() {
                        selectedProvider = val;
                        if (val == "centipede") {
                          nameCtrl.text = "Centipede-RTK";
                          hostCtrl.text = "crtk.net";
                          portCtrl.text = "2101";
                          mountCtrl.text = "NEAR";
                          userCtrl.text = "c";
                          pwdCtrl.text = "c";
                          ggaCtrl.text = "10";
                        } else if (val == "gnssnet") {
                          nameCtrl.text = "GNSSnet.hu";
                          hostCtrl.text = "gnssnet.hu";
                          portCtrl.text = "2101";
                        }
                      });
                    }
                  },
                ),
                const SizedBox(height: 10),
                TextField(controller: nameCtrl, decoration: InputDecoration(labelText: l10n.profileName)),
                TextField(controller: hostCtrl, decoration: const InputDecoration(labelText: "Host")),
                Row(
                  children: [
                    Expanded(child: TextField(controller: portCtrl, decoration: const InputDecoration(labelText: "Port"), keyboardType: TextInputType.number)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: mountCtrl, 
                        decoration: InputDecoration(
                          labelText: "Mountpoint",
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.list),
                            onPressed: () async {
                               try {
                                 final sources = await NtripClient.fetchSourceTable(
                                   host: hostCtrl.text,
                                   port: int.tryParse(portCtrl.text) ?? 2101,
                                   username: userCtrl.text,
                                   password: pwdCtrl.text,
                                 );
                                 final selectedMountpoint =
                                     await _showMountpointSelector(sources);
                                 if (!ctx.mounted || selectedMountpoint == null) {
                                   return;
                                 }
                                 mountCtrl.text = selectedMountpoint;
                               } catch (e) {
                                 if (ctx.mounted) {
                                   ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(e.toString())));
                                 }
                               }
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                
                // Quick Select Mountpoints
                Padding(
                  padding: const EdgeInsets.only(top: 8.0, bottom: 8.0),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      ActionChip(
                        label: const Text("NEAR", style: TextStyle(fontSize: 10)),
                        onPressed: () => setDialogState(() { mountCtrl.text = "NEAR"; ggaCtrl.text = "10"; }),
                      ),
                      ActionChip(
                        label: const Text("NEAR4", style: TextStyle(fontSize: 10)),
                        onPressed: () => setDialogState(() { mountCtrl.text = "NEAR4"; ggaCtrl.text = "10"; }),
                      ),
                    ],
                  ),
                ),

                TextField(controller: userCtrl, decoration: const InputDecoration(labelText: "Username")),
                TextField(controller: pwdCtrl, decoration: const InputDecoration(labelText: "Password (leave empty if unchanged)"), obscureText: true),
                TextField(controller: ggaCtrl, decoration: const InputDecoration(labelText: "GGA Interval (s)"), keyboardType: TextInputType.number),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.cancel)),
            ElevatedButton(
              onPressed: () {
                final p = NtripProfile(
                  id: existing?.id,
                  name: nameCtrl.text,
                  host: hostCtrl.text.trim(),
                  port: int.tryParse(portCtrl.text) ?? 2101,
                  mountpoint: mountCtrl.text.trim(),
                  username: userCtrl.text.trim(),
                  ggaInterval: int.tryParse(ggaCtrl.text) ?? 10,
                  provider: selectedProvider,
                );
                gnssService.saveProfile(p, pwdCtrl.text.isNotEmpty ? pwdCtrl.text : null);
                Navigator.pop(ctx);
              },
              child: Text(l10n.save),
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _showMountpointSelector(List<NtripSource> sources) async {
    return showDialog<String>(
      context: context,
      builder: (_) => _MountpointSelectorDialog(sources: sources),
    );
  }

  Color _getStatusColor(NtripStatus s) {
    switch (s) {
      case NtripStatus.connected:
        return Colors.blue;
      case NtripStatus.correctionDataActive:
        return Colors.green;
      case NtripStatus.error:
        return Colors.red;
      case NtripStatus.connecting:
      case NtripStatus.reconnecting:
        return Colors.orange;
      case NtripStatus.notConfigured:
        return Colors.redAccent;
      default:
        return Colors.grey;
    }
  }

  Color _getCorrectionAgeColor(NtripDataStatus s) {
    switch (s) {
      case NtripDataStatus.good:
        return Colors.green;
      case NtripDataStatus.warning:
        return Colors.orange;
      case NtripDataStatus.poor:
      case NtripDataStatus.noData:
        return Colors.red;
    }
  }

  String _getFriendlyStatus(NtripStatus s, AppLocalizations l10n) {
    switch (s) {
      case NtripStatus.connected:
        return l10n.connectedWait;
      case NtripStatus.correctionDataActive:
        return l10n.dataActive;
      case NtripStatus.error:
        return l10n.error;
      case NtripStatus.connecting:
        return l10n.connecting;
      case NtripStatus.reconnecting:
        return l10n.reconnecting;
      case NtripStatus.disconnected:
        return l10n.disconnected;
      case NtripStatus.notConfigured:
        return l10n.notConfigured;
    }
  }
}

class _MountpointSelectorDialog extends StatefulWidget {
  const _MountpointSelectorDialog({required this.sources});

  final List<NtripSource> sources;

  @override
  State<_MountpointSelectorDialog> createState() =>
      _MountpointSelectorDialogState();
}

class _MountpointSelectorDialogState
    extends State<_MountpointSelectorDialog> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final filteredSources = widget.sources.where((source) {
      if (query.isEmpty) return true;
      return source.mountpoint.toLowerCase().contains(query) ||
          source.format.toLowerCase().contains(query) ||
          source.system.toLowerCase().contains(query);
    }).toList();

    return AlertDialog(
      title: const Text('Select Mountpoint'),
      content: SizedBox(
        width: double.maxFinite,
        height: 420,
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Search mountpoints',
                prefixIcon: Icon(Icons.search),
                suffixIcon: Icon(Icons.filter_alt_outlined),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: filteredSources.isEmpty
                  ? const Center(child: Text('No matching mountpoints'))
                  : ListView.builder(
                      itemCount: filteredSources.length,
                      itemBuilder: (context, index) {
                        final source = filteredSources[index];
                        return ListTile(
                          title: Text(source.mountpoint),
                          subtitle:
                              Text('${source.format} | ${source.system}'),
                          onTap: () =>
                              Navigator.pop(context, source.mountpoint),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

}
