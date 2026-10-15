import 'dart:math';

import 'package:latlong2/latlong.dart';

import '../models/field_definition.dart';
import '../models/geo_feature.dart';

enum ValidationSeverity { error, warning }

class DataValidationIssue {
  final ValidationSeverity severity;
  final String message;
  final String? featureName;

  const DataValidationIssue({
    required this.severity,
    required this.message,
    this.featureName,
  });
}

class DataValidationService {
  const DataValidationService();

  List<DataValidationIssue> validateFeature({
    required GeoFeature feature,
    required List<CustomFieldDefinition> fields,
    String? crsInfo,
  }) {
    final issues = <DataValidationIssue>[];
    void error(String message) => issues.add(DataValidationIssue(
          severity: ValidationSeverity.error,
          message: message,
          featureName: feature.name,
        ));
    void warning(String message) => issues.add(DataValidationIssue(
          severity: ValidationSeverity.warning,
          message: message,
          featureName: feature.name,
        ));

    final points = feature.geometry;
    final minimum = switch (feature.type) {
      FeatureType.point => 1,
      FeatureType.line => 2,
      FeatureType.polygon => 3,
    };
    if (points.isEmpty) {
      error('Üres geometria: nincs menthető koordináta.');
    } else if (points.length < minimum) {
      error('Kevés csúcspont: ehhez a geometriához legalább $minimum szükséges.');
    }

    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      if (!p.latitude.isFinite ||
          !p.longitude.isFinite ||
          p.latitude < -90 ||
          p.latitude > 90 ||
          p.longitude < -180 ||
          p.longitude > 180) {
        error('Érvénytelen WGS84 koordináta a(z) ${i + 1}. csúcspontnál.');
        break;
      }
    }

    final duplicateCheckLength = feature.type == FeatureType.polygon &&
            points.length > 3 && _samePoint(points.first, points.last)
        ? points.length - 1
        : points.length;
    for (var i = 1; i < duplicateCheckLength; i++) {
      if (_samePoint(points[i - 1], points[i])) {
        error('Egymás melletti ismétlődő csúcspont van a geometriában.');
        break;
      }
    }

    if (feature.type == FeatureType.polygon && points.length >= 3) {
      final ring = points.length > 3 && _samePoint(points.first, points.last)
          ? points.sublist(0, points.length - 1)
          : points;
      if (_hasSelfIntersection(ring)) {
        error('A poligon önmetsző; javítsd a csúcspontok sorrendjét.');
      }
      if (_polygonArea(ring) < 0.01) {
        error('A poligon területe nulla vagy túl kicsi.');
      }
    }

    if (feature.type == FeatureType.line && points.length >= 2 &&
        _lineLength(points) < 0.01) {
      error('A vonal hossza nulla vagy túl kicsi.');
    }

    for (final field in fields.where((f) => f.isRequired)) {
      final value = feature.customData[field.key];
      if (value == null || value.toString().trim().isEmpty) {
        error('Hiányzó kötelező mező: ${field.label}.');
      }
    }

    if (points.isNotEmpty && points.every((p) =>
        p.latitude.isFinite && p.longitude.isFinite &&
        p.latitude >= -90 && p.latitude <= 90 &&
        p.longitude >= -180 && p.longitude <= 180)) {
      final normalizedCrs = crsInfo?.toUpperCase() ?? '';
      final looksEov = normalizedCrs.contains('EOV') ||
          normalizedCrs.contains('23700') ||
          normalizedCrs.contains('HD72');
      if (looksEov && points.any((p) =>
          p.latitude < 45 || p.latitude > 49 ||
          p.longitude < 15 || p.longitude > 23)) {
        warning('A réteg EOV-ként van címkézve, de a tárolt koordináták '
            'nem magyarországi WGS84 tartományba esnek. Ellenőrizd a CRS-t.');
      } else if (normalizedCrs.contains('UNKNOWN') ||
          normalizedCrs.contains('ISMERETLEN')) {
        warning('A koordináta-rendszer nincs megbízhatóan megadva.');
      }
    }

    return issues;
  }

  bool _samePoint(LatLng a, LatLng b) =>
      (a.latitude - b.latitude).abs() < 1e-10 &&
      (a.longitude - b.longitude).abs() < 1e-10;

  bool _hasSelfIntersection(List<LatLng> ring) {
    final count = ring.length;
    for (var i = 0; i < count; i++) {
      final a = ring[i];
      final b = ring[(i + 1) % count];
      for (var j = i + 1; j < count; j++) {
        if (j == i || j == (i + 1) % count || (j + 1) % count == i) {
          continue;
        }
        final c = ring[j];
        final d = ring[(j + 1) % count];
        if (_segmentsIntersect(a, b, c, d)) return true;
      }
    }
    return false;
  }

  bool _segmentsIntersect(LatLng a, LatLng b, LatLng c, LatLng d) {
    final abC = _orientation(a, b, c);
    final abD = _orientation(a, b, d);
    final cdA = _orientation(c, d, a);
    final cdB = _orientation(c, d, b);
    const epsilon = 1e-12;
    if (abC.abs() < epsilon && _onSegment(a, b, c)) return true;
    if (abD.abs() < epsilon && _onSegment(a, b, d)) return true;
    if (cdA.abs() < epsilon && _onSegment(c, d, a)) return true;
    if (cdB.abs() < epsilon && _onSegment(c, d, b)) return true;
    return (abC > 0) != (abD > 0) && (cdA > 0) != (cdB > 0);
  }

  double _orientation(LatLng a, LatLng b, LatLng c) =>
      (b.longitude - a.longitude) * (c.latitude - a.latitude) -
      (b.latitude - a.latitude) * (c.longitude - a.longitude);

  bool _onSegment(LatLng a, LatLng b, LatLng p) =>
      p.longitude >= min(a.longitude, b.longitude) - 1e-12 &&
      p.longitude <= max(a.longitude, b.longitude) + 1e-12 &&
      p.latitude >= min(a.latitude, b.latitude) - 1e-12 &&
      p.latitude <= max(a.latitude, b.latitude) + 1e-12;

  double _polygonArea(List<LatLng> ring) {
    const earthRadius = 6371008.8;
    var sum = 0.0;
    for (var i = 0; i < ring.length; i++) {
      final a = ring[i];
      final b = ring[(i + 1) % ring.length];
      final latA = a.latitude * pi / 180;
      final latB = b.latitude * pi / 180;
      final lonDelta = (b.longitude - a.longitude) * pi / 180;
      sum += lonDelta * (2 + sin(latA) + sin(latB));
    }
    return (sum * earthRadius * earthRadius / 2).abs();
  }

  double _lineLength(List<LatLng> points) {
    const distance = Distance();
    var length = 0.0;
    for (var i = 1; i < points.length; i++) {
      length += distance.as(LengthUnit.Meter, points[i - 1], points[i]);
    }
    return length;
  }
}
