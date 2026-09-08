import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../models/cogo_session.dart';
import '../services/cogo_service.dart';
import '../services/eov_service.dart';

class CogoProvider extends ChangeNotifier {
  final CogoService _cogoService;
  final EovService _eovService;
  EovService get eovService => _eovService;

  CogoProvider(this._cogoService, this._eovService);

  CogoType? _activeType;
  CogoType? get activeType => _activeType;

  final Map<String, CogoPoint> _points = {};
  Map<String, CogoPoint> get points => _points;

  // Területszámításhoz külön pontlista
  final List<CogoPoint> _areaPoints = [];
  List<CogoPoint> get areaPoints => _areaPoints;

  final Map<String, double> _parameters = {};
  Map<String, double> get parameters => _parameters;

  CogoCalculationReport? _report;
  CogoCalculationReport? get report => _report;

  int _selectedResultIndex = 0;
  int get selectedResultIndex => _selectedResultIndex;

  void setType(CogoType type) {
    _activeType = type;
    _points.clear();
    _areaPoints.clear();
    _parameters.clear();
    _report = null;
    _selectedResultIndex = 0;
    notifyListeners();
  }

  void addAreaPoint({double? y, double? x, LatLng? wgs, String source = 'manual'}) {
    double? finalY = y;
    double? finalX = x;
    LatLng? finalWgs = wgs;

    if (wgs != null && (y == null || x == null)) {
      final eov = _eovService.wgsToEov(wgs.latitude, wgs.longitude);
      finalY = eov[0];
      finalX = eov[1];
    } else if (y != null && x != null && wgs == null) {
      final w = _eovService.eovToWgs(y, x);
      finalWgs = LatLng(w[0], w[1]);
    }

    _areaPoints.add(CogoPoint(
      label: "P${_areaPoints.length + 1}",
      y: finalY,
      x: finalX,
      wgs: finalWgs,
      source: source,
    ));
    _calculate();
    notifyListeners();
  }

  void removeAreaPoint(int index) {
    if (index >= 0 && index < _areaPoints.length) {
      _areaPoints.removeAt(index);
      _calculate();
      notifyListeners();
    }
  }

  void updatePoint(String label, {double? y, double? x, LatLng? wgs, String source = 'manual'}) {
    double? finalY = y;
    double? finalX = x;
    LatLng? finalWgs = wgs;

    if (wgs != null && (y == null || x == null)) {
      final eov = _eovService.wgsToEov(wgs.latitude, wgs.longitude);
      finalY = eov[0];
      finalX = eov[1];
    } else if (y != null && x != null && wgs == null) {
      final w = _eovService.eovToWgs(y, x);
      finalWgs = LatLng(w[0], w[1]);
    }

    _points[label] = CogoPoint(label: label, y: finalY, x: finalX, wgs: finalWgs, source: source);
    _calculate();
    notifyListeners();
  }

  void clearPoint(String label) {
    _points.remove(label);
    _report = null;
    notifyListeners();
  }

  void updateParameter(String key, double value) {
    _parameters[key] = value;
    _calculate();
    notifyListeners();
  }

  void selectResult(int index) {
    _selectedResultIndex = index;
    notifyListeners();
  }

  String get pointsFingerprint {
    final sb = StringBuffer();
    _points.forEach((k, v) => sb.write("$k${v.y}${v.x}"));
    for (var p in _areaPoints) {
      sb.write("A${p.y}${p.x}");
    }
    return sb.toString();
  }

  void _calculate() {
    if (_activeType == null) return;

    try {
      switch (_activeType!) {
        case CogoType.inverse:
          if (_points['P1']?.isValid == true && _points['P2']?.isValid == true) {
            _report = _cogoService.generateEovInverseReport(
              _points['P1']!.y!, _points['P1']!.x!,
              _points['P2']!.y!, _points['P2']!.x!,
            );
          }
          break;
        case CogoType.angularIntersection:
          if (_points['P1']?.isValid == true && _points['P2']?.isValid == true &&
              _parameters['b1'] != null && _parameters['b2'] != null) {
            _report = _cogoService.generateAngularIntersectionReport(
              _points['P1']!.y!, _points['P1']!.x!, _parameters['b1']!,
              _points['P2']!.y!, _points['P2']!.x!, _parameters['b2']!,
            );
          }
          break;
        case CogoType.distanceIntersection:
          if (_points['P1']?.isValid == true && _points['P2']?.isValid == true &&
              _parameters['r1'] != null && _parameters['r2'] != null) {
            _report = _cogoService.generateDistanceIntersectionReport(
              _points['P1']!.y!, _points['P1']!.x!, _parameters['r1']!,
              _points['P2']!.y!, _points['P2']!.x!, _parameters['r2']!,
            );
          }
          break;
        case CogoType.resection:
          if (_points['P1']?.isValid == true && _points['P2']?.isValid == true && _points['P3']?.isValid == true &&
              _parameters['a1'] != null && _parameters['a2'] != null && _parameters['a3'] != null) {
            _report = _cogoService.generateResectionReport(
              [_points['P1']!.y!, _points['P1']!.x!],
              [_points['P2']!.y!, _points['P2']!.x!],
              [_points['P3']!.y!, _points['P3']!.x!],
              _parameters['a1']!, _parameters['a2']!, _parameters['a3']!,
            );
          }
          break;
        case CogoType.area:
          if (_areaPoints.length >= 3) {
            List<List<double>> eovPoints = _areaPoints
                .where((p) => p.isValid)
                .map((p) => [p.y!, p.x!])
                .toList();
            if (eovPoints.length >= 3) {
              _report = _cogoService.generateAreaReport(eovPoints);
            }
          } else {
            _report = null;
          }
          break;
      }
    } catch (e) {
      _report = CogoCalculationReport(title: "Hiba", results: {}, errorMessage: e.toString());
    }
  }
}
