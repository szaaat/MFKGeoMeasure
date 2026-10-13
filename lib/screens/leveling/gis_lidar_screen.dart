import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:latlong2/latlong.dart';
import '../../services/lidar/gis_lidar_service.dart';
import '../../services/project_service.dart';
import '../../models/geo_feature.dart';

class GisLidarScreen extends StatefulWidget {
  const GisLidarScreen({super.key});

  @override
  State<GisLidarScreen> createState() => _GisLidarScreenState();
}

class _GisLidarScreenState extends State<GisLidarScreen> {
  bool _isSupported = false;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final lidar = context.read<GisLidarService>();
    _isSupported = await lidar.isSupported();
    if (_isSupported) {
      await lidar.startSession();
    }
    if (mounted) setState(() => _checking = false);
  }

  @override
  void dispose() {
    context.read<GisLidarService>().stopSession();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (!_isSupported) return _buildUnsupported();

    final lidar = context.watch<GisLidarService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('GIS LiDAR Engine'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => lidar.startSession(),
          )
        ],
      ),
      body: Stack(
        children: [
          Container(color: Colors.black),
          _buildOverlay(lidar),
          Positioned(
            bottom: 30, left: 20, right: 20,
            child: _buildControls(lidar),
          ),
          _buildCrosshair(),
        ],
      ),
    );
  }

  Widget _buildUnsupported() {
    return Scaffold(
      appBar: AppBar(title: const Text('GIS LiDAR')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 60, color: Colors.red),
            const SizedBox(height: 20),
            const Text('iPhone Pro LiDAR required', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 30),
            ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('Back')),
          ],
        ),
      ),
    );
  }

  Widget _buildCrosshair() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 30, height: 1, color: Colors.white70),
          Container(width: 1, height: 30, color: Colors.white70),
        ],
      ),
    );
  }

  Widget _buildOverlay(GisLidarService lidar) {
    return Positioned(
      top: 20, left: 20, right: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoPanel(lidar),
          const SizedBox(height: 10),
          if (lidar.measurements.length >= 2) _buildDeltaPanel(lidar),
        ],
      ),
    );
  }

  Widget _buildInfoPanel(GisLidarService lidar) {
    final last = lidar.measurements.isNotEmpty ? lidar.measurements.last : null;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('SURFACE ANALYSIS', style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 10)),
          const Divider(color: Colors.white24),
          Text('Y: ${last?.y.toStringAsFixed(3) ?? "---"} m', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          Text('Slope: ${last?.slope.toStringAsFixed(1) ?? "--"}°', style: const TextStyle(color: Colors.white70)),
          Text('Aspect: ${last?.aspect.toStringAsFixed(1) ?? "--"}°', style: const TextStyle(color: Colors.white70)),
          Text('RMSE: ${last?.rmse.toStringAsFixed(3) ?? "---"} m', style: const TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }

  Widget _buildDeltaPanel(GisLidarService lidar) {
    final last = lidar.measurements.last;
    final first = lidar.measurements.first;
    final deltaH = last.y - first.y;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.indigo.withOpacity(0.6), borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('ΔH (Last - First):', style: TextStyle(color: Colors.white, fontSize: 12)),
          Text('${deltaH.toStringAsFixed(3)} m', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
        ],
      ),
    );
  }

  Widget _buildControls(GisLidarService lidar) {
    return Column(
      children: [
        ElevatedButton.icon(
          onPressed: () async {
            final m = await lidar.measureSurface();
            if (m != null && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Surface Point Captured'), duration: Duration(seconds: 1)));
            }
          },
          icon: const Icon(Icons.add_location_alt),
          label: const Text('CAPTURE SURFACE POINT'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.all(16),
            minimumSize: const Size(double.infinity, 50),
          ),
        ),
        const SizedBox(height: 12),
        if (lidar.measurements.isNotEmpty)
          ElevatedButton.icon(
            onPressed: () => _saveToProject(lidar),
            icon: const Icon(Icons.save),
            label: const Text('SAVE TO GIS PROJECT'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.all(16),
              minimumSize: const Size(double.infinity, 50),
            ),
          ),
      ],
    );
  }

  void _saveToProject(GisLidarService lidar) {
    if (lidar.measurements.isEmpty) return;
    final project = context.read<ProjectService>();
    final last = lidar.measurements.last;
    
    project.setTool(FeatureType.point);
    project.addPointToGeometry(const LatLng(0, 0), last.y, fix: null);
    project.finishRecording(
      "LiDAR Point ${lidar.measurements.length}", 
      "Slope: ${last.slope.toStringAsFixed(1)}°",
      customData: last.toMetadata(),
    );
    
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved to GIS Layer'), backgroundColor: Colors.green));
  }
}
