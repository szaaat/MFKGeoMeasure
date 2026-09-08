enum ReadingType {
  backsight,
  intermediate,
  foresight,
}

enum ValidationStatus { normal, suspicious, invalid }

class ValidationResult {
  final ValidationStatus status;
  final String? message;
  ValidationResult(this.status, [this.message]);
}

class LevelingReading {
  final String id;
  final String pointId;
  final ReadingType type;
  final double value;
  final DateTime timestamp;

  LevelingReading({
    required this.id,
    required this.pointId,
    required this.type,
    required this.value,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'pointId': pointId,
      'type': type.name,
      'value': value,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory LevelingReading.fromJson(Map<String, dynamic> json) {
    return LevelingReading(
      id: json['id'],
      pointId: json['pointId'],
      type: ReadingType.values.byName(json['type']),
      value: (json['value'] as num).toDouble(),
      timestamp: DateTime.parse(json['timestamp']),
    );
  }
}
