import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart' as btc;
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as ble;
import 'package:usb_serial/usb_serial.dart' as usb;

import 'package:intl/intl.dart';
import '../services/gnss_info_service.dart';
import '../services/gnss/internal_gnss_provider.dart';
import '../services/gnss/external_gnss_provider.dart';
import '../services/gnss/bluetooth_classic_transport.dart';
import '../services/gnss/ble_transport.dart';
import '../services/gnss/usb_serial_transport.dart';
import '../services/gnss/rtcm_service.dart';
import '../services/gnss/ntrip_client.dart';
import '../models/gnss_fix.dart';
import '../models/ntrip_profile.dart';
import '../models/ntrip_source.dart';
import '../models/ntrip_diagnostics.dart';
import '../l10n/app_localizations.dart';
import '../services/geoid_service.dart';

class GnssSettingsScreen extends StatefulWidget {
  const GnssSettingsScreen({super.key});

  @override
  State<GnssSettingsScreen> createState() => _GnssSettingsScreenState();
}

class _GnssSettingsScreenState extends State<GnssSettingsScreen> {
  GnssConnectionType _selectedConnectionType = GnssConnectionType.internal;
  
  List<dynamic> _discoveredDevices = [];
  bool _isScanning = false;
  StreamSubscription? _bleScanSubscription;

  @override
  void initState() {
    super.initState();
    final gnssService = context.read<GnssInfoService>();
    final active = gnssService.activeProvider;

    if (active is InternalGnssProvider) {
      _selectedConnectionType = GnssConnectionType.internal;
    } else if (active is ExternalGnssProvider) {
       // Note: active connection type is not explicitly stored in provider yet
       // but we can infer from transport if needed. Defaulting to Internal if unknown.
    }
  }

  @override
  void dispose() {
    _bleScanSubscription?.cancel();
    super.dispose();
  }

  void _startScan() async {
    setState(() {
      _isScanning = true;
      _discoveredDevices = [];
    });

    try {
      if (_selectedConnectionType == GnssConnectionType.bluetoothClassic && Platform.isAndroid) {
        final devices = await btc.FlutterBluetoothSerial.instance.getBondedDevices();
        if (!mounted) return;
        setState(() => _discoveredDevices = devices);
      } else if (_selectedConnectionType == GnssConnectionType.ble) {
        await ble.FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
        _bleScanSubscription?.cancel();
        _bleScanSubscription = ble.FlutterBluePlus.scanResults.listen((results) {
          if (!mounted) return;
          setState(() => _discoveredDevices = results.map((r) => r.device).toList());
        });
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

  void _connectToDevice(dynamic device) {
    final gnssService = context.read<GnssInfoService>();
    final geoidService = context.read<GeoidCorrectionService>();
    final rtcmService = context.read<RtcmService>();
    
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
      final transport = BleTransport(deviceId: (device as ble.BluetoothDevice).remoteId.str);
      gnssService.setProvider(ExternalGnssProvider(
        transport: transport,
        connectionType: GnssConnectionType.ble,
        receiverName: device.platformName,
      ), rtcmService: rtcmService);
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
            _buildNtripSection(l10n),
          ],
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
            
            ...settings.profiles.map((p) => ListTile(
              title: Text(p.name, style: TextStyle(fontWeight: p.id == settings.activeProfileId ? FontWeight.bold : FontWeight.normal)),
              subtitle: Text("${p.host}:${p.port}"),
              leading: Radio<String>(
                value: p.id,
                groupValue: settings.activeProfileId,
                onChanged: (val) => gnssService.setActiveProfile(val, rtcmService: rtcmService),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(icon: const Icon(Icons.edit, size: 20), onPressed: () => _showProfileDialog(p)),
                  IconButton(icon: const Icon(Icons.delete, size: 20, color: Colors.red), onPressed: () => gnssService.deleteProfile(p.id)),
                ],
              ),
              onTap: () => gnssService.setActiveProfile(p.id, rtcmService: rtcmService),
            )),
            
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

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing == null ? l10n.addProfile : l10n.editProfile),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
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
                                 _showMountpointSelector(sources, (m) => setDialogState(() => mountCtrl.text = m));
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

  void _showMountpointSelector(List<NtripSource> sources, Function(String) onSelected) {
     showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Select Mountpoint"),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: sources.length,
            itemBuilder: (context, index) {
              final s = sources[index];
              return ListTile(
                title: Text(s.mountpoint),
                subtitle: Text("${s.format} | ${s.system}"),
                onTap: () {
                  onSelected(s.mountpoint);
                  Navigator.pop(ctx);
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Color _getStatusColor(NtripStatus s) {
    switch (s) {
      case NtripStatus.connected: return Colors.blue;
      case NtripStatus.correctionDataActive: return Colors.green;
      case NtripStatus.error: return Colors.red;
      case NtripStatus.connecting:
      case NtripStatus.reconnecting: return Colors.orange;
      case NtripStatus.notConfigured: return Colors.redAccent;
      default: return Colors.grey;
    }
  }

  Color _getCorrectionAgeColor(NtripDataStatus s) {
    switch (s) {
      case NtripDataStatus.good: return Colors.green;
      case NtripDataStatus.warning: return Colors.orange;
      case NtripDataStatus.poor:
      case NtripDataStatus.noData: return Colors.red;
    }
  }

  String _getFriendlyStatus(NtripStatus s, AppLocalizations l10n) {
    switch (s) {
      case NtripStatus.connected: return "Connected (Wait)";
      case NtripStatus.correctionDataActive: return "Data Active";
      case NtripStatus.error: return "Error";
      case NtripStatus.connecting: return "Connecting...";
      case NtripStatus.reconnecting: return l10n.reconnecting;
      case NtripStatus.disconnected: return "Disconnected";
      case NtripStatus.notConfigured: return "Not Configured";
    }
  }
}
