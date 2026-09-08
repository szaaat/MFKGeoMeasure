import 'package:latlong2/latlong.dart';

enum CogoType {
  inverse,
  angularIntersection,
  distanceIntersection,
  resection,
  area
}

class CogoPoint {
  final String label;
  final double? y;
  final double? x;
  final LatLng? wgs;
  final String source; // 'map', 'gnss', 'project', 'manual'

  CogoPoint({
    required this.label,
    this.y,
    this.x,
    this.wgs,
    this.source = 'manual',
  });

  bool get isValid => y != null && x != null;
}

class CogoCalculationReport {
  final String title;
  final Map<String, dynamic> results;
  final List<String> derivationSteps;
  final List<List<double>>? resultPoints; // [y, x] list
  final String? errorMessage;

  CogoCalculationReport({
    required this.title,
    required this.results,
    this.derivationSteps = const [],
    this.resultPoints,
    this.errorMessage,
  });

  bool get hasError => errorMessage != null;
}
