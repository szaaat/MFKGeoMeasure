import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/learning_task.dart';
import '../models/cogo_session.dart';
import 'cogo_service.dart';

class LearningService extends ChangeNotifier {
  final CogoService _cogoService;
  final Random _rng = Random();

  LearningService(this._cogoService);

  // Campus bázispontok (EOV Y, X)
  final Map<CampusLocation, List<double>> _basePoints = {
    CampusLocation.miskolc: [754000, 303000],
    CampusLocation.szekesfehervar: [582000, 205000],
  };

  CogoTask generateTask(CogoType type, CampusLocation campus, {bool isEnglish = false}) {
    final base = _basePoints[campus]!;
    final id = "task_${DateTime.now().millisecondsSinceEpoch}";

    switch (type) {
      case CogoType.inverse:
        return _generateInverseTask(id, campus, base, isEnglish: isEnglish);
      case CogoType.distanceIntersection:
        return _generateDistanceIntersectionTask(id, campus, base, isEnglish: isEnglish);
      case CogoType.angularIntersection:
        return _generateAngularIntersectionTask(id, campus, base, isEnglish: isEnglish);
      case CogoType.resection:
        return _generateResectionTask(id, campus, base, isEnglish: isEnglish);
      case CogoType.area:
        return _generateAreaTask(id, campus, base, isEnglish: isEnglish);
    }
  }

  CogoTask _generateInverseTask(String id, CampusLocation campus, List<double> base, {bool isEnglish = false}) {
    final p1 = [base[0] - 50 + _rng.nextDouble() * 100, base[1] - 50 + _rng.nextDouble() * 100];
    final p2 = [base[0] + 50 + _rng.nextDouble() * 100, base[1] + 50 + _rng.nextDouble() * 100];

    final report = _cogoService.generateEovInverseReport(p1[0], p1[1], p2[0], p2[1]);

    return CogoTask(
      id: id,
      type: CogoType.inverse,
      campus: campus,
      description: isEnglish
          ? "Calculate horizontal distance and bearing (WCB) between the given points (P1 and P2)!"
          : "Számítsa ki a megadott két pont (P1 és P2) közötti vízszintes távolságot és az irányszöget (WCB)!",
      steps: isEnglish
          ? [
              "Calculate coordinate differences: ΔY = Y2 - Y1 and ΔX = X2 - X1",
              "Determine distance: d = √(ΔY² + ΔX²)",
              "Calculate direction angle (α): atan2(ΔY, ΔX)",
              "Apply quadrant correction for WCB (0-360°)!"
            ]
          : [
              "Számítsa ki a koordinátakülönbségeket: ΔY = Y2 - Y1 és ΔX = X2 - X1",
              "A távolság meghatározása: d = √(ΔY² + ΔX²)",
              "Az irányszög (α) kiszámítása: atan2(ΔY, ΔX)",
              "Végezze el a síknegyedi korrekciót a WCB (0-360°) értékhez!"
            ],
      inputs: {
        'P1': {'y': p1[0], 'x': p1[1]},
        'P2': {'y': p2[0], 'x': p2[1]},
      },
      groundTruth: report.results,
      derivation: report.derivationSteps,
      tolerance: 0.005,
    );
  }

  CogoTask _generateAngularIntersectionTask(String id, CampusLocation campus, List<double> base, {bool isEnglish = false}) {
    final p1 = [base[0] - 100, base[1]];
    final p2 = [base[0] + 100, base[1]];
    final target = [base[0] + _rng.nextDouble() * 40 - 20, base[1] + 150 + _rng.nextDouble() * 50];

    final inv1 = _cogoService.generateEovInverseReport(p1[0], p1[1], target[0], target[1]);
    final inv2 = _cogoService.generateEovInverseReport(p2[0], p2[1], target[0], target[1]);

    final b1 = inv1.results['bearing'] as double;
    final b2 = inv2.results['bearing'] as double;

    final report = _cogoService.generateAngularIntersectionReport(p1[0], p1[1], b1, p2[0], p2[1], b2);

    return CogoTask(
      id: id,
      type: CogoType.angularIntersection,
      campus: campus,
      description: isEnglish
          ? "Determine coordinates of intersection point (M) based on bearings (b1 and b2) measured from P1 and P2!"
          : "Határozza meg a metszéspont (M) koordinátáit az ismert P1 és P2 pontokból mért irányszögek (b1 és b2) alapján!",
      steps: isEnglish
          ? [
              "Formulate equations of both lines using known points and bearings.",
              "Solve system of equations for unknown Y and X coordinates.",
              "Check if intersection point is geometrically valid."
            ]
          : [
              "Írja fel a két egyenes egyenletét az ismert pontok és irányszögek segítségével.",
              "Oldja meg az egyenletrendszert az ismeretlen Y és X koordinátákra.",
              "Ellenőrizze, hogy a metszéspont geometriailag reális-e."
            ],
      inputs: {
        'P1': {'y': p1[0], 'x': p1[1]},
        'P2': {'y': p2[0], 'x': p2[1]},
        'b1': b1,
        'b2': b2,
      },
      groundTruth: report.results,
      derivation: report.derivationSteps,
      tolerance: 0.01,
    );
  }

  CogoTask _generateDistanceIntersectionTask(String id, CampusLocation campus, List<double> base, {bool isEnglish = false}) {
    final p1 = [base[0] - 100, base[1]];
    final p2 = [base[0] + 100, base[1]];
    final target = [base[0] + _rng.nextDouble() * 100 - 50, base[1] + 120];

    double r1 = sqrt(pow(target[0] - p1[0], 2) + pow(target[1] - p1[1], 2));
    double r2 = sqrt(pow(target[0] - p2[0], 2) + pow(target[1] - p2[1], 2));

    final report = _cogoService.generateDistanceIntersectionReport(p1[0], p1[1], r1, p2[0], p2[1], r2);

    return CogoTask(
      id: id,
      type: CogoType.distanceIntersection,
      campus: campus,
      description: isEnglish
          ? "Calculate intersection point coordinates using distances (r1 and r2) from base points P1 and P2!"
          : "Számítsa ki a metszéspont(ok) koordinátáit a P1 és P2 alappontoktól mért távolságok (r1 és r2) segítségével!",
      steps: isEnglish
          ? [
              "Calculate distance between the two base points (P1-P2).",
              "Determine circle intersections using law of cosines or analytic geometry.",
              "Select primary (M1) and secondary (M2) solution!"
            ]
          : [
              "Számítsa ki a két alappont (P1-P2) távolságát.",
              "Határozza meg a körök metszéspontjait a koszinusztétel vagy analitikus geometria segítségével.",
              "Válassza ki az elsődleges (M1) és másodlagos (M2) megoldást!"
            ],
      inputs: {
        'P1': {'y': p1[0], 'x': p1[1]},
        'P2': {'y': p2[0], 'x': p2[1]},
        'r1': r1,
        'r2': r2,
      },
      groundTruth: report.results,
      derivation: report.derivationSteps,
      tolerance: 0.01,
    );
  }

  CogoTask _generateResectionTask(String id, CampusLocation campus, List<double> base, {bool isEnglish = false}) {
    final p1 = [base[0] - 200, base[1] + 200];
    final p2 = [base[0] + 200, base[1] + 200];
    final p3 = [base[0], base[1] + 400];
    
    final target = [base[0] + _rng.nextDouble() * 20, base[1] + 250];

    final inv1 = _cogoService.generateEovInverseReport(target[0], target[1], p1[0], p1[1]);
    final inv2 = _cogoService.generateEovInverseReport(target[0], target[1], p2[0], p2[1]);
    final inv3 = _cogoService.generateEovInverseReport(target[0], target[1], p3[0], p3[1]);

    final a1 = inv1.results['bearing'] as double;
    final a2 = inv2.results['bearing'] as double;
    final a3 = inv3.results['bearing'] as double;

    final report = _cogoService.generateResectionReport(p1, p2, p3, a1, a2, a3);

    return CogoTask(
      id: id,
      type: CogoType.resection,
      campus: campus,
      description: isEnglish
          ? "Determine station coordinates based on directional measurements to three known base points (P1, P2, P3)!"
          : "Határozza meg saját álláspontjának koordinátáit három ismert alappontra (P1, P2, P3) végzett iránymérés alapján!",
      steps: isEnglish
          ? [
              "Calculate angles measured at station (α, β, γ) from direction differences.",
              "Calculate interior angles of base triangle from coordinates.",
              "Apply Tienstra formula to determine weights (w1, w2, w3).",
              "Determine target Y and X coordinates using weighted average."
            ]
          : [
              "Számítsa ki az állásponton mért szögeket (α, β, γ) az irányértékek különbségéből.",
              "Számítsa ki az alapponti háromszög belső szögeit a koordináták alapján.",
              "Alkalmazza a Tienstra-formulát a súlyok (w1, w2, w3) meghatározásához.",
              "Határozza meg a súlyozott középértékkel a keresett Y és X koordinátákat."
            ],
      inputs: {
        'P1': {'y': p1[0], 'x': p1[1]},
        'P2': {'y': p2[0], 'x': p2[1]},
        'P3': {'y': p3[0], 'x': p3[1]},
        'a1': a1,
        'a2': a2,
        'a3': a3,
      },
      groundTruth: report.results,
      derivation: report.derivationSteps,
      tolerance: 0.02,
    );
  }

  CogoTask _generateAreaTask(String id, CampusLocation campus, List<double> base, {bool isEnglish = false}) {
    final List<List<double>> points = [
      [base[0], base[1]],
      [base[0] + 100 + _rng.nextDouble() * 10, base[1]],
      [base[0] + 100 + _rng.nextDouble() * 10, base[1] + 80 + _rng.nextDouble() * 10],
      [base[0], base[1] + 80 + _rng.nextDouble() * 10],
    ];

    final report = _cogoService.generateAreaReport(points);

    Map<String, dynamic> inputs = {};
    for (int i = 0; i < points.length; i++) {
      inputs['P${i + 1}'] = {'y': points[i][0], 'x': points[i][1]};
    }

    return CogoTask(
      id: id,
      type: CogoType.area,
      campus: campus,
      description: isEnglish
          ? "Calculate area enclosed by given vertices in m² and hectares!"
          : "Számítsa ki a megadott töréspontok által meghatározott zárt terület nagyságát m²-ben és hektárban!",
      steps: isEnglish
          ? [
              "Apply Gauss area formula (shoelace formula).",
              "Calculate cross products of coordinate pairs: (Yi * Xi+1 - Yi+1 * Xi).",
              "Sum terms and take half of absolute value of sum.",
              "Convert m² value to hectares (1 ha = 10,000 m²)."
            ]
          : [
              "Alkalmazza a Gauss-féle területszámítási módszert (poligonmódszer).",
              "Számítsa ki a koordinátapárok kereszt-szorzatait: (Yi * Xi+1 - Yi+1 * Xi).",
              "Összegezze a tagokat, majd vegye az összeg abszolút értékének felét.",
              "Váltsa át a kapott m² értéket hektárra (1 ha = 10 000 m²)."
            ],
      inputs: inputs,
      groundTruth: report.results,
      derivation: report.derivationSteps,
      tolerance: 0.1,
    );
  }

  TaskEvaluation evaluate(CogoTask task, Map<String, double> userResults, {bool isEnglish = false}) {
    Map<String, double> diffs = {};
    bool success = true;

    task.groundTruth.forEach((key, value) {
      if (value is double) {
        double userVal = userResults[key] ?? 0.0;
        double d = (userVal - value).abs();
        diffs[key] = userVal - value;
        if (d > task.tolerance) success = false;
      }
    });

    String grade = isEnglish ? "Error" : "Hiba";
    String message = isEnglish ? "Calculation inaccurate. Check formulas!" : "A számítás pontatlan. Ellenőrizd a képleteket!";

    if (success) {
      grade = isEnglish ? "Excellent" : "Kiváló";
      message = isEnglish ? "Congratulations! Engineering level precision." : "Gratulálunk! Mérnöki pontosságú megoldás.";
    } else {
      double maxDiff = diffs.values.map((v) => v.abs()).reduce(max);
      if (maxDiff < 0.1) {
        grade = isEnglish ? "Good" : "Jó";
        message = isEnglish ? "Close, but there is a slight rounding or calculation error." : "Közel jársz, de van egy kis kerekítési vagy számítási pontatlanság.";
      }
    }

    return TaskEvaluation(
      isSuccess: success,
      differences: diffs,
      grade: grade,
      message: message,
    );
  }
}
