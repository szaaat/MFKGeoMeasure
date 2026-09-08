import 'dart:math';
import 'package:latlong2/latlong.dart';
import 'eov_service.dart';
import '../models/cogo_session.dart';

class CogoResult {
  final double distance; // méter
  final double bearing; // fok (WCB)
  
  CogoResult({required this.distance, required this.bearing});
}

class CogoService {
  final EovService _eovService;

  CogoService(this._eovService);

  /// Inverz feladat számítása két LatLng pont között (Gömbi közelítés)
  CogoResult calculateInverse(LatLng p1, LatLng p2) {
    const distanceCalc = Distance();
    double dist = distanceCalc.as(LengthUnit.Meter, p1, p2);
    
    // Bearing (irányszög) számítása
    double lat1 = p1.latitude * pi / 180;
    double lon1 = p1.longitude * pi / 180;
    double lat2 = p2.latitude * pi / 180;
    double lon2 = p2.longitude * pi / 180;

    double dLon = lon2 - lon1;
    double y = sin(dLon) * cos(lat2);
    double x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);
    double brng = atan2(y, x) * 180 / pi;
    
    return CogoResult(
      distance: dist,
      bearing: (brng + 360) % 360,
    );
  }

  /// Inverz feladat számítása EOV (sík) koordinátákkal (Pitagorasz)
  CogoCalculationReport generateEovInverseReport(double y1, double x1, double y2, double x2) {
    // Geodéziai koordinátarendszerben (X észak, Y kelet) a különbségek:
    double dyGeo = y2 - y1;
    double dxGeo = x2 - x1;
    
    double dist = sqrt(dyGeo * dyGeo + dxGeo * dxGeo);
    double angle = atan2(dyGeo, dxGeo) * 180 / pi;
    double wcb = (90 - angle + 360) % 360;

    return CogoCalculationReport(
      title: "Inverz feladat",
      results: {
        'distance': dist,
        'bearing': wcb,
      },
      derivationSteps: [
        "ΔY = Y₂ - Y₁ = ${dyGeo.toStringAsFixed(3)} m",
        "ΔX = X₂ - X₁ = ${dxGeo.toStringAsFixed(3)} m",
        "d = √(ΔY² + ΔX²) = ${dist.toStringAsFixed(3)} m",
        "α = atan2(ΔY, ΔX) = ${angle.toStringAsFixed(4)}°",
        "WCB = (90 - α) mod 360 = ${wcb.toStringAsFixed(4)}°",
      ],
    );
  }

  /// Iránymetszés (Angular Intersection)
  CogoCalculationReport generateAngularIntersectionReport(
      double y1, double x1, double b1, double y2, double x2, double b2) {
    double b1Rad = b1 * pi / 180;
    double b2Rad = b2 * pi / 180;

    double det = sin(b2Rad - b1Rad);
    if (det.abs() < 1e-9) {
      return CogoCalculationReport(
        title: "Iránymetszés",
        results: {},
        errorMessage: "Hiba: A vonalak párhuzamosak vagy egybeesnek!",
      );
    }

    double c1 = x1 * sin(b1Rad) - y1 * cos(b1Rad);
    double c2 = x2 * sin(b2Rad) - y2 * cos(b2Rad);

    double x = (c1 * (-cos(b2Rad)) - c2 * (-cos(b1Rad))) / det;
    double y = (sin(b1Rad) * c2 - sin(b2Rad) * c1) / det;

    return CogoCalculationReport(
      title: "Iránymetszés",
      results: {'y': y, 'x': x},
      resultPoints: [[y, x]],
      derivationSteps: [
        "b1_rad = ${b1Rad.toStringAsFixed(4)}",
        "b2_rad = ${b2Rad.toStringAsFixed(4)}",
        "det = sin(b2 - b1) = ${det.toStringAsFixed(4)}",
        "Y = ${y.toStringAsFixed(3)} m",
        "X = ${x.toStringAsFixed(3)} m",
      ],
    );
  }

  /// Ívmetszés (Distance Intersection)
  CogoCalculationReport generateDistanceIntersectionReport(
      double y1, double x1, double r1, double y2, double x2, double r2) {
    double dy = y2 - y1;
    double dx = x2 - x1;
    double d2 = dy * dy + dx * dx;
    double d = sqrt(d2);

    if (d < 1e-6) {
      return CogoCalculationReport(
        title: "Ívmetszés",
        results: {},
        errorMessage: "Hiba: A két alappont egybeesik!",
      );
    }

    if (d > r1 + r2 + 0.001) {
      return CogoCalculationReport(
        title: "Ívmetszés",
        results: {},
        errorMessage: "Hiba: A körök nem érnek össze (távolság: ${d.toStringAsFixed(2)} m > r1+r2: ${(r1+r2).toStringAsFixed(2)} m)",
      );
    }
    if (d < (r1 - r2).abs() - 0.001) {
      return CogoCalculationReport(
        title: "Ívmetszés",
        results: {},
        errorMessage: "Hiba: Egyik kör a másikban van!",
      );
    }

    double a = (r1 * r1 - r2 * r2 + d2) / (2 * d);
    double h2 = r1 * r1 - a * a;
    double h = sqrt(max(0.0, h2));

    double y0 = y1 + a * dy / d;
    double x0 = x1 + a * dx / d;

    double rx = -dy * (h / d);
    double ry = dx * (h / d);

    return CogoCalculationReport(
      title: "Ívmetszés",
      results: {
        'y1': y0 + ry, 'x1': x0 + rx,
        'y2': y0 - ry, 'x2': x0 - rx,
      },
      resultPoints: [
        [y0 + ry, x0 + rx],
        [y0 - ry, x0 - rx],
      ],
      derivationSteps: [
        "d = √(ΔY² + ΔX²) = ${d.toStringAsFixed(3)} m",
        "a = (r1² - r2² + d²) / 2d = ${a.toStringAsFixed(3)}",
        "h = √(r1² - a²) = ${h.toStringAsFixed(3)}",
        "M1: (${(y0 + ry).toStringAsFixed(3)}, ${(x0 + rx).toStringAsFixed(3)})",
        "M2: (${(y0 - ry).toStringAsFixed(3)}, ${(x0 - rx).toStringAsFixed(3)})",
      ],
    );
  }

  /// Területszámítás Gauss-módszerrel
  CogoCalculationReport generateAreaReport(List<List<double>> points) {
    if (points.length < 3) {
      return CogoCalculationReport(
        title: "Területszámítás",
        results: {},
        errorMessage: "Hiba: Legalább 3 pont szükséges!",
      );
    }
    double area = 0.0;
    List<String> steps = [];
    for (int i = 0; i < points.length; i++) {
      int next = (i + 1) % points.length;
      double term = points[i][0] * points[next][1] - points[next][0] * points[i][1];
      area += term;
      steps.add("P${i+1}*P${next+1} term: ${term.toStringAsFixed(1)}");
    }
    double finalArea = area.abs() / 2.0;

    return CogoCalculationReport(
      title: "Területszámítás",
      results: {
        'area_m2': finalArea,
        'area_ha': finalArea / 10000,
      },
      derivationSteps: [
        ...steps,
        "Összeg / 2 = ${finalArea.toStringAsFixed(2)} m²",
      ],
    );
  }

  /// Területszámítás Gauss-módszerrel (EOV koordinátákból)
  double calculateAreaFromEov(List<List<double>> points) {
    if (points.length < 3) return 0.0;
    double area = 0.0;
    for (int i = 0; i < points.length; i++) {
      int next = (i + 1) % points.length;
      area += points[i][0] * points[next][1] - points[next][0] * points[i][1];
    }
    return area.abs() / 2.0;
  }

  /// Területszámítás koordináták alapján
  double calculateArea(List<LatLng> points) {
    if (points.length < 3) return 0.0;
    List<List<double>> eovPoints =
        points.map((p) => _eovService.wgsToEov(p.latitude, p.longitude)).toList();
    return calculateAreaFromEov(eovPoints);
  }

  /// Hátrametszés (Resection) - Tienstra formula
  CogoCalculationReport generateResectionReport(
      List<double> p1, List<double> p2, List<double> p3, double a1, double a2, double a3) {
    
    // Szögek számítása az állásponton (P)
    double alpha = (a3 - a2 + 360) % 360;
    double beta  = (a1 - a3 + 360) % 360;
    double gamma = (a2 - a1 + 360) % 360;

    double alphaRad = alpha * pi / 180;
    double betaRad  = beta * pi / 180;
    double gammaRad = gamma * pi / 180;

    // Belső szögek az alapponti háromszögben
    double a = sqrt(pow(p3[0] - p2[0], 2) + pow(p3[1] - p2[1], 2));
    double b = sqrt(pow(p1[0] - p3[0], 2) + pow(p1[1] - p3[1], 2));
    double c = sqrt(pow(p2[0] - p1[0], 2) + pow(p2[1] - p1[1], 2));

    double cosA = (b * b + c * c - a * a) / (2 * b * c);
    double cosB = (a * a + c * c - b * b) / (2 * a * c);
    double cosC = (a * a + b * b - c * c) / (2 * a * b);

    double angleA = acos(max(-1, min(1, cosA)));
    double angleB = acos(max(-1, min(1, cosB)));
    double angleC = acos(max(-1, min(1, cosC)));

    // Súlyok (Tienstra weights)
    double w1 = 1.0 / (1.0 / tan(angleA) - 1.0 / tan(alphaRad));
    double w2 = 1.0 / (1.0 / tan(angleB) - 1.0 / tan(betaRad));
    double w3 = 1.0 / (1.0 / tan(angleC) - 1.0 / tan(gammaRad));

    double sumW = w1 + w2 + w3;
    if (!sumW.isFinite || sumW.abs() < 1e-9) {
      return CogoCalculationReport(
        title: "Hátrametszés",
        results: {},
        errorMessage: "Hiba: Veszélyes kör vagy érvénytelen geometria!",
      );
    }

    double y = (w1 * p1[0] + w2 * p2[0] + w3 * p3[0]) / sumW;
    double x = (w1 * p1[1] + w2 * p2[1] + w3 * p3[1]) / sumW;

    if (!y.isFinite || !x.isFinite) {
      return CogoCalculationReport(
        title: "Hátrametszés",
        results: {},
        errorMessage: "Hiba: A számítás eredménye érvénytelen!",
      );
    }

    return CogoCalculationReport(
      title: "Hátrametszés",
      results: {'y': y, 'x': x},
      resultPoints: [[y, x]],
      derivationSteps: [
        "α (szög P2-P-P3) = ${alpha.toStringAsFixed(4)}°",
        "β (szög P3-P-P1) = ${beta.toStringAsFixed(4)}°",
        "γ (szög P1-P-P2) = ${gamma.toStringAsFixed(4)}°",
        "w1 (súly) = ${w1.toStringAsFixed(4)}",
        "w2 (súly) = ${w2.toStringAsFixed(4)}",
        "w3 (súly) = ${w3.toStringAsFixed(4)}",
        "Y = ${y.toStringAsFixed(3)} m",
        "X = ${x.toStringAsFixed(3)} m",
      ],
    );
  }
}
