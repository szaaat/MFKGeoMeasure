import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
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

class ProjectService extends ChangeNotifier {
  final List<Project> _projects = [];
  Project? _activeProject;
  ProjectLayer? _activeLayer;
  EovService? _eovService;
  GeoidCorrectionService? _geoidService;
  RtcmService? _rtcmService;
  GnssInfoService? _gnssInfoService;

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

  ProjectService() {
    _loadProjectsFromDisk(); // Induláskor betöltjük a mentett adatokat
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
    _projects.add(newProj);
    _activeProject = newProj;
    _activeLayer = baseLayer;
    _saveProjectsToDisk();
    notifyListeners();
  }

  void selectProject(Project project) {
    _activeProject = project;
    _activeLayer = project.layers.isNotEmpty ? project.layers.first : null;
    notifyListeners();
  }

  void createLayer(String name) {
    if (_activeProject == null) return;
    final newLayer = ProjectLayer(name: name);
    _activeProject!.layers.add(newLayer);
    _activeLayer = newLayer;
    _saveProjectsToDisk();
    notifyListeners();
  }

  void selectLayer(ProjectLayer layer) {
    _activeLayer = layer;
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

  void updateCustomFieldInLayer(ProjectLayer layer, CustomFieldDefinition field) {
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
    Rect? sharePositionOrigin,
  }) async {
    try {
      if (format == "zip") {
        await _exportProjectAsZip(geoidService, project, sharePositionOrigin: sharePositionOrigin);
      } else if (layer != null) {
        // Egyetlen réteg exportálása
        if (format == "csv") {
          await _exportAsCsv(geoidService, project, layer: layer, sharePositionOrigin: sharePositionOrigin);
        } else if (format == "geojson") {
          await _exportAsGeoJson(geoidService, project, layer: layer, sharePositionOrigin: sharePositionOrigin);
        } else if (format == "shp") {
          await _exportAsShp(geoidService, project, layer: layer, sharePositionOrigin: sharePositionOrigin);
        }
      } else {
        // Teljes projekt exportálása (régi stílus vagy alapértelmezett)
        if (format == "csv") await _exportAsCsv(geoidService, project, sharePositionOrigin: sharePositionOrigin);
        if (format == "geojson") await _exportAsGeoJson(geoidService, project, sharePositionOrigin: sharePositionOrigin);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Hiba: $e"), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _exportAsCsv(GeoidCorrectionService geoidService, Project project, {ProjectLayer? layer, Rect? sharePositionOrigin}) async {
    if (_eovService == null) return;
    final csvContent = _generateCsvString(geoidService, project, layer: layer);
    final String fileName = layer != null ? "${project.name}_${layer.name}" : project.name;
    await _saveAndShareFile(csvContent, "csv", project, customFileName: fileName, sharePositionOrigin: sharePositionOrigin);
  }

  String _generateCsvString(GeoidCorrectionService geoidService, Project project, {ProjectLayer? layer}) {
    if (_eovService == null) return "";
    final layersToExport = layer != null ? [layer] : project.layers;
    final StringBuffer csv = StringBuffer();
    
    // Fejlécek meghatározása a rétegek alapján
    final Set<String> customKeys = {};
    final Map<String, String> keyToLabel = {};
    for (var l in layersToExport) {
      for (var f in l.fields) {
        customKeys.add(f.key);
        keyToLabel[f.key] = f.label;
      }
    }
    final List<String> sortedKeys = customKeys.toList()..sort();

    csv.write('Reteg;Nev;Leiras;Tipus;Pont_Sorszam;Lat;Lon;EOV_Y;EOV_X;Ellipsoidal_Height;Baltic_Height;Datum;foto_fajl');
    for (var key in sortedKeys) {
      csv.write(';${keyToLabel[key] ?? key}');
    }
    csv.writeln();

    for (var l in layersToExport) {
      for (var f in l.features) {
        if (f.geometry.isEmpty) continue;
        for (int i = 0; i < f.geometry.length; i++) {
          final p = f.geometry[i];
          double gpsAltitude = (i < f.altitudes.length) ? f.altitudes[i] : 0.0;
          
          bool isEllipsoidal = Platform.isAndroid;
          final prop = f.properties['isEllipsoidal'];
          if (prop is List && i < prop.length) {
            isEllipsoidal = prop[i];
          }

          final eov = _eovService!.wgsToEov(p.latitude, p.longitude);
          double? orthoH = geoidService.getOrthoHeight(p.latitude, p.longitude, gpsAltitude, isEllipsoidal: isEllipsoidal);

          String customVals = "";
          for (var key in sortedKeys) {
            final val = f.customData[key] ?? f.calculatedStats[key] ?? '';
            customVals += ';$val';
          }

          csv.writeln('${l.name};${f.name};${f.description};${f.type.name};${i + 1};'
              '${p.latitude.toStringAsFixed(7)};${p.longitude.toStringAsFixed(7)};'
              '${eov[0].toStringAsFixed(2)};${eov[1].toStringAsFixed(2)};'
              '${gpsAltitude.toStringAsFixed(3)};${(orthoH ?? gpsAltitude).toStringAsFixed(3)};'
              '${f.createdAt.toIso8601String()};'
              '${f.photos.map((path) => path.split('/').last).join(', ')}$customVals');
        }
      }
    }
    return csv.toString();
  }

  Future<void> _exportAsGeoJson(GeoidCorrectionService geoidService, Project project, {ProjectLayer? layer, Rect? sharePositionOrigin}) async {
    final Map<String, dynamic> geoJson = _buildGeoJson(geoidService, project, layer: layer);
    final String fileName = layer != null ? "${project.name}_${layer.name}" : project.name;
    await _saveAndShareFile(jsonEncode(geoJson), "geojson", project, customFileName: fileName, sharePositionOrigin: sharePositionOrigin);
  }

  Map<String, dynamic> _buildGeoJson(GeoidCorrectionService geoidService, Project project, {ProjectLayer? layer}) {
    if (_eovService == null) return {};

    final layersToExport = layer != null ? [layer] : project.layers;
    final allFeatures = layersToExport.expand((l) => l.features.map((f) => {"feature": f, "layer": l})).toList();

    return {
      "type": "FeatureCollection",
      "features": allFeatures.map((item) {
        final f = item['feature'] as GeoFeature;
        final l = item['layer'] as ProjectLayer;

        String type = "";
        dynamic coordinates;
        Map<String, dynamic> extraProperties = {};

        double getOrthoH(double lat, double lon, double gpsH, {bool isEllipsoidal = true}) {
          double? h = geoidService.getOrthoHeight(lat, lon, gpsH, isEllipsoidal: isEllipsoidal);
          return h ?? gpsH;
        }

        if (f.type == FeatureType.point) {
          type = "Point";
          final p = f.geometry.first;
          final gpsH = f.altitudes.isNotEmpty ? f.altitudes[0] : 0.0;
          
          bool isEllipsoidal = Platform.isAndroid;
          final prop = f.properties['isEllipsoidal'];
          if (prop is List && prop.isNotEmpty) isEllipsoidal = prop[0];

          final orthoH = getOrthoH(p.latitude, p.longitude, gpsH, isEllipsoidal: isEllipsoidal);
          final eov = _eovService!.wgsToEov(p.latitude, p.longitude);
          extraProperties['EOV_Y'] = double.parse(eov[0].toStringAsFixed(2));
          extraProperties['EOV_X'] = double.parse(eov[1].toStringAsFixed(2));
          extraProperties['Ellipsoidal_Height'] = isEllipsoidal 
              ? double.parse(gpsH.toStringAsFixed(3))
              : double.parse((gpsH + (geoidService.getUndulation(p.latitude, p.longitude) ?? 0.0)).toStringAsFixed(3));
          extraProperties['Baltic_Height'] = double.parse(orthoH.toStringAsFixed(3));
          coordinates = [p.longitude, p.latitude, double.parse(orthoH.toStringAsFixed(3))];

        } else if (f.type == FeatureType.line) {
          type = "LineString";
          coordinates = f.geometry.asMap().entries.map((entry) {
            final p = entry.value;
            final i = entry.key;
            final gpsH = (i < f.altitudes.length) ? f.altitudes[i] : 0.0;
            
            bool isEllipsoidal = Platform.isAndroid;
            final prop = f.properties['isEllipsoidal'];
            if (prop is List && i < prop.length) isEllipsoidal = prop[i];

            return [p.longitude, p.latitude, double.parse(getOrthoH(p.latitude, p.longitude, gpsH, isEllipsoidal: isEllipsoidal).toStringAsFixed(3))];
          }).toList();

        } else if (f.type == FeatureType.polygon) {
          type = "Polygon";
          var points = f.geometry.asMap().entries.map((entry) {
            final p = entry.value;
            final i = entry.key;
            final gpsH = (i < f.altitudes.length) ? f.altitudes[i] : 0.0;
            
            bool isEllipsoidal = Platform.isAndroid;
            final prop = f.properties['isEllipsoidal'];
            if (prop is List && i < prop.length) isEllipsoidal = prop[i];

            return [p.longitude, p.latitude, double.parse(getOrthoH(p.latitude, p.longitude, gpsH, isEllipsoidal: isEllipsoidal).toStringAsFixed(3))];
          }).toList();
          
          if (points.isNotEmpty && (points.first[0] != points.last[0] || points.first[1] != points.last[1])) {
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
            "foto_fajl": f.photos.map((path) => path.split('/').last).join(', '),
            ...extraProperties,
            ...f.customData,
            ...f.calculatedStats
          },
          "geometry": {"type": type, "coordinates": coordinates}
        };
      }).toList(),
    };
  }

  Future<void> _exportAsShp(GeoidCorrectionService geoidService, Project project, {ProjectLayer? layer, Rect? sharePositionOrigin}) async {
    if (layer == null) return;
    final tempDir = await getTemporaryDirectory();
    final String baseName = "${project.name}_${layer.name}".replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    
    // Csoportosítás geometria típus szerint
    final Map<FeatureType, List<GeoFeature>> grouped = {};
    for (var f in layer.features) {
      grouped.putIfAbsent(f.type, () => []).add(f);
    }

    final encoder = ZipFileEncoder();
    final zipPath = '${tempDir.path}/$baseName.zip';
    encoder.create(zipPath);

    for (var type in grouped.keys) {
      final features = grouped[type]!;
      String typeSuffix = "";
      if (grouped.length > 1) {
        switch (type) {
          case FeatureType.point: typeSuffix = "_points"; break;
          case FeatureType.line: typeSuffix = "_lines"; break;
          case FeatureType.polygon: typeSuffix = "_polygons"; break;
        }
      }
      
      final shpFiles = await ShpExportService.generateShapefile(
        tempDir.path, 
        "$baseName$typeSuffix", 
        layer, 
        features: features,
        eovService: _eovService
      );
      for (var file in shpFiles) encoder.addFile(file);
    }
    
    encoder.close();
    await Share.shareXFiles([XFile(zipPath)], text: 'SHP Export: ${layer.name}', sharePositionOrigin: sharePositionOrigin);
  }

  Future<void> _exportProjectAsZip(GeoidCorrectionService geoidService, Project project, {Rect? sharePositionOrigin}) async {
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
      final csvContent = _generateCsvString(geoidService, project, layer: layer);
      final csvFile = File('${tempDir.path}/$layerSafeName.csv');
      await csvFile.writeAsString(csvContent);
      encoder.addFile(csvFile);

      // 3. SHP (Típusonkénti bontással)
      final Map<FeatureType, List<GeoFeature>> grouped = {};
      for (var f in layer.features) {
        grouped.putIfAbsent(f.type, () => []).add(f);
      }

      for (var type in grouped.keys) {
        final features = grouped[type]!;
        String typeSuffix = "";
        if (grouped.length > 1) {
          switch (type) {
            case FeatureType.point: typeSuffix = "_points"; break;
            case FeatureType.line: typeSuffix = "_lines"; break;
            case FeatureType.polygon: typeSuffix = "_polygons"; break;
          }
        }

        final shpFiles = await ShpExportService.generateShapefile(
          tempDir.path, 
          "$layerSafeName$typeSuffix", 
          layer, 
          features: features,
          eovService: _eovService
        );
        for (var f in shpFiles) encoder.addFile(f);
      }
    }

    encoder.close();
    await Share.shareXFiles([XFile(zipPath)], text: 'Teljes Projekt Export: ${project.name}', sharePositionOrigin: sharePositionOrigin);
  }

  Future<void> _saveAndShareFile(String content, String extension, Project project, {String? customFileName, Rect? sharePositionOrigin}) async {
    final directory = await getTemporaryDirectory();
    final name = customFileName ?? project.name;
    final safeName = name.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    final dataFile = File('${directory.path}/$safeName.$extension');
    await dataFile.writeAsString(content);

    // Gyűjtsük össze csak az ebben a projektben szereplő fotókat
    final Set<String> projectPhotoPaths = {};
    for (var layer in project.layers) {
      for (var f in layer.features) {
        projectPhotoPaths.addAll(f.photos);
      }
    }

    final appDir = await getApplicationDocumentsDirectory();
    final ppkDir = Directory('${appDir.path}/ppk_logs');
    
    // Csak akkor készítünk ZIP-et, ha van mit belecsomagolni (fotók vagy PPK logok)
    // Megjegyzés: a PPK logok jelenleg session alapúak, minden logot beleveszünk, 
    // de a fotókat már szűrjük.
    bool hasExtras = projectPhotoPaths.isNotEmpty || await ppkDir.exists();
    
    if (hasExtras) {
      final encoder = ZipFileEncoder();
      final zipPath = '${directory.path}/${safeName}_package.zip';
      encoder.create(zipPath);
      encoder.addFile(dataFile);
      
      // PPK logok hozzáadása (ha vannak)
      if (await ppkDir.exists()) {
        await encoder.addDirectory(ppkDir);
      }
      
      // Csak a projektben hivatkozott fotók hozzáadása
      if (projectPhotoPaths.isNotEmpty) {
        for (var path in projectPhotoPaths) {
          final file = File(path);
          if (await file.exists()) {
            // A fájlt közvetlenül a ZIP gyökerébe tesszük, 
            // hogy a CSV/GeoJSON mellé kerüljön kicsomagoláskor.
            encoder.addFile(file);
          }
        }
      }
      
      encoder.close();
      
      await Share.shareXFiles(
        [XFile(zipPath)], 
        text: 'Export (Adatok + Extrák): ${project.name}',
        sharePositionOrigin: sharePositionOrigin,
      );
    } else {
      // Ha nincs fotó/log, csak a CSV/GeoJSON fájlt küldjük
      await Share.shareXFiles(
        [XFile(dataFile.path)], 
        text: 'Export: ${project.name}',
        sharePositionOrigin: sharePositionOrigin,
      );
    }
  }

  // --- BEÁLLÍTÁSOK ---
  void setAntennaHeight(double height) {
    antennaHeight = height;
    notifyListeners();
  }

  void setRequiredAccuracy(double accuracy) {
    requiredAccuracy = accuracy;
    notifyListeners();
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
    final startTime = DateTime.now();

    // Szűrési küszöb: az elvárt pontosság 2-szerese, de max 10m
    double filterLimit = min(10.0, requiredAccuracy * 2);

    await for (var fix in gnssStream) {
      final elapsed = DateTime.now().difference(startTime).inMilliseconds;
      averagingProgress = (elapsed / (maxDurationSeconds * 1000)).clamp(0.0, 1.0);

      // 1. Alap szűrés
      if (fix.horizontalAccuracy > filterLimit) continue;

      // 2. Outlier szűrés (ha már van 3 mintánk)
      if (samples.length >= 3 && currentBatchBestAccuracy != null) {
        if (fix.horizontalAccuracy > currentBatchBestAccuracy! * 3) continue;
      }

      samples.add(fix);

      // Frissítsük a statisztikákat
      double best = samples.map((p) => p.horizontalAccuracy).reduce((a, b) => a < b ? a : b);
      double avg = samples.map((p) => p.horizontalAccuracy).reduce((a, b) => a + b) / samples.length;
      currentBatchBestAccuracy = best;
      currentBatchAverageAccuracy = avg;

      // 3. Számoljuk a súlyozott átlagot és a becsült pontosságot
      double totalWeight = 0;
      for (var s in samples) {
        totalWeight += 1.0 / (s.horizontalAccuracy * s.horizontalAccuracy);
      }
      double estimatedAccuracy = 1.0 / sqrt(totalWeight);
      
      // 4. KORAI LEÁLLÁS:
      // - legalább 10 minta legyen
      // - a becsült pontosság jobb vagy egyenlő a kívánt pontossággal
      // - és eltelt legalább 8 másodperc (stabilizálódás)
      if (samples.length >= 10 &&
          estimatedAccuracy <= requiredAccuracy &&
          elapsed >= 8000) {
        debugPrint("✅ Korai leállás: becsült hiba ${estimatedAccuracy.toStringAsFixed(2)}m <= $requiredAccuracy m");
        break;
      }

      // Ha eltelt a max idő, kilépünk
      if (elapsed >= maxDurationSeconds * 1000) break;

      notifyListeners();
    }

    // --- Eredmény felhasználása ---
    if (samples.isNotEmpty) {
      // Számoljuk újra a végső súlyozott átlagot
      double totalWeight = 0;
      double weightedLat = 0, weightedLon = 0, weightedAlt = 0;
      for (var s in samples) {
        double w = 1.0 / (s.horizontalAccuracy * s.horizontalAccuracy);
        weightedLat += s.latitude * w;
        weightedLon += s.longitude * w;
        weightedAlt += s.ellipsoidalHeight * w;
        totalWeight += w;
      }
      double avgLat = weightedLat / totalWeight;
      double avgLon = weightedLon / totalWeight;
      double avgAlt = weightedAlt / totalWeight;

      double finalAccuracy = 1.0 / sqrt(totalWeight);
      debugPrint("🏁 Végső minta: ${samples.length} db, becsült hiba: ${finalAccuracy.toStringAsFixed(2)}m");

      addPointToGeometry(
        LatLng(avgLat, avgLon), 
        avgAlt, 
        isEllipsoidal: samples.first.isEllipsoidal,
        fix: samples.first,
      );
    } else {
      debugPrint("⚠️ Nem volt elég jó mérés, a pont rögzítése megszakadt.");
    }

    isAveraging = false;
    averagingProgress = 0.0;
    currentBatchBestAccuracy = null;
    currentBatchAverageAccuracy = null;
    notifyListeners();
  }

  void addPointToGeometry(LatLng point, double altitude, {bool isEllipsoidal = true, GnssFix? fix}) {
    // Korrekció az antenna magasságával (a földfelszíni magasságot mentjük)
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

  void addPhotoToCurrent(String path) {
    currentPhotos.add(path);
    // Sandbox fix: Nem hívunk notifyListeners()-t itt.
    // Ez megakadályozza a háttérben lévő térkép újratöltését (és az SQLite zárolási hibát).
    // A UI-t a hívó oldalon (dialog) frissítjük helyileg.
  }

  void addImportedFeatures(List<GeoFeature> imported) {
    if (_activeLayer == null || imported.isEmpty) return;
    _activeLayer!.features.addAll(imported);
    _saveProjectsToDisk();
    notifyListeners();
  }

  void finishRecording(String name, String description, {String? templateName, Map<String, dynamic> customData = const {}}) {
    if (currentGeometry.isEmpty) return;
    _saveFeature(
      name, description, activeTool, 
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
    notifyListeners();
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

  void _saveFeature(String name, String description, FeatureType type, 
      List<LatLng> geometry, List<double> altitudes, List<bool> isEllipsoidalFlags, List<String> photos, 
      String? templateName, Map<String, dynamic> customData, {List<GnssFix>? fixes}) {
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
        final eov = _eovService!.wgsToEov(lat, lon);
        stats['EOV Y'] = double.parse(eov[0].toStringAsFixed(2));
        stats['EOV X'] = double.parse(eov[1].toStringAsFixed(2));
      }
      
      final double gpsAlt = altitudes.isNotEmpty ? altitudes.first : 0.0;
      final bool isEllipsoidal = isEllipsoidalFlags.isNotEmpty ? isEllipsoidalFlags.first : Platform.isAndroid;
      
      if (isEllipsoidal) {
        stats['Ellipszoidi magasság'] = double.parse(gpsAlt.toStringAsFixed(3));
        if (_geoidService != null) {
          final orthoH = _geoidService!.getOrthoHeight(lat, lon, gpsAlt, isEllipsoidal: true);
          if (orthoH != null) {
            stats['Balti magasság'] = double.parse(orthoH.toStringAsFixed(3));
          }
        }
      } else {
        // MSL (pl. iOS internal GPS)
        stats['Balti magasság'] = double.parse(gpsAlt.toStringAsFixed(3));
        if (_geoidService != null) {
          final undulation = _geoidService!.getUndulation(lat, lon);
          if (undulation != null) {
            stats['Ellipszoidi magasság'] = double.parse((gpsAlt + undulation).toStringAsFixed(3));
          } else {
            stats['Ellipszoidi magasság'] = double.parse(gpsAlt.toStringAsFixed(3));
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
        'gnssFixes': fixes?.map((f) => f.toMap()).toList(),
      },
    );

    // Add summary stats from GNSS fixes if available
    if (fixes != null && fixes.isNotEmpty) {
      final last = fixes.last;
      feature.calculatedStats['GNSS Source'] = last.source.name;
      feature.calculatedStats['Fix Type'] = last.fixType.name;
      if (last.rtkStatus != RtkStatus.none) {
        feature.calculatedStats['RTK Status'] = last.rtkStatus.name;
      }
      if (last.correctionAge != null) {
        feature.calculatedStats['Correction Age'] = "${last.correctionAge}s";
      }
    }

    _activeLayer!.features.add(feature);
    _saveProjectsToDisk();

    // Auto-stop NTRIP if enabled
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
      _saveProjectsToDisk();
      notifyListeners();
    }
  }

  /// Frissíti egy elem egyedi adatait és elmenti a lemezre
  void updateFeatureCustomData(String featureId, Map<String, dynamic> data) {
    bool found = false;
    for (var project in _projects) {
      for (var layer in project.layers) {
        for (var feature in layer.features) {
          if (feature.id == featureId) {
            feature.customData.addAll(data);
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

  double _calculatePolygonArea(List<LatLng> points) {
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

  // --- OFFLINE MENTÉS ÉS BETÖLTÉS LOGIKÁJA ---

  Future<void> _saveProjectsToDisk() async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/saved_projects.json');
    final backupFile = File('${directory.path}/saved_projects.json.bak');
    final tempFile = File('${directory.path}/saved_projects.json.tmp');

    try {
      // 1. Biztonsági másolat készítése a meglévő érvényes fájlról
      if (await file.exists()) {
        if (await backupFile.exists()) await backupFile.delete();
        await file.copy(backupFile.path);
      }

      // 2. Mentés ideiglenes fájlba
      final jsonString = jsonEncode(_projects.map((p) => p.toJson()).toList());
      await tempFile.writeAsString(jsonString);

      // 3. Atomikus jellegű csere: régi törlése (ha van), ideiglenes átnevezése
      if (await file.exists()) await file.delete();
      await tempFile.rename(file.path);

      // 4. Sikeres írás után a biztonsági másolat törölhető
      if (await backupFile.exists()) await backupFile.delete();
      
      debugPrint("Projektek sikeresen mentve (v${Project.currentFormatVersion})");
    } catch (e) {
      debugPrint("HIBA a mentés során: $e");
      // Megpróbáljuk visszaállítani a backupot, ha a fő fájl megsérült volna
      if (await backupFile.exists() && !(await file.exists())) {
        await backupFile.copy(file.path);
        debugPrint("Backup visszaállítva hiba miatt.");
      }
    }
  }

  Future<void> _loadProjectsFromDisk() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/saved_projects.json');
      final backupFile = File('${directory.path}/saved_projects.json.bak');

      // Ha a fő fájl hiányzik, de a backup létezik (félbeszakadt mentés), állítsuk vissza
      if (!await file.exists() && await backupFile.exists()) {
        await backupFile.copy(file.path);
        debugPrint("Félbeszakadt mentés helyreállítva a backup fájlból.");
      }

      if (await file.exists()) {
        final jsonString = await file.readAsString();
        final List<dynamic> decoded = jsonDecode(jsonString);

        bool needsResave = false;
        final List<Project> loadedProjects = [];

        for (var projectJson in decoded) {
          final Map<String, dynamic> projectMap = Map<String, dynamic>.from(projectJson);
          final int originalVersion = projectMap['formatVersion'] ?? 1;

          // Migráció végrehajtása a JSON-on a betöltés előtt
          final migratedJson = ProjectMigrationService.migrate(projectMap);
          
          if (migratedJson['formatVersion'] > originalVersion) {
            needsResave = true;
            debugPrint("Projekt migráltatva: v$originalVersion -> v${migratedJson['formatVersion']}");
          }
          
          loadedProjects.add(Project.fromJson(migratedJson));
        }

        _projects.clear();
        _projects.addAll(loadedProjects);

        if (_projects.isNotEmpty) {
          _activeProject = _projects.first;
          _activeLayer = _activeProject!.layers.isNotEmpty ? _activeProject!.layers.first : null;
        }

        // Ha történt migráció, mentsük is vissza a frissített formátumot
        if (needsResave) {
          await _saveProjectsToDisk();
        }
        
        notifyListeners();
      } else {
        // Ha nincs még fájl (első indítás), létrehozunk egy alap projektet
        createProject("Gyakorló Mérés");
      }
    } catch (e) {
      debugPrint("Hiba a projektek betöltésekor: $e");
      // Hibatűrés: ha valamiért korrupt a fájl, csinálunk egy újat a megmaradt listából (ha volt)
      if (_projects.isEmpty) createProject("Gyakorló Mérés");
    }
  }
}
