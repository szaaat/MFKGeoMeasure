import 'package:proj4dart/proj4dart.dart';

class EovService {
  late Projection _wgs84;
  late Projection _eov;
  static bool _isRegistered = false;

  EovService() {
    _wgs84 = Projection.get('EPSG:4326')!;

    String eovDef =
        '+proj=somerc +lat_0=47.14439372222222 +lon_0=19.04857177777778 +k_0=0.99993 +x_0=650000 +y_0=200000 +ellps=GRS67 +towgs84=52.17,-71.82,-14.9,0,0,0,0 +units=m +no_defs';

    if (!_isRegistered && Projection.get('EPSG:23700') == null) {
      _eov = Projection.add('EPSG:23700', eovDef);
      _isRegistered = true;
    } else {
      _eov = Projection.get('EPSG:23700')!;
    }
  }

  List<double> wgsToEov(double lat, double lon) {
    Point p = Point(x: lon, y: lat);
    Point res = _wgs84.transform(_eov, p);
    return [res.y, res.x];
  }

  List<double> eovToWgs(double eovY, double eovX) {
    Point p = Point(x: eovY, y: eovX);
    Point res = _eov.transform(_wgs84, p);
    return [res.y, res.x];
  }
}
