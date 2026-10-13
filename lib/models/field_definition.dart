enum FieldType { text, integer, decimal, bool, date, dateTime, choice }

class CustomFieldDefinition {
  final String key;
  final String label;
  final FieldType type;
  final List<String>? choices;
  final bool isRequired;

  CustomFieldDefinition({
    required this.key,
    required this.label,
    required this.type,
    this.choices,
    this.isRequired = false,
  });

  factory CustomFieldDefinition.fromJson(Map<String, dynamic> json) {
    return CustomFieldDefinition(
      key: json['key'],
      label: json['label'],
      type: FieldType.values[json['type']],
      choices: json['choices'] != null ? List<String>.from(json['choices']) : null,
      isRequired: json['isRequired'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
    'key': key,
    'label': label,
    'type': type.index,
    if (choices != null) 'choices': choices,
    'isRequired': isRequired,
  };

  // Segédfüggvény a régi mezőnév normalizálásához (slug generálás)
  static String normalizeKey(String name) {
    return name.toLowerCase()
        .replaceAll('á', 'a').replaceAll('é', 'e').replaceAll('í', 'i')
        .replaceAll('ó', 'o').replaceAll('ö', 'o').replaceAll('ő', 'o')
        .replaceAll('ú', 'u').replaceAll('ü', 'u').replaceAll('ű', 'u')
        .replaceAll(RegExp(r'[^a-z0-9_]'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
  }
}
