import '../../models/leveling/leveling_reading.dart';

class LevelingCalculationService {
  /// MH = Alappont magassága + Hátra leolvasás
  double calculateInstrumentHeight(double benchmarkHeight, double backsight) {
    return benchmarkHeight + backsight;
  }

  /// Pontmagasság = MH - Előre/Közbenső leolvasás
  double calculatePointHeight(double instrumentHeight, double reading) {
    return instrumentHeight - reading;
  }

  /// Precíziós magasságkülönbség (H1-E1 és H2-E2 átlaga)
  double calculateMeanDeltaH(double h1, double e1, double h2, double e2) {
    return ((h1 - e1) + (h2 - e2)) / 2.0;
  }

  /// Záróhiba = Számított végmagasság - Ismert végmagasság
  double calculateClosureError(double calculatedEndHeight, double knownEndHeight) {
    return calculatedEndHeight - knownEndHeight;
  }

  /// Korrekció állomásonként (egyenletes elosztás)
  double calculateCorrectionPerStation(double closureError, int totalStations) {
    if (totalStations == 0) return 0.0;
    return -closureError / totalStations;
  }

  /// Korrekció távolságarányosan
  double calculateCorrectionByDistance(double closureError, double stationDistance, double totalDistance) {
    if (totalDistance == 0) return 0.0;
    return -closureError * (stationDistance / totalDistance);
  }

  /// Háromszintű validáció
  ValidationResult validateReading(double? value) {
    if (value == null) {
      return ValidationResult(ValidationStatus.invalid, 'Hiányzó adat');
    }
    if (value < 0) {
      return ValidationResult(ValidationStatus.invalid, 'Negatív leolvasás');
    }
    if (value > 4.0) {
      return ValidationResult(ValidationStatus.suspicious, 'Szokatlanul nagy leolvasás (>4m)');
    }
    // Esetleg gyanús ugrás? De ehhez kellene az előző érték is.
    return ValidationResult(ValidationStatus.normal);
  }
}
