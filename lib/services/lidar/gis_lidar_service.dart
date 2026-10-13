import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../models/geo_feature.dart';

class LidarSurfaceMeasurement {
  final double x;
  final double y;
  final double z;
  final double slope;
  final double aspect;
  final double rmse;
  final int pointCount;
  final String anchorId;
  final DateTime timestamp;

  LidarSurfaceMeasurement({
    required this.x,
    required this.y,
    required this.z,
    required this.slope,
    required this.aspect,
    required this.rmse,
    required this.pointCount,
    required this.anchorId,
    required this.timestamp,
  });

  Map<String, dynamic> toMetadata() {
    return {
      'Survey Method': SurveyMethods.lidarSurface,
      'L_Y': y.toStringAsFixed(3),
      'L_SLOPE': slope.toStringAsFixed(1),
      'L_ASPECT': aspect.toStringAsFixed(1),
      'L_RMSE': rmse.toStringAsFixed(3),
      'L_PNTS': pointCount,
      'L_ANCHOR': anchorId,
    };
  }
}

class GisLidarService extends ChangeNotifier {
  static const _channel = MethodChannel('com.mfk.geomeasure/gis_lidar');

  bool _isActive = false;
  bool get isActive => _isActive;

  final List<LidarSurfaceMeasurement> _measurements = [];
  List<LidarSurfaceMeasurement> get measurements => List.unmodifiable(_measurements);

  Future<bool> isSupported() async {
    if (!Platform.isIOS) return false;
    try {
      return await _channel.invokeMethod<bool>('isSupported') ?? false;
    } catch (e) {
      return false;
    }
  }

  Future<void> startSession() async {
    await _channel.invokeMethod('startSession');
    _isActive = true;
    _measurements.clear();
    notifyListeners();
  }

  Future<void> stopSession() async {
    await _channel.invokeMethod('stopSession');
    _isActive = false;
    notifyListeners();
  }

  Future<LidarSurfaceMeasurement?> measureSurface() async {
    final result = await _channel.invokeMapMethod<String, dynamic>('performSurfaceMeasurement');
    if (result != null) {
      final measurement = LidarSurfaceMeasurement(
        x: result['x'],
        y: result['y'],
        z: result['z'],
        slope: result['slope'],
        aspect: result['aspect'],
        rmse: result['rmse'],
        pointCount: result['pointCount'],
        anchorId: result['anchorId'],
        timestamp: DateTime.now(),
      );
      _measurements.add(measurement);
      notifyListeners();
      return measurement;
    }
    return null;
  }
}
