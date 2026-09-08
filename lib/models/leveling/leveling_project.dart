import 'leveling_station.dart';

enum AdjustmentMethod { none, stationCount, distance }

class LevelingProject {
  final String id;
  final String name;
  final String startPointId;
  final double startHeight;
  String? endPointId;
  double? knownEndHeight;
  final List<LevelingStation> stations;
  final bool isPrecision;
  AdjustmentMethod adjustmentMethod;

  LevelingProject({
    required this.id,
    required this.name,
    required this.startPointId,
    required this.startHeight,
    this.endPointId,
    this.knownEndHeight,
    List<LevelingStation>? stations,
    this.isPrecision = false,
    this.adjustmentMethod = AdjustmentMethod.none,
  }) : stations = stations ?? [];

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'startPointId': startPointId,
      'startHeight': startHeight,
      'endPointId': endPointId,
      'knownEndHeight': knownEndHeight,
      'stations': stations.map((e) => e.toJson()).toList(),
      'isPrecision': isPrecision,
      'adjustmentMethod': adjustmentMethod.name,
    };
  }

  factory LevelingProject.fromJson(Map<String, dynamic> json) {
    return LevelingProject(
      id: json['id'],
      name: json['name'],
      startPointId: json['startPointId'],
      startHeight: (json['startHeight'] as num).toDouble(),
      endPointId: json['endPointId'],
      knownEndHeight: json['knownEndHeight']?.toDouble(),
      stations: (json['stations'] as List?)
              ?.map((e) => LevelingStation.fromJson(e))
              .toList() ??
          [],
      isPrecision: json['isPrecision'] ?? false,
      adjustmentMethod: AdjustmentMethod.values.byName(json['adjustmentMethod'] ?? 'none'),
    );
  }
}
