import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';
import 'field_definition.dart';

enum FeatureType { point, line, polygon }

enum LayerCrs {
  wgs84,
  eov,
}

extension LayerCrsExtension on LayerCrs {
  String get epsg => this == LayerCrs.eov ? 'EPSG:23700' : 'EPSG:4326';
  String get label => this == LayerCrs.eov ? 'EOV (EPSG:23700)' : 'WGS84 (EPSG:4326)';

  static LayerCrs fromEpsg(String? value) {
    return value == 'EPSG:23700' ? LayerCrs.eov : LayerCrs.wgs84;
  }
}

class SurveyMethods {
  static const String rtk = "RTK";
  static const String internalGps = "PHONE_GPS";
  static const String externalGnss = "EXTERNAL_GNSS";
  static const String imported = "IMPORTED";
}

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
    required List<LatLng> geometry,
    List<double>? altitudes,
    List<String>? photos,
    this.templateName,
    Map<String, dynamic>? customData,
    Map<String, dynamic>? properties,
    Map<String, dynamic>? calculatedStats,
    DateTime? createdAt,
  })  : id = id ?? const Uuid().v4(),
        geometry = List<LatLng>.from(geometry),
        altitudes = altitudes != null ? List<double>.from(altitudes) : [],
        photos = photos != null ? List<String>.from(photos) : [],
        customData = customData != null ? Map<String, dynamic>.from(customData) : {},
        properties = properties != null ? Map<String, dynamic>.from(properties) : {},
        calculatedStats = calculatedStats != null ? Map<String, dynamic>.from(calculatedStats) : {},
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
      calculatedStats: Map<String, dynamic>.from(json['calculatedStats'] ?? {}),
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
  String sourceType; // 'survey' or 'import'
  String? crsInfo;   // e.g. 'EOV EPSG:23700'
  LayerCrs coordinateCrs;

  ProjectLayer({
    String? id,
    required this.name,
    List<GeoFeature>? features,
    List<CustomFieldDefinition>? fields,
    this.isVisible = true,
    this.sourceType = 'survey',
    this.crsInfo,
    this.coordinateCrs = LayerCrs.wgs84,
  }) : id = id ?? const Uuid().v4(),
        features = features ?? [],
        fields = fields ?? [];

  Set<FeatureType> get containedGeometryTypes => features.map((f) => f.type).toSet();

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
      sourceType: json['sourceType'] ?? 'survey',
      crsInfo: json['crsInfo'],
      coordinateCrs: LayerCrsExtension.fromEpsg(json['coordinateCrs']),
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
    'sourceType': sourceType,
    'crsInfo': crsInfo,
    'coordinateCrs': coordinateCrs.epsg,
    'features': features.map((f) => f.toJson()).toList(),
    'fields': fields.map((f) => f.toJson()).toList(),
  };
}

class Project {
  static const int currentFormatVersion = 2;

  final String id;
  String name;
  List<ProjectLayer> layers;
  String? activeLayerId; // New field to persist active layer
  final int formatVersion;
  DateTime createdAt;

  Project({
    String? id,
    required this.name,
    this.activeLayerId,
    List<ProjectLayer>? layers,
    int? formatVersion,
    DateTime? createdAt,
  })  : id = id ?? const Uuid().v4(),
        layers = layers ?? [],
        formatVersion = formatVersion ?? currentFormatVersion,
        createdAt = createdAt ?? DateTime.now();

  factory Project.fromJson(Map<String, dynamic> json) {
    final List<ProjectLayer> loadedLayers = (json['layers'] as List).map((l) => ProjectLayer.fromJson(l)).toList();
    return Project(
      id: json['id'],
      name: json['name'],
      activeLayerId: json['activeLayerId'],
      layers: loadedLayers,
      formatVersion: json['formatVersion'] ?? 1,
      createdAt: DateTime.parse(json['createdAt']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'activeLayerId': activeLayerId,
    'layers': layers.map((l) => l.toJson()).toList(),
    'formatVersion': formatVersion,
    'createdAt': createdAt.toIso8601String(),
  };
}
