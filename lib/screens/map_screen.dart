import 'dart:async';
import 'dart:math';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart' as vmt;
import 'package:vector_map_tiles_mbtiles/vector_map_tiles_mbtiles.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vtr;
import 'package:mbtiles/mbtiles.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:latlong2/latlong.dart';
import '../models/gnss_fix.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:flutter_compass/flutter_compass.dart';
import 'package:provider/provider.dart';

import 'package:camera/camera.dart';
import '../l10n/app_localizations.dart';
import 'camera_screen.dart';
import '../services/geoid_service.dart';
import '../services/eov_service.dart';
import '../services/project_service.dart';
import '../services/kalman_service.dart';
import '../services/gnss_info_service.dart';
import '../services/photo_service.dart';
import '../services/template_service.dart';
import '../services/import_service.dart';
import '../services/vector_map_service.dart';
import '../services/gnss/rtcm_service.dart';
import '../services/gnss/ntrip_client.dart';
import '../models/geo_feature.dart';
import '../models/field_definition.dart';
import '../widgets/image_viewer.dart';
import 'package:intl/intl.dart';
import '../widgets/libella_widget.dart';
import '../widgets/skyplot_widget.dart';
import 'cogo_screen.dart';
import 'leveling/leveling_screen.dart';
import 'gnss_settings_screen.dart';

// --- 1. SAJÁT OFFLINE TÁROLÓ ---
final customCacheManager = CacheManager(
  Config(
    'offlineMapCache',
    stalePeriod: const Duration(days: 365),
    maxNrOfCacheObjects: 100000,
    repo: JsonCacheInfoRepository(databaseName: 'offlineMapCache'),
    fileService: HttpFileService(),
  ),
);

// --- 2. LETÖLTÉS VEZÉRLŐ OSZTÁLY ---
class OfflineDownloadManager {
  final StreamController<double> _progressController = StreamController<double>.broadcast();
  Stream<double> get progressStream => _progressController.stream;

  bool _isCancelled = false;

  void cancel() {
    _isCancelled = true;
  }

  Future<void> downloadRegion({
    required LatLngBounds bounds,
    required int minZoom,
    required int maxZoom,
    required String urlTemplate,
  }) async {
    _isCancelled = false;
    List<String> urls = _generateUrls(bounds, minZoom, maxZoom, urlTemplate);
    int total = urls.length;
    int completed = 0;

    int batchSize = 50;

    for (int i = 0; i < total; i += batchSize) {
      if (_isCancelled) break;

      int end = (i + batchSize < total) ? i + batchSize : total;
      List<String> batch = urls.sublist(i, end);

      await Future.wait(batch.map((url) async {
        try {
          var fileInfo = await customCacheManager.getFileFromCache(url);
          if (fileInfo == null) {
            await customCacheManager.downloadFile(url);
          }
        } catch (e) {
          debugPrint("Hiba a csempe letöltésekor: $url");
        }
      }));

      completed += batch.length;
      _progressController.add(completed / total);

      await Future.delayed(const Duration(milliseconds: 10));
    }

    _progressController.close();
  }

  List<String> _generateUrls(LatLngBounds bounds, int minZ, int maxZ, String template) {
    List<String> urls = [];
    for (int z = minZ; z <= maxZ; z++) {
      var p1 = _project(bounds.northWest, z);
      var p2 = _project(bounds.southEast, z);

      int minX = min(p1.x, p2.x).floor();
      int maxX = max(p1.x, p2.x).floor();
      int minY = min(p1.y, p2.y).floor();
      int maxY = max(p1.y, p2.y).floor();

      for (int x = minX; x <= maxX; x++) {
        for (int y = minY; y <= maxY; y++) {
          urls.add(template
              .replaceAll('{z}', z.toString())
              .replaceAll('{x}', x.toString())
              .replaceAll('{y}', y.toString()));
        }
      }
    }
    return urls;
  }

  Point<double> _project(LatLng latLng, int zoom) {
    var siny = sin(latLng.latitude * pi / 180);
    siny = min(max(siny, -0.9999), 0.9999);
    return Point(
      256 * (0.5 + latLng.longitude / 360) * pow(2, zoom),
      256 * (0.5 - log((1 + siny) / (1 - siny)) / (4 * pi)) * pow(2, zoom),
    );
  }
}

// --- 3. TILE PROVIDER (JAVÍTVA OSM-HEZ) ---
class CachedTileProvider extends TileProvider {
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    final url = getTileUrl(coordinates, options);
    return CachedNetworkImageProvider(
      url,
      cacheManager: customCacheManager,
      // Az OSM szerverei blokkolják a kéréseket User-Agent nélkül!
      headers: const {'User-Agent': 'com.mfk.geomeasure'},
    );
  }
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  StreamSubscription<GnssFix>? _gnssSubscription;
  StreamSubscription<CompassEvent>? _compassStream;

  final GpsKalmanFilter _kalmanFilter = GpsKalmanFilter();

  LatLng? _currentLocation;
  double _currentAccuracy = 0.0;
  double _gpsAltitude = 0.0;

  bool _isTracking = true;
  bool _mapReady = false;
  String _activeLayer = 'OpenStreetMap';

  // --- KITŰZÉS (STAKEOUT) VÁLTOZÓI ---
  GeoFeature? _stakeoutTarget;
  double _distanceToTarget = 0.0;
  double _bearingToTarget = 0.0;
  double _deviceHeading = 0.0;

  AppLocalizations get l10n => AppLocalizations.of(context)!;

  String _getLocalizedTemplateName(String key) {
    switch (key) {
      case 'templateGeneral': return l10n.templateGeneral;
      case 'templateWaterManhole': return l10n.templateWaterManhole;
      case 'templateBoundaryStone': return l10n.templateBoundaryStone;
      case 'templateUtilityPole': return l10n.templateUtilityPole;
      default: return key;
    }
  }

  String _getLocalizedFieldLabel(String key) {
    switch (key) {
      case 'fieldMaterial': return l10n.fieldMaterial;
      case 'fieldDiameter': return l10n.fieldDiameter;
      case 'fieldDepth': return l10n.fieldDepth;
      case 'fieldCondition': return l10n.fieldCondition;
      case 'fieldType': return l10n.fieldType;
      case 'fieldStatus': return l10n.fieldStatus;
      case 'fieldVoltage': return l10n.fieldVoltage;
      case 'fieldHasLamp': return l10n.fieldHasLamp;
      default: return key;
    }
  }


  @override
  void initState() {
    super.initState();
    _startLocationUpdates();
    _startCompassUpdates();
  }

  @override
  void dispose() {
    _gnssSubscription?.cancel();
    _compassStream?.cancel();
    super.dispose();
  }

  void _startCompassUpdates() {
    _compassStream = FlutterCompass.events?.listen((CompassEvent event) {
      if (!mounted) return;
      double? heading = event.heading;
      if (heading != null && heading.isFinite) {
        setState(() {
          _deviceHeading = heading;
        });
      }
    });
  }

  void _safeMove(LatLng dest, double zoom) {
    if (!_mapReady) return;
    if (!dest.latitude.isFinite || !dest.longitude.isFinite || !zoom.isFinite) {
      debugPrint("REJECTED move to invalid location or zoom: $dest, $zoom");
      return;
    }
    _mapController.move(dest, zoom);
  }

  Future<void> _startLocationUpdates() async {
    final gnssService = context.read<GnssInfoService>();
    
    // Kezdeti pozíció lekérése az utolsó ismert fix alapján (ha van)
    if (gnssService.lastFix != null) {
      final fix = gnssService.lastFix!;
      _kalmanFilter.reset();
      final filtered = _kalmanFilter.filter(fix.latitude, fix.longitude, fix.horizontalAccuracy);
      setState(() {
        _currentLocation = LatLng(filtered[0], filtered[1]);
        _gpsAltitude = fix.ellipsoidalHeight; // TODO: Itt el kell dönteni, mit jelenítsünk meg
        _currentAccuracy = fix.horizontalAccuracy;
      });
      _safeMove(_currentLocation!, 15.0);
    }

    _gnssSubscription = gnssService.fixStream.listen((GnssFix fix) {
      if (!mounted || !fix.latitude.isFinite || !fix.longitude.isFinite) return;

      final filtered = _kalmanFilter.filter(
        fix.latitude,
        fix.longitude,
        fix.horizontalAccuracy,
      );
      
      if (!filtered[0].isFinite || !filtered[1].isFinite) return;
      
      final filteredLocation = LatLng(filtered[0], filtered[1]);

      setState(() {
        _currentLocation = filteredLocation;
        // A térképen a megjelenítéshez eldöntjük, melyik magasságot használjuk.
        // Geodéziai app lévén az ellipszoidi a biztos alap, de a UI-n 
        // esetleg a Balti magasságot is mutathatjuk.
        _gpsAltitude = fix.ellipsoidalHeight; 
        _currentAccuracy = fix.horizontalAccuracy;

        if (_stakeoutTarget != null && _stakeoutTarget!.geometry.isNotEmpty) {
          final target = _stakeoutTarget!.geometry.first;
          const distance = Distance();
          _distanceToTarget = distance.as(LengthUnit.Meter, _currentLocation!, target);

          _bearingToTarget = geo.Geolocator.bearingBetween(
            _currentLocation!.latitude,
            _currentLocation!.longitude,
            target.latitude,
            target.longitude,
          );
        }
      });
      
      if (_isTracking && _currentLocation != null) {
        double currentZoom = 15.0;
        try {
           currentZoom = _mapController.camera.zoom;
           if (!currentZoom.isFinite) currentZoom = 15.0;
        } catch (e) { /* Map maybe not ready */ }
        
        _safeMove(_currentLocation!, currentZoom);
      }
    }, onError: (error) {
      debugPrint("GNSS UPDATE FAILURE: $error");
    });
  }

  // --- KOORDINÁTA KERESŐ ÉS PROJEKTBE MENTŐ ---
  void _showSettingsDialog() {
    final projectService = context.read<ProjectService>();
    final antController = TextEditingController(text: projectService.antennaHeight.toString());
    final accController = TextEditingController(text: projectService.requiredAccuracy.toString());

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.geodeticSettings),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: antController,
              decoration: InputDecoration(labelText: l10n.antennaHeight, hintText: "Pl: 2.0"),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: accController,
              decoration: InputDecoration(labelText: l10n.requiredAccuracy, hintText: "Pl: 3.0"),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const GnssSettingsScreen()));
              },
              icon: const Icon(Icons.settings_bluetooth),
              label: Text(l10n.gnssSource),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.cancel)),
          ElevatedButton(
            onPressed: () {
              projectService.setAntennaHeight(double.tryParse(antController.text) ?? 0.0);
              projectService.setRequiredAccuracy(double.tryParse(accController.text) ?? 5.0);
              Navigator.pop(ctx);
            },
            child: Text(l10n.save),
          ),
        ],
      ),
    );
  }

  void _showSearchDialog() {
    final searchController = TextEditingController();
    final projectService = context.read<ProjectService>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.searchCoord),
        content: TextField(
          controller: searchController,
          decoration: const InputDecoration(
            hintText: 'Pl: 47.902, 20.373 vagy 723000, 283000',
            labelText: 'WGS84 (Lat, Lon) vagy EOV (Y, X)',
          ),
          keyboardType: TextInputType.text,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () {
              String cleanInput = searchController.text
                  .replaceAll(', ', ' ')
                  .replaceAll(',', '.')
                  .replaceAll(';', ' ');

              final parts = cleanInput.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();

              if (parts.length >= 2) {
                double? val1 = double.tryParse(parts[0]);
                double? val2 = double.tryParse(parts[1]);

                if (val1 != null && val2 != null) {
                  double lat, lon;

                  if (val1 > 10000 && val2 > 10000) {
                    double eovY = val1 > val2 ? val1 : val2;
                    double eovX = val1 < val2 ? val1 : val2;

                    final wgs = context.read<EovService>().eovToWgs(eovY, eovX);
                    lat = wgs[0];
                    lon = wgs[1];
                  } else {
                    lat = val1;
                    lon = val2;
                  }

                  LatLng newPoint = LatLng(lat, lon);

                  projectService.setTool(FeatureType.point);
                  projectService.addPointToGeometry(newPoint, 0.0);
                  projectService.finishRecording(
                      "${l10n.searched}: ${lat.toStringAsFixed(4)}, ${lon.toStringAsFixed(4)}",
                      l10n.recordedFromSearch
                  );

                  _safeMove(newPoint, 17.0);
                  setState(() => _isTracking = false);
                  Navigator.pop(ctx);

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.pointSaved), backgroundColor: Colors.green),
                  );
                  return;
                }
              }
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l10n.invalidCoord)),
              );
            },
            child: Text(l10n.searchAndSave),
          ),
        ],
      ),
    );
  }

  // --- LETÖLTŐ ABLAK ---
  void _showDownloadDialog() {
    final bounds = _mapController.camera.visibleBounds;
    final currentZoom = _mapController.camera.zoom.floor();

    int minZoom = currentZoom;
    int maxZoom = min(17, currentZoom + 2);

    int estimatedTiles = _estimateTiles(bounds, minZoom, maxZoom);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {

          bool isLarge = estimatedTiles > 50000;
          bool isHuge = estimatedTiles > 200000;

          return AlertDialog(
            title: Text(l10n.saveArea),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.selectDetail),
                  const SizedBox(height: 10),
                  Text("${l10n.zoomLevels}: $minZoom - $maxZoom"),
                  RangeSlider(
                    values: RangeValues(minZoom.toDouble(), maxZoom.toDouble()),
                    min: 5, max: 18, divisions: 13,
                    labels: RangeLabels("$minZoom", "$maxZoom"),
                    onChanged: (val) {
                      setDialogState(() {
                        minZoom = val.start.round();
                        maxZoom = val.end.round();
                        estimatedTiles = _estimateTiles(bounds, minZoom, maxZoom);
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(isLarge ? Icons.warning : Icons.storage,
                          color: isHuge ? Colors.red : (isLarge ? Colors.orange : Colors.blue)),
                      const SizedBox(width: 8),
                      Expanded(child: Text("${l10n.tileCount}: ~$estimatedTiles db", style: const TextStyle(fontWeight: FontWeight.bold))),
                    ],
                  ),

                  if (isLarge) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(5)),
                      child: Text(
                        isHuge ? l10n.attentionHuge : l10n.attentionLarge,
                        style: TextStyle(color: isHuge ? Colors.red : Colors.orange[800], fontSize: 11),
                      ),
                    ),
                  ]
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.cancel)),
              ElevatedButton(
                onPressed: isHuge ? null : () {
                  Navigator.pop(ctx);
                  _startProgressDownload(bounds, minZoom, maxZoom, estimatedTiles);
                },
                child: Text(l10n.startDownload),
              ),
            ],
          );
        },
      ),
    );
  }

  void _startProgressDownload(LatLngBounds bounds, int minZ, int maxZ, int totalEst) {
    final manager = OfflineDownloadManager();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StreamBuilder<double>(
          stream: manager.progressStream,
          initialData: 0.0,
          builder: (context, snapshot) {
            double progress = snapshot.data ?? 0.0;
            int percentage = (progress * 100).toInt();

            if (progress >= 1.0) {
              Future.delayed(const Duration(milliseconds: 500), () {
                if(!context.mounted) return;
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.downloadDone), backgroundColor: Colors.green));
              });
            }

            return AlertDialog(
              title: Text(l10n.downloading),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(value: progress, minHeight: 10, color: percentage > 90 ? Colors.green : Colors.blue),
                  const SizedBox(height: 15),
                  Text("$percentage%", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  Text("~${(totalEst * progress).toInt()} / $totalEst csempe", style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 20),
                  Text(l10n.dontClose, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                  Text(l10n.keepScreenOn, style: const TextStyle(fontSize: 10)),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    manager.cancel();
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.downloadAborted)));
                  },
                  child: Text(l10n.abort, style: const TextStyle(color: Colors.red)),
                )
              ],
            );
          },
        );
      },
    );

    manager.downloadRegion(
        bounds: bounds,
        minZoom: minZ,
        maxZoom: maxZ,
        urlTemplate: _getLayerUrl(_activeLayer)
    );
  }

  int _estimateTiles(LatLngBounds bounds, int minZ, int maxZ) {
    int count = 0;
    final mgr = OfflineDownloadManager();
    for (int z = minZ; z <= maxZ; z++) {
      var p1 = mgr._project(bounds.northWest, z);
      var p2 = mgr._project(bounds.southEast, z);
      int dx = (max(p1.x, p2.x).floor() - min(p1.x, p2.x).floor()).abs() + 1;
      int dy = (max(p1.y, p2.y).floor() - min(p1.y, p2.y).floor()).abs() + 1;
      count += (dx * dy);
    }
    return count;
  }

  Future<void> _clearOfflineCache() async {
    try {
      await customCacheManager.emptyCache();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.storageCleared), backgroundColor: Colors.orange)
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("${l10n.error}: $e")));
    }
  }

  String _getLayerUrl(String layerName) {
    switch (layerName) {
      case 'Satellite': return 'https://mt1.google.com/vt/lyrs=s&x={x}&y={y}&z={z}';
      case 'Turistautak': return 'http://terkep.turistautak.hu/tiles/turistautak-domborzattal/{z}/{x}/{y}.png';
      case 'OpenStreetMap': default: return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
    }
  }

  // --- UI ---
  void _handleRecordButton() {
    if (_currentLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.noGps)));
      return;
    }

    final projectService = context.read<ProjectService>();
    final gnssService = context.read<GnssInfoService>();

    if (projectService.activeTool == FeatureType.point) {
      _showPointModeSelection(projectService);
    } else {
      projectService.addPointToGeometry(
        _currentLocation!, 
        _gpsAltitude, 
        isEllipsoidal: gnssService.lastFix?.isEllipsoidal ?? true,
        fix: gnssService.lastFix,
      );
    }
  }

  void _showPointModeSelection(ProjectService service) {
    final gnssService = context.read<GnssInfoService>();
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.flash_on, color: Colors.orange),
              title: Text(l10n.fastRecord),
              subtitle: Text(l10n.fastRecordDesc),
              onTap: () {
                Navigator.pop(ctx);
                service.addPointToGeometry(
                  _currentLocation!, 
                  _gpsAltitude,
                  isEllipsoidal: gnssService.lastFix?.isEllipsoidal ?? true,
                  fix: gnssService.lastFix,
                );
                _showSaveDialog(service);
              },
            ),
            ListTile(
              leading: const Icon(Icons.timer, color: Colors.blue),
              title: Text(l10n.avgRecord),
              subtitle: Text(l10n.avgRecordDesc),
              onTap: () {
                Navigator.pop(ctx);
                _startAveragingProcess(service);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _startAveragingProcess(ProjectService service) async {
    final gnssService = context.read<GnssInfoService>();
    final stream = gnssService.fixStream;

    await service.startAveraging(
      stream,
      maxDurationSeconds: 30,
      requiredAccuracy: service.requiredAccuracy,
    );
    if (mounted) {
      _showSaveDialog(service);
    }
  }

  void _showSaveDialog(ProjectService service) {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    final photoService = context.read<PhotoService>();
    final templateService = context.read<TemplateService>();
    
    FeatureTemplate? selectedTemplate = templateService.templates.first;
    Map<String, dynamic> templateData = {};

    String typeName = "";
    if (service.activeTool == FeatureType.point) typeName = l10n.point;
    if (service.activeTool == FeatureType.line) typeName = l10n.line;
    if (service.activeTool == FeatureType.polygon) typeName = l10n.polygon;

    nameController.text = "$typeName ${service.visibleFeatures.length + 1}";

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text("$typeName ${l10n.saveItem}"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameController, decoration: InputDecoration(labelText: l10n.name)),
                
                DropdownButtonFormField<FeatureTemplate>(
                  initialValue: selectedTemplate,
                  decoration: InputDecoration(labelText: l10n.templateLabel),
                  items: templateService.templates.map((t) => DropdownMenuItem(value: t, child: Text(_getLocalizedTemplateName(t.nameKey)))).toList(),
                  onChanged: (val) {
                    setDialogState(() {
                      selectedTemplate = val;
                      templateData = {};
                    });
                  },
                ),

                if (selectedTemplate != null && selectedTemplate!.fields.isNotEmpty) ...[
                  const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Divider()),
                  ...selectedTemplate!.fields.map((field) {
                    return _buildFieldInput(
                      context: context,
                      label: _getLocalizedFieldLabel(field.labelKey),
                      type: field.type,
                      choices: field.optionKeys,
                      onChanged: (val) => templateData[field.key] = val,
                    );
                  }),
                ],

                TextField(controller: descController, decoration: InputDecoration(labelText: l10n.description)),
                
                // --- EGYEDI RÉTEG ATTRIBÚTUMOK ---
                if (service.activeLayer != null) ...[
                  const Divider(height: 30),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(l10n.customFields, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blueGrey)),
                      TextButton.icon(
                        onPressed: () => _showAddCustomFieldDialog(context, service, setDialogState),
                        icon: const Icon(Icons.add_chart, size: 16),
                        label: Text(l10n.add, style: const TextStyle(fontSize: 11)),
                      )
                    ],
                  ),
                  ...service.activeLayer!.fields.map((fDef) => Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: _buildFieldInput(
                      context: context,
                      label: fDef.label,
                      type: fDef.type,
                      choices: fDef.choices,
                      onChanged: (val) => templateData[fDef.key] = val,
                    ),
                  )),
                ],

                const SizedBox(height: 15),
                if (service.currentPhotos.isNotEmpty)
                  SizedBox(
                    height: 80,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: service.currentPhotos.length,
                      itemBuilder: (ctx, i) => Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.file(
                                File(service.currentPhotos[i]), 
                                width: 80, height: 80, 
                                fit: BoxFit.cover,
                                cacheWidth: 200, 
                                errorBuilder: (ctx, err, stack) => Container(
                                  width: 80, height: 80, 
                                  color: Colors.grey[300], 
                                  child: const Icon(Icons.broken_image, color: Colors.grey),
                                ),
                              ),
                            ),
                            Positioned(
                              right: 0, top: 0,
                              child: GestureDetector(
                                onTap: () {
                                  service.currentPhotos.removeAt(i);
                                  setDialogState(() {});
                                },
                                child: Container(color: Colors.black54, child: const Icon(Icons.close, size: 16, color: Colors.white)),
                              ),
                            )
                          ],
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: () async {
                    FocusScope.of(context).unfocus();
                    
                    // BIZTONSÁGI PILLANATKÉP: Elmentjük a jelenlegi koordinátákat a kamera előtt,
                    // hogy ha az app újraindulna a háttérben, ne vesszenek el az adatok.
                    final snapshotLoc = _currentLocation;
                    final snapshotHeading = _deviceHeading;
                    final snapshotAlt = _gpsAltitude;

                    if (snapshotLoc == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Várj a GPS jelre a fotózás előtt!")),
                      );
                      return;
                    }

                    // 1. Megnyitjuk a saját kameránkat
                    final XFile? rawPhoto = await Navigator.push<XFile>(
                      context,
                      MaterialPageRoute(builder: (_) => const CameraScreen()),
                    );

                    if (rawPhoto != null && context.mounted) {
                      // 2. Feldolgozzuk a fotót a biztonságos pillanatkép adatokkal
                      final path = await photoService.processCapturedPhoto(
                        photo: rawPhoto,
                        location: snapshotLoc,
                        heading: snapshotHeading,
                        altitude: snapshotAlt,
                      );

                      if (path != null && context.mounted) {
                        // Biztonsági várakozás a Sandbox feloldásához
                        await Future.delayed(const Duration(milliseconds: 300));
                        if (context.mounted) {
                          service.addPhotoToCurrent(path);
                          setDialogState(() {}); 
                        }
                      }
                    }
                  },
                  icon: const Icon(Icons.camera_alt),
                  label: Text(l10n.takePhoto),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () { service.cancelRecording(); Navigator.pop(ctx); }, child: Text(l10n.cancel)),
            Consumer<GnssInfoService>(
              builder: (context, gnss, child) {
                final canSave = gnss.isStableRtkFix;
                return ElevatedButton(
                  onPressed: canSave ? () { 
                    service.finishRecording(nameController.text, descController.text, 
                        templateName: selectedTemplate?.nameKey, customData: templateData); 
                    Navigator.pop(ctx); 
                  } : null, 
                  child: Text(canSave ? l10n.save : "Waiting for Stable FIX (${gnss.currentFixStabilityDuration.toStringAsFixed(1)}s)")
                );
              }
            ),
          ],
        ),
      ),
    );
  }

  void _showSkyplotDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.skyplotTitle),
        content: Consumer<GnssInfoService>(
          builder: (context, gnss, child) {
            if (Platform.isIOS) {
              return Text(l10n.skyplotAndroidOnly);
            }
            if (gnss.currentStatus.satellites.isEmpty) {
              return SizedBox(
                height: 200,
                child: Center(child: Text(l10n.searchingSatellites)),
              );
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SkyplotWidget(satellites: gnss.currentStatus.satellites, size: 250),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 10,
                  children: [
                    _buildLegendItem("GPS", Colors.blue),
                    _buildLegendItem("GLONASS", Colors.red),
                    _buildLegendItem("Galileo", Colors.green),
                    _buildLegendItem("Beidou", Colors.orange),
                  ],
                ),
                const SizedBox(height: 10),
                Text(l10n.satUsedLegend, style: const TextStyle(fontSize: 10, color: Colors.grey)),
              ],
            );
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.close)),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 10)),
      ],
    );
  }

  Widget _buildFieldInput({
    required BuildContext context,
    required String label,
    required FieldType type,
    List<String>? choices,
    dynamic initialValue,
    required Function(dynamic) onChanged,
  }) {
    if (type == FieldType.bool) {
      return SwitchListTile(
        title: Text(label, style: const TextStyle(fontSize: 14)),
        value: initialValue ?? false,
        onChanged: onChanged,
      );
    } else if (type == FieldType.choice && choices != null) {
      return DropdownButtonFormField<String>(
        value: initialValue,
        decoration: InputDecoration(labelText: label),
        items: choices.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
        onChanged: onChanged,
      );
    } else if (type == FieldType.date || type == FieldType.dateTime) {
      final dt = initialValue is DateTime ? initialValue : (initialValue != null ? DateTime.tryParse(initialValue.toString()) : null);
      final format = type == FieldType.date ? DateFormat('yyyy-MM-dd') : DateFormat('yyyy-MM-dd HH:mm');
      return ListTile(
        title: Text(label),
        subtitle: Text(dt != null ? format.format(dt) : "Nincs kiválasztva"),
        trailing: const Icon(Icons.calendar_today),
        onTap: () async {
          final date = await showDatePicker(
            context: context, 
            initialDate: dt ?? DateTime.now(),
            firstDate: DateTime(2000), 
            lastDate: DateTime(2100)
          );
          if (date != null) {
            if (type == FieldType.dateTime) {
              final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(dt ?? DateTime.now()));
              if (time != null) {
                onChanged(DateTime(date.year, date.month, date.day, time.hour, time.minute));
              }
            } else {
              onChanged(date);
            }
          }
        },
      );
    } else {
      return TextField(
        decoration: InputDecoration(labelText: label),
        keyboardType: (type == FieldType.integer || type == FieldType.decimal) ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
        controller: TextEditingController(text: initialValue?.toString() ?? ""),
        onChanged: (val) {
          if (type == FieldType.integer) onChanged(int.tryParse(val));
          else if (type == FieldType.decimal) onChanged(double.tryParse(val));
          else onChanged(val);
        },
      );
    }
  }
  void _showAddCustomFieldDialog(BuildContext context, ProjectService service, StateSetter setDialogState) {
    final nameCtrl = TextEditingController();
    FieldType selectedType = FieldType.text;
    final choicesCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(l10n.addCustomField),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(labelText: l10n.newFieldName),
                autofocus: true,
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<FieldType>(
                value: selectedType,
                decoration: const InputDecoration(labelText: "Mező típusa"),
                items: FieldType.values.map((t) => DropdownMenuItem(value: t, child: Text(t.name))).toList(),
                onChanged: (val) => setState(() => selectedType = val!),
              ),
              if (selectedType == FieldType.choice) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: choicesCtrl,
                  decoration: const InputDecoration(labelText: "Opciók (vesszővel elválasztva)", hintText: "A, B, C"),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.cancel)),
            ElevatedButton(
              onPressed: () {
                if (nameCtrl.text.isNotEmpty && service.activeLayer != null) {
                  final key = CustomFieldDefinition.normalizeKey(nameCtrl.text);
                  List<String>? choices;
                  if (selectedType == FieldType.choice && choicesCtrl.text.isNotEmpty) {
                    choices = choicesCtrl.text.split(',').map((e) => e.trim()).toList();
                  }
                  
                  service.addCustomFieldToLayer(service.activeLayer!, CustomFieldDefinition(
                    key: key,
                    label: nameCtrl.text,
                    type: selectedType,
                    choices: choices,
                  ));
                  Navigator.pop(ctx);
                  setDialogState(() {});
                }
              },
              child: Text(l10n.add),
            ),
          ],
        ),
      ),
    );
  }

  void _showFeatureDetails(GeoFeature feature) {
    final tSvc = context.read<TemplateService>();
    final template = tSvc.getTemplateByNameKey(feature.templateName);
    final service = context.read<ProjectService>();

    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(feature.name)),
          IconButton(
            icon: const Icon(Icons.edit, size: 20, color: Colors.blue),
            onPressed: () {
              Navigator.pop(ctx);
              _showFeatureEditDialog(feature);
            },
          )
        ],
      ),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if(feature.description.isNotEmpty) Text(feature.description, style: const TextStyle(fontStyle: FontStyle.italic)),
          
          if (feature.templateName != null && feature.templateName != "templateGeneral") ...[
            const Divider(),
            Text("${l10n.templateLabel}: ${_getLocalizedTemplateName(feature.templateName!)}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blue)),
          ],

          if (feature.customData.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...feature.customData.entries.map((e) {
              // Megpróbáljuk megtalálni a mező definícióját az aktív rétegben vagy a sablonban
              CustomFieldDefinition? customDef;
              if (service.activeLayer != null) {
                customDef = service.activeLayer!.fields.firstWhere((f) => f.key == e.key, orElse: () => CustomFieldDefinition(key: e.key, label: e.key, type: FieldType.text));
              }

              final fieldDef = template?.fields.firstWhere(
                (f) => f.key == e.key, 
                orElse: () => FieldDefinition(labelKey: customDef?.label ?? e.key, key: e.key, type: customDef?.type ?? FieldType.text)
              );
              
              String displayValue = e.value.toString();
              if (e.value is DateTime) {
                displayValue = DateFormat('yyyy-MM-dd HH:mm').format(e.value);
              }

              return Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Row(
                  children: [
                    Text("${_getLocalizedFieldLabel(fieldDef?.labelKey ?? e.key)}: ", style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    Text(displayValue, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ),
              );
            }),
          ],

          const Divider(),
          ...feature.calculatedStats.entries.map((e) => Text("${e.key}: ${e.value}")),
          if (feature.photos.isNotEmpty) ...[
            const Divider(),
            const Text("Fényképek:", style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 5, mainAxisSpacing: 5),
              itemCount: feature.photos.length,
              itemBuilder: (ctx, i) => GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ImageViewer(path: feature.photos[i]))),
                child: Hero(
                  tag: feature.photos[i],
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: Image.file(
                      File(feature.photos[i]), 
                      fit: BoxFit.cover,
                      cacheWidth: 300, 
                      errorBuilder: (ctx, err, stack) => Container(
                        color: Colors.grey[200],
                        child: const Icon(Icons.broken_image, color: Colors.grey),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ]
        ]),
      ),
      actions: [
        TextButton(onPressed: () { context.read<ProjectService>().deleteFeature(feature.id); Navigator.pop(ctx); }, style: TextButton.styleFrom(foregroundColor: Colors.red), child: Text(l10n.delete)),

        // --- KITŰZÉS GOMB ---
        if (feature.type == FeatureType.point)
          ElevatedButton.icon(
            onPressed: () {
              setState(() => _stakeoutTarget = feature);
              Navigator.pop(ctx);
            },
            icon: const Icon(Icons.explore),
            label: Text(l10n.stakeout),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
          ),

        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.close)),
      ],
    ));
  }

  Widget _buildQualityIndicator(double score) {
    Color color = Colors.red;
    if (score > 70) {
      color = Colors.green;
    } else if (score > 40) {
      color = Colors.orange;
    }

    return Container(
      width: 40, height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.3), width: 3),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              "${score.toInt()}%",
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color),
            ),
            const Icon(Icons.satellite_alt, size: 8, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  void _showPpkDialog() {
    final gnssService = context.read<GnssInfoService>();
    final projectService = context.read<ProjectService>();
    final timeStr = "${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}";
    final nameCtrl = TextEditingController(text: l10n.measurementTime(timeStr));
    final notesCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.ppkStartTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: InputDecoration(labelText: l10n.ppkNameLabel)),
            TextField(controller: notesCtrl, decoration: InputDecoration(labelText: l10n.ppkNotesLabel)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.cancel)),
          ElevatedButton(
            onPressed: () {
            gnssService.rawLogger.startSession(
                name: nameCtrl.text,
                antennaHeight: projectService.antennaHeight,
                rawStream: gnssService.activeProvider!.rawMeasurementStream,
                approxPosition: _currentLocation,
                notes: notesCtrl.text,
              );
              Navigator.pop(ctx);
            },
            child: Text(l10n.ppkStartBtn),
          ),
        ],
      ),
    );
  }

  void _showExportDialog(ProjectService service, Project project, Rect? origin) {
    showDialog(
      context: context, 
      builder: (innerCtx) => AlertDialog(
        title: Text(l10n.export),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (service.activeLayer != null) ...[
              Text("Aktuális réteg: ${service.activeLayer!.name}", style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _exportBtn(innerCtx, service, project, "csv", Colors.green, "CSV", origin),
                  _exportBtn(innerCtx, service, project, "geojson", Colors.orange, "GeoJSON", origin),
                  _exportBtn(innerCtx, service, project, "shp", Colors.blue, "SHP", origin),
                ],
              ),
              const Divider(height: 30),
            ],
            Text("Teljes projekt: ${project.name}", style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              icon: const Icon(Icons.archive),
              label: const Text("ZIP (Minden réteg külön)"),
              onPressed: () {
                Navigator.pop(innerCtx);
                service.exportWithFormat(context, context.read<GeoidCorrectionService>(), project, format: "zip", sharePositionOrigin: origin);
              },
            ),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(innerCtx), child: Text(l10n.close))],
      )
    );
  }

  Widget _exportBtn(BuildContext ctx, ProjectService service, Project project, String format, Color color, String label, Rect? origin) {
    return Column(
      children: [
        IconButton(
          icon: Icon(format == "csv" ? Icons.table_chart : format == "geojson" ? Icons.code : Icons.layers, color: color),
          onPressed: () {
            Navigator.pop(ctx);
            service.exportWithFormat(context, context.read<GeoidCorrectionService>(), project, format: format, layer: service.activeLayer, sharePositionOrigin: origin);
          },
        ),
        Text(label, style: const TextStyle(fontSize: 10)),
      ],
    );
  }

  void _showFeatureEditDialog(GeoFeature feature) {
    final service = context.read<ProjectService>();
    final tSvc = context.read<TemplateService>();
    final template = tSvc.getTemplateByNameKey(feature.templateName);
    
    final nameCtrl = TextEditingController(text: feature.name);
    final descCtrl = TextEditingController(text: feature.description);
    Map<String, dynamic> editData = Map.from(feature.customData);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text("Szerkesztés"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: "Név")),
                TextField(controller: descCtrl, decoration: const InputDecoration(labelText: "Leírás")),
                const Divider(height: 30),
                
                // Sablon mezők (ha vannak)
                if (template != null) ...template.fields.map((field) {
                  return _buildFieldInput(
                    context: context,
                    label: _getLocalizedFieldLabel(field.labelKey),
                    type: field.type,
                    choices: field.optionKeys,
                    initialValue: editData[field.key],
                    onChanged: (val) => setDialogState(() => editData[field.key] = val),
                  );
                }),

                // Réteg egyedi mezői
                if (service.activeLayer != null) ...service.activeLayer!.fields.map((fDef) {
                  return _buildFieldInput(
                    context: context,
                    label: fDef.label,
                    type: fDef.type,
                    choices: fDef.choices,
                    initialValue: editData[fDef.key],
                    onChanged: (val) => setDialogState(() => editData[fDef.key] = val),
                  );
                }),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.cancel)),
            ElevatedButton(
              onPressed: () {
                feature.name = nameCtrl.text;
                feature.description = descCtrl.text;
                service.updateFeatureCustomData(feature.id, editData);
                Navigator.pop(ctx);
              }, 
              child: Text(l10n.save)
            ),
          ],
        ),
      ),
    );
  }

  void _showProjectManager() {
    final service = context.read<ProjectService>();
    final nameCtrl = TextEditingController();
    showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                title: Text(l10n.projectsLayers),
                content: SizedBox(
                  width: double.maxFinite, height: 400,
                  child: Column(children: [
                    Row(children: [
                      Expanded(child: TextField(controller: nameCtrl, decoration: InputDecoration(hintText: "${l10n.name}...", isDense: true))),
                      IconButton(icon: const Icon(Icons.add_circle, color: Colors.blue), onPressed: () {
                        if(nameCtrl.text.isEmpty) return;
                        if(service.activeProject==null) {
                          service.createProject(nameCtrl.text);
                          nameCtrl.clear();
                          setDialogState((){});
                        } else {
                          showDialog(context: context, builder: (c) => AlertDialog(
                              title: Text(l10n.newElement),
                              content: Text("${l10n.createWhat}: '${nameCtrl.text}'?"),
                              actions: [
                                TextButton(onPressed: (){ service.createProject(nameCtrl.text); nameCtrl.clear(); Navigator.pop(c); setDialogState((){}); }, child: Text(l10n.newProject)),
                                ElevatedButton(onPressed: (){ service.createLayer(nameCtrl.text); nameCtrl.clear(); Navigator.pop(c); setDialogState((){}); }, child: Text(l10n.newLayer)),
                              ]
                          ));
                        }
                      })
                    ]),
                    const Divider(),
                    if (service.activeProject != null)
                      Padding(padding: const EdgeInsets.only(bottom: 8.0), child: Text("${l10n.activeProject}: ${service.activeProject!.name}", style: const TextStyle(fontSize: 12, color: Colors.grey))),
                    Expanded(child: ListView.builder(itemCount: service.projects.length, itemBuilder: (ctx, i) {
                      final p = service.projects[i];
                      final isProjectActive = p.id == service.activeProject?.id;
                      return Column(children: [
                        ListTile(
                            title: Text(p.name, style: TextStyle(fontWeight: FontWeight.bold, color: isProjectActive?Colors.blue:Colors.black)),
                            leading: const Icon(Icons.folder),
                            trailing: isProjectActive 
                              ? Builder(
                                  builder: (btnCtx) => IconButton(
                                    icon: const Icon(Icons.share), 
                                    onPressed: () { 
                                      Navigator.pop(ctx); 
                                      final box = btnCtx.findRenderObject() as RenderBox?;
                                      final origin = box != null ? box.localToGlobal(Offset.zero) & box.size : null;
                                      _showExportDialog(service, p, origin); 
                                    }
                                  ),
                                ) 
                              : IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () { service.deleteProject(p.id); setDialogState((){}); }),
                            onTap: () { service.selectProject(p); setDialogState((){}); },
                            tileColor: isProjectActive ? Colors.blue.withValues(alpha: 0.1) : null
                        ),
                        if(isProjectActive) ...p.layers.map((l) => Padding(padding: const EdgeInsets.only(left: 30), child: ListTile(dense: true, title: Text(l.name), leading: Icon(l.id==service.activeLayer?.id ? Icons.radio_button_checked : Icons.radio_button_unchecked, size: 16), onTap: () { service.selectLayer(l); setDialogState((){}); })))
                      ]);
                    }))
                  ]),
                ),
                actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.close))],
              );
            }
        )
    );
  }

  @override
  Widget build(BuildContext context) {
    final projectService = context.watch<ProjectService>();
    final geoidService = context.watch<GeoidCorrectionService>();
    final gnssService = context.watch<GnssInfoService>();
    final vectorService = context.watch<VectorMapService>();
    final eovService = context.read<EovService>();

    final eov = _currentLocation != null ? eovService.wgsToEov(_currentLocation!.latitude, _currentLocation!.longitude) : [0.0, 0.0];
    final orthoHeight = _currentLocation != null ? geoidService.getOrthoHeight(_currentLocation!.latitude, _currentLocation!.longitude, _gpsAltitude) : null;

    final topPadding = MediaQuery.of(context).padding.top;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    const bottomPanelMinHeight = 160.0;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          children: [
            Text(projectService.activeProject?.name ?? l10n.noProject, style: const TextStyle(fontSize: 16)),
            Text(projectService.activeLayer?.name ?? l10n.noLayer, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.upload_file),
            tooltip: l10n.gisImportTooltip,
            onPressed: () async {
              final importService = context.read<ImportService>();
              final projectService = context.read<ProjectService>();
              final messenger = ScaffoldMessenger.of(context);
              final imported = await importService.importGisData();
              if (imported.isNotEmpty) {
                projectService.addImportedFeatures(imported);
                messenger.showSnackBar(
                  SnackBar(content: Text(l10n.itemsImported(imported.length))),
                );
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings_suggest),
            tooltip: l10n.settingsTooltip,
            onPressed: _showSettingsDialog,
          ),
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: l10n.searchCoord,
            onPressed: _showSearchDialog,
          ),
          IconButton(
            icon: const Icon(Icons.download_for_offline),
            tooltip: l10n.offlineMaps,
            onPressed: () {
              showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text(l10n.offlineMaps),
                    content: Text(l10n.manageDownloads),
                    actionsAlignment: MainAxisAlignment.spaceBetween,
                    actions: [
                      TextButton.icon(
                        icon: const Icon(Icons.delete_forever, color: Colors.red),
                        label: Text(l10n.deleteStorage, style: const TextStyle(color: Colors.red)),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _clearOfflineCache();
                        },
                      ),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.download),
                        label: Text(l10n.newDownload),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _showDownloadDialog();
                        },
                      ),
                    ],
                  )
              );
            },
          ),
          IconButton(onPressed: _showProjectManager, icon: const Icon(Icons.folder_open)),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: _currentLocation ?? const LatLng(47.4979, 19.0402),
                  initialZoom: 15.0,
                  interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
                  onPositionChanged: (pos, hasGesture) { if (hasGesture) setState(() => _isTracking = false); },
                  onMapReady: () {
                    setState(() => _mapReady = true);
                    if (_isTracking && _currentLocation != null) {
                      _safeMove(_currentLocation!, 15.0);
                    }
                  },
                ),
                children: [
                  if (!vectorService.isVectorEnabled || vectorService.mbtilesPath == null)
                    TileLayer(
                      urlTemplate: _getLayerUrl(_activeLayer),
                      userAgentPackageName: 'com.mfk.geomeasure',
                      tileProvider: CachedTileProvider(),
                    )
                  else
                    vmt.VectorTileLayer(
                      tileProviders: vmt.TileProviders({
                        'openmaptiles': MbTilesVectorTileProvider(
                          mbtiles: MbTiles(mbtilesPath: vectorService.mbtilesPath!),
                        ),
                      }),
                      theme: _getVectorTheme(),
                    ),
                  PolygonLayer(polygons: [
                    ...projectService.visibleFeatures.where((f) => f.type == FeatureType.polygon).map((f) => Polygon(points: f.geometry, color: Colors.blue.withValues(alpha: 0.3), borderColor: Colors.blue, borderStrokeWidth: 2, label: f.name))
                  ]),
                  PolylineLayer(polylines: [
                    ...projectService.visibleFeatures.where((f) => f.type == FeatureType.line).map((f) => Polyline(points: f.geometry, color: Colors.green, strokeWidth: 3))
                  ]),
                  MarkerLayer(markers: [
                    ...projectService.visibleFeatures.where((f) => f.type == FeatureType.point).map((f) => Marker(point: f.geometry.first, width: 40, height: 40, child: GestureDetector(onTap: () => _showFeatureDetails(f), child: const Icon(Icons.location_on, color: Colors.red, size: 30))))
                  ]),

                  if (projectService.isRecording && projectService.activeTool != FeatureType.point)
                    PolylineLayer(polylines: [ Polyline(points: [...projectService.currentGeometry, if(_currentLocation!=null) _currentLocation!], color: Colors.red, strokeWidth: 2, isDotted: true) ]),

                  if (_currentLocation != null)
                    MarkerLayer(
                        markers: [
                          Marker(
                              point: _currentLocation!,
                              width: 60,
                              height: 60,
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.blue.withValues(alpha: 0.15),
                                ),
                                child: const Icon(
                                    Icons.my_location,
                                    color: Colors.blue,
                                    size: 28
                                ),
                              )
                          )
                        ]
                    ),

                ],
              ),

              // --- KITŰZÉS (STAKEOUT) PANEL ---
              if (_stakeoutTarget != null)
                Positioned(
                  top: topPadding + 10,
                  left: 20,
                  right: 20,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: Colors.orange, width: 2),
                      boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8)],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Transform.rotate(
                              angle: (_bearingToTarget - _deviceHeading) * (pi / 180),
                              child: const Icon(Icons.arrow_upward, size: 50, color: Colors.orange),
                            ),
                            const SizedBox(width: 15),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text("${l10n.target}: ${_stakeoutTarget!.name}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                  Text(
                                      _distanceToTarget < 1.0
                                          ? "${(_distanceToTarget * 100).toStringAsFixed(0)} cm"
                                          : "${_distanceToTarget.toStringAsFixed(2)} m",
                                      style: TextStyle(
                                          fontSize: 28,
                                          fontWeight: FontWeight.bold,
                                          color: _distanceToTarget < 0.1 ? Colors.green : (_distanceToTarget < 1.0 ? Colors.blue : Colors.black)
                                      )
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.red, size: 30),
                              onPressed: () => setState(() => _stakeoutTarget = null),
                            )
                          ],
                        ),
                        if (_distanceToTarget < 2.0)
                          Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: ElevatedButton.icon(
                              onPressed: () => _startAveragingProcess(projectService),
                              icon: const Icon(Icons.verified),
                              label: Text(l10n.stakeoutCheck),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                minimumSize: const Size(double.infinity, 36)
                              ),
                            ),
                          )
                      ],
                    ),
                  ),
                ),

              // --- ÁTLAGOLÁS PROGRESS ---
              if (projectService.isAveraging)
                Container(
                  color: Colors.black54,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.all(25),
                      margin: const EdgeInsets.symmetric(horizontal: 40),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(l10n.measuringInProgress, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                          const SizedBox(height: 10),
                          Text(l10n.keepStill, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                          const SizedBox(height: 20),
                          const LibellaWidget(size: 150),
                          const SizedBox(height: 30),
                          LinearProgressIndicator(value: projectService.averagingProgress),
                          const SizedBox(height: 10),
                          Text("${(projectService.averagingProgress * 100).toInt()}%", style: const TextStyle(fontWeight: FontWeight.bold)),
                          if (projectService.currentBatchBestAccuracy != null) ...[
                            const Divider(height: 30),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(l10n.bestAcc, style: const TextStyle(fontSize: 11)),
                                Text("±${projectService.currentBatchBestAccuracy!.toStringAsFixed(2)} m", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 13)),
                              ],
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(l10n.avgAcc, style: const TextStyle(fontSize: 11)),
                                Text("±${projectService.currentBatchAverageAccuracy!.toStringAsFixed(2)} m", style: const TextStyle(color: Colors.blue, fontSize: 13)),
                              ],
                            ),
                          ]
                        ],
                      ),
                    ),
                  ),
                ),

              Positioned(
                top: topPadding + (_stakeoutTarget != null ? 140 : 40), 
                bottom: bottomPanelMinHeight + bottomPadding + 20,
                left: 10, 
                child: SizedBox(
                  width: 50,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildToolBtn(Icons.place, l10n.point, FeatureType.point, projectService),
                        const SizedBox(height: 10),
                        _buildToolBtn(Icons.timeline, l10n.line, FeatureType.line, projectService),
                        const SizedBox(height: 10),
                        _buildToolBtn(Icons.pentagon_outlined, l10n.polygon, FeatureType.polygon, projectService),
                        const SizedBox(height: 10),
                        FloatingActionButton.small(
                            heroTag: "levelingBtn",
                            backgroundColor: Colors.white,
                            child: const Icon(Icons.height, color: Colors.blue),
                            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LevelingScreen())),
                        ),
                        const SizedBox(height: 20),
                        FloatingActionButton.small(
                            heroTag: "cogoBtn",
                            backgroundColor: Colors.white,
                            child: const Icon(Icons.calculate, color: Colors.blue),
                            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CogoScreen())),
                        ),
                        const SizedBox(height: 10),
                        FloatingActionButton.small(
                            heroTag: "layersBtn",
                            backgroundColor: Colors.white,
                            child: const Icon(Icons.layers, color: Colors.black),
                            onPressed: () {
                              showDialog(context: context, builder: (ctx) => SimpleDialog(title: Text(l10n.mapType), children: [
                                _layerOption(ctx, l10n.osm, "OpenStreetMap"),
                                _layerOption(ctx, l10n.satellite, "Satellite"),
                                _layerOption(ctx, l10n.hiking, "Turistautak"),
                                const Divider(),
                                ListTile(
                                  leading: const Icon(Icons.map, color: Colors.blue),
                                  title: Text(l10n.loadVectorMbtiles),
                                  subtitle: Text(context.watch<VectorMapService>().mbtilesPath?.split('/').last ?? l10n.notLoaded),
                                  onTap: () {
                                    Navigator.pop(ctx);
                                    context.read<VectorMapService>().pickMbTiles();
                                  },
                                ),
                                if (context.watch<VectorMapService>().mbtilesPath != null)
                                  SwitchListTile(
                                    title: Text(l10n.vectorMode),
                                    value: context.watch<VectorMapService>().isVectorEnabled,
                                    onChanged: (val) {
                                      context.read<VectorMapService>().toggleVector(val);
                                      Navigator.pop(ctx);
                                    },
                                  )
                              ]));
                            }
                        ),
                      ],
                    ),
                  ),
                )
              ),
              Positioned(
                bottom: 0, left: 0, right: 0, 
                child: GestureDetector(
                  onTap: () {
                    if (_currentLocation != null) {
                      setState(() => _isTracking = true);
                      _safeMove(_currentLocation!, 17.0);
                    }
                  },
                  child: Container(
                    padding: EdgeInsets.only(bottom: bottomPadding > 0 ? bottomPadding : 20),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.95),
                      boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 5, offset: Offset(0, -2))],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: _currentLocation != null ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("EOV Y, X:", style: TextStyle(fontWeight: FontWeight.bold)), Text("${eov[0].toStringAsFixed(0)}, ${eov[1].toStringAsFixed(0)}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.blue))]),
                          const Divider(height: 10),
                          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                            Text("φ: ${_currentLocation!.latitude.toStringAsFixed(6)}\nλ: ${_currentLocation!.longitude.toStringAsFixed(6)}", style: const TextStyle(fontSize: 12)),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (context.watch<RtcmService>().status != NtripStatus.disconnected)
                                    GestureDetector(
                                      onTap: () => _showNtripQuickMenu(context),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            margin: const EdgeInsets.only(right: 4),
                                            width: 12, height: 12,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: _getNtripColor(context.watch<RtcmService>().status),
                                              border: Border.all(color: Colors.white, width: 2),
                                            ),
                                          ),
                                          if (context.watch<RtcmService>().status == NtripStatus.correctionDataActive)
                                            Padding(
                                              padding: const EdgeInsets.only(right: 4),
                                              child: Text(
                                                context.watch<RtcmService>().diagnostics.correctionAgeString,
                                                style: TextStyle(
                                                  fontSize: 10, 
                                                  fontWeight: FontWeight.bold,
                                                  color: _getNtripColor(context.watch<RtcmService>().status),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  if (gnssService.lastFix?.fixType == GnssFixType.rtk)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: gnssService.lastFix?.rtkStatus == RtkStatus.fixed ? Colors.green : Colors.orange,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        gnssService.lastFix?.rtkStatus == RtkStatus.fixed ? "RTK FIX" : "RTK FLOAT",
                                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  const SizedBox(width: 8),
                                  GestureDetector(
                                    onTap: Platform.isAndroid ? _showSkyplotDialog : null,
                                    child: _buildQualityIndicator(gnssService.currentStatus.qualityScore),
                                  ),
                                  const SizedBox(width: 8),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      if (gnssService.currentStatus.satellitesInView > 0)
                                        Text(
                                          "${l10n.satellites}: ${gnssService.currentStatus.satellitesUsedInFix}/${gnssService.currentStatus.satellitesInView}",
                                          style: const TextStyle(fontSize: 10, color: Colors.blueGrey, fontWeight: FontWeight.bold),
                                        ),
                                      Text(
                                        "±${_currentAccuracy.toStringAsFixed(2)} m",
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: _getAccuracyColor(_currentAccuracy, projectService.requiredAccuracy),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              if (projectService.antennaHeight > 0)
                                Text("${l10n.ant}: ${projectService.antennaHeight}m", style: const TextStyle(fontSize: 10, color: Colors.grey)),
                            ],
                          )
                        ]),
                        const SizedBox(height: 6),
                        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          _buildHeightBox(
                            (gnssService.lastFix?.isEllipsoidal ?? true) ? "GPS h (Ell.)" : "GPS H (MSL)", 
                            "${_gpsAltitude.toStringAsFixed(2)} m", 
                            Colors.orange
                          ), 
                          const Icon(Icons.arrow_right_alt, color: Colors.grey), 
                          _buildHeightBox("EOV H (Balti)", "${orthoHeight?.toStringAsFixed(2) ?? '--'} m", Colors.green[700]!)
                        ]),
                      ]) : Center(child: Text(l10n.searchingGps, style: const TextStyle(fontStyle: FontStyle.italic))),
                    ),
                  ),
                )
              ),
            ],
          );
        }
      ),
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: bottomPadding + bottomPanelMinHeight - 20),
        child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
          if (Platform.isAndroid) ...[
            FloatingActionButton.small(
              heroTag: "ppkBtn",
              onPressed: gnssService.rawLogger.isLogging ? () => gnssService.rawLogger.stopSession() : _showPpkDialog,
              backgroundColor: gnssService.rawLogger.isLogging ? Colors.red : Colors.blueGrey,
              child: Icon(gnssService.rawLogger.isLogging ? Icons.stop_circle : Icons.sensors, color: Colors.white),
            ),
            const SizedBox(height: 10),
          ],
          if (projectService.isRecording) FloatingActionButton.extended(heroTag: "saveBtn", onPressed: () => _showSaveDialog(projectService), backgroundColor: Colors.green, icon: const Icon(Icons.check), label: Text(l10n.done)),
          const SizedBox(height: 10),
          FloatingActionButton(heroTag: "recBtn", onPressed: _handleRecordButton, backgroundColor: projectService.isRecording ? Colors.orange : Colors.blue, child: Icon(projectService.isRecording ? Icons.add : Icons.fiber_manual_record, color: Colors.white)),
          const SizedBox(height: 10),
          FloatingActionButton.small(heroTag: "gpsBtn", onPressed: () { setState(() => _isTracking = true); if (_currentLocation != null) _safeMove(_currentLocation!, 17); }, backgroundColor: Colors.white, child: Icon(Icons.my_location, color: _isTracking ? Colors.blue : Colors.grey)),
        ]),
      ),
    );
  }

  vtr.Theme _getVectorTheme() {
    return vtr.ProvidedThemes.lightTheme();
  }

  Widget _layerOption(BuildContext ctx, String name, String id) {
    return SimpleDialogOption(
      onPressed: () { setState(() => _activeLayer = id); Navigator.pop(ctx); },
      child: Row(children: [Icon(_activeLayer == id ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: Colors.blue), const SizedBox(width: 10), Text(name)]),
    );
  }

  Widget _buildHeightBox(String label, String value, Color color) {
    return Column(children: [Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)), Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 15))]);
  }

  Color _getAccuracyColor(double acc, double required) {
    if (acc <= required) return Colors.green;
    if (acc <= required * 2) return Colors.orange;
    return Colors.red;
  }

  Color _getNtripColor(NtripStatus s) {
    switch (s) {
      case NtripStatus.connected: return Colors.blue;
      case NtripStatus.correctionDataActive: return Colors.green;
      case NtripStatus.error: return Colors.red;
      case NtripStatus.connecting: return Colors.orange;
      case NtripStatus.notConfigured: return Colors.redAccent;
      default: return Colors.grey;
    }
  }

  void _showNtripQuickMenu(BuildContext context) {
    final rtcmService = context.read<RtcmService>();
    final gnssService = context.read<GnssInfoService>();
    final activeProfile = gnssService.ntripSettings.activeProfile;
    
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.link, color: _getNtripColor(rtcmService.status)),
              title: Text("NTRIP: ${rtcmService.status.name}"),
              subtitle: Text(activeProfile?.host ?? ""),
            ),
            if (rtcmService.status == NtripStatus.correctionDataActive)
               Padding(
                 padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                 child: Row(
                   mainAxisAlignment: MainAxisAlignment.spaceBetween,
                   children: [
                     Text("Correction Age: ${rtcmService.diagnostics.correctionAgeString}"),
                     Text("Bitrate: ${rtcmService.diagnostics.bitrateKbps.toStringAsFixed(1)} kbps"),
                   ],
                 ),
               ),
            if (rtcmService.status == NtripStatus.disconnected || rtcmService.status == NtripStatus.error || rtcmService.status == NtripStatus.notConfigured)
              ListTile(
                leading: const Icon(Icons.play_arrow, color: Colors.green),
                title: const Text("Csatlakozás"),
                enabled: rtcmService.status != NtripStatus.notConfigured,
                onTap: () {
                  Navigator.pop(ctx);
                  gnssService.updateNtripSettings(gnssService.ntripSettings, rtcmService: rtcmService);
                },
              ),
            if (rtcmService.status != NtripStatus.disconnected && rtcmService.status != NtripStatus.notConfigured)
              ListTile(
                leading: const Icon(Icons.stop, color: Colors.red),
                title: const Text("Bontás"),
                onTap: () {
                  Navigator.pop(ctx);
                  rtcmService.stopNtrip();
                },
              ),
            ListTile(
              leading: const Icon(Icons.settings, color: Colors.blueGrey),
              title: const Text("Beállítások megnyitása"),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const GnssSettingsScreen()));
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolBtn(IconData icon, String label, FeatureType type, ProjectService service) {
    return FloatingActionButton.small(
        heroTag: "tool_$label",
        backgroundColor: service.activeTool == type ? Colors.blue : Colors.white,
        onPressed: () => service.setTool(type),
        child: Icon(icon, color: service.activeTool == type ? Colors.white : Colors.black87)
    );
  }
}
