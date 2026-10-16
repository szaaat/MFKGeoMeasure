import 'dart:io';
import 'dart:typed_data';
import 'package:latlong2/latlong.dart';
import '../models/geo_feature.dart';
import '../models/field_definition.dart';
import 'eov_service.dart';

class ShpExportService {
  
  /// Generálja a Shapefile csomagot (.shp, .shx, .dbf, .prj)
  static Future<List<File>> generateShapefile(
    String directoryPath, 
    String baseName, 
    ProjectLayer layer,
    {
      List<GeoFeature>? features, 
      int? forceShapeType, 
      EovService? eovService,
      bool useEov = false, // Új paraméter a cél koordinátarendszerhez
    }
  ) async {
    final shpFile = File('$directoryPath/$baseName.shp');
    final shxFile = File('$directoryPath/$baseName.shx');
    final dbfFile = File('$directoryPath/$baseName.dbf');
    final prjFile = File('$directoryPath/$baseName.prj');

    final exportFeatures = features ?? layer.features;
    if (exportFeatures.isEmpty) return [];

    // 1. PRJ fájl
    if (useEov) {
      // EOV (EPSG:23700) WKT
      await prjFile.writeAsString('PROJCS["HD72 / EOV",GEOGCS["HD72",DATUM["Hungarian_Datum_1972",SPHEROID["GRS 1967",6378160,298.247167427,AUTHORITY["EPSG","7019"]],TOWGS84[52.17,-71.82,-14.9,0,0,0,0],AUTHORITY["EPSG","6237"]],PRIMEM["Greenwich",0,AUTHORITY["EPSG","8901"]],UNIT["degree",0.0174532925199433,AUTHORITY["EPSG","9122"]],AUTHORITY["EPSG","4237"]],PROJECTION["Hotine_Oblique_Mercator_Azimuth_Center"],PARAMETER["latitude_of_center",47.1443937222222],PARAMETER["longitude_of_center",19.0485717777778],PARAMETER["azimuth",90],PARAMETER["rectified_grid_angle",90],PARAMETER["scale_factor",0.99993],PARAMETER["false_easting",650000],PARAMETER["false_northing",200000],UNIT["metre",1,AUTHORITY["EPSG","9001"]],AXIS["Easting",EAST],AXIS["Northing",NORTH],AUTHORITY["EPSG","23700"]]');
    } else {
      // WGS84 (EPSG:4326) WKT
      await prjFile.writeAsString('GEOGCS["GCS_WGS_1984",DATUM["D_WGS_1984",SPHEROID["WGS_1984",6378137.0,298.257223563]],PRIMEM["Greenwich",0.0],UNIT["Degree",0.0174532925199433]]');
    }

    // Meghatározzuk a Shape típust
    int shapeType = forceShapeType ?? 1;
    if (forceShapeType == null && exportFeatures.isNotEmpty) {
      switch (exportFeatures.first.type) {
        case FeatureType.point: shapeType = 1; break;
        case FeatureType.line: shapeType = 3; break;
        case FeatureType.polygon: shapeType = 5; break;
      }
    }

    final List<Uint8List> records = [];
    double minX = 1e18, minY = 1e18, maxX = -1e18, maxY = -1e18;

    for (var feature in exportFeatures) {
      final recordData = _createRecord(feature, shapeType, eovService: eovService, useEov: useEov);
      if (recordData != null) {
        records.add(recordData);
        
        for (var p in feature.geometry) {
          double x = p.longitude;
          double y = p.latitude;
          
          if (useEov && eovService != null) {
            final eov = eovService.wgsToEov(p.latitude, p.longitude);
            x = eov[0]; // EOV Y (Easting)
            y = eov[1]; // EOV X (Northing)
          }

          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }
    }

    if (records.isEmpty) return [];

    // 2. SHP és SHX mentése
    await _writeShp(shpFile, records, shapeType, minX, minY, maxX, maxY);
    await _writeShx(shxFile, records, shapeType, minX, minY, maxX, maxY);

    // 3. DBF mentése
    await _writeDbf(dbfFile, layer, exportFeatures, eovService: eovService);

    return [shpFile, shxFile, dbfFile, prjFile];
  }

  static Uint8List? _createRecord(GeoFeature f, int shapeType, {EovService? eovService, bool useEov = false}) {
    final builder = BytesBuilder();
    
    if (shapeType == 1) { // Point
      if (f.geometry.isEmpty) return null;
      final p = f.geometry.first;
      
      double x = p.longitude;
      double y = p.latitude;
      if (useEov && eovService != null) {
        final eov = eovService.wgsToEov(p.latitude, p.longitude);
        x = eov[0]; // EOV Y (Easting)
        y = eov[1]; // EOV X (Northing)
      }

      builder.add(_int32LE(1)); // Type
      builder.add(_float64LE(x));
      builder.add(_float64LE(y));
    } else if (shapeType == 3 || shapeType == 5) { // PolyLine vagy Polygon
      if (f.geometry.length < 2) return null;
      
      var points = List<LatLng>.from(f.geometry);
      if (shapeType == 5) { // Polygon specifikus
        // Zárás
        if (points.first.latitude != points.last.latitude || points.first.longitude != points.last.longitude) {
          points.add(points.first);
        }
        if (!_isClockwise(points)) {
          points = points.reversed.toList();
        }
      }

      final List<List<double>> transformedPoints = points.map((p) {
        if (useEov && eovService != null) {
          final eov = eovService.wgsToEov(p.latitude, p.longitude);
          return [eov[0], eov[1]]; // [Y (Easting), X (Northing)]
        }
        return [p.longitude, p.latitude];
      }).toList();

      double boxMinX = 1e18, boxMinY = 1e18, boxMaxX = -1e18, boxMaxY = -1e18;
      for (var p in transformedPoints) {
        if (p[0] < boxMinX) boxMinX = p[0];
        if (p[0] > boxMaxX) boxMaxX = p[0];
        if (p[1] < boxMinY) boxMinY = p[1];
        if (p[1] > boxMaxY) boxMaxY = p[1];
      }

      builder.add(_int32LE(shapeType));
      builder.add(_float64LE(boxMinX));
      builder.add(_float64LE(boxMinY));
      builder.add(_float64LE(boxMaxX));
      builder.add(_float64LE(boxMaxY));
      
      builder.add(_int32LE(1)); // NumParts
      builder.add(_int32LE(transformedPoints.length)); // NumPoints
      builder.add(_int32LE(0)); // Parts start index
      
      for (var p in transformedPoints) {
        builder.add(_float64LE(p[0]));
        builder.add(_float64LE(p[1]));
      }
    }
    
    return builder.toBytes();
  }

  static Future<void> _writeShp(File file, List<Uint8List> records, int type, double x1, double y1, double x2, double y2) async {
    final builder = BytesBuilder();
    
    // Header (100 bytes)
    builder.add(_int32BE(9994)); // File Code
    builder.add(Uint8List(20)); // Unused
    
    int totalContentLen = 0;
    for (var r in records) {
      totalContentLen += r.length + 8;
    }
    builder.add(_int32BE(50 + (totalContentLen ~/ 2))); // File Length (16-bit words)
    
    builder.add(_int32LE(1000)); // Version
    builder.add(_int32LE(type));
    
    builder.add(_float64LE(x1)); builder.add(_float64LE(y1));
    builder.add(_float64LE(x2)); builder.add(_float64LE(y2));
    builder.add(Uint8List(32)); // Z, M range (unused)

    // Records
    for (int i = 0; i < records.length; i++) {
      builder.add(_int32BE(i + 1)); // Record Number
      builder.add(_int32BE(records[i].length ~/ 2)); // Content Length
      builder.add(records[i]);
    }
    
    await file.writeAsBytes(builder.toBytes());
  }

  static Future<void> _writeShx(File file, List<Uint8List> records, int type, double x1, double y1, double x2, double y2) async {
    final builder = BytesBuilder();
    builder.add(_int32BE(9994));
    builder.add(Uint8List(20));
    builder.add(_int32BE(50 + records.length * 4)); // Header + 4 words per record
    builder.add(_int32LE(1000));
    builder.add(_int32LE(type));
    builder.add(_float64LE(x1)); builder.add(_float64LE(y1));
    builder.add(_float64LE(x2)); builder.add(_float64LE(y2));
    builder.add(Uint8List(32));

    int offset = 50; // In words
    for (var r in records) {
      builder.add(_int32BE(offset));
      builder.add(_int32BE(r.length ~/ 2));
      offset += (r.length + 8) ~/ 2;
    }
    await file.writeAsBytes(builder.toBytes());
  }

  static Future<void> _writeDbf(File file, ProjectLayer layer, List<GeoFeature> features, {EovService? eovService}) async {
    final builder = BytesBuilder();
    
    // DBF Header
    builder.addByte(0x03); // dBase III
    final now = DateTime.now();
    builder.addByte(now.year - 1900);
    builder.addByte(now.month);
    builder.addByte(now.day);
    
    builder.add(_int32LE(features.length));
    
    // Mezők meghatározása (alap mezők + professzionális geodéziai metaadatok + egyedi mezők)
    final dbfFields = [
      _DbfField("NAME", "C", 50),
      _DbfField("DESC", "C", 100),
      _DbfField("CREATED", "C", 20),
      // Geodéziai metaadatok (Rövidített SHP nevek)
      _DbfField("SURVEY_MTH", "C", 15),
      _DbfField("GNSS_SRC", "C", 15),
      _DbfField("GEOM_TYPE", "C", 12),
      _DbfField("RTK_STAT", "C", 10),
      _DbfField("RECEIVER", "C", 20),
      _DbfField("NTRIP", "C", 5),
      _DbfField("CORR_AGE", "N", 10, decimal: 1),
      _DbfField("SATS_USED", "N", 5, decimal: 0),
      _DbfField("HDOP", "N", 8, decimal: 2),
      _DbfField("VDOP", "N", 8, decimal: 2),
      _DbfField("PDOP", "N", 8, decimal: 2),
      _DbfField("STATION_ID", "C", 15),
      _DbfField("TS_SOURCE", "C", 10),
    ];

    // Rendszerattribútumok hozzáadása Point típus esetén (Koordináták)
    bool isPoint = features.any((f) => f.type == FeatureType.point);
    if (isPoint) {
      dbfFields.add(_DbfField("EOV_Y", "N", 15, decimal: 2));
      dbfFields.add(_DbfField("EOV_X", "N", 15, decimal: 2));
      dbfFields.add(_DbfField("SRC_H", "N", 15, decimal: 3));
      dbfFields.add(_DbfField("ELL_H", "N", 15, decimal: 3));
      dbfFields.add(_DbfField("BALT_H", "N", 15, decimal: 3));
    }

    final Map<String, String> keyToShpName = {};
    final Set<String> usedShpNames = dbfFields.map((f) => f.name).toSet();

    for (var fDef in layer.fields) {
      String shpName = fDef.key.toUpperCase();
      if (shpName.length > 10) shpName = shpName.substring(0, 10);
      
      int counter = 1;
      String originalShpName = shpName;
      while (usedShpNames.contains(shpName)) {
        String suffix = counter.toString();
        shpName = originalShpName.substring(0, 10 - suffix.length) + suffix;
        counter++;
      }
      usedShpNames.add(shpName);
      keyToShpName[fDef.key] = shpName;

      String type = "C"; 
      int len = 50;
      int decimal = 0;

      switch (fDef.type) {
        case FieldType.integer: type = "N"; len = 10; break;
        case FieldType.decimal: type = "N"; len = 15; decimal = 6; break;
        case FieldType.bool: type = "L"; len = 1; break;
        case FieldType.date:
        case FieldType.dateTime: type = "C"; len = 20; break;
        default: type = "C"; len = 50;
      }
      dbfFields.add(_DbfField(shpName, type, len, decimal: decimal));
    }

    int headerLen = 32 + dbfFields.length * 32 + 1;
    int recordLen = 1; // Deletion flag
    for (var f in dbfFields) {
      recordLen += f.length;
    }

    builder.add(_int16LE(headerLen));
    builder.add(_int16LE(recordLen));
    builder.add(Uint8List(20)); // Reserved

    // Field Descriptors
    for (var f in dbfFields) {
      final nameBytes = Uint8List(11);
      final encodedName = f.name.codeUnits;
      for (int i = 0; i < encodedName.length && i < 11; i++) {
        nameBytes[i] = encodedName[i];
      }
      builder.add(nameBytes);
      builder.addByte(f.type.codeUnitAt(0));
      builder.add(Uint8List(4)); // Reserved
      builder.addByte(f.length);
      builder.addByte(f.decimal);
      builder.add(Uint8List(14)); // Reserved
    }
    
    builder.addByte(0x0D); // Header terminator

    // Records
    for (var feature in features) {
      builder.addByte(0x20); // Not deleted (space)
      
      _addDbfValue(builder, feature.name, dbfFields[0]);
      _addDbfValue(builder, feature.description, dbfFields[1]);
      _addDbfValue(builder, feature.createdAt.toIso8601String(), dbfFields[2]);

      // Professional Metadata Mapping
      _addDbfValue(builder, feature.calculatedStats['Survey Method'], dbfFields[3]);
      _addDbfValue(builder, feature.calculatedStats['GNSS Source'], dbfFields[4]);
      _addDbfValue(builder, feature.calculatedStats['Geometry Type'], dbfFields[5]);
      _addDbfValue(builder, feature.calculatedStats['RTK Status'], dbfFields[6]);
      _addDbfValue(builder, feature.calculatedStats['Receiver'], dbfFields[7]);
      _addDbfValue(builder, feature.calculatedStats['NTRIP Active'], dbfFields[8]);
      _addDbfValue(builder, feature.calculatedStats['Correction Age'], dbfFields[9]);
      _addDbfValue(builder, feature.calculatedStats['Sats Used'], dbfFields[10]);
      _addDbfValue(builder, feature.calculatedStats['HDOP'], dbfFields[11]);
      _addDbfValue(builder, feature.calculatedStats['VDOP'], dbfFields[12]);
      _addDbfValue(builder, feature.calculatedStats['PDOP'], dbfFields[13]);
      _addDbfValue(builder, feature.calculatedStats['Station ID'], dbfFields[14]);
      _addDbfValue(builder, feature.calculatedStats['Timestamp Source'], dbfFields[15]);

      int fieldIdx = 16;
      if (isPoint) {
        if (feature.type == FeatureType.point && feature.geometry.isNotEmpty) {
          final p = feature.geometry.first;
          final double gpsAlt = feature.altitudes.isNotEmpty ? feature.altitudes.first : double.nan;
          
          if (eovService != null) {
            final eov = eovService.wgsToEov(p.latitude, p.longitude);
            _addDbfValue(builder, eov[0], dbfFields[fieldIdx++]); // Y
            _addDbfValue(builder, eov[1], dbfFields[fieldIdx++]); // X
          } else {
            _addDbfValue(builder, null, dbfFields[fieldIdx++]);
            _addDbfValue(builder, null, dbfFields[fieldIdx++]);
          }
          
          _addDbfValue(builder, gpsAlt.isFinite ? gpsAlt : null, dbfFields[fieldIdx++]); // SRC_H
          
          double? ellH = feature.calculatedStats['Ellipszoidi magasság'] ?? feature.calculatedStats['Ellipszoidi magasság (számított)'];
          _addDbfValue(builder, ellH, dbfFields[fieldIdx++]); // ELL_H
          
          // Balti magasság számítása, ha nincs kész érték a statisztikákban
          double? orthoH = feature.calculatedStats['Balti magasság'] ?? feature.calculatedStats['Tengerszint feletti magasság (forrás)'];
          _addDbfValue(builder, orthoH, dbfFields[fieldIdx++]); // BALT_H
        } else {
          _addDbfValue(builder, null, dbfFields[fieldIdx++]);
          _addDbfValue(builder, null, dbfFields[fieldIdx++]);
          _addDbfValue(builder, null, dbfFields[fieldIdx++]);
          _addDbfValue(builder, null, dbfFields[fieldIdx++]);
          _addDbfValue(builder, null, dbfFields[fieldIdx++]);
        }
      }

      for (var fDef in layer.fields) {
        final val = feature.customData[fDef.key];
        _addDbfValue(builder, val, dbfFields[fieldIdx++]);
      }
    }
    
    builder.addByte(0x1A); // EOF
    await file.writeAsBytes(builder.toBytes());
  }

  static void _addDbfValue(BytesBuilder builder, dynamic value, _DbfField field) {
    String strVal = "";
    if (value != null) {
      if (field.type == "L") {
        strVal = (value == true) ? "T" : "F";
      } else if (field.type == "N") {
        strVal = value.toString();
      } else {
        strVal = value.toString();
      }
    }
    
    final bytes = Uint8List(field.length);
    for (int i = 0; i < field.length; i++) {
      bytes[i] = 0x20;
    } // Padding with spaces
    
    final encoded = strVal.codeUnits;
    for (int i = 0; i < encoded.length && i < field.length; i++) {
      bytes[i] = encoded[i];
    }
    builder.add(bytes);
  }

  // Helper metódusok bináris íráshoz
  static Uint8List _int32BE(int value) => Uint8List(4)..buffer.asByteData().setInt32(0, value, Endian.big);
  static Uint8List _int32LE(int value) => Uint8List(4)..buffer.asByteData().setInt32(0, value, Endian.little);
  static Uint8List _int16LE(int value) => Uint8List(2)..buffer.asByteData().setInt16(0, value, Endian.little);
  static Uint8List _float64LE(double value) => Uint8List(8)..buffer.asByteData().setFloat64(0, value, Endian.little);

  static bool _isClockwise(List<LatLng> points) {
    double area = 0;
    for (int i = 0; i < points.length; i++) {
      final p1 = points[i];
      final p2 = points[(i + 1) % points.length];
      area += (p2.longitude - p1.longitude) * (p2.latitude + p1.latitude);
    }
    return area > 0;
  }
}

class _DbfField {
  final String name;
  final String type;
  final int length;
  final int decimal;
  _DbfField(this.name, this.type, this.length, {this.decimal = 0});
}
