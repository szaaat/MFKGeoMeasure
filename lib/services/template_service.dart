import 'package:flutter/material.dart';
import '../models/field_definition.dart';

class FieldDefinition {
  final String labelKey;
  final String key;
  final FieldType type;
  final List<String>? optionKeys;

  FieldDefinition({
    required this.labelKey,
    required this.key,
    required this.type,
    this.optionKeys,
  });
}

class FeatureTemplate {
  final String nameKey;
  final List<FieldDefinition> fields;

  FeatureTemplate({required this.nameKey, required this.fields});
}

class TemplateService extends ChangeNotifier {
  final List<FeatureTemplate> _templates = [
    FeatureTemplate(
      nameKey: "templateGeneral",
      fields: [],
    ),
    FeatureTemplate(
      nameKey: "templateWaterManhole",
      fields: [
        FieldDefinition(labelKey: "fieldMaterial", key: "material", type: FieldType.choice, optionKeys: ["optConcrete", "optPlastic", "optBrick", "optCastIron"]),
        FieldDefinition(labelKey: "fieldDiameter", key: "diameter", type: FieldType.decimal),
        FieldDefinition(labelKey: "fieldDepth", key: "depth", type: FieldType.decimal),
        FieldDefinition(labelKey: "fieldCondition", key: "condition", type: FieldType.choice, optionKeys: ["optGood", "optDamaged", "optMissing"]),
      ],
    ),
    FeatureTemplate(
      nameKey: "templateBoundaryStone",
      fields: [
        FieldDefinition(labelKey: "fieldType", key: "type", type: FieldType.choice, optionKeys: ["optConcreteStone", "optGranite", "optIronPipe", "optPlasticPeg"]),
        FieldDefinition(labelKey: "fieldStatus", key: "status", type: FieldType.choice, optionKeys: ["optIntact", "optTilted", "optDisplaced", "optUncertain"]),
      ],
    ),
    FeatureTemplate(
      nameKey: "templateUtilityPole",
      fields: [
        FieldDefinition(labelKey: "fieldMaterial", key: "material", type: FieldType.choice, optionKeys: ["optWood", "optConcrete", "optIron"]),
        FieldDefinition(labelKey: "fieldVoltage", key: "voltage", type: FieldType.choice, optionKeys: ["0.4 kV", "20 kV", "120 kV"]),
        FieldDefinition(labelKey: "fieldHasLamp", key: "has_lamp", type: FieldType.choice, optionKeys: ["optYes", "optNo"]),
      ],
    ),
  ];

  List<FeatureTemplate> get templates => _templates;

  FeatureTemplate? getTemplateByNameKey(String? nameKey) {
    if (nameKey == null) return null;
    return _templates.firstWhere((t) => t.nameKey == nameKey, orElse: () => _templates.first);
  }
}
