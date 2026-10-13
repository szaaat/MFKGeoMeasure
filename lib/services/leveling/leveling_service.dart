import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../../models/leveling/leveling_project.dart';
import '../../models/leveling/leveling_reading.dart';
import '../../models/leveling/leveling_station.dart';
import '../../models/geo_feature.dart';
import '../project_service.dart';
import 'leveling_calculation_service.dart';

class LevelingService extends ChangeNotifier {
  final LevelingCalculationService _calculator;
  ProjectService? _projectService;
  LevelingProject? _activeProject;
  final List<LevelingProject> _history = [];

  LevelingService(this._calculator) {
    loadData();
  }

  LevelingProject? get activeProject => _activeProject;
  List<LevelingProject> get history => List.unmodifiable(_history);

  void updateProjectService(ProjectService service) {
    _projectService = service;
  }

  // --- MENTÉS ÉS BETÖLTÉS ---

  Future<void> _saveActiveToDisk() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/active_leveling.json');
      if (_activeProject == null) {
        if (await file.exists()) await file.delete();
      } else {
        await file.writeAsString(jsonEncode(_activeProject!.toJson()));
      }
    } catch (e) {
      debugPrint("Error saving active leveling: $e");
    }
  }

  Future<void> _saveHistoryToDisk() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/leveling_history.json');
      await file.writeAsString(jsonEncode(_history.map((p) => p.toJson()).toList()));
    } catch (e) {
      debugPrint("Error saving leveling history: $e");
    }
  }

  Future<void> loadData() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      
      // Betöltés: Aktív projekt
      final activeFile = File('${dir.path}/active_leveling.json');
      if (await activeFile.exists()) {
        final content = await activeFile.readAsString();
        _activeProject = LevelingProject.fromJson(jsonDecode(content));
      }

      // Betöltés: Történet
      final historyFile = File('${dir.path}/leveling_history.json');
      if (await historyFile.exists()) {
        final content = await historyFile.readAsString();
        final List<dynamic> decoded = jsonDecode(content);
        _history.clear();
        _history.addAll(decoded.map((p) => LevelingProject.fromJson(p)).toList());
      }
      notifyListeners();
    } catch (e) {
      debugPrint("Error loading leveling data: $e");
    }
  }

  void startNewProject({
    required String id,
    required String name,
    required String startPointId,
    required double startHeight,
    String? endPointId,
    double? knownEndHeight,
    bool isPrecision = false,
  }) {
    _activeProject = LevelingProject(
      id: id,
      name: name,
      startPointId: startPointId,
      startHeight: startHeight,
      endPointId: endPointId,
      knownEndHeight: knownEndHeight,
      isPrecision: isPrecision,
    );
    _saveActiveToDisk();
    notifyListeners();
  }

  void finishProject() {
    if (_activeProject != null) {
      if (_activeProject!.stations.isNotEmpty) {
        _history.insert(0, _activeProject!);
        _saveHistoryToDisk();
      }
      _activeProject = null;
      _saveActiveToDisk();
      notifyListeners();
    }
  }

  void discardActiveProject() {
    _activeProject = null;
    _saveActiveToDisk();
    notifyListeners();
  }

  void deleteFromHistory(String id) {
    _history.removeWhere((p) => p.id == id);
    _saveHistoryToDisk();
    notifyListeners();
  }

  void resumeFromHistory(LevelingProject project) {
    _activeProject = project;
    _saveActiveToDisk();
    notifyListeners();
  }

  /// Meglévő pontok lekérése a ProjectService-ből
  List<GeoFeature> get availablePoints {
    if (_projectService == null) return [];
    return _projectService!.visibleFeatures
        .where((f) => f.type == FeatureType.point)
        .toList();
  }

  void addStation(String backsightPointId) {
    if (_activeProject == null) return;
    
    // Alapértelmezett értékek az előző állomásból (Smart Defaults)
    String? prevSurveyor;
    String? prevInstrument;
    String? prevOrder;
    if (_activeProject!.stations.isNotEmpty) {
      final last = _activeProject!.stations.last;
      prevSurveyor = last.surveyor;
      prevInstrument = last.instrument;
      prevOrder = last.measurementOrder;
    }

    final newStation = LevelingStation(
      stationId: _activeProject!.stations.length + 1,
      backsightPointId: backsightPointId,
      surveyor: prevSurveyor,
      instrument: prevInstrument,
      measurementOrder: prevOrder,
    );
    
    _activeProject!.stations.add(newStation);
    _saveActiveToDisk();
    notifyListeners();
  }

  void updateStationMetadata({
    String? surveyor,
    String? instrument,
    String? measurementOrder,
    String? notes,
  }) {
    final station = currentStation;
    if (station != null) {
      if (surveyor != null) station.surveyor = surveyor;
      if (instrument != null) station.instrument = instrument;
      if (measurementOrder != null) station.measurementOrder = measurementOrder;
      if (notes != null) station.notes = notes;
      _saveActiveToDisk();
      notifyListeners();
    }
  }

  LevelingStation? get currentStation {
    if (_activeProject == null || _activeProject!.stations.isEmpty) return null;
    return _activeProject!.stations.last;
  }

  double? get currentInstrumentHeight {
    final station = currentStation;
    if (station == null || station.backsight == null) return null;

    double previousHeight = getPointHeight(station.backsightPointId);
    return _calculator.calculateInstrumentHeight(previousHeight, station.backsight!);
  }

  double getPointHeight(String pointIdOrName) {
    if (_activeProject == null) return 0.0;
    if (pointIdOrName == _activeProject!.startPointId) return _activeProject!.startHeight;

    // Megkeressük az előző állomást, ahol ez a pont foresight volt
    for (var station in _activeProject!.stations) {
      if (station.foresightPointId == pointIdOrName) {
        double prevH = getPointHeight(station.backsightPointId);
        
        // Ha precíziós mérés volt
        if (station.meanDeltaH != null) {
          return prevH + station.meanDeltaH!;
        }
        
        // Ha sima szintezés volt
        if (station.foresight != null && station.backsight != null) {
          double mh = _calculator.calculateInstrumentHeight(prevH, station.backsight!);
          return _calculator.calculatePointHeight(mh, station.foresight!);
        }
      }
    }

    // Ha nem találtuk a szintezési vonalban, nézzük meg a ProjectService-ben hátha van GNSS magassága
    if (_projectService != null) {
      try {
        final feature = _projectService!.visibleFeatures.firstWhere(
          (f) => f.id == pointIdOrName || f.name == pointIdOrName,
        );
        if (feature.altitudes.isNotEmpty) return feature.altitudes.first;
      } catch (e) {
        // Nem található
      }
    }

    return 0.0;
  }

  void updateBacksight(double value) {
    final station = currentStation;
    if (station != null) {
      station.backsight = value;
      _saveActiveToDisk();
      notifyListeners();
    }
  }

  void updateForesight(String pointId, double value) {
    final station = currentStation;
    if (station != null) {
      station.foresightPointId = pointId;
      station.foresight = value;
      _saveActiveToDisk();
      notifyListeners();
    }
  }

  void updateStationDistance(double value) {
    final station = currentStation;
    if (station != null) {
      station.distance = value;
      _saveActiveToDisk();
      notifyListeners();
    }
  }

  void updatePrecisionReading({
    double? h1,
    double? e1,
    double? h2,
    double? e2,
  }) {
    final station = currentStation;
    if (station != null) {
      if (h1 != null) station.h1 = h1;
      if (e1 != null) station.e1 = e1;
      if (h2 != null) station.h2 = h2;
      if (e2 != null) station.e2 = e2;
      _saveActiveToDisk();
      notifyListeners();
    }
  }

  void addIntermediateReading(String pointId, double value) {
    final station = currentStation;
    if (station == null) return;

    final reading = LevelingReading(
      id: const Uuid().v4(),
      pointId: pointId,
      type: ReadingType.intermediate,
      value: value,
      timestamp: DateTime.now(),
    );

    station.intermediateReadings.add(reading);
    _saveActiveToDisk();
    notifyListeners();
  }

  void setEndPoint(String pointId, double knownHeight) {
    if (_activeProject != null) {
      _activeProject!.endPointId = pointId;
      _activeProject!.knownEndHeight = knownHeight;
      _saveActiveToDisk();
      notifyListeners();
    }
  }

  // --- SZERKESZTÉS ÉS ÚJRACSILLAGÁZÁS ---

  void updateReading(int stationId, String? readingId, ReadingType type, double newValue) {
    if (_activeProject == null) return;
    
    final station = _activeProject!.stations.firstWhere((s) => s.stationId == stationId);
    
    if (type == ReadingType.backsight) {
      station.backsight = newValue;
    } else if (type == ReadingType.foresight) {
      station.foresight = newValue;
    } else if (type == ReadingType.intermediate && readingId != null) {
      final reading = station.intermediateReadings.firstWhere((r) => r.id == readingId);
      final index = station.intermediateReadings.indexOf(reading);
      station.intermediateReadings[index] = LevelingReading(
        id: reading.id,
        pointId: reading.pointId,
        type: reading.type,
        value: newValue,
        timestamp: reading.timestamp,
      );
    }
    
    _saveActiveToDisk();
    notifyListeners();
  }

  void updatePointName(int stationId, String? readingId, ReadingType type, String newName) {
    if (_activeProject == null) return;
    
    final station = _activeProject!.stations.firstWhere((s) => s.stationId == stationId);
    
    if (type == ReadingType.backsight) {
      // station.backsightPointId = newName; // final
    } else if (type == ReadingType.foresight) {
      station.foresightPointId = newName;
    } else if (type == ReadingType.intermediate && readingId != null) {
      final reading = station.intermediateReadings.firstWhere((r) => r.id == readingId);
      final index = station.intermediateReadings.indexOf(reading);
      station.intermediateReadings[index] = LevelingReading(
        id: reading.id,
        pointId: newName,
        type: reading.type,
        value: reading.value,
        timestamp: reading.timestamp,
      );
    }
    
    _saveActiveToDisk();
    notifyListeners();
  }

  // --- STATISZTIKÁK ---

  int get stationCount => _activeProject?.stations.length ?? 0;

  int get totalPointCount {
    if (_activeProject == null) return 0;
    final Set<String> points = {_activeProject!.startPointId};
    for (var s in _activeProject!.stations) {
      if (s.foresightPointId != null) points.add(s.foresightPointId!);
      for (var r in s.intermediateReadings) {
        points.add(r.pointId);
      }
    }
    return points.length;
  }

  int readingCount(ReadingType type) {
    if (_activeProject == null) return 0;
    int count = 0;
    for (var s in _activeProject!.stations) {
      if (type == ReadingType.backsight && s.backsight != null) count++;
      if (type == ReadingType.foresight && s.foresight != null) count++;
      if (type == ReadingType.intermediate) count += s.intermediateReadings.length;
    }
    return count;
  }

  /// Összes hátra leolvasás összege
  double get sumBacksights {
    if (_activeProject == null) return 0.0;
    return _activeProject!.stations
        .where((s) => s.backsight != null)
        .fold(0.0, (sum, s) => sum + s.backsight!);
  }

  /// Összes előre leolvasás összege
  double get sumForesights {
    if (_activeProject == null) return 0.0;
    return _activeProject!.stations
        .where((s) => s.foresight != null)
        .fold(0.0, (sum, s) => sum + s.foresight!);
  }

  /// Precíziós módban a két lécskála magasságkülönbségének átlaga, egyébként ΣBS - ΣFS.
  double get calculatedHeightDifference {
    final project = _activeProject;
    if (project == null) return 0.0;
    if (project.isPrecision) {
      return project.stations.fold(
        0.0,
        (sum, station) => sum + (station.meanDeltaH ?? 0.0),
      );
    }
    return sumBacksights - sumForesights;
  }

  /// Számított végmagasság
  double get calculatedEndHeight {
    if (_activeProject == null) return 0.0;
    return _activeProject!.startHeight + calculatedHeightDifference;
  }

  /// Záróhiba (m)
  double? get closureError {
    if (_activeProject == null || _activeProject!.knownEndHeight == null) return null;
    return calculatedEndHeight - _activeProject!.knownEndHeight!;
  }

  /// Kiegyenlített magasságok számítása egy adott pontra
  double getAdjustedHeight(String pointId) {
    if (_activeProject == null) return 0.0;
    
    final rawHeight = getPointHeight(pointId);
    
    // Keressük meg a korrekciót a műszerállásokban
    for (var s in _activeProject!.stations) {
      if (s.corrections.containsKey(pointId)) {
        return rawHeight + s.corrections[pointId]!;
      }
    }

    return rawHeight;
  }

  /// Visszaadja a korrekció mértékét egy ponthoz
  double getCorrectionForPoint(String pointId) {
    if (_activeProject == null) return 0.0;
    for (var s in _activeProject!.stations) {
      if (s.corrections.containsKey(pointId)) {
        return s.corrections[pointId]!;
      }
    }
    return 0.0;
  }

  /// Kiegyenlítés végrehajtása
  void performAdjustment(AdjustmentMethod method) {
    if (_activeProject == null) return;
    final error = closureError;
    if (error == null) return;

    _activeProject!.adjustmentMethod = method;
    final stations = _activeProject!.stations;

    if (method == AdjustmentMethod.stationCount) {
      final corrPerStation = _calculator.calculateCorrectionPerStation(error, stations.length);
      for (int i = 0; i < stations.length; i++) {
        final s = stations[i];
        final cumulativeCorr = (i + 1) * corrPerStation;
        if (s.foresightPointId != null) s.corrections[s.foresightPointId!] = cumulativeCorr;
        for (var r in s.intermediateReadings) {
          s.corrections[r.pointId] = cumulativeCorr;
        }
      }
    } else if (method == AdjustmentMethod.distance) {
      double totalDist = stations.fold(0.0, (sum, s) => sum + (s.distance ?? 0.0));
      if (totalDist > 0) {
        double currentDist = 0.0;
        for (int i = 0; i < stations.length; i++) {
          final s = stations[i];
          currentDist += (s.distance ?? 0.0);
          final cumulativeCorr = _calculator.calculateCorrectionByDistance(error, currentDist, totalDist);
          if (s.foresightPointId != null) s.corrections[s.foresightPointId!] = cumulativeCorr;
          for (var r in s.intermediateReadings) {
            s.corrections[r.pointId] = cumulativeCorr;
          }
        }
      }
    }
    
    _saveActiveToDisk();
    notifyListeners();
  }

  /// Kiegyenlítés visszavonása
  void clearAdjustments() {
    if (_activeProject == null) return;
    _activeProject!.adjustmentMethod = AdjustmentMethod.none;
    for (var s in _activeProject!.stations) {
      s.corrections.clear();
    }
    _saveActiveToDisk();
    notifyListeners();
  }

  /// Kiegyenlített magasságok mentése a ProjectService-be
  void applyAdjustmentToProject() {
    if (_activeProject == null || _projectService == null) return;

    final Set<String> pointIds = {};
    for (var s in _activeProject!.stations) {
      if (s.foresightPointId != null) pointIds.add(s.foresightPointId!);
      for (var r in s.intermediateReadings) {
        pointIds.add(r.pointId);
      }
    }

    for (var id in pointIds) {
      final adjustedH = getAdjustedHeight(id);
      saveLeveledHeightToPoint(id, adjustedH);
    }
  }

  /// Szintezett magasság mentése a ProjectService-be
  void saveLeveledHeightToPoint(String pointId, double height) {
    if (_projectService == null) return;

    _projectService!.updateFeatureCustomData(pointId, {
      'leveled_height': height,
      'leveling_timestamp': DateTime.now().toIso8601String(),
    });
    notifyListeners();
  }

  /// Ellenőrzi, hogy egy pont el lett-e már mentve a projektbe szintezett magassággal
  bool isPointSaved(String pointIdOrName, double currentHeight) {
    if (_projectService == null) return false;
    
    try {
      final feature = _projectService!.visibleFeatures.firstWhere(
        (f) => f.id == pointIdOrName || f.name == pointIdOrName,
      );
      
      final savedHeight = feature.customData['leveled_height'];
      if (savedHeight != null && ((savedHeight as double) - currentHeight).abs() < 0.0001) {
        return true;
      }
    } catch (e) {
      // Nem található
    }
    return false;
  }
}
