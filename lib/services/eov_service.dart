import 'package:proj4dart/proj4dart.dart';
import 'bme_grid_service.dart';

enum EovInputFrame { unknown, etrf2000 }

enum EovTransformMode { unknown, bmeEtrf2000, bmeAssumed, legacy }

enum EovTransformStatus {
  bmeGrid,
  bmeGridAssumedFrame,
  legacy,
  unknownReferenceFrame,
  outsideGrid,
  gridNotLoaded
}

class EovTransformResult {
  final List<double>? coordinates;
  final EovTransformMode mode;
  final EovTransformStatus status;

  const EovTransformResult({
    required this.coordinates,
    required this.mode,
    required this.status,
  });

  bool get isAvailable => coordinates != null;
}

class EovService {
  late Projection _wgs84;
  late Projection _eov;
  final BmeGridService gridService;
  final bool requireBme;
  final EovInputFrame inputFrame;
  final EovTransformMode mode;
  static bool _isRegistered = false;

  EovService([
    BmeGridService? gridService,
    this.requireBme = false,
    this.inputFrame = EovInputFrame.unknown,
    EovTransformMode? explicitMode,
  ])  : mode = explicitMode ??
            (inputFrame == EovInputFrame.etrf2000
                ? EovTransformMode.bmeEtrf2000
                : EovTransformMode.bmeAssumed),
        gridService = gridService ?? BmeGridService() {
    _wgs84 = Projection.get('EPSG:4326')!;

    String eovDef =
        '+proj=somerc +lat_0=47.14439372222222 +lon_0=19.04857177777778 +k_0=0.99993 +x_0=650000 +y_0=200000 +ellps=GRS67 +towgs84=52.17,-71.82,-14.9,0,0,0,0 +units=m +no_defs';
    const hdDef =
        '+proj=somerc +lat_0=47.14439372222222 +lon_0=19.04857177777778 +k_0=0.99993 +x_0=650000 +y_0=200000 +ellps=GRS67 +units=m +no_defs';

    if (!_isRegistered && Projection.get('EPSG:23700') == null) {
      _eov = Projection.add('EPSG:23700', eovDef);
      _isRegistered = true;
    } else {
      _eov = Projection.get('EPSG:23700')!;
    }
    if (Projection.get('MFK_HD72_EOV') == null) {
      Projection.add('MFK_HD72_EOV', hdDef);
    }
  }

  Future<void> loadBmeGrids() => gridService.load();

  EovTransformResult transformWgsToEov(double lat, double lon,
      {EovInputFrame? sourceFrame, EovTransformMode? requestedMode}) {
    final selected = requestedMode ??
        (sourceFrame == EovInputFrame.etrf2000
            ? EovTransformMode.bmeEtrf2000
            : mode);
    if (selected == EovTransformMode.unknown) {
      return const EovTransformResult(
        coordinates: null,
        mode: EovTransformMode.unknown,
        status: EovTransformStatus.unknownReferenceFrame,
      );
    }
    if (selected == EovTransformMode.legacy) {
      final res = _wgs84.transform(_eov, Point(x: lon, y: lat));
      return EovTransformResult(
        coordinates: [res.x, res.y],
        mode: selected,
        status: EovTransformStatus.legacy,
      );
    }
    if (!gridService.isLoaded) {
      return EovTransformResult(
        coordinates: null,
        mode: selected,
        status: EovTransformStatus.gridNotLoaded,
      );
    }
    final hd = gridService.etrfToHd(lon, lat);
    if (hd == null) {
      return EovTransformResult(
        coordinates: null,
        mode: selected,
        status: EovTransformStatus.outsideGrid,
      );
    }
    final res = _wgs84.transform(
      Projection.get('MFK_HD72_EOV')!,
      Point(x: hd[0], y: hd[1]),
    );
    return EovTransformResult(
      coordinates: [res.x, res.y],
      mode: selected,
      status: selected == EovTransformMode.bmeAssumed
          ? EovTransformStatus.bmeGridAssumedFrame
          : EovTransformStatus.bmeGrid,
    );
  }

  List<double> wgsToEov(double lat, double lon) {
    final result = transformWgsToEov(lat, lon);
    if (result.coordinates == null ||
        (requireBme && result.mode != EovTransformMode.bmeEtrf2000)) {
      throw StateError(result.status == EovTransformStatus.unknownReferenceFrame
          ? 'No verified EOV transformation is available for an unknown reference frame'
          : 'BME EOV transformation requires an explicitly identified ETRF2000 input frame');
    }
    return result.coordinates!;
  }

  EovTransformResult transformEovToWgs(double eovY, double eovX,
      {EovTransformMode? requestedMode}) {
    final selected = requestedMode ?? mode;
    if (selected == EovTransformMode.unknown) {
      return const EovTransformResult(
        coordinates: null,
        mode: EovTransformMode.unknown,
        status: EovTransformStatus.unknownReferenceFrame,
      );
    }
    if (selected == EovTransformMode.legacy) {
      final res = _eov.transform(_wgs84, Point(x: eovY, y: eovX));
      return EovTransformResult(
        coordinates: [res.y, res.x],
        mode: selected,
        status: EovTransformStatus.legacy,
      );
    }
    if (!gridService.isLoaded) {
      return EovTransformResult(
        coordinates: null,
        mode: selected,
        status: EovTransformStatus.gridNotLoaded,
      );
    }
    final hdProjection = Projection.get('MFK_HD72_EOV')!;
    final hd = hdProjection.transform(_wgs84, Point(x: eovY, y: eovX));
    final etrf = gridService.hdToEtrf(hd.x, hd.y);
    if (etrf == null) {
      return EovTransformResult(
        coordinates: null,
        mode: selected,
        status: EovTransformStatus.outsideGrid,
      );
    }
    return EovTransformResult(
      coordinates: [etrf[1], etrf[0]],
      mode: selected,
      status: selected == EovTransformMode.bmeAssumed
          ? EovTransformStatus.bmeGridAssumedFrame
          : EovTransformStatus.bmeGrid,
    );
  }

  List<double> eovToWgs(double eovY, double eovX) {
    final result = transformEovToWgs(eovY, eovX);
    if (result.coordinates == null ||
        (requireBme && result.mode != EovTransformMode.bmeEtrf2000)) {
      throw StateError(result.status == EovTransformStatus.unknownReferenceFrame
          ? 'No verified EOV transformation is available for an unknown reference frame'
          : 'BME EOV transformation requires an explicitly identified ETRF2000 input frame or is outside grid');
    }
    return result.coordinates!;
  }
}
