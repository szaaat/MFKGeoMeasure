import 'dart:math';

class KalmanStepDiagnostic {
  final double xBefore;
  final double pBefore;
  final double measurement;
  final double q;
  final double r;
  final double kalmanGain;
  final double xAfter;
  final double pAfter;

  const KalmanStepDiagnostic({
    required this.xBefore,
    required this.pBefore,
    required this.measurement,
    required this.q,
    required this.r,
    required this.kalmanGain,
    required this.xAfter,
    required this.pAfter,
  });

  Map<String, dynamic> toJson() => {
    'x_before': xBefore,
    'p_before': pBefore,
    'measurement': measurement,
    'q': q,
    'r': r,
    'kalman_gain': kalmanGain,
    'x_after': xAfter,
    'p_after': pAfter,
  };
}

class GpsKalmanDiagnostic {
  final KalmanStepDiagnostic latStep;
  final KalmanStepDiagnostic lonStep;

  const GpsKalmanDiagnostic({
    required this.latStep,
    required this.lonStep,
  });

  Map<String, dynamic> toJson() => {
    'lat': latStep.toJson(),
    'lon': lonStep.toJson(),
  };
}

/// Egy egyszerű 1D Kalman-szűrő implementáció.
/// Segít kiszűrni a GPS jel zaját és ugrálását.
class KalmanFilter {
  final double _q; // Folyamatzaj kovariancia (Process noise)
  final double _r; // Mérési zaj kovariancia (Measurement noise)
  double _x; // Becsült érték (State estimate)
  double _p; // Becslési hiba kovariancia (Estimation error covariance)
  double _k = 0; // Kalman-erősítés (Kalman gain)

  KalmanStepDiagnostic? lastDiagnostic;

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

    final double xBefore = _x;

    // Jóslási fázis (Prediction)
    _p = _p + _q;
    final double pBeforePredict = _p;

    // Frissítési fázis (Update / Correction)
    double denominator = _p + _r;
    if (denominator.abs() < 1e-12) return _x; // Protection against zero division

    _k = _p / denominator;
    _x = _x + _k * (measurement - _x);
    _p = (1 - _k) * _p;

    lastDiagnostic = KalmanStepDiagnostic(
      xBefore: xBefore,
      pBefore: pBeforePredict,
      measurement: measurement,
      q: _q,
      r: _r,
      kalmanGain: _k,
      xAfter: _x,
      pAfter: _p,
    );

    return _x;
  }

  double get value => _x;
}

/// GPS koordináták (Lat, Lon) szűrésére specializált osztály.
class GpsKalmanFilter {
  KalmanFilter? _latFilter;
  KalmanFilter? _lonFilter;

  GpsKalmanDiagnostic? lastDiagnostic;

  /// Frissíti a koordinátákat és visszaadja a szűrt értéket.
  List<double> filter(double lat, double lon, double accuracy) {
    if (!lat.isFinite || !lon.isFinite) return [lat, lon];
    if (!accuracy.isFinite || accuracy <= 0 || accuracy >= 99.0) return [lat, lon]; // Ha a pontosság ismeretlen (NaN) vagy durván érvénytelen, bypassoljuk a szűrőt.
    
    double safeAccuracy = accuracy;

    // Ha még nincsenek szűrők, inicializáljuk őket a kezdőértékkel.
    _latFilter ??= KalmanFilter(initialValue: lat, measurementNoise: _mapAccuracyToR(safeAccuracy));
    _lonFilter ??= KalmanFilter(initialValue: lon, measurementNoise: _mapAccuracyToR(safeAccuracy));

    final newLat = _latFilter!.update(lat);
    final newLon = _lonFilter!.update(lon);

    if (_latFilter!.lastDiagnostic != null && _lonFilter!.lastDiagnostic != null) {
      lastDiagnostic = GpsKalmanDiagnostic(
        latStep: _latFilter!.lastDiagnostic!,
        lonStep: _lonFilter!.lastDiagnostic!,
      );
    }

    return [newLat, newLon];
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
    lastDiagnostic = null;
  }
}
