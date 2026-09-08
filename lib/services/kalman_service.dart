import 'dart:math';

/// Egy egyszerű 1D Kalman-szűrő implementáció.
/// Segít kiszűrni a GPS jel zaját és ugrálását.
class KalmanFilter {
  final double _q; // Folyamatzaj kovariancia (Process noise)
  final double _r; // Mérési zaj kovariancia (Measurement noise)
  double _x; // Becsült érték (State estimate)
  double _p; // Becslési hiba kovariancia (Estimation error covariance)
  double _k = 0; // Kalman-erősítés (Kalman gain)

  KalmanFilter({
    double processNoise = 0.000001,
    double measurementNoise = 0.0001,
    double initialValue = 0,
  })  : _q = processNoise,
        _r = measurementNoise,
        _x = initialValue,
        _p = 1.0;

  double update(double measurement) {
    if (!measurement.isFinite) return _x;

    // Jóslási fázis (Prediction)
    _p = _p + _q;

    // Frissítési fázis (Update / Correction)
    double denominator = _p + _r;
    if (denominator.abs() < 1e-12) return _x; // Protection against zero division

    _k = _p / denominator;
    _x = _x + _k * (measurement - _x);
    _p = (1 - _k) * _p;

    return _x;
  }

  double get value => _x;
}

/// GPS koordináták (Lat, Lon) szűrésére specializált osztály.
class GpsKalmanFilter {
  KalmanFilter? _latFilter;
  KalmanFilter? _lonFilter;

  /// Frissíti a koordinátákat és visszaadja a szűrt értéket.
  List<double> filter(double lat, double lon, double accuracy) {
    if (!lat.isFinite || !lon.isFinite) return [lat, lon];
    
    double safeAccuracy = accuracy.isFinite ? accuracy : 10.0;

    // Ha még nincsenek szűrők, inicializáljuk őket a kezdőértékkel.
    _latFilter ??= KalmanFilter(initialValue: lat, measurementNoise: _mapAccuracyToR(safeAccuracy));
    _lonFilter ??= KalmanFilter(initialValue: lon, measurementNoise: _mapAccuracyToR(safeAccuracy));

    return [
      _latFilter!.update(lat),
      _lonFilter!.update(lon),
    ];
  }

  /// Átalakítja a GPS pontosságot (méter) a szűrő számára értelmezhető mérési zajra (R).
  double _mapAccuracyToR(double accuracy) {
    if (!accuracy.isFinite) return 0.001;
    // Minél nagyobb a hiba méterben, annál kevésbé bízunk a mérésben (nagyobb R).
    return max(0.00001, accuracy * 0.00001);
  }

  void reset() {
    _latFilter = null;
    _lonFilter = null;
  }
}
