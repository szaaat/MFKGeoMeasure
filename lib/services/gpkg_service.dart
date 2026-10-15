import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:latlong2/latlong.dart';
import 'package:sqlite3/sqlite3.dart';

import '../models/field_definition.dart';
import '../models/geo_feature.dart';
import 'eov_service.dart';
import 'import_service.dart';

class GeoPackageService {
  Future<List<ImportedLayer>> importFile(File file, EovService eov) async {
    final db = sqlite3.open(file.path, mode: OpenMode.readOnly);
    try {
      final tables = db.select(
        "SELECT table_name, identifier, srs_id FROM gpkg_contents "
        "WHERE data_type = 'features' ORDER BY table_name",
      );
      final layers = <ImportedLayer>[];
      for (final table in tables) {
        final tableName = table['table_name'] as String;
        final geomInfo = db.select(
          'SELECT column_name, srs_id FROM gpkg_geometry_columns WHERE table_name = ?',
          [tableName],
        );
        if (geomInfo.isEmpty) continue;
        final geometryColumn = geomInfo.first['column_name'] as String;
        final srsId = (geomInfo.first['srs_id'] as int?) ?? 4326;
        final crsInfo = _crsName(db, srsId);
        if (!_isSupportedSrs(srsId)) {
          // Never interpret an arbitrary projected CRS as lon/lat.
          layers.add(ImportedLayer(
            (table['identifier'] as String?) ?? tableName,
            const [],
            sourceType: 'GeoPackage',
            crsInfo: '$crsInfo (unsupported; no transform applied)',
          ));
          continue;
        }
        final safeTable = _quoteIdentifier(tableName);
        final rows = db.select('SELECT * FROM $safeTable');
        final columns = db.select('PRAGMA table_info($safeTable)');
        final fields = columns
            .where((column) => column['name'] != geometryColumn && column['name'] != 'fid')
            .map((column) {
              final name = column['name'] as String;
              final declaredType = (column['type'] as String? ?? '').toUpperCase();
              final fieldType = declaredType.contains('INT')
                  ? FieldType.integer
                  : (declaredType.contains('REAL') || declaredType.contains('NUM'))
                      ? FieldType.decimal
                      : FieldType.text;
              return CustomFieldDefinition(
                key: name,
                label: name,
                type: fieldType,
                isRequired: column['notnull'] == 1,
              );
            })
            .toList();
        final features = <GeoFeature>[];
        for (final row in rows) {
          final blob = row[geometryColumn];
          if (blob is! Uint8List || blob.length < 9) continue;
          final geometry = _readGeometry(blob, eov, srsId);
          if (geometry == null || geometry.points.isEmpty) continue;
          final attributes = <String, dynamic>{};
          for (final field in fields) {
            attributes[field.key] = row[field.key];
          }
          features.add(GeoFeature(
            name: (attributes['name'] ?? attributes['NAME'] ?? table['identifier']).toString(),
            description: (attributes['description'] ?? '').toString(),
            type: geometry.type,
            geometry: geometry.points,
            customData: attributes,
            calculatedStats: {'Imported CRS': crsInfo},
          ));
        }
        layers.add(ImportedLayer(
          (table['identifier'] as String?) ?? tableName,
          features,
          sourceType: 'GeoPackage',
          crsInfo: crsInfo,
          fields: fields,
        ));
      }
      return layers;
    } finally {
      db.dispose();
    }
  }

  Future<File> exportLayer({
    required ProjectLayer layer,
    required String outputPath,
    required bool useEov,
    required EovService eov,
    List<GeoFeature>? selectedFeatures,
  }) async {
    final srsId = useEov ? 23700 : 4326;
    final tableName = _safeName(layer.name);
    const geometryColumn = 'geom';
    final db = sqlite3.open(outputPath);
    try {
      db.execute('PRAGMA application_id = 1196437808');
      db.execute('PRAGMA user_version = 10300');
      db.execute('CREATE TABLE gpkg_spatial_ref_sys (srs_name TEXT NOT NULL, srs_id INTEGER NOT NULL PRIMARY KEY, organization TEXT NOT NULL, organization_coordsys_id INTEGER NOT NULL, definition TEXT NOT NULL, description TEXT)');
      db.execute('CREATE TABLE gpkg_contents (table_name TEXT NOT NULL PRIMARY KEY, data_type TEXT NOT NULL, identifier TEXT UNIQUE, description TEXT DEFAULT \'\', last_change DATETIME NOT NULL DEFAULT (strftime(\'%Y-%m-%dT%H:%M:%fZ\',\'now\')), min_x DOUBLE, min_y DOUBLE, max_x DOUBLE, max_y DOUBLE, srs_id INTEGER, FOREIGN KEY (srs_id) REFERENCES gpkg_spatial_ref_sys(srs_id))');
      db.execute('CREATE TABLE gpkg_geometry_columns (table_name TEXT NOT NULL, column_name TEXT NOT NULL, geometry_type_name TEXT NOT NULL, srs_id INTEGER NOT NULL, z TINYINT NOT NULL, m TINYINT NOT NULL, PRIMARY KEY (table_name, column_name))');
      db.execute("INSERT INTO gpkg_spatial_ref_sys VALUES ('Undefined Cartesian', -1, 'NONE', -1, 'undefined', '')");
      db.execute("INSERT INTO gpkg_spatial_ref_sys VALUES ('Undefined Geographic', 0, 'NONE', 0, 'undefined', '')");
      db.execute("INSERT INTO gpkg_spatial_ref_sys VALUES ('WGS 84 geodetic', 4326, 'EPSG', 4326, 'GEOGCS[\"WGS 84\"]', 'longitude/latitude')");
      db.execute("INSERT INTO gpkg_spatial_ref_sys VALUES ('Hungarian EOV', 23700, 'EPSG', 23700, 'LOCAL_CS[\"HD72 / EOV\"]', 'EOV')");
      final attributes = <CustomFieldDefinition>[];
      for (final field in layer.fields) {
        if (field.key.toLowerCase() != geometryColumn &&
            field.key.toLowerCase() != 'name' &&
            field.key.toLowerCase() != 'description') {
          attributes.add(field);
        }
      }
      final definitions = [
        '"fid" INTEGER PRIMARY KEY AUTOINCREMENT',
        '"$geometryColumn" BLOB NOT NULL',
        '"name" TEXT',
        '"description" TEXT',
        ...attributes.map((field) => '${_quoteIdentifier(field.key)} ${_sqlType(field.type)}${field.isRequired ? ' NOT NULL' : ''}'),
      ];
      db.execute('CREATE TABLE ${_quoteIdentifier(tableName)} (${definitions.join(', ')})');
      db.execute('INSERT INTO gpkg_contents (table_name, data_type, identifier, srs_id) VALUES (?, \'features\', ?, ?)', [tableName, layer.name, srsId]);
      db.execute('INSERT INTO gpkg_geometry_columns VALUES (?, ?, \'GEOMETRY\', ?, 0, 0)', [tableName, geometryColumn, srsId]);
      final featureRows = selectedFeatures ?? layer.features;
      db.execute('BEGIN');
      for (final feature in featureRows) {
        final wkb = _writeGeometry(feature, useEov, eov);
        final values = <Object?>[
          _gpkgHeader(wkb, srsId),
          feature.name,
          feature.description,
          ...attributes.map((field) => feature.customData[field.key]),
        ];
        final names = [
          '"$geometryColumn"',
          '"name"',
          '"description"',
          ...attributes.map((field) => _quoteIdentifier(field.key)),
        ];
        final placeholders = List.filled(values.length, '?').join(', ');
        db.execute('INSERT INTO ${_quoteIdentifier(tableName)} (${names.join(', ')}) VALUES ($placeholders)', values);
      }
      db.execute('COMMIT');
    } finally {
      db.dispose();
    }
    return File(outputPath);
  }

  _ParsedGeometry? _readGeometry(Uint8List blob, EovService eov, int fallbackSrs) {
    final data = ByteData.sublistView(blob);
    if (blob[0] != 0x47 || blob[1] != 0x50) return null;
    final flags = blob[3];
    final headerLittleEndian = (flags & 1) != 0;
    final srsId = data.getInt32(4, headerLittleEndian ? Endian.little : Endian.big);
    var offset = 8;
    if ((flags & 0x20) != 0) {
      final envelopeIndicator = (flags >> 1) & 7;
      offset += switch (envelopeIndicator) { 1 => 32, 2 || 3 => 48, 4 => 64, _ => 0 };
    }
    final parsed = _readWkb(blob, offset, eov, srsId == 0 ? fallbackSrs : srsId);
    return parsed;
  }

  _ParsedGeometry? _readWkb(Uint8List bytes, int offset, EovService eov, int srsId) {
    if (offset + 5 > bytes.length) return null;
    final data = ByteData.sublistView(bytes);
    final little = bytes[offset] == 1;
    final endian = little ? Endian.little : Endian.big;
    final rawType = data.getUint32(offset + 1, endian);
    final typeCode = rawType % 1000;
    var cursor = offset + 5;
    List<LatLng> points = [];
    FeatureType? type;
    if (typeCode == 1) {
      final coord = _readCoord(data, cursor, endian);
      if (coord == null) return null;
      points = [_toWgs(coord.$1, coord.$2, srsId, eov)];
      type = FeatureType.point;
    } else if (typeCode == 2 || typeCode == 3) {
      final count = data.getUint32(cursor, endian);
      cursor += 4;
      final ringCount = typeCode == 3 ? count : 1;
      if (typeCode == 3) {
        points = [];
        for (var ring = 0; ring < ringCount; ring++) {
          final pointCount = data.getUint32(cursor, endian);
          cursor += 4;
          for (var i = 0; i < pointCount; i++) {
            final coord = _readCoord(data, cursor, endian);
            if (coord == null) return null;
            points.add(_toWgs(coord.$1, coord.$2, srsId, eov));
            cursor += 16;
          }
        }
        type = FeatureType.polygon;
      } else {
        for (var i = 0; i < count; i++) {
          final coord = _readCoord(data, cursor, endian);
          if (coord == null) return null;
          points.add(_toWgs(coord.$1, coord.$2, srsId, eov));
          cursor += 16;
        }
        type = FeatureType.line;
      }
    } else {
      return null;
    }
    return _ParsedGeometry(points, type);
  }

  (double, double)? _readCoord(ByteData data, int offset, Endian endian) {
    if (offset + 16 > data.lengthInBytes) return null;
    return (data.getFloat64(offset, endian), data.getFloat64(offset + 8, endian));
  }

  LatLng _toWgs(double x, double y, int srsId, EovService eov) {
    if (srsId == 23700) {
      final wgs = eov.eovToWgs(x, y);
      return LatLng(wgs[0], wgs[1]);
    }
    return LatLng(y, x);
  }

  Uint8List _writeGeometry(GeoFeature feature, bool useEov, EovService eov) {
    final typeCode = switch (feature.type) {
      FeatureType.point => 1,
      FeatureType.line => 2,
      FeatureType.polygon => 3,
    };
    final bytes = BytesBuilder(copy: false);
    bytes.add([1]);
    final typeData = ByteData(4)..setUint32(0, typeCode, Endian.little);
    bytes.add(typeData.buffer.asUint8List());
    void addPoint(LatLng point) {
      final coords = useEov
          ? eov.wgsToEov(point.latitude, point.longitude)
          : [point.latitude, point.longitude];
      final x = useEov ? coords[1] : point.longitude;
      final y = useEov ? coords[0] : point.latitude;
      final data = ByteData(16)
        ..setFloat64(0, x, Endian.little)
        ..setFloat64(8, y, Endian.little);
      bytes.add(data.buffer.asUint8List());
    }
    if (feature.type == FeatureType.point) {
      addPoint(feature.geometry.first);
    } else if (feature.type == FeatureType.line) {
      _addCount(bytes, feature.geometry.length);
      for (final point in feature.geometry) {
        addPoint(point);
      }
    } else {
      final points = List<LatLng>.from(feature.geometry);
      if (points.isNotEmpty &&
          (points.first.latitude != points.last.latitude ||
              points.first.longitude != points.last.longitude)) {
        points.add(points.first);
      }
      _addCount(bytes, 1);
      _addCount(bytes, points.length);
      for (final point in points) {
        addPoint(point);
      }
    }
    return bytes.takeBytes();
  }

  Uint8List _gpkgHeader(Uint8List wkb, int srsId) {
    final header = Uint8List(8);
    header[0] = 0x47;
    header[1] = 0x50;
    header[2] = 0;
    header[3] = 1;
    ByteData.sublistView(header).setInt32(4, srsId, Endian.little);
    return Uint8List.fromList([...header, ...wkb]);
  }

  void _addCount(BytesBuilder bytes, int count) {
    final data = ByteData(4)..setUint32(0, count, Endian.little);
    bytes.add(data.buffer.asUint8List());
  }

  String _sqlType(FieldType type) => switch (type) {
    FieldType.integer => 'INTEGER',
    FieldType.decimal => 'REAL',
    FieldType.bool => 'BOOLEAN',
    _ => 'TEXT',
  };

    String _quoteIdentifier(String input) => '"${input.replaceAll('"', '""')}"';
  String _safeName(String input) {
    final name = p.basenameWithoutExtension(input).replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
    return name.isEmpty ? 'features' : name;
  }
  bool _isSupportedSrs(int srsId) => srsId == 23700 || srsId == 4326;

  String _crsName(Database db, int srsId) {
    final rows = db.select(
      'SELECT organization, organization_coordsys_id, srs_name '
      'FROM gpkg_spatial_ref_sys WHERE srs_id = ?',
      [srsId],
    );
    if (srsId == 23700) return 'EOV (EPSG:23700)';
    if (srsId == 4326) return 'WGS84 (EPSG:4326)';
    if (rows.isEmpty) return 'EPSG:$srsId';
    final row = rows.first;
    final organization = row['organization'];
    final code = row['organization_coordsys_id'];
    final name = row['srs_name'];
    return organization != null && code != null
        ? '$name ($organization:$code)'
        : 'EPSG:$srsId';
  }
}

class _ParsedGeometry {
  final List<LatLng> points;
  final FeatureType type;
  _ParsedGeometry(this.points, this.type);
}
