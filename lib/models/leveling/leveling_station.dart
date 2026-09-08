import 'leveling_reading.dart';

class LevelingStation {
  final int stationId;
  final String backsightPointId;
  String? foresightPointId;
  
  // Sima szintezés adatai
  double? backsight;
  double? foresight;

  // Precíziós szintezés adatai (H1-E1-H2-E2)
  double? h1;
  double? e1;
  double? h2;
  double? e2;

  final List<LevelingReading> intermediateReadings;
  final DateTime createdAt;

  // Metaadatok
  String? surveyor;
  String? instrument;
  String? measurementOrder;
  String? notes;
  double? distance;
  Map<String, double> corrections; // pointId -> correction value

  LevelingStation({
    required this.stationId,
    required this.backsightPointId,
    this.foresightPointId,
    this.backsight,
    this.foresight,
    this.h1,
    this.e1,
    this.h2,
    this.e2,
    this.surveyor,
    this.instrument,
    this.measurementOrder,
    this.notes,
    this.distance,
    Map<String, double>? corrections,
    List<LevelingReading>? intermediateReadings,
    DateTime? createdAt,
  })  : corrections = corrections ?? {},
        intermediateReadings = intermediateReadings ?? [],
        createdAt = createdAt ?? DateTime.now();

  // Precíziós számítások
  double? get deltaH1 => (h1 != null && e1 != null) ? h1! - e1! : null;
  double? get deltaH2 => (h2 != null && e2 != null) ? h2! - e2! : null;
  double? get stationDiff => (deltaH1 != null && deltaH2 != null) ? (deltaH1! - deltaH2!).abs() : null;
  double? get meanDeltaH => (deltaH1 != null && deltaH2 != null) ? (deltaH1! + deltaH2!) / 2.0 : null;
  
  bool get isPrecisionAccepted => stationDiff != null && stationDiff! <= 0.0005; // 0.5 mm

  Map<String, dynamic> toJson() {
    return {
      'stationId': stationId,
      'backsightPointId': backsightPointId,
      'foresightPointId': foresightPointId,
      'backsight': backsight,
      'foresight': foresight,
      'h1': h1,
      'e1': e1,
      'h2': h2,
      'e2': e2,
      'surveyor': surveyor,
      'instrument': instrument,
      'measurementOrder': measurementOrder,
      'notes': notes,
      'distance': distance,
      'corrections': corrections,
      'intermediateReadings':
          intermediateReadings.map((e) => e.toJson()).toList(),
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory LevelingStation.fromJson(Map<String, dynamic> json) {
    return LevelingStation(
      stationId: json['stationId'],
      backsightPointId: json['backsightPointId'],
      foresightPointId: json['foresightPointId'],
      backsight: json['backsight']?.toDouble(),
      foresight: json['foresight']?.toDouble(),
      h1: json['h1']?.toDouble(),
      e1: json['e1']?.toDouble(),
      h2: json['h2']?.toDouble(),
      e2: json['e2']?.toDouble(),
      surveyor: json['surveyor'],
      instrument: json['instrument'],
      measurementOrder: json['measurementOrder'],
      notes: json['notes'],
      distance: json['distance']?.toDouble(),
      corrections: Map<String, double>.from(json['corrections'] ?? {}),
      intermediateReadings: (json['intermediateReadings'] as List?)
              ?.map((e) => LevelingReading.fromJson(e))
              .toList() ??
          [],
      createdAt: DateTime.parse(json['createdAt']),
    );
  }
}
