import 'package:flutter_test/flutter_test.dart';
import 'package:mfk_geomeasure/models/gnss_fix.dart';
import 'package:mfk_geomeasure/services/eov_service.dart';
import 'package:mfk_geomeasure/services/geoid_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('BME horizontal and vertical grids reproduce PROJ reference point',
      () async {
    final geoid = GeoidCorrectionService();
    await geoid.loadBmeGrid();
    final eov = EovService(geoid.gridService, true, EovInputFrame.etrf2000);
    await eov.loadBmeGrids();

    final result = eov.wgsToEov(47.97801236, 20.43002679);
    expect(result[0], closeTo(753218.9656450956, 0.00001));
    expect(result[1], closeTo(293622.2580149178, 0.00001));
    final inverse = eov.eovToWgs(result[0], result[1]);
    expect(inverse[0], closeTo(47.97801236, 0.00000005));
    expect(inverse[1], closeTo(20.43002679, 0.00000005));

    final undulation = geoid.getUndulation(
      47.97801236,
      20.43002679,
      referenceFrame: GeoidInputFrame.etrf2000,
    );
    expect(undulation, closeTo(42.345627, 0.00001));
    expect(
      geoid.getOrthoHeight(
        47.97801236,
        20.43002679,
        233.625,
        isEllipsoidal: true,
        referenceFrame: GeoidInputFrame.etrf2000,
      ),
      closeTo(191.279373063, 0.00001),
    );
  });

  test('BME grid rejects points outside its coverage', () async {
    final geoid = GeoidCorrectionService();
    await geoid.loadBmeGrid();
    final eov = EovService(geoid.gridService, true, EovInputFrame.etrf2000);
    await eov.loadBmeGrids();

    expect(() => eov.wgsToEov(60, 20), throwsStateError);
    expect(geoid.getUndulation(60, 20), isNull);
  });

  test('Unknown ellipsoidal height can use the documented assumed BME geoid',
      () async {
    final geoid = GeoidCorrectionService();
    await geoid.loadBmeGrid();
    final height = geoid.getOrthoHeight(
      47.97801236,
      20.43002679,
      233.625,
      isEllipsoidal: true,
      referenceFrame: GeoidInputFrame.assumed,
    );
    expect(height, closeTo(191.279373063, 0.00001));
  });

  test('Orthometric source height is never corrected a second time', () async {
    final geoid = GeoidCorrectionService();
    await geoid.loadBmeGrid();
    expect(
      geoid.getOrthoHeight(
        47.97801236,
        20.43002679,
        191.279373063,
        isEllipsoidal: false,
        referenceFrame: GeoidInputFrame.assumed,
      ),
      closeTo(191.279373063, 0.000001),
    );
  });

  test('BME transformation matches PROJ at additional Hungarian points',
      () async {
    final geoid = GeoidCorrectionService();
    await geoid.loadBmeGrid();
    final eov = EovService(geoid.gridService, true, EovInputFrame.etrf2000);
    await eov.loadBmeGrids();
    const points = <(double, double, double, double)>[
      (47.0, 19.0, 646390.8696705152, 183979.35805050327),
      (47.5, 19.5, 684095.1277083699, 239661.07389460443),
      (48.2, 21.0, 795147.2767348439, 319206.98639065615),
      (46.2, 17.0, 491976.26926968934, 97121.04387352985),
    ];
    for (final (lat, lon, expectedE, expectedN) in points) {
      final actual = eov.wgsToEov(lat, lon);
      expect(actual[0], closeTo(expectedE, 0.00002));
      expect(actual[1], closeTo(expectedN, 0.00002));
      final inverse = eov.eovToWgs(actual[0], actual[1]);
      expect(inverse[0], closeTo(lat, 0.00000005));
      expect(inverse[1], closeTo(lon, 0.00000005));
    }
  });

  test('Unknown reference frame never receives a BME correction', () async {
    final geoid = GeoidCorrectionService();
    await geoid.loadBmeGrid();
    final eov = EovService(
      geoid.gridService,
      false,
      EovInputFrame.unknown,
      EovTransformMode.unknown,
    );
    await eov.loadBmeGrids();
    final result = eov.transformWgsToEov(47.97801236, 20.43002679);
    expect(result.coordinates, isNull);
    expect(result.status, EovTransformStatus.unknownReferenceFrame);
    expect(() => eov.wgsToEov(47.97801236, 20.43002679), throwsStateError);
    expect(geoid.getUndulation(47.97801236, 20.43002679), isNull);
  });

  test('Unknown frame uses the documented BME assumption in default mode',
      () async {
    final geoid = GeoidCorrectionService();
    await geoid.loadBmeGrid();
    final eov = EovService(geoid.gridService);
    final result = eov.transformWgsToEov(47.97801236, 20.43002679);
    expect(result.coordinates, isNotNull);
    expect(result.status, EovTransformStatus.bmeGridAssumedFrame);
  });

  test('Legacy transformation is available only when explicitly selected', () {
    final eov =
        EovService(null, false, EovInputFrame.unknown, EovTransformMode.legacy);
    final result = eov.transformWgsToEov(47.97801236, 20.43002679);
    expect(result.coordinates, isNotNull);
    expect(result.status, EovTransformStatus.legacy);
  });

  test('EOV inverse never falls back to legacy when BME is unavailable', () {
    final eov = EovService();
    expect(
      () => eov.eovToWgs(753218.9656450956, 293622.2580149178),
      throwsStateError,
    );

    final unknown = EovService(
      null,
      false,
      EovInputFrame.unknown,
      EovTransformMode.unknown,
    );
    expect(
      () => unknown.eovToWgs(753218.9656450956, 293622.2580149178),
      throwsStateError,
    );
  });

  test('GNSS reference metadata defaults to unknown and survives serialization',
      () {
    final fix = GnssFix(
      latitude: 47,
      longitude: 19,
      altitude: 100,
      ellipsoidalHeight: 100,
      isEllipsoidal: true,
      source: GnssSource.internal,
      connectionType: GnssConnectionType.internal,
      timestamp: DateTime.utc(2026),
    );
    expect(fix.referenceFrame, GnssReferenceFrame.unknown);
    expect(fix.toMap()['referenceFrame'], 'unknown');
  });
}
