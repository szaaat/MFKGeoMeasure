import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';
import 'field_definition.dart';

enum FeatureType { point, line, polygon }

class GeoFeature {
  final String id;
  String name;
  String description;
  final FeatureType type;
  final List<LatLng> geometry;
  final List<double> altitudes;
  final List<String> photos;
  final String? templateName;
  final Map<String, dynamic> customData;
  final Map<String, dynamic> properties;
  final Map<String, dynamic> calculatedStats;
  final DateTime createdAt;

  GeoFeature({
    String? id,
    required this.name,
    this.description = "",
    required this.type,
    required this.geometry,
    this.altitudes = const [],
    this.photos = const [],
    this.templateName,
    this.customData = const {},
    this.properties = const {},
    this.calculatedStats = const {},
    DateTime? createdAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  // --- JSON BETÖLTÉS ---
  factory GeoFeature.fromJson(Map<String, dynamic> json) {
    return GeoFeature(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      type: FeatureType.values[json['type']],
      geometry: (json['geometry'] as List).map((p) => LatLng(p['lat'], p['lon'])).toList(),
      altitudes: List<double>.from(json['altitudes'] ?? []),
      photos: List<String>.from(json['photos'] ?? []),
      templateName: json['templateName'],
      customData: Map<String, dynamic>.from(json['customData'] ?? {}),
      properties: Map<String, dynamic>.from(json['properties'] ?? {}),
      calculatedStats: json['calculatedStats'] ?? {},
      createdAt: DateTime.parse(json['createdAt']),
    );
  }

  // --- JSON MENTÉS ---
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'type': type.index,
    'geometry': geometry.map((p) => {'lat': p.latitude, 'lon': p.longitude}).toList(),
    'altitudes': altitudes,
    'photos': photos,
    'templateName': templateName,
    'customData': customData.map((k, v) => MapEntry(k, v is DateTime ? v.toIso8601String() : v)),
    'properties': properties,
    'calculatedStats': calculatedStats,
    'createdAt': createdAt.toIso8601String(),
  };
}

class ProjectLayer {
  final String id;
  String name;
  List<GeoFeature> features;
  List<CustomFieldDefinition> fields; // Új típusos meződefiníciók
  bool isVisible;

  ProjectLayer({
    String? id,
    required this.name,
    List<GeoFeature>? features,
    List<CustomFieldDefinition>? fields,
    this.isVisible = true,
  }) : id = id ?? const Uuid().v4(),
        features = features ?? [],
        fields = fields ?? [];

  factory ProjectLayer.fromJson(Map<String, dynamic> json) {
    final List<CustomFieldDefinition> fields = (json['fields'] as List? ?? [])
        .map((f) => CustomFieldDefinition.fromJson(f))
        .toList();

    final List<GeoFeature> features = (json['features'] as List? ?? [])
        .map((f) => GeoFeature.fromJson(f))
        .toList();

    // Típushelyes konverzió a meződefiníciók alapján betöltéskor
    for (var f in features) {
      for (var field in fields) {
        final val = f.customData[field.key];
        if (val != null) {
          f.customData[field.key] = _castValue(val, field.type);
        }
      }
    }

    return ProjectLayer(
      id: json['id'],
      name: json['name'],
      isVisible: json['isVisible'] ?? true,
      features: features,
      fields: fields,
    );
  }

  static dynamic _castValue(dynamic val, FieldType type) {
    if (val == null) return null;
    final str = val.toString();
    switch (type) {
      case FieldType.integer: return int.tryParse(str);
      case FieldType.decimal: return double.tryParse(str);
      case FieldType.bool: return str.toLowerCase() == 'true';
      case FieldType.date:
      case FieldType.dateTime: return DateTime.tryParse(str);
      default: return str;
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'isVisible': isVisible,
    'features': features.map((f) => f.toJson()).toList(),
    'fields': fields.map((f) => f.toJson()).toList(),
  };
}

class Project {
  static const int currentFormatVersion = 2;

  final String id;
  String name;
  List<ProjectLayer> layers;
  final int formatVersion;
  DateTime createdAt;

  Project({
    String? id,
    required this.name,
    List<ProjectLayer>? layers,
    int? formatVersion,
    DateTime? createdAt,
  })  : id = id ?? const Uuid().v4(),
        layers = layers ?? [],
        formatVersion = formatVersion ?? currentFormatVersion,
        createdAt = createdAt ?? DateTime.now();

  factory Project.fromJson(Map<String, dynamic> json) {
    return Project(
      id: json['id'],
      name: json['name'],
      layers: (json['layers'] as List).map((l) => ProjectLayer.fromJson(l)).toList(),
      formatVersion: json['formatVersion'] ?? 1,
      createdAt: DateTime.parse(json['createdAt']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'layers': layers.map((l) => l.toJson()).toList(),
    'formatVersion': formatVersion,
    'createdAt': createdAt.toIso8601String(),
  };
}
