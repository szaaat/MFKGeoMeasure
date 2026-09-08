import '../models/geo_feature.dart';
import '../models/field_definition.dart';

class ProjectMigrationService {
  
  /// A legfrissebb projektformátum verziója
  static const int targetVersion = Project.currentFormatVersion;

  /// Végrehajtja a szükséges migrációs lépéseket a nyers JSON adaton.
  static Map<String, dynamic> migrate(Map<String, dynamic> projectJson) {
    int version = projectJson['formatVersion'] ?? 1;

    if (version < 2) {
      projectJson = _migrateV1ToV2(projectJson);
      version = 2;
    }

    // Jövőbeli verziók helye:
    // if (version < 3) { projectJson = _migrateV2ToV3(projectJson); version = 3; }

    return projectJson;
  }

  /// Migráció v1-ről v2-re:
  /// - customFieldNames -> fields (CustomFieldDefinition)
  /// - customData kulcsok normalizálása
  static Map<String, dynamic> _migrateV1ToV2(Map<String, dynamic> json) {
    if (json['layers'] != null) {
      final List<dynamic> layers = json['layers'];
      for (var layerJson in layers) {
        final Map<String, String> keyMap = {};
        
        // 1. Mezők migrációja
        if (layerJson.containsKey('customFieldNames')) {
          final List<dynamic> oldNames = layerJson['customFieldNames'];
          final List<Map<String, dynamic>> newFields = [];
          final Set<String> usedKeys = {};

          for (var name in oldNames) {
            String key = CustomFieldDefinition.normalizeKey(name.toString());
            if (key.isEmpty) key = "field";
            
            String finalKey = key;
            int counter = 1;
            while (usedKeys.contains(finalKey)) {
              finalKey = "${key}_$counter";
              counter++;
            }
            usedKeys.add(finalKey);
            keyMap[name.toString()] = finalKey;

            newFields.add({
              'key': finalKey,
              'label': name,
              'type': FieldType.text.index,
            });
          }
          layerJson['fields'] = newFields;
          layerJson.remove('customFieldNames');
        }

        // 2. Feature adatok (customData) kulcsainak migrációja
        if (layerJson['features'] != null && keyMap.isNotEmpty) {
          final List<dynamic> features = layerJson['features'];
          for (var featureJson in features) {
            if (featureJson['customData'] != null) {
              final Map<String, dynamic> oldData = Map<String, dynamic>.from(featureJson['customData']);
              final Map<String, dynamic> newData = {};
              
              oldData.forEach((oldKey, value) {
                final newKey = keyMap[oldKey] ?? oldKey;
                newData[newKey] = value;
              });
              
              featureJson['customData'] = newData;
            }
          }
        }
      }
    }

    json['formatVersion'] = 2;
    return json;
  }
}
