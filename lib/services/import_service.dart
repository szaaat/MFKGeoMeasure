import 'dart:io';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:dxf/dxf.dart';
import 'package:latlong2/latlong.dart';
import 'package:geoxml/geoxml.dart';
import 'package:archive/archive.dart';
import 'package:shapefile/shapefile.dart' as shp;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:xml/xml.dart';
import '../models/geo_feature.dart';
import 'data_validation_service.dart';
import '../models/field_definition.dart';
import 'eov_service.dart';
import 'gpkg_service.dart';

/// Represents a set of related Shapefile components
class ShpFileSet {
  final String baseName;
  final File shpFile;
  final File? dbfFile;
  final File? shxFile;
  final File? prjFile;

  ShpFileSet({
    required this.baseName,
    required this.shpFile,
    this.dbfFile,
    this.shxFile,
    this.prjFile,
  });

  bool get isComplete => dbfFile != null && shxFile != null;
}

/// Represents a successfully parsed GIS layer ready for integration
class ImportedLayer {
  final String name;
  final List<GeoFeature> features;
  final String sourceType;
  final String? crsInfo;
  final List<CustomFieldDefinition> fields;

  ImportedLayer(
    this.name,
    this.features, {
    this.sourceType = 'import',
    this.crsInfo,
    this.fields = const [],
  });
}

class ImportService extends ChangeNotifier {
  EovService? _eovService;

  void updateEovService(EovService service) {
    _eovService = service;
  }

  Future<List<ImportedLayer>> importGisData(BuildContext context) async {
    if (_eovService == null) return [];

    try {
      final List<PlatformFile> pickedFiles = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'dxf',
          'kml',
          'kmz',
          'gpx',
          'shp',
          'dbf',
          'shx',
          'prj',
          'zip',
          'gml',
          'gpkg'
        ],
      );

      if (!context.mounted || pickedFiles.isEmpty) return [];

      // 1. Check for ZIP
      if (pickedFiles.length == 1 &&
          pickedFiles.first.extension?.toLowerCase() == 'zip') {
        return await _parseZip(context, File(pickedFiles.first.path!));
      }

      // 2. Handle single or multiple uncompressed files
      final List<ImportedLayer> results = [];

      for (var pf in pickedFiles) {
        final ext = pf.extension?.toLowerCase();
        final file = File(pf.path!);
        final baseName = p.basenameWithoutExtension(file.path);

        if (ext == 'dxf') {
          final features = await _parseDxf(file);
          if (features.isNotEmpty) {
            results.add(
                ImportedLayer(baseName, features, crsInfo: 'EOV (Assumed)'));
          }
        } else if (ext == 'kml') {
          final features = await _parseKml(await _readTextFile(file));
          if (features.isNotEmpty) {
            results.add(ImportedLayer(baseName, features, crsInfo: 'WGS84'));
          }
        } else if (ext == 'kmz') {
          final features = await _parseKmz(file);
          if (features.isNotEmpty) {
            results.add(ImportedLayer(baseName, features, crsInfo: 'WGS84'));
          }
        } else if (ext == 'gpx') {
          final features = await _parseGpx(await _readTextFile(file));
          if (features.isNotEmpty) {
            results.add(ImportedLayer(baseName, features, crsInfo: 'WGS84'));
          }
        } else if (ext == 'gml') {
          final content = await _readTextFile(file);
          if (!context.mounted) return results;
          results.addAll(await _parseGml(context, content, baseName));
        } else if (ext == 'gpkg') {
          results
              .addAll(await GeoPackageService().importFile(file, _eovService!));
        }
      }

      // Process SHP sets
      final shpSets =
          _groupFilesToSets(pickedFiles.map((f) => File(f.path!)).toList());
      for (var shpSet in shpSets) {
        String? crs;
        if (shpSet.prjFile != null) {
          final prjWkt = await _readTextFile(shpSet.prjFile!);
          crs = _detectCrsFromPrj(prjWkt);
        }
        if (!context.mounted) return results;
        final features = await _parseShpSet(context, shpSet, detectedCrs: crs);
        if (features != null) {
          results.add(ImportedLayer(
            shpSet.baseName,
            features,
            crsInfo: crs,
            fields: await _readDbfFields(shpSet.dbfFile!),
          ));
        }
      }

      if (results.isEmpty || !context.mounted) return results;
      return await _showImportPreview(context, results)
          ? results
          : <ImportedLayer>[];
    } catch (e) {
      debugPrint("Hiba a GIS importálásakor: $e");
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("Import error: $e"), backgroundColor: Colors.red));
      }
      return [];
    }
  }

  Future<List<ImportedLayer>> _parseGml(
      BuildContext context, String content, String fallbackName) async {
    final root = XmlDocument.parse(content).rootElement;
    final srsName = root.descendantElements
            .map((element) => element.getAttribute('srsName'))
            .whereType<String>()
            .firstOrNull ??
        root.getAttribute('srsName') ??
        '';
    final upperSrs = srsName.toUpperCase();
    var crs = upperSrs.contains('23700') ||
            upperSrs.contains('EOV') ||
            upperSrs.contains('HD72')
        ? 'EOV'
        : upperSrs.contains('4326') || upperSrs.contains('WGS')
            ? 'WGS84'
            : _guessCoordinateCrs(content);
    if (crs == 'UNKNOWN' && context.mounted) {
      crs = await _promptForCrs(context) ?? 'UNKNOWN';
    }
    if (crs == 'UNKNOWN' || !context.mounted) return [];
    final members = <XmlElement>[];
    for (final member in root.descendantElements.where(
      (element) =>
          element.name.local == 'featureMember' ||
          element.name.local == 'member',
    )) {
      members.addAll(member.childElements);
    }
    if (members.isEmpty) {
      members.addAll(root.descendantElements.where(
        (element) => element.childElements
            .any((child) => _isGmlGeometry(child.name.local)),
      ));
    }
    final grouped = <String, List<GeoFeature>>{};
    final fieldMaps = <String, Map<String, CustomFieldDefinition>>{};
    for (final member in members) {
      final layerName = member.name.local;
      final geometry = member.descendantElements
          .where((element) => _isGmlGeometry(element.name.local))
          .firstOrNull;
      if (geometry == null) continue;
      final coordElement = geometry.descendantElements
          .where((element) =>
              element.name.local == 'pos' ||
              element.name.local == 'posList' ||
              element.name.local == 'coordinates')
          .firstOrNull;
      if (coordElement == null) continue;
      final coordinates = <double>[];
      if (coordElement.name.local == 'coordinates') {
        for (final tuple
            in coordElement.innerText.trim().split(RegExp(r'\s+'))) {
          if (tuple.isEmpty) continue;
          coordinates.addAll(
              tuple.split(',').map((value) => double.parse(value.trim())));
        }
      } else {
        coordinates.addAll(coordElement.innerText
            .trim()
            .split(RegExp(r'\s+'))
            .where((v) => v.isNotEmpty)
            .map(double.parse));
      }
      final dimension =
          int.tryParse(coordElement.getAttribute('srsDimension') ?? '') ??
              (coordElement.name.local == 'pos' ? coordinates.length : 2);
      final points = <LatLng>[];
      final altitudes = <double>[];
      final latLonAxis = _gmlUsesLatLonAxis(srsName);
      for (var i = 0; i + 1 < coordinates.length; i += dimension) {
        final first = coordinates[i];
        final second = coordinates[i + 1];
        points.add(latLonAxis
            ? _toWgs(second, first, crs)
            : _toWgs(first, second, crs));
        if (dimension > 2 && i + 2 < coordinates.length) {
          altitudes.add(coordinates[i + 2]);
        }
      }
      if (points.isEmpty) continue;
      final geometryName = geometry.name.local.toLowerCase();
      final type =
          geometryName.contains('polygon') || geometryName.contains('surface')
              ? FeatureType.polygon
              : geometryName == 'point'
                  ? FeatureType.point
                  : FeatureType.line;
      final attrs = <String, dynamic>{};
      for (final child in member.childElements) {
        if (_isGmlGeometry(child.name.local)) continue;
        final value = child.innerText.trim();
        if (value.isEmpty) continue;
        attrs[child.name.local] = value;
        fieldMaps.putIfAbsent(layerName, () => {})[child.name.local] =
            CustomFieldDefinition(
          key: child.name.local,
          label: child.name.local,
          type: int.tryParse(value) != null
              ? FieldType.integer
              : double.tryParse(value) != null
                  ? FieldType.decimal
                  : FieldType.text,
        );
      }
      grouped.putIfAbsent(layerName, () => []).add(GeoFeature(
            name: (attrs['name'] ??
                    attrs['Nev'] ??
                    member.getAttribute('id') ??
                    layerName)
                .toString(),
            type: type,
            geometry: points,
            altitudes: altitudes,
            customData: attrs,
            calculatedStats: {
              'Imported CRS': crs,
              if (altitudes.isNotEmpty) 'Height Reference': 'unknown',
            },
            description:
                (attrs['description'] ?? attrs['Leiras'] ?? 'GML feature')
                    .toString(),
          ));
    }
    return grouped.entries
        .map((entry) => ImportedLayer(
              entry.key.isEmpty ? fallbackName : entry.key,
              entry.value,
              sourceType: 'GML',
              crsInfo: crs == 'EOV'
                  ? 'EOV (EPSG:23700)'
                  : crs == 'WGS84'
                      ? 'WGS84 (EPSG:4326)'
                      : 'UNKNOWN',
              fields: fieldMaps[entry.key]!.values.toList(),
            ))
        .toList();
  }

  bool _isGmlGeometry(String name) => const {
        'Point',
        'MultiPoint',
        'LineString',
        'MultiLineString',
        'Curve',
        'MultiCurve',
        'Polygon',
        'MultiPolygon',
        'Surface',
        'MultiSurface',
      }.contains(name);

  String _guessCoordinateCrs(String content) {
    final values = RegExp(r'[-+]?\d+(?:\.\d+)?')
        .allMatches(content)
        .take(2)
        .map((match) => double.tryParse(match.group(0)!) ?? 0)
        .toList();
    if (values.length == 2 && values[0].abs() <= 180 && values[1].abs() <= 90)
      return 'WGS84';
    return 'UNKNOWN';
  }

  bool _gmlUsesLatLonAxis(String srsName) {
    final upper = srsName.toUpperCase();
    // GML EPSG:4326 commonly follows the EPSG axis order (lat, lon).
    // CRS84 explicitly uses the GIS order (lon, lat).
    return upper.contains('4326') && !upper.contains('CRS84');
  }

  Future<bool> _showImportPreview(
      BuildContext context, List<ImportedLayer> layers) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Import előnézete'),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: layers
                      .map((layer) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(layer.name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold)),
                                Text(
                                    '${layer.sourceType} · ${layer.features.length} elem · CRS: ${layer.crsInfo ?? 'ismeretlen'}'),
                                Text(
                                    'Mezők: ${layer.fields.isEmpty ? 'nincs attribútummező' : layer.fields.map((field) => field.label).join(', ')}'),
                                if (layer.features.isNotEmpty)
                                  Text(
                                      'Minta: ${layer.features.take(3).map((feature) => feature.name).join(', ')}'),
                                ..._layerValidationMessages(layer)
                                    .map((entry) => Padding(
                                          padding:
                                              const EdgeInsets.only(top: 4),
                                          child: Text(entry,
                                              style: const TextStyle(
                                                  color: Colors.deepOrange,
                                                  fontSize: 12)),
                                        )),
                                if (layer.features.isEmpty)
                                  const Text(
                                      'Figyelem: a réteg üres, nincs benne objektum.',
                                      style: TextStyle(
                                          color: Colors.deepOrange,
                                          fontSize: 12)),
                              ],
                            ),
                          ))
                      .toList(),
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Mégse')),
              FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Importálás')),
            ],
          ),
        ) ??
        false;
  }

  List<String> _layerValidationMessages(ImportedLayer layer) {
    const validator = DataValidationService();
    final messages = <String>[];
    var invalidCount = 0;
    var warningCount = 0;
    for (final feature in layer.features) {
      final issues = validator.validateFeature(
        feature: feature,
        fields: layer.fields,
        crsInfo: layer.crsInfo,
      );
      if (issues.any((issue) => issue.severity == ValidationSeverity.error)) {
        invalidCount++;
      }
      warningCount += issues
          .where((issue) => issue.severity == ValidationSeverity.warning)
          .length;
      for (final issue in issues.take(2)) {
        if (messages.length >= 4) break;
        messages.add(
            '${issue.severity == ValidationSeverity.error ? 'Hiba' : 'Figyelem'}: ${feature.name}: ${issue.message}');
      }
    }
    if (invalidCount > 0) {
      messages.insert(0, 'Hibás geometriájú objektum: $invalidCount');
    }
    if (warningCount > 0) {
      messages.add('CRS/attribútum figyelmeztetések: $warningCount');
    }
    return messages.take(5).toList();
  }

  List<ShpFileSet> _groupFilesToSets(List<File> files) {
    final Map<String, Map<String, File>> groups = {};

    for (var file in files) {
      final ext = p.extension(file.path).toLowerCase();
      if (!['.shp', '.dbf', '.shx', '.prj'].contains(ext)) continue;

      final base = p.withoutExtension(file.path);
      groups.putIfAbsent(base, () => {})[ext] = file;
    }

    final List<ShpFileSet> sets = [];
    groups.forEach((base, components) {
      final shp = components['.shp'];
      if (shp != null) {
        sets.add(ShpFileSet(
          baseName: p.basename(base),
          shpFile: shp,
          dbfFile: components['.dbf'],
          shxFile: components['.shx'],
          prjFile: components['.prj'],
        ));
      }
    });
    return sets;
  }

  Future<List<ImportedLayer>> _parseZip(
      BuildContext context, File zipFile) async {
    final tempDir = await getTemporaryDirectory();
    final extractPath =
        p.join(tempDir.path, "import_${DateTime.now().millisecondsSinceEpoch}");
    final directory = Directory(extractPath);
    await directory.create(recursive: true);

    try {
      final bytes = await zipFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      for (final file in archive) {
        final filename = file.name.replaceAll('\\', '/');
        final normalized = p.normalize(filename);
        if (filename.startsWith('/') ||
            normalized == '..' ||
            normalized.startsWith('../') ||
            p.isAbsolute(normalized))
          continue; // Path traversal protection

        final destPath = p.join(extractPath, normalized);
        if (file.isFile) {
          final data = file.content as List<int>;
          await File(destPath).create(recursive: true);
          await File(destPath).writeAsBytes(data);
        } else {
          await Directory(destPath).create(recursive: true);
        }
      }

      final List<File> allExtractedFiles =
          directory.listSync(recursive: true).whereType<File>().toList();
      final shpSets = _groupFilesToSets(allExtractedFiles);

      final List<ImportedLayer> results = [];
      for (var shpSet in shpSets) {
        if (!context.mounted) break;

        String? crs;
        if (shpSet.prjFile != null) {
          final prjWkt = await _readTextFile(shpSet.prjFile!);
          crs = _detectCrsFromPrj(prjWkt);
        }

        if (!context.mounted) break;
        final features = await _parseShpSet(context, shpSet, detectedCrs: crs);
        if (features != null) {
          results.add(ImportedLayer(
            shpSet.baseName,
            features,
            crsInfo: crs,
            fields: await _readDbfFields(shpSet.dbfFile!),
          ));
        }
      }

      // ZIP files may contain other supported GIS formats as well as
      // shapefile sidecars. Process those through the same parsers.
      for (final file in allExtractedFiles) {
        if (!context.mounted) break;
        final ext = p.extension(file.path).toLowerCase();
        if (['.shp', '.dbf', '.shx', '.prj'].contains(ext)) continue;
        final baseName = p.basenameWithoutExtension(file.path);
        if (ext == '.kml') {
          final features = await _parseKml(await _readTextFile(file));
          if (features.isNotEmpty) {
            results.add(ImportedLayer(baseName, features, crsInfo: 'WGS84'));
          }
        } else if (ext == '.kmz') {
          final features = await _parseKmz(file);
          if (features.isNotEmpty) {
            results.add(ImportedLayer(baseName, features, crsInfo: 'WGS84'));
          }
        } else if (ext == '.gpx') {
          final features = await _parseGpx(await _readTextFile(file));
          if (features.isNotEmpty) {
            results.add(ImportedLayer(baseName, features, crsInfo: 'WGS84'));
          }
        } else if (ext == '.gml') {
          results.addAll(await _parseGml(
              context, await _readTextFile(file), baseName));
        } else if (ext == '.dxf') {
          final features = await _parseDxf(file);
          if (features.isNotEmpty) {
            results.add(ImportedLayer(baseName, features,
                crsInfo: 'EOV (Assumed)'));
          }
        } else if (ext == '.gpkg') {
          results.addAll(
              await GeoPackageService().importFile(file, _eovService!));
        }
      }

      if (context.mounted && shpSets.isNotEmpty) {
        final messenger = ScaffoldMessenger.of(context);
        messenger.showSnackBar(SnackBar(
            content: Text("Imported ${results.length} layers from ZIP")));
      }

      return results;
    } catch (e) {
      debugPrint("ZIP extraction error: $e");
      rethrow;
    } finally {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    }
  }

  Future<List<GeoFeature>?> _parseShpSet(
      BuildContext context, ShpFileSet shpSet,
      {String? detectedCrs}) async {
    if (!shpSet.isComplete) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              "Incomplete Shapefile: ${shpSet.baseName}. Missing .dbf or .shx."),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 5),
        ));
      }
      return null;
    }

    if (!context.mounted) return null;
    final messenger = ScaffoldMessenger.of(context);
    final shpBytes = await shpSet.shpFile.readAsBytes();
    final dbfBytes = await shpSet.dbfFile!.readAsBytes();
    final shxBytes = await shpSet.shxFile!.readAsBytes();

    // QGIS writes valid, header-only SHP/SHX and DBF files for empty layers.
    // Some shapefile parser versions reject those files instead of returning
    // an empty FeatureCollection, so recognize that valid zero-record case.
    final shpFeatures = _isEmptyShapefile(shpBytes, shxBytes, dbfBytes)
        ? <dynamic>[]
        : List<dynamic>.from(await shp
            .featureCollection(
              Stream.value(shpBytes),
              dbf: Stream.value(dbfBytes),
            )
            .then((collection) => collection['features'] ?? []));

    String crs = detectedCrs ?? "UNKNOWN";
    if (shpFeatures.isNotEmpty && crs == "UNKNOWN") {
      if (!context.mounted) return null;
      crs = await _promptForCrs(context) ?? "";
      if (!context.mounted || crs.isEmpty) return null;
    }

    if (!context.mounted) return null;
    if (crs != "UNKNOWN") {
      final crsLabel = crs == "EOV" ? "EOV (EPSG:23700)" : "WGS84 (EPSG:4326)";
      messenger
          .showSnackBar(SnackBar(content: Text("Detected CRS: $crsLabel")));
    }

    List<GeoFeature> results = [];
    for (var f in shpFeatures) {
      final geometry = f['geometry'];
      final properties = f['properties'] ?? {};
      final type = geometry['type'];
      final coords = geometry['coordinates'];

      List<LatLng> points = [];
      List<double> altitudes = [];
      FeatureType featureType = FeatureType.point;

      if (type == "Point") {
        featureType = FeatureType.point;
        points.add(_toWgs(coords[0], coords[1], crs));
        if (coords.length > 2) altitudes.add(coords[2]);
      } else if (type == "LineString") {
        featureType = FeatureType.line;
        for (var pt in coords) {
          points.add(_toWgs(pt[0], pt[1], crs));
          if (pt.length > 2) altitudes.add(pt[2]);
        }
      } else if (type == "Polygon") {
        featureType = FeatureType.polygon;
        final List<dynamic> rings = coords;
        if (rings.isNotEmpty) {
          for (var pt in rings[0]) {
            points.add(_toWgs(pt[0], pt[1], crs));
            if (pt.length > 2) altitudes.add(pt[2]);
          }
        }
      }

      if (points.isNotEmpty) {
        final stats = {
          'Survey Method': 'IMPORTED',
          'GNSS Source': 'N/A',
          'RTK Status': 'N/A',
          'NTRIP Active': 'NO',
          'Imported CRS': crs,
        };
        if (altitudes.isNotEmpty) {
          stats['Height Reference'] = 'unknown';
        }

        results.add(GeoFeature(
          name: properties['NAME']?.toString() ??
              properties['Nev']?.toString() ??
              "${shpSet.baseName} element",
          type: featureType,
          geometry: points,
          altitudes: altitudes,
          description: properties['DESC']?.toString() ??
              properties['Leiras']?.toString() ??
              "Imported from ${shpSet.baseName}",
          customData: Map<String, dynamic>.from(properties),
          calculatedStats: stats,
        ));
      }
    }
    return results;
  }

  bool _isEmptyShapefile(
      List<int> shpBytes, List<int> shxBytes, List<int> dbfBytes) {
    if (shpBytes.length != 100 ||
        shxBytes.length != 100 ||
        dbfBytes.length < 33) return false;
    final shpFileCode = (shpBytes[0] << 24) |
        (shpBytes[1] << 16) |
        (shpBytes[2] << 8) |
        shpBytes[3];
    final shxFileCode = (shxBytes[0] << 24) |
        (shxBytes[1] << 16) |
        (shxBytes[2] << 8) |
        shxBytes[3];
    if (shpFileCode != 9994 || shxFileCode != 9994) return false;

    final dbfRecordCount = dbfBytes[4] |
        (dbfBytes[5] << 8) |
        (dbfBytes[6] << 16) |
        (dbfBytes[7] << 24);
    final dbfHeaderLength = dbfBytes[8] | (dbfBytes[9] << 8);
    return dbfRecordCount == 0 &&
        dbfHeaderLength > 32 &&
        dbfHeaderLength <= dbfBytes.length &&
        dbfBytes[dbfHeaderLength - 1] == 0x0D;
  }

  Future<List<CustomFieldDefinition>> _readDbfFields(File dbfFile) async {
    final bytes = await dbfFile.readAsBytes();
    if (bytes.length < 33) return [];

    final headerLength = bytes[8] | (bytes[9] << 8);
    if (headerLength > bytes.length || headerLength < 33) return [];

    final fields = <CustomFieldDefinition>[];
    for (var offset = 32; offset + 32 <= headerLength; offset += 32) {
      if (bytes[offset] == 0x0D) break;
      var nameEnd = offset;
      while (nameEnd < offset + 11 && bytes[nameEnd] != 0) {
        nameEnd++;
      }
      final name = latin1.decode(bytes.sublist(offset, nameEnd)).trim();
      if (name.isEmpty) continue;

      final fieldType = String.fromCharCode(bytes[offset + 11]).toUpperCase();
      final decimalCount = bytes[offset + 17];
      final type = switch (fieldType) {
        'N' when decimalCount == 0 => FieldType.integer,
        'N' || 'F' => FieldType.decimal,
        'L' => FieldType.bool,
        'D' => FieldType.date,
        'T' || '@' => FieldType.dateTime,
        _ => FieldType.text,
      };
      fields.add(CustomFieldDefinition(key: name, label: name, type: type));
    }
    return fields;
  }

  LatLng _toWgs(double x, double y, String sourceCrs) {
    if (sourceCrs == "EOV") {
      final wgs = _eovService!.eovToWgs(x, y);
      return LatLng(wgs[0], wgs[1]);
    }
    return LatLng(y, x); // WGS84: x=lon, y=lat
  }

  String _detectCrsFromPrj(String prjWkt) {
    final String upper = prjWkt.toUpperCase();
    if (upper.contains("23700") ||
        upper.contains("EOV") ||
        upper.contains("HUNGARIAN_1972") ||
        upper.contains("HD72")) {
      return "EOV";
    }
    if (upper.contains("4326") ||
        upper.contains("WGS_1984") ||
        upper.contains("GCS_WGS_1984")) {
      return "WGS84";
    }
    return "UNKNOWN";
  }

  Future<String?> _promptForCrs(BuildContext context) async {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text("Select Coordinate System"),
        content: const Text(
            "The CRS could not be automatically detected for this Shapefile."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, "WGS84"),
              child: const Text("WGS84 (GPS)")),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, "EOV"),
              child: const Text("EOV (Hungarian)")),
        ],
      ),
    );
  }

  Future<List<GeoFeature>> _parseDxf(File file) async {
    final dxfString = await _readDxfText(file);
    final dxf = DXF.fromString(dxfString);
    List<GeoFeature> features = [];

    for (var entity in dxf.entities) {
      if (entity is AcDbLine) {
        final startWgs = _eovService!.eovToWgs(entity.x, entity.y);
        final endWgs = _eovService!.eovToWgs(entity.x1, entity.y1);
        features.add(GeoFeature(
          name: "DXF Vonal",
          type: FeatureType.line,
          geometry: [
            LatLng(startWgs[0], startWgs[1]),
            LatLng(endWgs[0], endWgs[1])
          ],
          description: "Importálva DXF-ből",
        ));
      } else if (entity is AcDbPoint) {
        final wgs = _eovService!.eovToWgs(entity.x, entity.y);
        features.add(GeoFeature(
          name: "DXF Pont",
          type: FeatureType.point,
          geometry: [LatLng(wgs[0], wgs[1])],
          description: "Importálva DXF-ből",
        ));
      } else if (entity is AcDbPolyline) {
        List<LatLng> points = [];
        for (var v in entity.vertices) {
          if (v.length >= 2) {
            final wgs = _eovService!.eovToWgs(v[0], v[1]);
            points.add(LatLng(wgs[0], wgs[1]));
          }
        }
        if (points.isNotEmpty) {
          features.add(GeoFeature(
            name: "DXF Polyline",
            type: FeatureType.line,
            geometry: points,
            description: "Importálva DXF-ből",
          ));
        }
      }
    }
    return features;
  }

  /// DXF files are commonly written using the drawing's legacy code page
  /// (often Windows-1250/Latin-1), not UTF-8. Read bytes first so a localized
  /// layer name cannot prevent the geometry parser from running.
  Future<String> _readDxfText(File file) async {
    final bytes = await file.readAsBytes();
    String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      text = latin1.decode(bytes);
    }
    return text.startsWith('\uFEFF') ? text.substring(1) : text;
  }

  Future<String> _readTextFile(File file) async =>
      _decodeText(await file.readAsBytes());

  String _decodeText(List<int> bytes) {
    try {
      final text = utf8.decode(bytes);
      return text.startsWith('\uFEFF') ? text.substring(1) : text;
    } on FormatException {
      // Windows-1250 and ISO-8859-1 share most characters. Correct the
      // Hungarian letters that differ after the Latin-1 fallback.
      return latin1
          .decode(bytes)
          .replaceAll('Õ', 'Ő')
          .replaceAll('õ', 'ő')
          .replaceAll('Û', 'Ű')
          .replaceAll('û', 'ű');
    }
  }

  Future<List<GeoFeature>> _parseKml(String content) async {
    final geoXml = await GeoXml.fromKmlString(content);
    return _convertGeoXmlToFeatures(geoXml, "KML");
  }

  Future<List<GeoFeature>> _parseKmz(File file) async {
    final bytes = await file.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    for (final file in archive) {
      if (file.isFile && file.name.toLowerCase().endsWith('.kml')) {
        final kmlString = _decodeText(file.content as List<int>);
        return _parseKml(kmlString);
      }
    }
    return [];
  }

  Future<List<GeoFeature>> _parseGpx(String content) async {
    final geoXml = await GeoXml.fromGpxString(content);
    return _convertGeoXmlToFeatures(geoXml, "GPX");
  }

  List<GeoFeature> _convertGeoXmlToFeatures(GeoXml geoXml, String source) {
    List<GeoFeature> features = [];

    // Útpontok (Waypoints) -> Pontok
    for (var wpt in geoXml.wpts) {
      if (wpt.lat != null && wpt.lon != null) {
        features.add(GeoFeature(
          name: wpt.name ?? "$source Pont",
          type: FeatureType.point,
          geometry: [LatLng(wpt.lat!, wpt.lon!)],
          altitudes: [wpt.ele ?? 0.0],
          description: wpt.desc ?? "Importálva $source fájlból",
        ));
      }
    }

    // Nyomvonalak (Tracks) -> Vonalak
    for (var trk in geoXml.trks) {
      List<LatLng> points = [];
      List<double> alts = [];
      for (var seg in trk.trksegs) {
        for (var pt in seg.trkpts) {
          points.add(LatLng(pt.lat!, pt.lon!));
          alts.add(pt.ele ?? 0.0);
        }
      }
      if (points.isNotEmpty) {
        features.add(GeoFeature(
          name: trk.name ?? "$source Nyomvonal",
          type: FeatureType.line,
          geometry: points,
          altitudes: alts,
          description: trk.desc ?? "Importálva $source fájlból",
        ));
      }
    }

    // Útvonalak (Routes) -> Vonalak
    for (var rte in geoXml.rtes) {
      List<LatLng> points = [];
      List<double> alts = [];
      for (var pt in rte.rtepts) {
        points.add(LatLng(pt.lat!, pt.lon!));
        alts.add(pt.ele ?? 0.0);
      }
      if (points.isNotEmpty) {
        features.add(GeoFeature(
          name: rte.name ?? "$source Útvonal",
          type: FeatureType.line,
          geometry: points,
          altitudes: alts,
          description: rte.desc ?? "Importálva $source fájlból",
        ));
      }
    }

    return features;
  }

  @visibleForTesting
  List<ShpFileSet> groupFilesToSetsForTest(List<File> files) =>
      _groupFilesToSets(files);

  @visibleForTesting
  LatLng toWgsForTest(double x, double y, String sourceCrs) =>
      _toWgs(x, y, sourceCrs);
}
