import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

class BmeGridService {
  static const _horizontalWidth = 251;
  static const _horizontalHeight = 121;
  static const _horizontalLon0 = 16.11111111111111;
  static const _horizontalLat0 = 48.88888888888889;
  static const _horizontalStep = 0.027777777777777776;

  static const _verticalWidth = 268;
  static const _verticalHeight = 186;
  static const _verticalLon0 = 16.1;
  static const _verticalLat0 = 48.89;
  static const _verticalLonStep = 0.026;
  static const _verticalLatStep = 0.018;

  Float32List? _horizontal;
  Float32List? _vertical;
  Future<void>? _loadFuture;

  bool get isLoaded => _horizontal != null && _vertical != null;

  Future<void> load() {
    return _loadFuture ??= _load();
  }

  Future<void> _load() async {
    final horizontal = await rootBundle.load('assets/data/hu_bme_hd72corr.f32');
    final vertical = await rootBundle.load('assets/data/hu_bme_geoid2014.f32');
    final h = Float32List.sublistView(horizontal);
    final v = Float32List.sublistView(vertical);
    if (h.length != _horizontalWidth * _horizontalHeight * 2 ||
        v.length != _verticalWidth * _verticalHeight) {
      throw const FormatException('Invalid BME grid cache size');
    }
    _horizontal = h;
    _vertical = v;
  }

  double? _interpolate(
    Float32List values,
    int width,
    int height,
    double x,
    double y, {
    int bands = 1,
    int band = 0,
    double noData = double.nan,
  }) {
    if (!x.isFinite ||
        !y.isFinite ||
        x < 0 ||
        y < 0 ||
        x > width - 1 ||
        y > height - 1) {
      return null;
    }
    final x0 = x.floor();
    final y0 = y.floor();
    final x1 = x0 == width - 1 ? x0 : x0 + 1;
    final y1 = y0 == height - 1 ? y0 : y0 + 1;
    final tx = x - x0;
    final ty = y - y0;

    double sample(int ix, int iy) =>
        values[(iy * width + ix) * bands + band].toDouble();
    final a = sample(x0, y0);
    final b = sample(x1, y0);
    final c = sample(x0, y1);
    final d = sample(x1, y1);
    bool invalid(double value) =>
        !value.isFinite || (noData.isFinite && value == noData);
    if ([a, b, c, d].any(invalid)) return null;
    final top = a + (b - a) * tx;
    final bottom = c + (d - c) * tx;
    return top + (bottom - top) * ty;
  }

  /// Converts ETRF2000 longitude/latitude to HD72 longitude/latitude.
  ///
  /// The official grid stores latitude correction in band 0 and longitude
  /// correction in band 1, in arc-seconds. PROJ's inverse hgridshift subtracts
  /// these corrections for the ETRF2000 -> HD72 direction.
  List<double>? etrfToHd(double longitude, double latitude) {
    final grid = _horizontal;
    if (grid == null) return null;
    var resultLon = longitude;
    var resultLat = latitude;
    for (var i = 0; i < 3; i++) {
      final x = (resultLon - _horizontalLon0) / _horizontalStep;
      final y = (_horizontalLat0 - resultLat) / _horizontalStep;
      final dLat = _interpolate(grid, _horizontalWidth, _horizontalHeight, x, y,
          bands: 2, band: 0);
      final dLon = _interpolate(grid, _horizontalWidth, _horizontalHeight, x, y,
          bands: 2, band: 1);
      if (dLat == null || dLon == null) return null;
      resultLon = longitude - dLon / 3600.0;
      resultLat = latitude - dLat / 3600.0;
    }
    return [resultLon, resultLat];
  }

  /// Converts HD72 longitude/latitude to ETRF2000 longitude/latitude.
  List<double>? hdToEtrf(double longitude, double latitude) {
    final grid = _horizontal;
    if (grid == null) return null;
    var resultLon = longitude;
    var resultLat = latitude;
    for (var i = 0; i < 3; i++) {
      final x = (resultLon - _horizontalLon0) / _horizontalStep;
      final y = (_horizontalLat0 - resultLat) / _horizontalStep;
      final dLat = _interpolate(grid, _horizontalWidth, _horizontalHeight, x, y,
          bands: 2, band: 0);
      final dLon = _interpolate(grid, _horizontalWidth, _horizontalHeight, x, y,
          bands: 2, band: 1);
      if (dLat == null || dLon == null) return null;
      resultLon = longitude + dLon / 3600.0;
      resultLat = latitude + dLat / 3600.0;
    }
    return [resultLon, resultLat];
  }

  double? geoidUndulation(double longitude, double latitude) {
    final grid = _vertical;
    if (grid == null) return null;
    final x = (longitude - _verticalLon0) / _verticalLonStep;
    final y = (_verticalLat0 - latitude) / _verticalLatStep;
    return _interpolate(grid, _verticalWidth, _verticalHeight, x, y,
        noData: -32768.0);
  }
}
