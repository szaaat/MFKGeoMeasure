import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:archive/archive_io.dart';
import '../models/gnss_fix.dart';

import '../models/geo_feature.dart';
import '../models/field_definition.dart';
import 'project_migration_service.dart';
import 'eov_service.dart';
import 'geoid_service.dart';
import 'shp_export_service.dart';
import 'gnss/rtcm_service.dart';
import 'gnss_info_service.dart';
import 'import_service.dart';
import 'gpkg_service.dart';
import 'data_validation_service.dart';
import '../models/feature_selection.dart';

class ProjectService extends ChangeNotifier {
  static bool enableSaving = true; // For testing purposes
  final List<Project> _projects = [];
  Project? _activeProject;
  ProjectLayer? _activeLayer;
  EovService? _eovService;
  GeoidCorrectionService? _geoidService;
  RtcmService? _rtcmService;
  GnssInfoService? _gnssInfoService;

  FeatureSelection? _selectedFeature;
  FeatureSelection? get selectedFeature => _selectedFeature;

  final Set<String> _selectedFeatureIds = {};
  Set<String> get selectedFeatureIds => _selectedFeatureIds;

  void selectFeature(String? layerId, String? featureId,
      {bool multiSelect = false}) {
    if (layerId == null || featureId == null) {
      if (!multiSelect) {
        _selectedFeature = null;
        _selectedFeatureIds.clear();
      }
    } else {
      _selectedFeature =
          FeatureSelection(layerId: layerId, featureId: featureId);
      if (multiSelect) {
        if (_selectedFeatureIds.contains(featureId)) {
          _selectedFeatureIds.remove(featureId);
        } else {
          _selectedFeatureIds.add(featureId);
        }
      } else {
        _selectedFeatureIds.clear();
        _selectedFeatureIds.add(featureId);
      }
    }
    notifyListeners();
  }

  void clearSelection() {
    _selectedFeature = null;
    _selectedFeatureIds.clear();
    notifyListeners();
  }

  void updateEovService(EovService service) {
    _eovService = service;
  }

  void updateGeoidService(GeoidCorrectionService service) {
    _geoidService = service;
  }

  void updateGnssServices(GnssInfoService info, RtcmService rtcm) {
    _gnssInfoService = info;
    _rtcmService = rtcm;
  }

  // Állapotok
  bool isRecording = false;
  bool isAveraging = false;
  double averagingProgress = 0.0;
  double? currentBatchBestAccuracy;
  double? currentBatchAverageAccuracy;
  FeatureType activeTool = FeatureType.point;

  // Geodéziai beállítások
  double antennaHeight = 0.0; // méter
  double requiredAccuracy = 5.0; // méter

  List<LatLng> currentGeometry = [];
  List<double> currentAltitudes = [];
  List<bool> currentIsEllipsoidal = [];
  List<GnssFix> currentFixes = [];
  List<String> currentPhotos = [];
  final List<_GeometryEditSnapshot> _undoHistory = [];
  final List<_GeometryEditSnapshot> _redoHistory = [];
  bool get canUndoGeometry => _undoHistory.isNotEmpty;
  bool get canRedoGeometry => _redoHistory.isNotEmpty;
  bool get canFinishRecording =>
      currentGeometry.length >=
      switch (activeTool) {
        FeatureType.point => 1,
        FeatureType.line => 2,
        FeatureType.polygon => 3,
      };

  ProjectService() {
    _loadProjectsFromDisk(); // Induláskor betöltjük a mentett adatokat
    _loadGeodeticSettings();
  }

  Future<void> _loadGeodeticSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      antennaHeight =
          prefs.getDouble('geodetic_antenna_height') ?? antennaHeight;
      requiredAccuracy =
          prefs.getDouble('geodetic_required_accuracy') ?? requiredAccuracy;
      notifyListeners();
    } catch (error) {
      debugPrint('Geodetic settings could not be loaded: $error');
    }
  }

  // Getterek
  List<Project> get projects => _projects;
  Project? get activeProject => _activeProject;
  ProjectLayer? get activeLayer => _activeLayer;

  List<GeoFeature> get visibleFeatures {
    if (_activeProject == null) return [];
    return _activeProject!.layers
        .where((l) => l.isVisible)
        .expand((l) => l.features)
        .toList();
  }

  // --- PROJEKT ÉS RÉTEG KEZELÉS ---
  void createProject(String name) {
    final newProj = Project(name: name);
    final baseLayer = ProjectLayer(name: "Alap réteg");
    newProj.layers.add(baseLayer);
    newProj.activeLayerId = baseLayer.id; // Set default active
    _projects.add(newProj);
    _activeProject = newProj;
    _activeLayer = baseLayer;
    _saveProjectsToDisk();
    notifyListeners();
  }

  void selectProject(Project project) {
    _activeProject = project;
    _selectedFeature = null;
    _selectedFeatureIds.clear();
    // Restore active layer if possible, otherwise default to first
    if (project.activeLayerId != null) {
      _activeLayer = project.layers.firstWhere(
          (l) => l.id == project.activeLayerId,
          orElse: () => project.layers.first);
    } else {
      _activeLayer = project.layers.isNotEmpty ? project.layers.first : null;
    }
    notifyListeners();
  }

  void createLayer(String name, {LayerCrs coordinateCrs = LayerCrs.wgs84}) {
    if (_activeProject == null) return;
    final newLayer = ProjectLayer(name: name, coordinateCrs: coordinateCrs);
    _activeProject!.layers.add(newLayer);
    _activeLayer = newLayer;
    _activeProject!.activeLayerId = newLayer.id;
    _saveProjectsToDisk();
    notifyListeners();
  }

  void selectLayer(ProjectLayer layer) {
    _activeLayer = layer;
    if (_activeProject != null) {
      _activeProject!.activeLayerId = layer.id;
      _saveProjectsToDisk();
    }
    notifyListeners();
  }

  void renameLayer(ProjectLayer layer, String newName) {
    layer.name = newName;
    _saveProjectsToDisk();
    notifyListeners();
  }

  void deleteLayer(ProjectLayer layer) {
    if (_activeProject == null) return;
    if (_activeProject!.layers.length <= 1) {
      // Prevent deleting the last layer
      return;
    }
    _activeProject!.layers.removeWhere((l) => l.id == layer.id);
    _selectedFeatureIds.clear();
    _selectedFeature = null;
    if (_activeLayer?.id == layer.id) {
      _activeLayer = _activeProject!.layers.first;
      _activeProject!.activeLayerId = _activeLayer!.id;
    }
    _saveProjectsToDisk();
    notifyListeners();
  }

  void toggleLayerVisibility(ProjectLayer layer) {
    layer.isVisible = !layer.isVisible;
    notifyListeners();
  }

  void addCustomFieldToLayer(ProjectLayer layer, CustomFieldDefinition field) {
    if (!layer.fields.any((f) => f.key == field.key)) {
      layer.fields.add(field);
      _saveProjectsToDisk();
      notifyListeners();
    }
  }

  void updateCustomFieldInLayer(
      ProjectLayer layer, CustomFieldDefinition field) {
    int idx = layer.fields.indexWhere((f) => f.key == field.key);
    if (idx != -1) {
      layer.fields[idx] = field;
      _saveProjectsToDisk();
      notifyListeners();
    }
  }

  void deleteCustomFieldFromLayer(ProjectLayer layer, String key) {
    layer.fields.removeWhere((f) => f.key == key);
    // Töröljük az adatokat is a feature-ökből? Inkább ne, de az exportban már nem lesz benne.
    _saveProjectsToDisk();
    notifyListeners();
  }

  void deleteProject(String id) {
    _projects.removeWhere((p) => p.id == id);
    if (_activeProject?.id == id) {
      _activeProject = _projects.isNotEmpty ? _projects.first : null;
      _activeLayer = _activeProject?.layers.first;
    }
    _saveProjectsToDisk();
    notifyListeners();
  }

  // --- EXPORT FUNKCIÓK ---
  Future<void> exportWithFormat(
    BuildContext context,
    GeoidCorrectionService geoidService,
    Project project, {
    required String format, // "csv", "geojson", "shp", "zip"
    ProjectLayer? layer,
    List<GeoFeature>? features, // New: optional feature subset
    Rect? sharePositionOrigin,
    bool useEov = false,
  }) async {
    try {
      if (format == "zip") {
        await _exportProjectAsZip(geoidService, project,
            sharePositionOrigin: sharePositionOrigin, useEov: useEov);
      } else if (layer != null) {
        // Egyetlen réteg exportálása
        if (format == "csv") {
          await _exportAsCsv(geoidService, project,
              layer: layer,
              features: features,
              sharePositionOrigin: sharePositionOrigin,
              useEov: useEov);
        } else if (format == "geojson") {
          await _exportAsGeoJson(geoidService, project,
              layer: layer,
              features: features,
              sharePositionOrigin: sharePositionOrigin,
              useEov: useEov);
        } else if (format == "shp") {
          await _exportAsShp(geoidService, project,
              layer: layer,
              features: features,
              sharePositionOrigin: sharePositionOrigin,
              useEov: useEov);
        } else if (format == "gml") {
          await _exportAsGml(project,
              layer: layer,
              features: features,
              sharePositionOrigin: sharePositionOrigin,
              useEov: useEov);
        } else if (format == "gpkg") {
          await _exportAsGeoPackage(project,
              layer: layer,
              features: features,
              sharePositionOrigin: sharePositionOrigin,
              useEov: useEov);
        }
      } else {
        // Teljes projekt exportálása
        if (format == "csv") {
          await _exportAsCsv(geoidService, project,
              sharePositionOrigin: sharePositionOrigin, useEov: useEov);
        }
        if (format == "geojson") {
          await _exportAsGeoJson(geoidService, project,
              sharePositionOrigin: sharePositionOrigin, useEov: useEov);
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Hiba: $e"), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _exportAsGml(
    Project project, {
    required ProjectLayer layer,
    List<GeoFeature>? features,
    Rect? sharePositionOrigin,
    required bool useEov,
  }) async {
    if (_eovService == null) return;
    final directory = await getTemporaryDirectory();
    final safeName = '${project.name}_${layer.name}'
        .replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final file = File('${directory.path}/$safeName.gml');
    final srsName = useEov ? 'EPSG:23700' : 'EPSG:4326';
    final output = StringBuffer('<?xml version="1.0" encoding="UTF-8"?>')
      ..write(
          '<wfs:FeatureCollection xmlns:wfs="http://www.opengis.net/wfs" xmlns:gml="http://www.opengis.net/gml/3.2" xmlns:app="https://mfk-geomeasure.local/schema" srsName="$srsName">');
    for (final feature in features ?? layer.features) {
      final geometryName = switch (feature.type) {
        FeatureType.point => 'Point',
        FeatureType.line => 'LineString',
        FeatureType.polygon => 'Polygon',
      };
      final positions = <String>[];
      for (final point in feature.geometry) {
        final coordinate = useEov
            ? _eovService!.wgsToEov(point.latitude, point.longitude)
            : [point.longitude, point.latitude];
        positions.add('${coordinate[0]} ${coordinate[1]}');
      }
      output.write(
          '<gml:featureMember><app:feature><app:name>${_xmlEscape(feature.name)}</app:name>');
      output.write(
          '<app:description>${_xmlEscape(feature.description)}</app:description>');
      for (final field in layer.fields) {
        final value = feature.customData[field.key];
        if (value != null) {
          output.write(
              '<app:${_xmlName(field.key)}>${_xmlEscape(value.toString())}</app:${_xmlName(field.key)}>');
        }
      }
      if (feature.type == FeatureType.polygon) {
        output.write(
            '<app:geometry><gml:Polygon srsName="$srsName"><gml:exterior><gml:LinearRing><gml:posList>${positions.join(' ')}</gml:posList></gml:LinearRing></gml:exterior></gml:Polygon></app:geometry>');
      } else {
        output.write(
            '<app:geometry><gml:$geometryName srsName="$srsName"><gml:posList>${positions.join(' ')}</gml:posList></gml:$geometryName></app:geometry>');
      }
      output.write('</app:feature></wfs:featureMember>');
    }
    output.write('</wfs:FeatureCollection>');
    await file.writeAsString(output.toString());
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path)],
      text: 'GML Export: ${layer.name}',
      sharePositionOrigin: sharePositionOrigin,
    ));
  }

  String _xmlEscape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  String _xmlName(String value) {
    final name = value.replaceAll(RegExp(r'[^a-zA-Z0-9_.-]'), '_');
    return RegExp(r'^[A-Za-z_]').hasMatch(name) ? name : '_$name';
  }

  Future<void> _exportAsGeoPackage(
    Project project, {
    required ProjectLayer layer,
    List<GeoFeature>? features,
    Rect? sharePositionOrigin,
    required bool useEov,
  }) async {
    if (_eovService == null) return;
    final directory = await getTemporaryDirectory();
    final safeName = '${project.name}_${layer.name}'
        .replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final outputPath = '${directory.path}/$safeName.gpkg';
    final outputFile = File(outputPath);
    if (await outputFile.exists()) await outputFile.delete();
    await GeoPackageService().exportLayer(
      layer: layer,
      outputPath: outputPath,
      useEov: useEov,
      eov: _eovService!,
      selectedFeatures: features,
    );
    await SharePlus.instance.share(ShareParams(
      files: [XFile(outputPath)],
      text: 'GeoPackage Export: ${layer.name}',
      sharePositionOrigin: sharePositionOrigin,
    ));
  }

  Future<void> _exportAsCsv(
      GeoidCorrectionService geoidService, Project project,
      {ProjectLayer? layer,
      List<GeoFeature>? features,
      Rect? sharePositionOrigin,
      bool useEov = false}) async {
    if (_eovService == null) return;
    final csvContent = _generateCsvString(geoidService, project,
        layer: layer, features: features, useEov: useEov);
    final String fileName =
        layer != null ? "${project.name}_${layer.name}" : project.name;
    await _saveAndShareFile(csvContent, "csv", project,
        customFileName: fileName, sharePositionOrigin: sharePositionOrigin);
  }

  String _generateCsvString(
      GeoidCorrectionService geoidService, Project project,
      {ProjectLayer? layer, List<GeoFeature>? features, bool useEov = false}) {
    if (_eovService == null) return "";
    final layersToExport = layer != null ? [layer] : project.layers;
    final StringBuffer csv = StringBuffer();

    // Fejlécek meghatározása
    final Set<String> customKeys = {};
    final Map<String, String> keyToLabel = {};
    for (var l in layersToExport) {
      for (var f in l.fields) {
        customKeys.add(f.key);
        keyToLabel[f.key] = f.label;
      }
    }
    final List<String> sortedKeys = customKeys.toList()..sort();

    // Standard geodetic headers
    final baseHeaders = [
      'Reteg',
      'Nev',
      'Leiras',
      'Tipus',
      'Pont_Sorszam',
      'Lat',
      'Lon',
      'EOV_Y',
      'EOV_X',
      'Source_Height',
      'Baltic_Height',
      'Height_Type',
      'Height_Reference',
      'Geoid_Model',
      'Survey_Method',
      'GNSS_Source',
      'RTK_Status',
      'Correction_Age',
      'Sats_Used',
      'HDOP',
      'VDOP',
      'PDOP',
      'Station_ID',
      'Timestamp_Source',
      'Datum',
      'foto_fajl'
    ];

    csv.write(baseHeaders.join(';'));
    for (var key in sortedKeys) {
      csv.write(';${keyToLabel[key] ?? key}');
    }
    csv.writeln();

    for (var l in layersToExport) {
      final featuresToProcess =
          (layer != null && features != null) ? features : l.features;
      for (var f in featuresToProcess) {
        if (f.geometry.isEmpty) continue;
        for (int i = 0; i < f.geometry.length; i++) {
          final p = f.geometry[i];
          double gpsAltitude = (i < f.altitudes.length) ? f.altitudes[i] : 0.0;

          bool isEllipsoidal = false;
          final prop = f.properties['isEllipsoidal'];
          if (prop is List && i < prop.length) {
            isEllipsoidal = prop[i];
          }

          final geoidFrame = isEllipsoidal
              ? (f.properties['referenceFrame'] == 'etrf2000'
                  ? GeoidInputFrame.etrf2000
                  : GeoidInputFrame.assumed)
              : GeoidInputFrame.unknown;
          final eov = _eovService!.wgsToEov(p.latitude, p.longitude);
          final orthoH = geoidService.getOrthoHeight(
            p.latitude,
            p.longitude,
            gpsAltitude,
            isEllipsoidal: isEllipsoidal,
            referenceFrame: geoidFrame,
          );

          final stats = f.calculatedStats;

          final row = [
            l.name, f.name, f.description, f.type.name, i + 1,
            p.latitude.toStringAsFixed(7), p.longitude.toStringAsFixed(7),
            eov[0].toStringAsFixed(2), // EOV_Y (Easting)
            eov[1].toStringAsFixed(2), // EOV_X (Northing)
            gpsAltitude.toString(),
            orthoH?.value.toStringAsFixed(3) ?? '',
            isEllipsoidal ? 'ellipsoidal' : 'orthometric_source',
            f.properties['referenceFrame'] ?? 'unknown',
            isEllipsoidal && orthoH != null ? orthoH.gridName : '',
            stats['Survey Method'] ?? 'IMPORTED',
            stats['GNSS Source'] ?? 'N/A',
            stats['RTK Status'] ?? 'N/A',
            stats['Correction Age'] ?? '',
            stats['Sats Used'] ?? '',
            stats['HDOP'] ?? '',
            stats['VDOP'] ?? '',
            stats['PDOP'] ?? '',
            stats['Station ID'] ?? '',
            stats['Timestamp Source'] ??
                (stats['Survey Method'] == 'IMPORTED' ? 'N/A' : 'device'),
            f.createdAt.toIso8601String(),
            f.photos.map((path) => path.split('/').last).join(', ')
          ];

          csv.write(row.join(';'));
          for (var key in sortedKeys) {
            final val = f.customData[key] ?? '';
            csv.write(';$val');
          }
          csv.writeln();
        }
      }
    }
    return csv.toString();
  }

  Future<void> _exportAsGeoJson(
      GeoidCorrectionService geoidService, Project project,
      {ProjectLayer? layer,
      List<GeoFeature>? features,
      Rect? sharePositionOrigin,
      bool useEov = false}) async {
    final Map<String, dynamic> geoJson = _buildGeoJson(geoidService, project,
        layer: layer, features: features, useEov: useEov);
    final String fileName =
        layer != null ? "${project.name}_${layer.name}" : project.name;
    await _saveAndShareFile(jsonEncode(geoJson), "geojson", project,
        customFileName: fileName, sharePositionOrigin: sharePositionOrigin);
  }

  Map<String, dynamic> _buildGeoJson(
      GeoidCorrectionService geoidService, Project project,
      {ProjectLayer? layer, List<GeoFeature>? features, bool useEov = false}) {
    if (_eovService == null) return {};

    final layersToExport = layer != null ? [layer] : project.layers;
    final allItems = <Map<String, dynamic>>[];

    for (var l in layersToExport) {
      final featuresToProcess =
          (layer != null && features != null) ? features : l.features;
      for (var f in featuresToProcess) {
        allItems.add({"feature": f, "layer": l});
      }
    }

    return {
      "type": "FeatureCollection",
      "features": allItems.map((item) {
        final f = item['feature'] as GeoFeature;
        final l = item['layer'] as ProjectLayer;

        String type = "";
        dynamic coordinates;
        Map<String, dynamic> extraProperties = {};

        List<dynamic> geoJsonCoordinate(double lat, double lon, double gpsH,
            {required bool isEllipsoidal}) {
          final frame = isEllipsoidal
              ? (f.properties['referenceFrame'] == 'etrf2000'
                  ? GeoidInputFrame.etrf2000
                  : GeoidInputFrame.assumed)
              : GeoidInputFrame.unknown;
          double? ellipsoidalH;
          if (isEllipsoidal) {
            ellipsoidalH = gpsH;
          } else {
            final undulation = geoidService.getUndulation(
              lat,
              lon,
              referenceFrame: frame,
            );
            if (undulation != null) {
              ellipsoidalH = gpsH + undulation.value;
            }
          }
          return [
            lon,
            lat,
            if (ellipsoidalH != null && ellipsoidalH.isFinite)
              double.parse(ellipsoidalH.toStringAsFixed(3))
          ];
        }

        if (f.type == FeatureType.point) {
          type = "Point";
          final p = f.geometry.first;
          final gpsH = f.altitudes.isNotEmpty ? f.altitudes[0] : 0.0;

          bool isEllipsoidal = false;
          final prop = f.properties['isEllipsoidal'];
          if (prop is List && prop.isNotEmpty) isEllipsoidal = prop[0];

          final geoidFrame = isEllipsoidal
              ? (f.properties['referenceFrame'] == 'etrf2000'
                  ? GeoidInputFrame.etrf2000
                  : GeoidInputFrame.assumed)
              : GeoidInputFrame.unknown;
          final orthoH = geoidService.getOrthoHeight(
            p.latitude,
            p.longitude,
            gpsH,
            isEllipsoidal: isEllipsoidal,
            referenceFrame: geoidFrame,
          );
          final eov = _eovService!.wgsToEov(p.latitude, p.longitude);
          extraProperties['EOV_Y'] = double.parse(eov[0].toStringAsFixed(2));
          extraProperties['EOV_X'] = double.parse(eov[1].toStringAsFixed(2));
          extraProperties['Source_Height'] = gpsH;
          extraProperties['Height_Reference'] =
              isEllipsoidal ? 'ellipsoidal' : 'orthometric_source';
          extraProperties['Height_Reference_Frame'] =
              f.properties['referenceFrame'] ?? 'unknown';
          extraProperties['Geoid_Model'] =
              isEllipsoidal && orthoH != null ? orthoH.gridName : null;
          extraProperties['EOV_Transform'] =
              f.properties['eovTransform'] ?? 'bmeGridAssumedFrame';
          if (isEllipsoidal) {
            extraProperties['Ellipsoidal_Height'] =
                double.parse(gpsH.toStringAsFixed(3));
          } else {
            final undulation = geoidService.getUndulation(
              p.latitude,
              p.longitude,
              referenceFrame: geoidFrame,
            );
            if (undulation != null) {
              extraProperties['Ellipsoidal_Height'] =
                  double.parse((gpsH + undulation.value).toStringAsFixed(3));
            }
          }
          if (orthoH != null) {
            extraProperties['Baltic_Height'] =
                double.parse(orthoH.value.toStringAsFixed(3));
          }
          coordinates = geoJsonCoordinate(p.latitude, p.longitude, gpsH,
              isEllipsoidal: isEllipsoidal);
        } else if (f.type == FeatureType.line) {
          type = "LineString";
          coordinates = f.geometry.asMap().entries.map((entry) {
            final p = entry.value;
            final i = entry.key;
            final gpsH = (i < f.altitudes.length) ? f.altitudes[i] : 0.0;

            bool isEllipsoidal = false;
            final prop = f.properties['isEllipsoidal'];
            if (prop is List && i < prop.length) isEllipsoidal = prop[i];

            return geoJsonCoordinate(p.latitude, p.longitude, gpsH,
                isEllipsoidal: isEllipsoidal);
          }).toList();
        } else if (f.type == FeatureType.polygon) {
          type = "Polygon";
          var points = f.geometry.asMap().entries.map((entry) {
            final p = entry.value;
            final i = entry.key;
            final gpsH = (i < f.altitudes.length) ? f.altitudes[i] : 0.0;

            bool isEllipsoidal = false;
            final prop = f.properties['isEllipsoidal'];
            if (prop is List && i < prop.length) isEllipsoidal = prop[i];

            return geoJsonCoordinate(p.latitude, p.longitude, gpsH,
                isEllipsoidal: isEllipsoidal);
          }).toList();

          if (points.isNotEmpty &&
              (points.first[0] != points.last[0] ||
                  points.first[1] != points.last[1])) {
            points.add(points.first);
          }
          coordinates = [points];
        }

        return {
          "type": "Feature",
          "properties": {
            "layer": l.name,
            "name": f.name,
            "description": f.description,
            "createdAt": f.createdAt.toIso8601String(),
            "foto_fajl":
                f.photos.map((path) => path.split('/').last).join(', '),
            ...extraProperties,
            ...f.customData,
            ...f.calculatedStats
          },
          "geometry": {"type": type, "coordinates": coordinates}
        };
      }).toList(),
    };
  }

  Future<void> _exportAsShp(
      GeoidCorrectionService geoidService, Project project,
      {ProjectLayer? layer,
      List<GeoFeature>? features,
      Rect? sharePositionOrigin,
      bool useEov = false}) async {
    if (layer == null) return;
    final tempDir = await getTemporaryDirectory();
    final String baseName = "${project.name}_${layer.name}"
        .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');

    final featuresToProcess = features ?? layer.features;
    if (featuresToProcess.isEmpty) return;

    // Csoportosítás geometria típus szerint
    final Map<FeatureType, List<GeoFeature>> grouped = {};
    for (var f in featuresToProcess) {
      grouped.putIfAbsent(f.type, () => []).add(f);
    }

    final encoder = ZipFileEncoder();
    final zipPath = '${tempDir.path}/$baseName.zip';
    encoder.create(zipPath);

    for (var type in grouped.keys) {
      final featuresSet = grouped[type]!;
      String typeSuffix = "";
      if (grouped.length > 1) {
        switch (type) {
          case FeatureType.point:
            typeSuffix = "_points";
            break;
          case FeatureType.line:
            typeSuffix = "_lines";
            break;
          case FeatureType.polygon:
            typeSuffix = "_polygons";
            break;
        }
      }

      final shpFiles = await ShpExportService.generateShapefile(
        tempDir.path,
        "$baseName$typeSuffix",
        layer,
        features: featuresSet,
        eovService: _eovService,
        useEov: _eovService != null &&
            (useEov || layer.coordinateCrs == LayerCrs.eov),
      );
      for (var file in shpFiles) {
        encoder.addFile(file);
      }
    }

    encoder.close();
    await SharePlus.instance.share(ShareParams(
      files: [XFile(zipPath)],
      text: 'SHP Export: ${layer.name}',
      sharePositionOrigin: sharePositionOrigin,
    ));
  }

  Future<void> _exportProjectAsZip(
      GeoidCorrectionService geoidService, Project project,
      {Rect? sharePositionOrigin, bool useEov = false}) async {
    final tempDir = await getTemporaryDirectory();
    final safeName = project.name.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    final zipPath = '${tempDir.path}/${safeName}_full_export.zip';

    final encoder = ZipFileEncoder();
    encoder.create(zipPath);

    for (var layer in project.layers) {
      final layerSafeName = layer.name.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');

      // 1. GeoJSON
      final geoJson = _buildGeoJson(geoidService, project, layer: layer);
      final gjFile = File('${tempDir.path}/$layerSafeName.geojson');
      await gjFile.writeAsString(jsonEncode(geoJson));
      encoder.addFile(gjFile);

      // 2. CSV
      final csvContent =
          _generateCsvString(geoidService, project, layer: layer);
      final csvFile = File('${tempDir.path}/$layerSafeName.csv');
      await csvFile.writeAsString(csvContent);
      encoder.addFile(csvFile);

      // 3. SHP
      final Map<FeatureType, List<GeoFeature>> grouped = {};
      for (var f in layer.features) {
        grouped.putIfAbsent(f.type, () => []).add(f);
      }

      for (var type in grouped.keys) {
        final featuresSet = grouped[type]!;
        String typeSuffix = "";
        if (grouped.length > 1) {
          switch (type) {
            case FeatureType.point:
              typeSuffix = "_points";
              break;
            case FeatureType.line:
              typeSuffix = "_lines";
              break;
            case FeatureType.polygon:
              typeSuffix = "_polygons";
              break;
          }
        }

        final shpFiles = await ShpExportService.generateShapefile(
          tempDir.path,
          "$layerSafeName$typeSuffix",
          layer,
          features: featuresSet,
          eovService: _eovService,
          useEov: _eovService != null &&
              (useEov || layer.coordinateCrs == LayerCrs.eov),
        );
        for (var f in shpFiles) {
          encoder.addFile(f);
        }
      }
    }

    encoder.close();
    await SharePlus.instance.share(ShareParams(
      files: [XFile(zipPath)],
      text: 'Teljes Projekt Export: ${project.name}',
      sharePositionOrigin: sharePositionOrigin,
    ));
  }

  Future<void> _saveAndShareFile(
      String content, String extension, Project project,
      {String? customFileName, Rect? sharePositionOrigin}) async {
    final directory = await getTemporaryDirectory();
    final name = customFileName ?? project.name;
    final safeName = name.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    final dataFile = File('${directory.path}/$safeName.$extension');
    await dataFile.writeAsString(content);

    final Set<String> projectPhotoPaths = {};
    for (var layer in project.layers) {
      for (var f in layer.features) {
        projectPhotoPaths.addAll(f.photos);
      }
    }

    final appDir = await getApplicationDocumentsDirectory();
    final ppkDir = Directory('${appDir.path}/ppk_logs');

    bool hasExtras = projectPhotoPaths.isNotEmpty || await ppkDir.exists();

    if (hasExtras) {
      final encoder = ZipFileEncoder();
      final zipPath = '${directory.path}/${safeName}_package.zip';
      encoder.create(zipPath);
      encoder.addFile(dataFile);

      if (await ppkDir.exists()) {
        await encoder.addDirectory(ppkDir);
      }

      if (projectPhotoPaths.isNotEmpty) {
        for (var path in projectPhotoPaths) {
          final file = File(path);
          if (await file.exists()) {
            encoder.addFile(file);
          }
        }
      }

      encoder.close();

      await SharePlus.instance.share(ShareParams(
        files: [XFile(zipPath)],
        text: 'Export (Adatok + Extrák): ${project.name}',
        sharePositionOrigin: sharePositionOrigin,
      ));
    } else {
      await SharePlus.instance.share(ShareParams(
        files: [XFile(dataFile.path)],
        text: 'Export: ${project.name}',
        sharePositionOrigin: sharePositionOrigin,
      ));
    }
  }

  // --- BEÁLLÍTÁSOK ---
  void setAntennaHeight(double height) {
    antennaHeight = height;
    _persistGeodeticSetting('geodetic_antenna_height', height);
    notifyListeners();
  }

  void setRequiredAccuracy(double accuracy) {
    requiredAccuracy = accuracy;
    _persistGeodeticSetting('geodetic_required_accuracy', accuracy);
    notifyListeners();
  }

  Future<void> _persistGeodeticSetting(String key, double value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(key, value);
    } catch (error) {
      debugPrint('Geodetic setting $key could not be saved: $error');
    }
  }

  // --- RÖGZÍTÉS LOGIKA ---
  void setTool(FeatureType tool) {
    activeTool = tool;
    cancelRecording();
    notifyListeners();
  }

  Future<void> startAveraging(
    Stream<GnssFix> gnssStream, {
    int maxDurationSeconds = 30,
    double requiredAccuracy = 5.0,
  }) async {
    isAveraging = true;
    averagingProgress = 0.0;
    currentBatchBestAccuracy = null;
    currentBatchAverageAccuracy = null;
    notifyListeners();

    List<GnssFix> samples = [];
    List<GnssFix> allReceivedFixes = [];
    final startTime = DateTime.now();

    double filterLimit = max(20.0, requiredAccuracy * 3);

    await for (var fix in gnssStream) {
      allReceivedFixes.add(fix);
      final elapsed = DateTime.now().difference(startTime).inMilliseconds;
      averagingProgress =
          (elapsed / (maxDurationSeconds * 1000)).clamp(0.0, 1.0);

      final acc = fix.horizontalAccuracy <= 0 ? 3.0 : fix.horizontalAccuracy;

      if (acc <= filterLimit) {
        if (samples.length < 3 ||
            currentBatchBestAccuracy == null ||
            acc <= currentBatchBestAccuracy! * 4) {
          samples.add(fix);
        }
      }

      final activeList = samples.isNotEmpty ? samples : allReceivedFixes;
      double best = activeList
          .map((p) => p.horizontalAccuracy <= 0 ? 3.0 : p.horizontalAccuracy)
          .reduce((a, b) => a < b ? a : b);
      double avg = activeList
              .map(
                  (p) => p.horizontalAccuracy <= 0 ? 3.0 : p.horizontalAccuracy)
              .reduce((a, b) => a + b) /
          activeList.length;
      currentBatchBestAccuracy = best;
      currentBatchAverageAccuracy = avg;

      if (elapsed >= maxDurationSeconds * 1000) break;

      notifyListeners();
    }

    final finalSamples = samples.isNotEmpty ? samples : allReceivedFixes;

    if (finalSamples.isNotEmpty) {
      double totalWeight = 0;
      double weightedLat = 0, weightedLon = 0, weightedAlt = 0;
      for (var s in finalSamples) {
        final acc = s.horizontalAccuracy <= 0 ? 3.0 : s.horizontalAccuracy;
        double w = 1.0 / (acc * acc);
        weightedLat += s.latitude * w;
        weightedLon += s.longitude * w;
        weightedAlt += s.ellipsoidalHeight * w;
        totalWeight += w;
      }
      double avgLat = weightedLat / totalWeight;
      double avgLon = weightedLon / totalWeight;
      double avgAlt = weightedAlt / totalWeight;

      double finalAccuracy = 1.0 / sqrt(totalWeight);
      debugPrint(
          "🏁 Végső minta: ${finalSamples.length} db, becsült hiba: ${finalAccuracy.toStringAsFixed(2)}m");

      addPointToGeometry(
        LatLng(avgLat, avgLon),
        avgAlt,
        isEllipsoidal: true,
        fix: finalSamples.first,
      );
    } else {
      debugPrint("⚠️ Nem volt mérés, a pont rögzítése megszakadt.");
    }

    isAveraging = false;
    averagingProgress = 0.0;
    currentBatchBestAccuracy = null;
    currentBatchAverageAccuracy = null;
    notifyListeners();
  }

  void beginManualDrawing() {
    if (_activeLayer == null) return;
    cancelRecording();
    _undoHistory.clear();
    _redoHistory.clear();
    isRecording = true;
    notifyListeners();
  }

  void addManualVertex(LatLng point,
      {bool snap = true, bool orthogonal = false}) {
    if (!isRecording) return;
    var adjusted = point;
    if (activeTool == FeatureType.point) {
      if (snap) adjusted = snapToGeometry(adjusted);
      _captureEditState();
      currentGeometry = [adjusted];
      currentAltitudes = [0];
      currentIsEllipsoidal = [false];
      isRecording = true;
      notifyListeners();
      return;
    }
    if (currentGeometry.isNotEmpty && orthogonal && _eovService != null) {
      final previous = _eovService!.wgsToEov(
          currentGeometry.last.latitude, currentGeometry.last.longitude);
      final candidate = _eovService!.wgsToEov(point.latitude, point.longitude);
      final eastDelta = candidate[1] - previous[1];
      final northDelta = candidate[0] - previous[0];
      if (eastDelta.abs() < northDelta.abs()) {
        candidate[1] = previous[1];
      } else {
        candidate[0] = previous[0];
      }
      final wgs = _eovService!.eovToWgs(candidate[0], candidate[1]);
      adjusted = LatLng(wgs[0], wgs[1]);
    }
    if (snap) adjusted = snapToGeometry(adjusted);
    _captureEditState();
    currentGeometry.add(adjusted);
    currentAltitudes.add(0);
    currentIsEllipsoidal.add(false);
    isRecording = true;
    notifyListeners();
  }

  LatLng snapToGeometry(LatLng point, {double toleranceMeters = 3}) {
    if (_eovService == null) return point;
    final candidate = _eovService!.wgsToEov(point.latitude, point.longitude);
    var nearest = candidate;
    var minimum = toleranceMeters;
    for (final feature in visibleFeatures) {
      final coordinates = feature.geometry
          .map((vertex) =>
              _eovService!.wgsToEov(vertex.latitude, vertex.longitude))
          .toList();
      for (var i = 0; i < coordinates.length; i++) {
        final dx = coordinates[i][0] - candidate[0];
        final dy = coordinates[i][1] - candidate[1];
        final distance = sqrt(dx * dx + dy * dy);
        if (distance <= minimum) {
          minimum = distance;
          nearest = coordinates[i];
        }
        if (i + 1 >= coordinates.length) continue;
        final a = coordinates[i];
        final b = coordinates[i + 1];
        final sx = b[0] - a[0];
        final sy = b[1] - a[1];
        final length = sx * sx + sy * sy;
        if (length == 0) continue;
        final t =
            (((candidate[0] - a[0]) * sx + (candidate[1] - a[1]) * sy) / length)
                .clamp(0.0, 1.0);
        final projected = [a[0] + t * sx, a[1] + t * sy];
        final distanceToSegment = sqrt(pow(projected[0] - candidate[0], 2) +
            pow(projected[1] - candidate[1], 2));
        if (distanceToSegment <= minimum) {
          minimum = distanceToSegment;
          nearest = projected;
        }
      }
    }
    final wgs = _eovService!.eovToWgs(nearest[0], nearest[1]);
    return LatLng(wgs[0], wgs[1]);
  }

  void recalculateFeatureStats(GeoFeature feature) {
    if (feature.geometry.isEmpty) return;

    if (feature.type == FeatureType.point) {
      final double lat = feature.geometry.first.latitude;
      final double lon = feature.geometry.first.longitude;

      if (_eovService != null) {
        final eov = _eovService!.wgsToEov(lat, lon);
        feature.calculatedStats['EOV Y'] =
            double.parse(eov[0].toStringAsFixed(2));
        feature.calculatedStats['EOV X'] =
            double.parse(eov[1].toStringAsFixed(2));
      }

      final double gpsAlt =
          feature.altitudes.isNotEmpty ? feature.altitudes.first : 0.0;
      final bool isEllipsoidal = feature.properties['isEllipsoidal'] is List &&
              (feature.properties['isEllipsoidal'] as List).isNotEmpty
          ? (feature.properties['isEllipsoidal'] as List).first == true
          : false;

      if (isEllipsoidal) {
        feature.calculatedStats['Ellipszoidi magasság'] =
            double.parse(gpsAlt.toStringAsFixed(3));
        if (_geoidService != null) {
          final orthoH = _geoidService!.getOrthoHeight(
            lat,
            lon,
            gpsAlt,
            isEllipsoidal: true,
            referenceFrame: feature.properties['referenceFrame'] == 'etrf2000'
                ? GeoidInputFrame.etrf2000
                : GeoidInputFrame.assumed,
          );
          if (orthoH != null) {
            feature.calculatedStats['Balti magasság'] =
                double.parse(orthoH.value.toStringAsFixed(3));
          }
        }
      } else {
        feature.calculatedStats['Tengerszint feletti magasság (forrás)'] =
            double.parse(gpsAlt.toStringAsFixed(3));
        if (_geoidService != null) {
          final undulation = _geoidService!.getUndulation(
            lat,
            lon,
            referenceFrame: GeoidInputFrame.assumed,
          );
          if (undulation != null) {
            feature.calculatedStats['Ellipszoidi magasság (számított)'] =
                double.parse((gpsAlt + undulation.value).toStringAsFixed(3));
          } else {
            feature.calculatedStats['Ellipszoidi magasság (számított)'] =
                double.parse(gpsAlt.toStringAsFixed(3));
          }
        }
      }
    } else if (feature.type == FeatureType.line) {
      double length = 0.0;
      const distance = Distance();
      for (int i = 0; i < feature.geometry.length - 1; i++) {
        length += distance.as(
            LengthUnit.Meter, feature.geometry[i], feature.geometry[i + 1]);
      }
      feature.calculatedStats['Hossz'] = "${length.toStringAsFixed(1)} m";
    } else if (feature.type == FeatureType.polygon) {
      double area = _calculatePolygonArea(feature.geometry);
      feature.calculatedStats['Terület'] = "${area.toStringAsFixed(1)} m²";
    }
  }

  void updateFeatureVertex(GeoFeature feature, int index, LatLng point,
      {double? altitude}) {
    if (index < 0 || index >= feature.geometry.length) return;
    _captureEditState(feature: feature);
    feature.geometry[index] = point;
    if (altitude != null) {
      if (index < feature.altitudes.length) {
        feature.altitudes[index] = altitude;
      } else {
        feature.altitudes.add(altitude);
      }
    }
    recalculateFeatureStats(feature);
    _saveProjectsToDisk();
    notifyListeners();
  }

  void deleteFeatureVertex(GeoFeature feature, int index) {
    if (index < 0 || index >= feature.geometry.length) return;
    if (feature.type == FeatureType.line && feature.geometry.length <= 2) {
      throw Exception("Vonal nem tartalmazhat 2-nél kevesebb csúcspontot.");
    }
    if (feature.type == FeatureType.polygon && feature.geometry.length <= 3) {
      throw Exception("Sokszög nem tartalmazhat 3-nál kevesebb csúcspontot.");
    }
    _captureEditState(feature: feature);
    feature.geometry.removeAt(index);
    if (index < feature.altitudes.length) {
      feature.altitudes.removeAt(index);
    }
    recalculateFeatureStats(feature);
    _saveProjectsToDisk();
    notifyListeners();
  }

  void insertFeatureVertex(GeoFeature feature, int index, LatLng point,
      {double altitude = 0.0}) {
    if (index < 0 || index > feature.geometry.length) return;
    _captureEditState(feature: feature);
    feature.geometry.insert(index, point);
    if (index <= feature.altitudes.length) {
      feature.altitudes.insert(index, altitude);
    } else {
      feature.altitudes.add(altitude);
    }
    recalculateFeatureStats(feature);
    _saveProjectsToDisk();
    notifyListeners();
  }

  void undoGeometry() {
    if (_undoHistory.isEmpty) return;
    final previous = _undoHistory.removeLast();
    _redoHistory.add(_snapshotEditState(previous.feature));
    _restoreEditState(previous);
  }

  void redoGeometry() {
    if (_redoHistory.isEmpty) return;
    final next = _redoHistory.removeLast();
    _undoHistory.add(_snapshotEditState(next.feature));
    _restoreEditState(next);
  }

  void _captureEditState({GeoFeature? feature}) {
    _undoHistory.add(_snapshotEditState(feature));
    if (_undoHistory.length > 100) _undoHistory.removeAt(0);
    _redoHistory.clear();
  }

  _GeometryEditSnapshot _snapshotEditState(GeoFeature? feature) =>
      _GeometryEditSnapshot(
        feature: feature,
        featureGeometry:
            feature == null ? null : List<LatLng>.from(feature.geometry),
        currentGeometry: List<LatLng>.from(currentGeometry),
        currentAltitudes: List<double>.from(currentAltitudes),
        currentIsEllipsoidal: List<bool>.from(currentIsEllipsoidal),
        currentFixes: List<GnssFix>.from(currentFixes),
        isRecording: isRecording,
      );

  void _restoreEditState(_GeometryEditSnapshot snapshot) {
    if (snapshot.feature != null && snapshot.featureGeometry != null) {
      snapshot.feature!.geometry
        ..clear()
        ..addAll(snapshot.featureGeometry!);
      _saveProjectsToDisk();
    } else {
      currentGeometry = List<LatLng>.from(snapshot.currentGeometry);
      currentAltitudes = List<double>.from(snapshot.currentAltitudes);
      currentIsEllipsoidal = List<bool>.from(snapshot.currentIsEllipsoidal);
      currentFixes = List<GnssFix>.from(snapshot.currentFixes);
      isRecording = snapshot.isRecording;
    }
    notifyListeners();
  }

  void addPointToGeometry(LatLng point, double altitude,
      {bool isEllipsoidal = true, GnssFix? fix}) {
    _captureEditState();
    double correctedAltitude = altitude - antennaHeight;

    if (activeTool == FeatureType.point) {
      currentGeometry = [point];
      currentAltitudes = [correctedAltitude];
      currentIsEllipsoidal = [isEllipsoidal];
      currentFixes = fix != null ? [fix] : [];
    } else {
      if (!isRecording) isRecording = true;
      currentGeometry.add(point);
      currentAltitudes.add(correctedAltitude);
      currentIsEllipsoidal.add(isEllipsoidal);
      if (fix != null) currentFixes.add(fix);
    }
    notifyListeners();
  }

  void createOffsetFeature(GeoFeature source, double distanceMeters,
      {bool buffer = false}) {
    if (_activeLayer == null || _eovService == null || distanceMeters == 0) {
      return;
    }
    final coordinates = source.geometry.map((point) {
      final eov = _eovService!.wgsToEov(point.latitude, point.longitude);
      return Point<double>(eov[0], eov[1]);
    }).toList();
    List<Point<double>> shifted;
    if (source.type == FeatureType.point && buffer) {
      shifted = List.generate(32, (i) {
        final angle = 2 * pi * i / 32;
        return Point(coordinates.first.x + distanceMeters * cos(angle),
            coordinates.first.y + distanceMeters * sin(angle));
      });
      shifted.add(shifted.first);
    } else {
      final path = List<Point<double>>.from(coordinates);
      if (source.type == FeatureType.polygon &&
          path.length > 2 &&
          path.first != path.last) {
        path.add(path.first);
      }
      shifted = [];
      for (var i = 0; i < path.length; i++) {
        final previous = path[max(0, i - 1)];
        final next = path[min(path.length - 1, i + 1)];
        final dx = next.x - previous.x;
        final dy = next.y - previous.y;
        final length = sqrt(dx * dx + dy * dy);
        shifted.add(length == 0
            ? path[i]
            : Point(path[i].x - dy / length * distanceMeters,
                path[i].y + dx / length * distanceMeters));
      }
    }
    final points = shifted.map((point) {
      final wgs = _eovService!.eovToWgs(point.x, point.y);
      return LatLng(wgs[0], wgs[1]);
    }).toList();
    final newFeature = GeoFeature(
      name: '${source.name} ${buffer ? 'buffer' : 'eltolás'}',
      description:
          '${distanceMeters.toStringAsFixed(2)} m ${buffer ? 'buffer' : 'párhuzamos eltolás'}',
      type: source.type == FeatureType.point && buffer
          ? FeatureType.polygon
          : source.type,
      geometry: points,
      customData: Map<String, dynamic>.from(source.customData),
    );
    recalculateFeatureStats(newFeature);
    _activeLayer!.features.add(newFeature);
    _saveProjectsToDisk();
    notifyListeners();
  }

  void addPhotoToCurrent(String path) {
    currentPhotos.add(path);
  }

  void addImportedLayers(List<ImportedLayer> imported) {
    if (_activeProject == null || imported.isEmpty) return;

    for (var imp in imported) {
      final newLayer = ProjectLayer(
        name: imp.name,
        features: imp.features,
        fields: imp.fields,
        sourceType: imp.sourceType,
        crsInfo: imp.crsInfo,
        coordinateCrs: imp.crsInfo?.contains('23700') == true ||
                imp.crsInfo?.toUpperCase().contains('EOV') == true
            ? LayerCrs.eov
            : LayerCrs.wgs84,
      );
      _activeProject!.layers.add(newLayer);
    }

    _saveProjectsToDisk();
    notifyListeners();
  }

  bool finishRecording(String name, String description,
      {String? templateName, Map<String, dynamic> customData = const {}}) {
    if (!canFinishRecording || _activeLayer == null) return false;
    final draft = GeoFeature(
      name: name,
      description: description,
      type: activeTool,
      geometry: List<LatLng>.from(currentGeometry),
      customData: Map<String, dynamic>.from(customData),
    );
    final issues = const DataValidationService().validateFeature(
      feature: draft,
      fields: _activeLayer!.fields,
      crsInfo: _activeLayer!.crsInfo,
    );
    final errors =
        issues.where((issue) => issue.severity == ValidationSeverity.error);
    if (errors.isNotEmpty) {
      debugPrint(
          '[DATA VALIDATION] Save blocked: ${errors.map((issue) => issue.message).join('; ')}');
      return false;
    }
    _saveFeature(
      name,
      description,
      activeTool,
      List.from(currentGeometry),
      List.from(currentAltitudes),
      List.from(currentIsEllipsoidal),
      List.from(currentPhotos),
      templateName,
      customData,
      fixes: List.from(currentFixes),
    );
    currentGeometry.clear();
    currentAltitudes.clear();
    currentIsEllipsoidal.clear();
    currentFixes.clear();
    currentPhotos.clear();
    isRecording = false;
    _undoHistory.clear();
    _redoHistory.clear();
    notifyListeners();
    return true;
  }

  void cancelRecording() {
    currentGeometry.clear();
    currentAltitudes.clear();
    currentIsEllipsoidal.clear();
    currentFixes.clear();
    currentPhotos.clear();
    isRecording = false;
    notifyListeners();
  }

  void _saveFeature(
      String name,
      String description,
      FeatureType type,
      List<LatLng> geometry,
      List<double> altitudes,
      List<bool> isEllipsoidalFlags,
      List<String> photos,
      String? templateName,
      Map<String, dynamic> customData,
      {List<GnssFix>? fixes}) {
    if (_activeLayer == null) return;

    Map<String, dynamic> stats = {};
    if (type == FeatureType.line) {
      double length = 0.0;
      const distance = Distance();
      for (int i = 0; i < geometry.length - 1; i++) {
        length += distance.as(LengthUnit.Meter, geometry[i], geometry[i + 1]);
      }
      stats['Hossz'] = "${length.toStringAsFixed(1)} m";
    } else if (type == FeatureType.polygon) {
      double area = _calculatePolygonArea(geometry);
      stats['Terület'] = "${area.toStringAsFixed(1)} m²";
    } else if (type == FeatureType.point && geometry.isNotEmpty) {
      final double lat = geometry.first.latitude;
      final double lon = geometry.first.longitude;

      if (_eovService != null) {
        final frame = fixes != null &&
                fixes.isNotEmpty &&
                fixes.first.referenceFrame == GnssReferenceFrame.etrf2000
            ? EovInputFrame.etrf2000
            : EovInputFrame.unknown;
        final eov = _eovService!.transformWgsToEov(
          lat,
          lon,
          sourceFrame: frame,
        );
        if (eov.coordinates != null) {
          stats['EOV Y'] = double.parse(eov.coordinates![0].toStringAsFixed(2));
          stats['EOV X'] = double.parse(eov.coordinates![1].toStringAsFixed(2));
          stats['EOV transzformáció'] = eov.status.name;
        } else {
          stats['EOV státusz'] = eov.status.name;
        }
      }

      final double gpsAlt = altitudes.isNotEmpty ? altitudes.first : 0.0;
      final bool isEllipsoidal =
          isEllipsoidalFlags.isNotEmpty ? isEllipsoidalFlags.first : false;
      final geoidFrame = isEllipsoidal &&
              fixes != null &&
              fixes.isNotEmpty &&
              fixes.first.referenceFrame == GnssReferenceFrame.etrf2000
          ? GeoidInputFrame.etrf2000
          : isEllipsoidal
              ? GeoidInputFrame.assumed
              : GeoidInputFrame.unknown;

      if (isEllipsoidal) {
        stats['Ellipszoidi magasság'] = double.parse(gpsAlt.toStringAsFixed(3));
        if (_geoidService != null) {
          final orthoH = _geoidService!.getOrthoHeight(
            lat,
            lon,
            gpsAlt,
            isEllipsoidal: true,
            referenceFrame: geoidFrame,
          );
          if (orthoH != null) {
            stats['Balti magasság'] = double.parse(orthoH.value.toStringAsFixed(3));
            stats['Használt geoid rács'] = orthoH.gridName;
          }
        }
      } else {
        stats['Tengerszint feletti magasság (forrás)'] = double.parse(gpsAlt.toStringAsFixed(3));
        if (_geoidService != null) {
          final undulation = _geoidService!.getUndulation(
            lat,
            lon,
            referenceFrame: GeoidInputFrame.assumed,
          );
          if (undulation != null) {
            stats['Ellipszoidi magasság (számított)'] =
                double.parse((gpsAlt + undulation.value).toStringAsFixed(3));
          }
        }
      }
    }

    final feature = GeoFeature(
      name: name,
      description: description,
      type: type,
      geometry: geometry,
      altitudes: altitudes,
      photos: photos,
      templateName: templateName,
      customData: customData,
      calculatedStats: stats,
      properties: {
        'isEllipsoidal': isEllipsoidalFlags,
        'heightType': isEllipsoidalFlags
            .map((value) => value ? 'ellipsoidal' : 'orthometric_source')
            .toList(),
        'referenceFrame': fixes != null && fixes.isNotEmpty
            ? fixes.first.referenceFrame.name
            : GnssReferenceFrame.unknown.name,
        'heightReferenceStatus': isEllipsoidalFlags.isNotEmpty &&
                isEllipsoidalFlags.first
            ? (fixes != null &&
                    fixes.isNotEmpty &&
                    fixes.first.referenceFrame == GnssReferenceFrame.etrf2000
                ? 'verified'
                : 'assumed')
            : 'source',
        'geoidModel': isEllipsoidalFlags.isNotEmpty && isEllipsoidalFlags.first
            ? 'hu_bme_geoid2014'
            : null,
        'eovTransform': stats['EOV transzformáció'] ?? 'bmeGridAssumedFrame',
        'gnssFixes': fixes?.map((f) => f.toMap()).toList(),
      },
    );

    if (fixes != null && fixes.isNotEmpty) {
      final last = fixes.last;
      String method = "EXTERNAL_GNSS";
      if (last.rtkStatus == RtkStatus.float ||
          last.rtkStatus == RtkStatus.fixed) {
        method = "RTK";
      } else if (last.source == GnssSource.internal) {
        method = "PHONE";
      }
      feature.calculatedStats['Survey Method'] = method;
      feature.calculatedStats['GNSS Source'] = last.source.name.toUpperCase();
      feature.calculatedStats['Geometry Type'] = type.name.toUpperCase();
      if (last.source == GnssSource.internal) {
        feature.calculatedStats['RTK Status'] = "N/A";
      } else {
        feature.calculatedStats['RTK Status'] =
            last.rtkStatus.name.toUpperCase();
      }
      feature.calculatedStats['NTRIP Active'] =
          (last.correctionAge != null || last.stationId != null) ? "YES" : "NO";
      feature.calculatedStats['Fix Type'] = last.fixType.name.toUpperCase();
      if (last.correctionAge != null) {
        feature.calculatedStats['Correction Age'] = last.correctionAge;
      }
      if (last.receiverName != null && last.receiverName != "Internal GPS") {
        feature.calculatedStats['Receiver'] = last.receiverName;
      }
      if (last.stationId != null) {
        feature.calculatedStats['Station ID'] = last.stationId;
      }
      feature.calculatedStats['Sats Used'] = last.satellitesUsed;
      if (last.pdop != null) feature.calculatedStats['PDOP'] = last.pdop;
      if (last.hdop != null) feature.calculatedStats['HDOP'] = last.hdop;
      if (last.vdop != null) feature.calculatedStats['VDOP'] = last.vdop;
      feature.calculatedStats['Timestamp Source'] = last.timestampSource.name;
    }

    _activeLayer!.features.add(feature);
    _saveProjectsToDisk();

    if (_gnssInfoService?.ntripSettings.autoStopAfterMeasurement ?? false) {
      _rtcmService?.stopNtrip();
    }

    notifyListeners();
  }

  void deleteFeature(String id) {
    if (_activeProject != null) {
      for (var layer in _activeProject!.layers) {
        layer.features.removeWhere((f) => f.id == id);
      }
      _selectedFeatureIds.remove(id);
      if (_selectedFeature?.featureId == id) {
        _selectedFeature = null;
      }
      _saveProjectsToDisk();
      notifyListeners();
    }
  }

  Future<String?> updateFeatureAttribute(
      String layerId, String featureId, String key, dynamic rawValue) async {
    if (_activeProject == null) return "Nincs aktív projekt";

    try {
      final layer = _activeProject!.layers.firstWhere((l) => l.id == layerId);
      final feature = layer.features.firstWhere((f) => f.id == featureId);
      final fieldDef = layer.fields.firstWhere((f) => f.key == key);

      final validatedValue = _castAndValidate(rawValue, fieldDef);
      feature.customData[key] = validatedValue;

      await _saveProjectsToDisk();
      notifyListeners();
      return null;
    } catch (e) {
      return e.toString().replaceFirst("Exception: ", "");
    }
  }

  dynamic _castAndValidate(dynamic value, CustomFieldDefinition def) {
    if (value == null) return null;
    final String str = value.toString().trim();
    if (str.isEmpty && def.type != FieldType.text) return null;

    switch (def.type) {
      case FieldType.integer:
        final val = int.tryParse(str);
        if (val == null) throw Exception("Érvénytelen egész szám: $str");
        return val;
      case FieldType.decimal:
        final val = double.tryParse(str.replaceAll(',', '.'));
        if (val == null) throw Exception("Érvénytelen tizedes szám: $str");
        return val;
      case FieldType.bool:
        if (value is bool) return value;
        return str.toLowerCase() == 'true' || str == '1';
      case FieldType.date:
      case FieldType.dateTime:
        if (value is DateTime) return value;
        final val = DateTime.tryParse(str);
        if (val == null) throw Exception("Érvénytelen dátum formátum: $str");
        return val;
      case FieldType.choice:
        if (def.choices != null && !def.choices!.contains(str)) {
          throw Exception(
              "A(z) '$str' érték nem szerepel a lehetőségek között.");
        }
        return str;
      case FieldType.text:
        return str;
    }
  }

  void updateFeatureCustomData(String featureId, Map<String, dynamic> data,
      {String? name, String? description}) {
    bool found = false;
    for (var project in _projects) {
      for (var layer in project.layers) {
        for (var feature in layer.features) {
          if (feature.id == featureId) {
            if (name != null) feature.name = name;
            if (description != null) feature.description = description;
            feature.customData.addAll(data);
            recalculateFeatureStats(feature);
            found = true;
            break;
          }
        }
        if (found) break;
      }
      if (found) break;
    }
    if (found) {
      _saveProjectsToDisk();
      notifyListeners();
    }
  }

  double calculatePolygonArea(List<LatLng> points) {
    if (points.length < 3) return 0.0;
    double area = 0.0;
    const double R = 6378137;
    for (int i = 0; i < points.length; i++) {
      var p1 = points[i];
      var p2 = points[(i + 1) % points.length];
      double p1LonRad = p1.longitude * pi / 180;
      double p2LonRad = p2.longitude * pi / 180;
      double p1LatRad = p1.latitude * pi / 180;
      double p2LatRad = p2.latitude * pi / 180;
      area += (p2LonRad - p1LonRad) * (2 + sin(p1LatRad) + sin(p2LatRad));
    }
    area = area * R * R / 2.0;
    return area.abs();
  }

  double _calculatePolygonArea(List<LatLng> points) =>
      calculatePolygonArea(points);

  Object? lastSaveError;
  Future<void>? _saveQueue;

  Future<void> _saveProjectsToDisk() async {
    if (!enableSaving) return;
    final previousSave = _saveQueue;
    final completer = Completer<void>();
    _saveQueue = completer.future;

    if (previousSave != null) {
      try {
        await previousSave;
      } catch (_) {}
    }

    try {
      await _performSaveToDisk();
    } finally {
      completer.complete();
    }
  }

  Future<void> flushPendingSaves() async {
    final currentQueue = _saveQueue;
    if (currentQueue != null) {
      try {
        await currentQueue;
      } catch (_) {}
    }
    if (lastSaveError != null) {
      final error = lastSaveError;
      throw StateError("Pending project save failed: $error");
    }
  }

  Future<void> _performSaveToDisk() async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/saved_projects.json');
    final backupFile = File('${directory.path}/saved_projects.json.bak');
    final tempFile = File(
        '${directory.path}/saved_projects_${DateTime.now().microsecondsSinceEpoch}.tmp');

    try {
      lastSaveError = null;
      if (await file.exists()) {
        try {
          if (await backupFile.exists()) await backupFile.delete();
          await file.copy(backupFile.path);
        } catch (_) {}
      }
      final jsonString = jsonEncode(_projects.map((p) => p.toJson()).toList());
      await tempFile.writeAsString(jsonString);
      try {
        if (await file.exists()) await file.delete();
        await tempFile.rename(file.path);
      } catch (_) {
        await tempFile.copy(file.path);
        if (await tempFile.exists()) await tempFile.delete();
      }
      if (await backupFile.exists()) await backupFile.delete();
      debugPrint("Projektek sikeresen mentve");
    } catch (e) {
      lastSaveError = e;
      debugPrint("HIBA a mentés során: $e");
      try {
        if (await backupFile.exists() && !(await file.exists())) {
          await backupFile.copy(file.path);
        }
      } catch (_) {}
      rethrow;
    }
  }

  Future<void> _loadProjectsFromDisk() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/saved_projects.json');
      final backupFile = File('${directory.path}/saved_projects.json.bak');

      if (!await file.exists() && await backupFile.exists()) {
        try {
          await backupFile.copy(file.path);
        } catch (_) {}
      }

      if (await file.exists()) {
        final jsonString = await file.readAsString();
        if (jsonString.trim().isNotEmpty) {
          final List<dynamic> decoded = jsonDecode(jsonString);
          final List<Project> loadedProjects = [];

          for (var projectJson in decoded) {
            final Map<String, dynamic> projectMap =
                Map<String, dynamic>.from(projectJson);
            final migratedJson = ProjectMigrationService.migrate(projectMap);
            loadedProjects.add(Project.fromJson(migratedJson));
          }

          _projects.clear();
          _projects.addAll(loadedProjects);

          if (_projects.isNotEmpty) {
            _activeProject = _projects.first;
            if (_activeProject!.activeLayerId != null) {
              _activeLayer = _activeProject!.layers.firstWhere(
                  (l) => l.id == _activeProject!.activeLayerId,
                  orElse: () => _activeProject!.layers.first);
            } else {
              _activeLayer = _activeProject!.layers.isNotEmpty
                  ? _activeProject!.layers.first
                  : null;
            }
          }
          notifyListeners();
          return;
        }
      }

      if (_projects.isEmpty) {
        createProject("Gyakorló Mérés");
      }
    } catch (e) {
      debugPrint("Hiba a projektek betöltésekor: $e");
      if (_projects.isEmpty) createProject("Gyakorló Mérés");
    }
  }

  @visibleForTesting
  Future<void> loadProjectsFromDiskForTest() => _loadProjectsFromDisk();

  @visibleForTesting
  Map<String, dynamic> buildGeoJsonForTest(
          GeoidCorrectionService geoidService, Project project,
          {ProjectLayer? layer,
          List<GeoFeature>? features,
          bool useEov = false}) =>
      _buildGeoJson(geoidService, project,
          layer: layer, features: features, useEov: useEov);

  @visibleForTesting
  String generateCsvForTest(
          GeoidCorrectionService geoidService, Project project,
          {ProjectLayer? layer,
          List<GeoFeature>? features,
          bool useEov = false}) =>
      _generateCsvString(geoidService, project,
          layer: layer, features: features, useEov: useEov);
}

class _GeometryEditSnapshot {
  final GeoFeature? feature;
  final List<LatLng>? featureGeometry;
  final List<LatLng> currentGeometry;
  final List<double> currentAltitudes;
  final List<bool> currentIsEllipsoidal;
  final List<GnssFix> currentFixes;
  final bool isRecording;

  const _GeometryEditSnapshot({
    required this.feature,
    required this.featureGeometry,
    required this.currentGeometry,
    required this.currentAltitudes,
    required this.currentIsEllipsoidal,
    required this.currentFixes,
    required this.isRecording,
  });
}
