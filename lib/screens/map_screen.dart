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
import 'package:flutter/services.dart';

import 'package:camera/camera.dart';
import '../l10n/app_localizations.dart';
import 'camera_screen.dart';
import '../services/geoid_service.dart';
import '../services/eov_service.dart';
import '../services/project_service.dart';
import '../services/data_validation_service.dart';
import '../services/gnss_info_service.dart';
import 'control_point_check_screen.dart';
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
import 'attribute_table_screen.dart';
import '../widgets/survey_summary_dialog.dart';
import '../widgets/export_config_dialog.dart';

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
  final StreamController<double> _progressController =
      StreamController<double>.broadcast();
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

  List<String> _generateUrls(
      LatLngBounds bounds, int minZ, int maxZ, String template) {
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

  LatLng? _currentLocation;
  double _currentAccuracy = 0.0;
  double _gpsAltitude = 0.0;

  bool _isTracking = true;
  bool _mapReady = false;
  bool _manualDrawing = false;
  bool _snapEnabled = true;
  bool _orthogonalEnabled = false;
  String _activeLayer = 'OpenStreetMap';

  // --- KITŰZÉS (STAKEOUT) VÁLTOZÓI ---
  GeoFeature? _stakeoutTarget;
  double _distanceToTarget = 0.0;
  double _bearingToTarget = 0.0;
  double _deviceHeading = 0.0;
  bool _hasExternalHeading = false;

  AppLocalizations get l10n => AppLocalizations.of(context)!;

  String _getLocalizedTemplateName(String key) {
    switch (key) {
      case 'templateGeneral':
        return l10n.templateGeneral;
      case 'templateWaterManhole':
        return l10n.templateWaterManhole;
      case 'templateBoundaryStone':
        return l10n.templateBoundaryStone;
      case 'templateUtilityPole':
        return l10n.templateUtilityPole;
      default:
        return key;
    }
  }

  String _getLocalizedFieldLabel(String key) {
    switch (key) {
      case 'fieldMaterial':
        return l10n.fieldMaterial;
      case 'fieldDiameter':
        return l10n.fieldDiameter;
      case 'fieldDepth':
        return l10n.fieldDepth;
      case 'fieldCondition':
        return l10n.fieldCondition;
      case 'fieldType':
        return l10n.fieldType;
      case 'fieldStatus':
        return l10n.fieldStatus;
      case 'fieldVoltage':
        return l10n.fieldVoltage;
      case 'fieldHasLamp':
        return l10n.fieldHasLamp;
      default:
        return key;
    }
  }

  @override
  void initState() {
    super.initState();
    _startLocationUpdates();
    _startCompassUpdates();

    // Selection and focus listener
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ProjectService>().addListener(_onProjectServiceChanged);
    });
  }

  @override
  void dispose() {
    // Note: context.read might fail in dispose if not careful
    // but better to remove listener
    try {
      context.read<ProjectService>().removeListener(_onProjectServiceChanged);
    } catch (_) {}

    _gnssSubscription?.cancel();
    _compassStream?.cancel();
    super.dispose();
  }

  void _onProjectServiceChanged() {
    if (!mounted) return;
    final selection = context.read<ProjectService>().selectedFeature;
    if (selection != null) {
      _focusOnFeature(selection.featureId);
    }
  }

  void _focusOnFeature(String id) {
    final projectService = context.read<ProjectService>();
    GeoFeature? feature;
    for (var layer in projectService.activeProject?.layers ?? []) {
      for (var f in layer.features) {
        if (f.id == id) {
          feature = f;
          break;
        }
      }
      if (feature != null) break;
    }

    if (feature != null && feature.geometry.isNotEmpty) {
      setState(() => _isTracking = false);
      if (feature.type == FeatureType.point) {
        _safeMove(feature.geometry.first, 18.0);
      } else {
        final bounds = LatLngBounds.fromPoints(feature.geometry);
        _mapController.fitCamera(CameraFit.bounds(
            bounds: bounds, padding: const EdgeInsets.all(50)));
      }
    }
  }

  void _startCompassUpdates() {
    _compassStream = FlutterCompass.events?.listen((CompassEvent event) {
      if (!mounted) return;
      if (_hasExternalHeading)
        return; // M21 heading takes priority when INS is aligned or good
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
    if (gnssService.lastFix != null && gnssService.isPositionValid) {
      final fix = gnssService.lastFix!;
      setState(() {
        _currentLocation = LatLng(fix.latitude, fix.longitude);
        _gpsAltitude = fix.ellipsoidalHeight;
        _currentAccuracy = fix.horizontalAccuracy;
      });
      _safeMove(_currentLocation!, 15.0);
    }

    _gnssSubscription = gnssService.fixStream.listen((GnssFix fix) {
      if (!mounted || !fix.latitude.isFinite || !fix.longitude.isFinite) return;

      final filteredLocation = LatLng(fix.latitude, fix.longitude);

      // M21 Heading override condition
      final bool isM21HeadingValid = fix.heading != null &&
          fix.heading!.isFinite &&
          (fix.insStatus == 'INS_ALIGNMENT_COMPLETE' ||
              fix.insStatus == 'INS_SOLUTION_GOOD');

      _hasExternalHeading = isM21HeadingValid;

      setState(() {
        _currentLocation = filteredLocation;
        _gpsAltitude = fix.ellipsoidalHeight;
        _currentAccuracy = fix.horizontalAccuracy;
        if (isM21HeadingValid) {
          _deviceHeading = fix.heading!;
        }

        if (_stakeoutTarget != null && _stakeoutTarget!.geometry.isNotEmpty) {
          final target = _stakeoutTarget!.geometry.first;
          const distance = Distance();
          _distanceToTarget =
              distance.as(LengthUnit.Meter, _currentLocation!, target);

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
        } catch (e) {/* Map maybe not ready */}

        _safeMove(_currentLocation!, currentZoom);
      }
    }, onError: (error) {
      debugPrint("GNSS UPDATE FAILURE: $error");
    });
  }

  // --- KOORDINÁTA KERESŐ ÉS PROJEKTBE MENTŐ ---
  void _showSettingsDialog() {
    final projectService = context.read<ProjectService>();
    final antController =
        TextEditingController(text: projectService.antennaHeight.toString());
    final accController =
        TextEditingController(text: projectService.requiredAccuracy.toString());

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.geodeticSettings),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: antController,
              decoration: InputDecoration(
                  labelText: l10n.antennaHeight, hintText: "Pl: 2.0"),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9,.\-]')),
              ],
            ),
            TextField(
              controller: accController,
              decoration: InputDecoration(
                  labelText: l10n.requiredAccuracy, hintText: "Pl: 3.0"),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9,.\-]')),
              ],
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const GnssSettingsScreen()));
              },
              icon: const Icon(Icons.settings_bluetooth),
              label: Text(l10n.gnssSource),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(l10n.cancel)),
          ElevatedButton(
            onPressed: () {
              projectService
                  .setAntennaHeight(
                    double.tryParse(antController.text.replaceAll(',', '.')) ??
                        0.0,
                  );
              projectService.setRequiredAccuracy(
                      double.tryParse(accController.text.replaceAll(',', '.')) ??
                          5.0);
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

              final parts = cleanInput
                  .split(RegExp(r'\s+'))
                  .where((s) => s.isNotEmpty)
                  .toList();

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
                  final saved = projectService.finishRecording(
                      "${l10n.searched}: ${lat.toStringAsFixed(4)}, ${lon.toStringAsFixed(4)}",
                      l10n.recordedFromSearch);
                  if (!saved) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text(
                              'Az objektum adatellenőrzés miatt nem menthető.')),
                    );
                    return;
                  }

                  _safeMove(newPoint, 17.0);
                  setState(() => _isTracking = false);
                  Navigator.pop(ctx);

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text(l10n.pointSaved),
                        backgroundColor: Colors.green),
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
                    min: 5,
                    max: 18,
                    divisions: 13,
                    labels: RangeLabels("$minZoom", "$maxZoom"),
                    onChanged: (val) {
                      setDialogState(() {
                        minZoom = val.start.round();
                        maxZoom = val.end.round();
                        estimatedTiles =
                            _estimateTiles(bounds, minZoom, maxZoom);
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(isLarge ? Icons.warning : Icons.storage,
                          color: isHuge
                              ? Colors.red
                              : (isLarge ? Colors.orange : Colors.blue)),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text("${l10n.tileCount}: ~$estimatedTiles db",
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold))),
                    ],
                  ),
                  if (isLarge) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(5)),
                      child: Text(
                        isHuge ? l10n.attentionHuge : l10n.attentionLarge,
                        style: TextStyle(
                            color: isHuge ? Colors.red : Colors.orange[800],
                            fontSize: 11),
                      ),
                    ),
                  ]
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(l10n.cancel)),
              ElevatedButton(
                onPressed: isHuge
                    ? null
                    : () {
                        Navigator.pop(ctx);
                        _startProgressDownload(
                            bounds, minZoom, maxZoom, estimatedTiles);
                      },
                child: Text(l10n.startDownload),
              ),
            ],
          );
        },
      ),
    );
  }

  void _startProgressDownload(
      LatLngBounds bounds, int minZ, int maxZ, int totalEst) {
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
                if (!context.mounted) return;
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(l10n.downloadDone),
                    backgroundColor: Colors.green));
              });
            }

            return AlertDialog(
              title: Text(l10n.downloading),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(
                      value: progress,
                      minHeight: 10,
                      color: percentage > 90 ? Colors.green : Colors.blue),
                  const SizedBox(height: 15),
                  Text("$percentage%",
                      style: const TextStyle(
                          fontSize: 24, fontWeight: FontWeight.bold)),
                  Text("~${(totalEst * progress).toInt()} / $totalEst csempe",
                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 20),
                  Text(l10n.dontClose,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, color: Colors.red)),
                  Text(l10n.keepScreenOn, style: const TextStyle(fontSize: 10)),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    manager.cancel();
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l10n.downloadAborted)));
                  },
                  child: Text(l10n.abort,
                      style: const TextStyle(color: Colors.red)),
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
        urlTemplate: _getLayerUrl(_activeLayer));
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(l10n.storageCleared), backgroundColor: Colors.orange));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("${l10n.error}: $e")));
    }
  }

  String _getLayerUrl(String layerName) {
    switch (layerName) {
      case 'Satellite':
        return 'https://mt1.google.com/vt/lyrs=s&x={x}&y={y}&z={z}';
      case 'Turistautak':
        return 'http://terkep.turistautak.hu/tiles/turistautak-domborzattal/{z}/{x}/{y}.png';
      case 'OpenStreetMap':
      default:
        return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
    }
  }

  // --- UI ---
  void _handleRecordButton() {
    final gnssService = context.read<GnssInfoService>();

    if (_currentLocation == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.noGps)));
      return;
    }

    // Tájékoztató jelzés nem-ideális RTK állapot esetén, de a rögzítést NEM blokkoljuk!
    if (gnssService.isMfkRtkActive &&
        gnssService.mfkRtkMeasurementState !=
            MfkRtkMeasurementState.readyToMeasure) {
      final stateMsg = switch (gnssService.mfkRtkMeasurementState) {
        MfkRtkMeasurementState.waitingInsAlign =>
          'INS dőlésmérés még igazodik · Rögzítés engedélyezve',
        MfkRtkMeasurementState.rtcmLost =>
          'RTCM korrekció megszakadt · Rögzítés engedélyezve',
        MfkRtkMeasurementState.waitingRtk =>
          'Nem RTK FIX pozíció (${gnssService.lastFix?.rtkStatus.name.toUpperCase() ?? 'FLOAT'}) · Rögzítés engedélyezve',
        MfkRtkMeasurementState.readyToMeasure => '',
      };
      if (stateMsg.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(stateMsg),
            duration: const Duration(seconds: 2),
            backgroundColor: Colors.orange.shade800,
          ),
        );
      }
    }

    final projectService = context.read<ProjectService>();

    if (projectService.activeTool == FeatureType.point) {
      _showPointModeSelection(projectService);
    } else {
      projectService.addPointToGeometry(
        _currentLocation!,
        _gpsAltitude,
        isEllipsoidal: true,
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
                  isEllipsoidal: true,
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
      maxDurationSeconds: 3,
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
                TextField(
                    controller: nameController,
                    decoration: InputDecoration(labelText: l10n.name)),

                DropdownButtonFormField<FeatureTemplate>(
                  initialValue: selectedTemplate,
                  decoration: InputDecoration(labelText: l10n.templateLabel),
                  items: templateService.templates
                      .map((t) => DropdownMenuItem(
                          value: t,
                          child: Text(_getLocalizedTemplateName(t.nameKey))))
                      .toList(),
                  onChanged: (val) {
                    setDialogState(() {
                      selectedTemplate = val;
                      templateData = {};
                    });
                  },
                ),

                if (selectedTemplate != null &&
                    selectedTemplate!.fields.isNotEmpty) ...[
                  const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Divider()),
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

                TextField(
                    controller: descController,
                    decoration: InputDecoration(labelText: l10n.description)),

                // --- EGYEDI RÉTEG ATTRIBÚTUMOK ---
                if (service.activeLayer != null) ...[
                  const Divider(height: 30),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(l10n.customFields,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: Colors.blueGrey)),
                      TextButton.icon(
                        onPressed: () => _showAddCustomFieldDialog(
                            context, service, setDialogState),
                        icon: const Icon(Icons.add_chart, size: 16),
                        label: Text(l10n.add,
                            style: const TextStyle(fontSize: 11)),
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
                                width: 80,
                                height: 80,
                                fit: BoxFit.cover,
                                cacheWidth: 200,
                                errorBuilder: (ctx, err, stack) => Container(
                                  width: 80,
                                  height: 80,
                                  color: Colors.grey[300],
                                  child: const Icon(Icons.broken_image,
                                      color: Colors.grey),
                                ),
                              ),
                            ),
                            Positioned(
                              right: 0,
                              top: 0,
                              child: GestureDetector(
                                onTap: () {
                                  service.currentPhotos.removeAt(i);
                                  setDialogState(() {});
                                },
                                child: Container(
                                    color: Colors.black54,
                                    child: const Icon(Icons.close,
                                        size: 16, color: Colors.white)),
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
                        const SnackBar(
                            content: Text("Várj a GPS jelre a fotózás előtt!")),
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
            TextButton(
                onPressed: () {
                  service.cancelRecording();
                  Navigator.pop(ctx);
                },
                child: Text(l10n.cancel)),
            Consumer<GnssInfoService>(builder: (context, gnss, child) {
              final isMfk = gnss.isMfkRtkActive;
              final last = gnss.lastFix;
              final rtkStatus = last?.rtkStatus ?? RtkStatus.none;

              bool isStrictReady = isMfk
                  ? gnss.mfkRtkMeasurementState ==
                      MfkRtkMeasurementState.readyToMeasure
                  : gnss.isStableRtkFix;

              bool canSave = isStrictReady;
              if (!canSave && gnss.allowFloatSave) {
                if (rtkStatus == RtkStatus.float ||
                    rtkStatus == RtkStatus.fixed ||
                    last != null ||
                    isMfk) {
                  canSave = true;
                }
              }

              String? statusMsg;
              if (!isStrictReady) {
                if (gnss.allowFloatSave) {
                  statusMsg = "RTK Float mentés engedélyezve";
                } else if (isMfk) {
                  statusMsg = switch (gnss.mfkRtkMeasurementState) {
                    MfkRtkMeasurementState.waitingInsAlign =>
                      l10n.waitingInsAlignMsg,
                    MfkRtkMeasurementState.rtcmLost => l10n.rtcmLost,
                    MfkRtkMeasurementState.waitingRtk => l10n.waitingRtkFix,
                    MfkRtkMeasurementState.readyToMeasure => null,
                  };
                } else {
                  if (last == null || last.fixType == GnssFixType.none) {
                    statusMsg = l10n.rtkStatusNoFix;
                  } else if (last.rtkStatus != RtkStatus.fixed) {
                    statusMsg = l10n.rtkStatusWaiting;
                  } else {
                    statusMsg = l10n.rtkStatusMeasuring;
                  }
                }
              }

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (statusMsg != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 12.0, bottom: 4.0),
                      child: Text(
                        statusMsg,
                        style: TextStyle(
                          fontSize: 10,
                          color: isStrictReady ? Colors.green : Colors.orange,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ElevatedButton(
                      onPressed: canSave
                          ? () async {
                              final layer = service.activeLayer;
                              final draft = GeoFeature(
                                name: nameController.text,
                                description: descController.text,
                                type: service.activeTool,
                                geometry:
                                    List<LatLng>.from(service.currentGeometry),
                                customData:
                                    Map<String, dynamic>.from(templateData),
                              );
                              final issues =
                                  const DataValidationService().validateFeature(
                                feature: draft,
                                fields: layer?.fields ?? const [],
                                crsInfo: layer?.crsInfo,
                              );
                              final errors = issues
                                  .where((i) =>
                                      i.severity == ValidationSeverity.error)
                                  .toList();
                              final warnings = issues
                                  .where((i) =>
                                      i.severity == ValidationSeverity.warning)
                                  .toList();
                              if (errors.isNotEmpty) {
                                await showDialog<void>(
                                  context: ctx,
                                  builder: (dialogContext) => AlertDialog(
                                    title:
                                        const Text('Az objektum nem menthető'),
                                    content: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: errors
                                          .map((issue) => Padding(
                                                padding: const EdgeInsets.only(
                                                    bottom: 8),
                                                child:
                                                    Text('• ${issue.message}'),
                                              ))
                                          .toList(),
                                    ),
                                    actions: [
                                      TextButton(
                                          onPressed: () =>
                                              Navigator.pop(dialogContext),
                                          child: const Text('Rendben'))
                                    ],
                                  ),
                                );
                                return;
                              }
                              if (warnings.isNotEmpty) {
                                final proceed = await showDialog<bool>(
                                  context: ctx,
                                  builder: (dialogContext) => AlertDialog(
                                    title: const Text('Ellenőrizd az adatokat'),
                                    content: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: warnings
                                          .map((issue) => Padding(
                                                padding: const EdgeInsets.only(
                                                    bottom: 8),
                                                child:
                                                    Text('• ${issue.message}'),
                                              ))
                                          .toList(),
                                    ),
                                    actions: [
                                      TextButton(
                                          onPressed: () => Navigator.pop(
                                              dialogContext, false),
                                          child: Text(l10n.cancel)),
                                      FilledButton(
                                          onPressed: () => Navigator.pop(
                                              dialogContext, true),
                                          child: Text(l10n.saveAnyway)),
                                    ],
                                  ),
                                );
                                if (proceed != true) return;
                              }
                              final saved = service.finishRecording(
                                  nameController.text, descController.text,
                                  templateName: selectedTemplate?.nameKey,
                                  customData: templateData);
                              if (saved && ctx.mounted) Navigator.pop(ctx);
                            }
                          : null,
                      child: Text(canSave
                          ? l10n.save
                          : l10n.waitingStableFix(gnss
                              .ntripSettings.stabilityThresholdSeconds
                              .toString()))),
                ],
              );
            }),
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
                SkyplotWidget(
                    satellites: gnss.currentStatus.satellites, size: 250),
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
                Text(l10n.satUsedLegend,
                    style: const TextStyle(fontSize: 10, color: Colors.grey)),
              ],
            );
          },
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(l10n.close)),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
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
        initialValue: initialValue,
        decoration: InputDecoration(labelText: label),
        items: choices
            .map((c) => DropdownMenuItem(value: c, child: Text(c)))
            .toList(),
        onChanged: onChanged,
      );
    } else if (type == FieldType.date || type == FieldType.dateTime) {
      final dt = initialValue is DateTime
          ? initialValue
          : (initialValue != null
              ? DateTime.tryParse(initialValue.toString())
              : null);
      final format = type == FieldType.date
          ? DateFormat('yyyy-MM-dd')
          : DateFormat('yyyy-MM-dd HH:mm');
      return ListTile(
        title: Text(label),
        subtitle: Text(dt != null ? format.format(dt) : "Nincs kiválasztva"),
        trailing: const Icon(Icons.calendar_today),
        onTap: () async {
          final date = await showDatePicker(
              context: context,
              initialDate: dt ?? DateTime.now(),
              firstDate: DateTime(2000),
              lastDate: DateTime(2100));
          if (date != null) {
            if (type == FieldType.dateTime) {
              if (!context.mounted) return;
              final time = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay.fromDateTime(dt ?? DateTime.now()));
              if (time != null) {
                onChanged(DateTime(
                    date.year, date.month, date.day, time.hour, time.minute));
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
        keyboardType: (type == FieldType.integer || type == FieldType.decimal)
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        controller: TextEditingController(text: initialValue?.toString() ?? ""),
        onChanged: (val) {
          if (type == FieldType.integer) {
            onChanged(int.tryParse(val));
          } else if (type == FieldType.decimal) {
            onChanged(double.tryParse(val));
          } else {
            onChanged(val);
          }
        },
      );
    }
  }

  void _showAddCustomFieldDialog(BuildContext context, ProjectService service,
      StateSetter setDialogState) {
    final nameCtrl = TextEditingController();
    FieldType selectedType = FieldType.text;
    bool isRequired = false;
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
                initialValue: selectedType,
                decoration: const InputDecoration(labelText: "Mező típusa"),
                items: FieldType.values
                    .map((t) => DropdownMenuItem(value: t, child: Text(t.name)))
                    .toList(),
                onChanged: (val) => setState(() => selectedType = val!),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Kötelező mező'),
                value: isRequired,
                onChanged: (value) => setState(() => isRequired = value),
              ),
              if (selectedType == FieldType.choice) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: choicesCtrl,
                  decoration: const InputDecoration(
                      labelText: "Opciók (vesszővel elválasztva)",
                      hintText: "A, B, C"),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: Text(l10n.cancel)),
            ElevatedButton(
              onPressed: () {
                if (nameCtrl.text.isNotEmpty && service.activeLayer != null) {
                  final key = CustomFieldDefinition.normalizeKey(nameCtrl.text);
                  List<String>? choices;
                  if (selectedType == FieldType.choice &&
                      choicesCtrl.text.isNotEmpty) {
                    choices = choicesCtrl.text
                        .split(',')
                        .map((e) => e.trim())
                        .toList();
                  }

                  service.addCustomFieldToLayer(
                      service.activeLayer!,
                      CustomFieldDefinition(
                        key: key,
                        label: nameCtrl.text,
                        type: selectedType,
                        choices: choices,
                        isRequired: isRequired,
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

    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
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
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (feature.description.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12.0),
                          child: Text(feature.description,
                              style: const TextStyle(
                                  fontStyle: FontStyle.italic,
                                  color: Colors.blueGrey)),
                        ),

                      // --- SECTION: POSITION ---
                      _buildDetailSection(Icons.location_on, "POSITION", [
                        if (feature.calculatedStats.containsKey('EOV X'))
                          _buildDetailRow("EOV X",
                              feature.calculatedStats['EOV X'].toString()),
                        if (feature.calculatedStats.containsKey('EOV Y'))
                          _buildDetailRow("EOV Y",
                              feature.calculatedStats['EOV Y'].toString()),
                        if (feature.calculatedStats
                            .containsKey('Ellipszoidi magasság'))
                          _buildDetailRow("Ell. H",
                              "${feature.calculatedStats['Ellipszoidi magasság']} m"),
                        if (feature.calculatedStats
                            .containsKey('Balti magasság'))
                          _buildDetailRow("Baltic H",
                              "${feature.calculatedStats['Balti magasság']} m"),
                        if (feature.type != FeatureType.point &&
                            feature.calculatedStats.containsKey('Hossz'))
                          _buildDetailRow(
                              "Length", feature.calculatedStats['Hossz']),
                        if (feature.type == FeatureType.polygon &&
                            feature.calculatedStats.containsKey('Terület'))
                          _buildDetailRow(
                              "Area", feature.calculatedStats['Terület']),
                      ]),

                      // --- SECTION: SURVEY PROVENANCE ---
                      _buildDetailSection(Icons.verified_user, "SURVEY", [
                        _buildDetailRow(
                            "Method",
                            feature.calculatedStats['Survey Method'] ??
                                "IMPORTED"),
                        if (feature.calculatedStats.containsKey('GNSS Source'))
                          _buildDetailRow(
                              "Source", feature.calculatedStats['GNSS Source']),
                        if (feature.calculatedStats.containsKey('RTK Status'))
                          _buildDetailRow(
                              "RTK", feature.calculatedStats['RTK Status']),
                        if (feature.calculatedStats.containsKey('NTRIP Active'))
                          _buildDetailRow(
                              "NTRIP", feature.calculatedStats['NTRIP Active']),
                        if (feature.calculatedStats
                            .containsKey('Correction Age'))
                          _buildDetailRow("Age",
                              "${feature.calculatedStats['Correction Age']} s"),
                      ]),

                      // --- SECTION: GNSS QUALITY ---
                      if (feature.calculatedStats.containsKey('HDOP') ||
                          feature.calculatedStats.containsKey('Sats Used'))
                        _buildDetailSection(Icons.satellite_alt, "GNSS", [
                          if (feature.calculatedStats.containsKey('Receiver'))
                            _buildDetailRow("Receiver",
                                feature.calculatedStats['Receiver']),
                          if (feature.calculatedStats.containsKey('Sats Used'))
                            _buildDetailRow(
                                "Satellites",
                                feature.calculatedStats['Sats Used']
                                    .toString()),
                          if (feature.calculatedStats.containsKey('HDOP'))
                            _buildDetailRow("HDOP",
                                feature.calculatedStats['HDOP'].toString()),
                          if (feature.calculatedStats.containsKey('VDOP'))
                            _buildDetailRow("VDOP",
                                feature.calculatedStats['VDOP'].toString()),
                          if (feature.calculatedStats.containsKey('PDOP'))
                            _buildDetailRow("PDOP",
                                feature.calculatedStats['PDOP'].toString()),
                          if (feature.calculatedStats.containsKey('Station ID'))
                            _buildDetailRow("Station ID",
                                feature.calculatedStats['Station ID']),
                        ]),

                      // --- SECTION: TIME ---
                      _buildDetailSection(Icons.access_time, "TIME", [
                        _buildDetailRow(
                            "Timestamp",
                            DateFormat('yyyy-MM-dd HH:mm:ss')
                                .format(feature.createdAt)),
                        if (feature.calculatedStats
                            .containsKey('Timestamp Source'))
                          _buildDetailRow("Source",
                              feature.calculatedStats['Timestamp Source']),
                      ]),

                      // --- SECTION: CUSTOM ATTRIBUTES ---
                      if (feature.customData.isNotEmpty)
                        _buildDetailSection(Icons.list_alt, "ATTRIBUTES", [
                          if (feature.templateName != null &&
                              feature.templateName != "templateGeneral")
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8.0),
                              child: Text(
                                  "${l10n.templateLabel}: ${_getLocalizedTemplateName(feature.templateName!)}",
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                      color: Colors.blue)),
                            ),
                          ...feature.customData.entries.map((e) {
                            CustomFieldDefinition? customDef;
                            if (service.activeLayer != null) {
                              customDef = service.activeLayer!.fields
                                  .firstWhere((f) => f.key == e.key,
                                      orElse: () => CustomFieldDefinition(
                                          key: e.key,
                                          label: e.key,
                                          type: FieldType.text));
                            }
                            final fieldDef = template?.fields.firstWhere(
                                (f) => f.key == e.key,
                                orElse: () => FieldDefinition(
                                    labelKey: customDef?.label ?? e.key,
                                    key: e.key,
                                    type: customDef?.type ?? FieldType.text));
                            String displayValue = e.value is DateTime
                                ? DateFormat('yyyy-MM-dd HH:mm').format(e.value)
                                : e.value.toString();
                            return _buildDetailRow(
                                _getLocalizedFieldLabel(
                                    fieldDef?.labelKey ?? e.key),
                                displayValue);
                          }),
                        ]),

                      if (feature.photos.isNotEmpty) ...[
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8.0),
                          child: Text("PHOTOS",
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey,
                                  letterSpacing: 1.2)),
                        ),
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 3,
                                  crossAxisSpacing: 5,
                                  mainAxisSpacing: 5),
                          itemCount: feature.photos.length,
                          itemBuilder: (ctx, i) => GestureDetector(
                            onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) =>
                                        ImageViewer(path: feature.photos[i]))),
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
                                    child: const Icon(Icons.broken_image,
                                        color: Colors.grey),
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
                if (feature.geometry.isNotEmpty)
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _showVertexEditor(feature);
                    },
                    icon: const Icon(Icons.control_point),
                    label: const Text('Csúcsok'),
                  ),
                TextButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _showOffsetDialog(feature);
                  },
                  icon: const Icon(Icons.open_with),
                  label: const Text('Eltolás / buffer'),
                ),
                TextButton(
                    onPressed: () {
                      context.read<ProjectService>().deleteFeature(feature.id);
                      Navigator.pop(ctx);
                    },
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                    child: Text(l10n.delete)),
                if (feature.type == FeatureType.point)
                  ElevatedButton.icon(
                    onPressed: () {
                      setState(() => _stakeoutTarget = feature);
                      Navigator.pop(ctx);
                    },
                    icon: const Icon(Icons.explore),
                    label: Text(l10n.stakeout),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white),
                  ),
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(l10n.close)),
              ],
            ));
  }

  void _showVertexEditor(GeoFeature feature) {
    final service = context.read<ProjectService>();
    final eovService = context.read<EovService>();
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Csúcspontok · ${feature.name}'),
        content: SizedBox(
          width: 420,
          height: 380,
          child: Column(
            children: [
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: feature.geometry.length,
                  itemBuilder: (context, index) {
                    final point = feature.geometry[index];
                    final double alt = index < feature.altitudes.length
                        ? feature.altitudes[index]
                        : 0.0;
                    final eov =
                        eovService.wgsToEov(point.latitude, point.longitude);
                    final double eovY = eov[0]; // Easting ~ 650,000 m
                    final double eovX = eov[1]; // Northing ~ 200,000 m

                    return ListTile(
                      dense: true,
                      leading: CircleAvatar(
                          radius: 12,
                          child: Text('${index + 1}',
                              style: const TextStyle(fontSize: 10))),
                      title: Text(
                          'EOV Y: ${eovY.toStringAsFixed(2)} m, X: ${eovX.toStringAsFixed(2)} m'),
                      subtitle: Text(
                          'Lat: ${point.latitude.toStringAsFixed(6)}, Lon: ${point.longitude.toStringAsFixed(6)}, H: ${alt.toStringAsFixed(2)} m'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_location_alt,
                                size: 20, color: Colors.blue),
                            tooltip: 'Szerkesztés / Mozgatás',
                            onPressed: () {
                              int mode = 0; // 0: EOV, 1: WGS84
                              final eovYCtrl = TextEditingController(
                                  text: eovY.toStringAsFixed(2));
                              final eovXCtrl = TextEditingController(
                                  text: eovX.toStringAsFixed(2));
                              final latCtrl = TextEditingController(
                                  text: point.latitude.toStringAsFixed(7));
                              final lonCtrl = TextEditingController(
                                  text: point.longitude.toStringAsFixed(7));
                              final altCtrl = TextEditingController(
                                  text: alt.toStringAsFixed(2));

                              showDialog<void>(
                                context: dialogContext,
                                builder: (vertexContext) => StatefulBuilder(
                                  builder: (vCtx, setVertexState) =>
                                      AlertDialog(
                                    title: Text(
                                        '${index + 1}. csúcspont szerkesztése'),
                                    content: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        SegmentedButton<int>(
                                          segments: const [
                                            ButtonSegment(
                                                value: 0,
                                                label: Text('EOV (Y, X)')),
                                            ButtonSegment(
                                                value: 1,
                                                label:
                                                    Text('WGS84 (Lat, Lon)')),
                                          ],
                                          selected: {mode},
                                          onSelectionChanged: (s) =>
                                              setVertexState(
                                                  () => mode = s.first),
                                        ),
                                        const SizedBox(height: 12),
                                        if (mode == 0) ...[
                                          TextField(
                                            controller: eovYCtrl,
                                            keyboardType: const TextInputType
                                                .numberWithOptions(
                                                decimal: true, signed: true),
                                            decoration: const InputDecoration(
                                                labelText: 'EOV Y / Keleti (m)',
                                                helperText: 'pl. 654321.50'),
                                          ),
                                          TextField(
                                            controller: eovXCtrl,
                                            keyboardType: const TextInputType
                                                .numberWithOptions(
                                                decimal: true, signed: true),
                                            decoration: const InputDecoration(
                                                labelText: 'EOV X / Északi (m)',
                                                helperText: 'pl. 234567.80'),
                                          ),
                                        ] else ...[
                                          TextField(
                                            controller: latCtrl,
                                            keyboardType: const TextInputType
                                                .numberWithOptions(
                                                decimal: true, signed: true),
                                            decoration: const InputDecoration(
                                                labelText: 'Szélesség / Lat',
                                                helperText: 'pl. 47.4979'),
                                          ),
                                          TextField(
                                            controller: lonCtrl,
                                            keyboardType: const TextInputType
                                                .numberWithOptions(
                                                decimal: true, signed: true),
                                            decoration: const InputDecoration(
                                                labelText: 'Hosszúság / Lon',
                                                helperText: 'pl. 19.0402'),
                                          ),
                                        ],
                                        TextField(
                                          controller: altCtrl,
                                          keyboardType: const TextInputType
                                              .numberWithOptions(
                                              decimal: true, signed: true),
                                          decoration: const InputDecoration(
                                              labelText: 'Magasság (m)'),
                                        ),
                                      ],
                                    ),
                                    actions: [
                                      TextButton(
                                          onPressed: () =>
                                              Navigator.pop(vertexContext),
                                          child: const Text('Mégse')),
                                      FilledButton(
                                        onPressed: () {
                                          final altitude = double.tryParse(
                                                  altCtrl.text
                                                      .replaceAll(',', '.')) ??
                                              alt;
                                          double? targetLat;
                                          double? targetLon;

                                          if (mode == 0) {
                                            final parsedY = double.tryParse(
                                                eovYCtrl.text
                                                    .replaceAll(',', '.'));
                                            final parsedX = double.tryParse(
                                                eovXCtrl.text
                                                    .replaceAll(',', '.'));
                                            if (parsedY == null ||
                                                parsedX == null) return;
                                            final wgs = eovService.eovToWgs(
                                                parsedY, parsedX);
                                            targetLat = wgs[0];
                                            targetLon = wgs[1];
                                          } else {
                                            var parsedLat = double.tryParse(
                                                latCtrl.text
                                                    .replaceAll(',', '.'));
                                            var parsedLon = double.tryParse(
                                                lonCtrl.text
                                                    .replaceAll(',', '.'));
                                            if (parsedLat == null ||
                                                parsedLon == null) return;
                                            if (parsedLat > 10000 &&
                                                parsedLon > 10000) {
                                              final eovYVal =
                                                  parsedLat > parsedLon
                                                      ? parsedLat
                                                      : parsedLon;
                                              final eovXVal =
                                                  parsedLat < parsedLon
                                                      ? parsedLat
                                                      : parsedLon;
                                              final wgs = eovService.eovToWgs(
                                                  eovYVal, eovXVal);
                                              targetLat = wgs[0];
                                              targetLon = wgs[1];
                                            } else {
                                              targetLat = parsedLat;
                                              targetLon = parsedLon;
                                            }
                                          }

                                          if (targetLat.abs() > 90 ||
                                              targetLon.abs() > 180) return;

                                          service.updateFeatureVertex(
                                              feature,
                                              index,
                                              LatLng(targetLat, targetLon),
                                              altitude: altitude);
                                          Navigator.pop(vertexContext);
                                          Navigator.pop(dialogContext);
                                          _showVertexEditor(feature);
                                        },
                                        child: const Text('Mentés'),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline,
                                size: 20, color: Colors.red),
                            tooltip: 'Csúcspont törlése',
                            onPressed: () {
                              try {
                                service.deleteFeatureVertex(feature, index);
                                Navigator.pop(dialogContext);
                                _showVertexEditor(feature);
                              } catch (e) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text(e
                                          .toString()
                                          .replaceAll("Exception: ", "")),
                                      backgroundColor: Colors.red),
                                );
                              }
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const Divider(),
              OutlinedButton.icon(
                icon: const Icon(Icons.add_location_alt),
                label: const Text('Új csúcspont beszúrása'),
                onPressed: () {
                  final lastPt = feature.geometry.last;
                  final lastEov =
                      eovService.wgsToEov(lastPt.latitude, lastPt.longitude);
                  final eovYCtrl = TextEditingController(
                      text: (lastEov[0] + 5.0).toStringAsFixed(2));
                  final eovXCtrl = TextEditingController(
                      text: (lastEov[1] + 5.0).toStringAsFixed(2));
                  final altCtrl = TextEditingController(
                      text: (feature.altitudes.isNotEmpty
                              ? feature.altitudes.last
                              : 0.0)
                          .toStringAsFixed(2));

                  showDialog<void>(
                    context: dialogContext,
                    builder: (addCtx) => AlertDialog(
                      title: const Text('Új csúcspont hozzáadása'),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextField(
                              controller: eovYCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true, signed: true),
                              decoration: const InputDecoration(
                                  labelText: 'EOV Y / Keleti (m)')),
                          TextField(
                              controller: eovXCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true, signed: true),
                              decoration: const InputDecoration(
                                  labelText: 'EOV X / Északi (m)')),
                          TextField(
                              controller: altCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true, signed: true),
                              decoration: const InputDecoration(
                                  labelText: 'Magasság (m)')),
                        ],
                      ),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(addCtx),
                            child: const Text('Mégse')),
                        FilledButton(
                          onPressed: () {
                            final parsedY = double.tryParse(
                                eovYCtrl.text.replaceAll(',', '.'));
                            final parsedX = double.tryParse(
                                eovXCtrl.text.replaceAll(',', '.'));
                            final parsedAlt = double.tryParse(
                                    altCtrl.text.replaceAll(',', '.')) ??
                                0.0;
                            if (parsedY == null || parsedX == null) return;
                            final wgs = eovService.eovToWgs(parsedY, parsedX);
                            service.insertFeatureVertex(feature,
                                feature.geometry.length, LatLng(wgs[0], wgs[1]),
                                altitude: parsedAlt);
                            Navigator.pop(addCtx);
                            Navigator.pop(dialogContext);
                            _showVertexEditor(feature);
                          },
                          child: const Text('Hozzáadás'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(l10n.close))
        ],
      ),
    );
  }

  void _showOffsetDialog(GeoFeature feature) {
    final distance = TextEditingController(text: '1.00');
    final service = context.read<ProjectService>();
    final isBuffer = feature.type == FeatureType.point;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title:
            Text(isBuffer ? 'Pont buffer létrehozása' : 'Párhuzamos eltolás'),
        content: TextField(
          controller: distance,
          keyboardType: const TextInputType.numberWithOptions(
              decimal: true, signed: true),
          decoration: const InputDecoration(
              labelText: 'Távolság (m)',
              helperText: 'Előjeles értékkel az eltolás iránya választható.'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(l10n.cancel)),
          FilledButton(
            onPressed: () {
              final value = double.tryParse(distance.text.replaceAll(',', '.'));
              if (value == null || value == 0) return;
              service.createOffsetFeature(
                  feature, isBuffer ? value.abs() : value,
                  buffer: isBuffer);
              Navigator.pop(dialogContext);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(isBuffer
                      ? 'Buffer objektum létrehozva.'
                      : 'Párhuzamos eltolás létrehozva.'),
                  backgroundColor: Colors.green,
                ),
              );
            },
            child: const Text('Létrehozás'),
          ),
        ],
      ),
    );
  }

  void _showQuickDistanceDialog() {
    final service = context.read<ProjectService>();
    final eovService = context.read<EovService>();

    final allPoints = service.visibleFeatures
        .where((f) => f.type == FeatureType.point && f.geometry.isNotEmpty)
        .toList();

    GeoFeature? selectedA = allPoints.isNotEmpty ? allPoints.first : null;
    GeoFeature? selectedB = allPoints.length >= 2 ? allPoints[1] : null;

    final y1Ctrl = TextEditingController();
    final x1Ctrl = TextEditingController();
    final h1Ctrl = TextEditingController();

    final y2Ctrl = TextEditingController();
    final x2Ctrl = TextEditingController();
    final h2Ctrl = TextEditingController();

    void updateFromFeatures() {
      if (selectedA != null && selectedA!.geometry.isNotEmpty) {
        final pt = selectedA!.geometry.first;
        final eov = eovService.wgsToEov(pt.latitude, pt.longitude);
        y1Ctrl.text = eov[0].toStringAsFixed(2);
        x1Ctrl.text = eov[1].toStringAsFixed(2);
        h1Ctrl.text =
            (selectedA!.altitudes.isNotEmpty ? selectedA!.altitudes.first : 0.0)
                .toStringAsFixed(2);
      }
      if (selectedB != null && selectedB!.geometry.isNotEmpty) {
        final pt = selectedB!.geometry.first;
        final eov = eovService.wgsToEov(pt.latitude, pt.longitude);
        y2Ctrl.text = eov[0].toStringAsFixed(2);
        x2Ctrl.text = eov[1].toStringAsFixed(2);
        h2Ctrl.text =
            (selectedB!.altitudes.isNotEmpty ? selectedB!.altitudes.first : 0.0)
                .toStringAsFixed(2);
      }
    }

    updateFromFeatures();

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final y1 = double.tryParse(y1Ctrl.text.replaceAll(',', '.')) ?? 0.0;
          final x1 = double.tryParse(x1Ctrl.text.replaceAll(',', '.')) ?? 0.0;
          final h1 = double.tryParse(h1Ctrl.text.replaceAll(',', '.')) ?? 0.0;

          final y2 = double.tryParse(y2Ctrl.text.replaceAll(',', '.')) ?? 0.0;
          final x2 = double.tryParse(x2Ctrl.text.replaceAll(',', '.')) ?? 0.0;
          final h2 = double.tryParse(h2Ctrl.text.replaceAll(',', '.')) ?? 0.0;

          final dy = y2 - y1;
          final dx = x2 - x1;
          final dh = h2 - h1;

          final planeDist = sqrt(dy * dy + dx * dx);
          final slopeDist = sqrt(dy * dy + dx * dx + dh * dh);

          double angleDeg = atan2(dy, dx) * 180 / pi;
          double wcb = (90 - angleDeg + 360) % 360;

          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.straighten, color: Colors.blue),
                SizedBox(width: 8),
                Expanded(
                  child: Text('Két pont közötti távolságmérés',
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (allPoints.isNotEmpty) ...[
                    const Text('1. Pont (P1) kiválasztása:',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 12)),
                    DropdownButton<GeoFeature>(
                      isExpanded: true,
                      value: selectedA,
                      items: allPoints
                          .map((f) =>
                              DropdownMenuItem(value: f, child: Text(f.name)))
                          .toList(),
                      onChanged: (val) {
                        setDialogState(() {
                          selectedA = val;
                          updateFromFeatures();
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    const Text('2. Pont (P2) kiválasztása:',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 12)),
                    DropdownButton<GeoFeature>(
                      isExpanded: true,
                      value: selectedB,
                      items: allPoints
                          .map((f) =>
                              DropdownMenuItem(value: f, child: Text(f.name)))
                          .toList(),
                      onChanged: (val) {
                        setDialogState(() {
                          selectedB = val;
                          updateFromFeatures();
                        });
                      },
                    ),
                    const Divider(height: 24),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: y1Ctrl,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true, signed: true),
                          decoration:
                              const InputDecoration(labelText: 'P1 EOV Y (m)'),
                          onChanged: (_) => setDialogState(() {}),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: x1Ctrl,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true, signed: true),
                          decoration:
                              const InputDecoration(labelText: 'P1 EOV X (m)'),
                          onChanged: (_) => setDialogState(() {}),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: y2Ctrl,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true, signed: true),
                          decoration:
                              const InputDecoration(labelText: 'P2 EOV Y (m)'),
                          onChanged: (_) => setDialogState(() {}),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: x2Ctrl,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true, signed: true),
                          decoration:
                              const InputDecoration(labelText: 'P2 EOV X (m)'),
                          onChanged: (_) => setDialogState(() {}),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8)),
                    child: Column(
                      children: [
                        _buildMeasureResultRow('Síkbeli (EOV) Távolság:',
                            '${planeDist.toStringAsFixed(3)} m',
                            isBold: true, color: Colors.blue.shade900),
                        _buildMeasureResultRow('Térbeli Távolság:',
                            '${slopeDist.toStringAsFixed(3)} m'),
                        _buildMeasureResultRow(
                            'Irányszög (WCB):', '${wcb.toStringAsFixed(4)}°',
                            color: Colors.deepOrange),
                        _buildMeasureResultRow('ΔY (Keleti eltérés):',
                            '${dy.toStringAsFixed(3)} m'),
                        _buildMeasureResultRow('ΔX (Északi eltérés):',
                            '${dx.toStringAsFixed(3)} m'),
                        _buildMeasureResultRow('ΔH (Magasságkülönbség):',
                            '${dh.toStringAsFixed(3)} m'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Bezárás')),
            ],
          );
        },
      ),
    );
  }

  Widget _buildMeasureResultRow(String label, String value,
      {bool isBold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(value,
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
                    color: color ?? Colors.black87)),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveMeasurementHUD(ProjectService service) {
    final pts = service.currentGeometry;
    if (pts.isEmpty) return const SizedBox.shrink();

    double totalDist = 0.0;
    double? lastDist;
    double? lastBearing;
    const distanceCalc = Distance();

    for (int i = 0; i < pts.length - 1; i++) {
      totalDist += distanceCalc.as(LengthUnit.Meter, pts[i], pts[i + 1]);
    }

    if (pts.length >= 2) {
      final p1 = pts[pts.length - 2];
      final p2 = pts.last;
      lastDist = distanceCalc.as(LengthUnit.Meter, p1, p2);

      final lat1 = p1.latitude * pi / 180;
      final lat2 = p2.latitude * pi / 180;
      final dLon = (p2.longitude - p1.longitude) * pi / 180;
      final y = sin(dLon) * cos(lat2);
      final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);
      lastBearing = (atan2(y, x) * 180 / pi + 360) % 360;
    }

    double? areaM2;
    if (service.activeTool == FeatureType.polygon && pts.length >= 3) {
      areaM2 = service.calculatePolygonArea(pts);
    }

    final topPadding = MediaQuery.of(context).padding.top;

    return Positioned(
      top: topPadding + 65,
      left: 16,
      right: 16,
      child: Card(
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        color: Colors.white.withValues(alpha: 0.95),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              if (pts.length >= 2) ...[
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text("Összhossz",
                        style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey,
                            fontWeight: FontWeight.bold)),
                    Text(
                      totalDist > 1000
                          ? "${(totalDist / 1000).toStringAsFixed(3)} km"
                          : "${totalDist.toStringAsFixed(2)} m",
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue),
                    ),
                  ],
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text("Szakasz",
                        style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey,
                            fontWeight: FontWeight.bold)),
                    Text(
                      "${lastDist!.toStringAsFixed(2)} m",
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87),
                    ),
                  ],
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text("Irányszög",
                        style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey,
                            fontWeight: FontWeight.bold)),
                    Text(
                      "${lastBearing!.toStringAsFixed(1)}°",
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.deepOrange),
                    ),
                  ],
                ),
              ] else ...[
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text("Mért pontok",
                        style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey,
                            fontWeight: FontWeight.bold)),
                    Text("${pts.length} db",
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
              if (areaM2 != null) ...[
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text("Terület",
                        style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey,
                            fontWeight: FontWeight.bold)),
                    Text(
                      areaM2 > 10000
                          ? "${(areaM2 / 10000).toStringAsFixed(3)} ha"
                          : "${areaM2.toStringAsFixed(1)} m²",
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.green),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailSection(
      IconData icon, String title, List<Widget> children) {
    if (children.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: Colors.grey),
            const SizedBox(width: 8),
            Text(title,
                style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                    letterSpacing: 1.2)),
          ],
        ),
        const Divider(height: 12),
        ...children,
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 110,
              child: Text("$label:",
                  style: const TextStyle(fontSize: 12, color: Colors.grey))),
          Expanded(
              child: Text(value,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }

  Widget _buildQualityIndicator(double score) {
    Color color = Colors.red;
    if (score > 70) {
      color = Colors.green;
    } else if (score > 40) {
      color = Colors.orange;
    }

    return Container(
      width: 40,
      height: 40,
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
              style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.bold, color: color),
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
    final timeStr =
        "${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}";
    final nameCtrl = TextEditingController(text: l10n.measurementTime(timeStr));
    final notesCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.ppkStartTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: nameCtrl,
                decoration: InputDecoration(labelText: l10n.ppkNameLabel)),
            TextField(
                controller: notesCtrl,
                decoration: InputDecoration(labelText: l10n.ppkNotesLabel)),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(l10n.cancel)),
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

  void _showExportDialog(ProjectService service, Project project, Rect? origin,
      {ProjectLayer? initialLayer}) {
    showDialog(
      context: context,
      builder: (ctx) => ExportConfigDialog(
        project: project,
        initialLayer: initialLayer,
        sharePositionOrigin: origin,
        initialSelection: initialLayer?.features
            .where((f) => service.selectedFeatureIds.contains(f.id))
            .toList(),
      ),
    );
  }

  void _showFeatureEditDialog(GeoFeature feature) {
    final service = context.read<ProjectService>();
    final eovService = context.read<EovService>();
    final tSvc = context.read<TemplateService>();
    final template = tSvc.getTemplateByNameKey(feature.templateName);

    final nameCtrl = TextEditingController(text: feature.name);
    final descCtrl = TextEditingController(text: feature.description);

    TextEditingController? eovYCtrl;
    TextEditingController? eovXCtrl;
    TextEditingController? altCtrl;

    if (feature.type == FeatureType.point && feature.geometry.isNotEmpty) {
      final pt = feature.geometry.first;
      final eov = eovService.wgsToEov(pt.latitude, pt.longitude);
      final alt = feature.altitudes.isNotEmpty ? feature.altitudes.first : 0.0;
      eovYCtrl = TextEditingController(text: eov[0].toStringAsFixed(2));
      eovXCtrl = TextEditingController(text: eov[1].toStringAsFixed(2));
      altCtrl = TextEditingController(text: alt.toStringAsFixed(2));
    }

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
                TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: "Név")),
                TextField(
                    controller: descCtrl,
                    decoration: const InputDecoration(labelText: "Leírás")),
                if (feature.type == FeatureType.point &&
                    eovYCtrl != null &&
                    eovXCtrl != null &&
                    altCtrl != null) ...[
                  const Divider(height: 30),
                  const Text("Koordináták (EOV)",
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: Colors.grey)),
                  const SizedBox(height: 8),
                  TextField(
                      controller: eovYCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true, signed: true),
                      decoration: const InputDecoration(
                          labelText: "EOV Y / Keleti (m)")),
                  TextField(
                      controller: eovXCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true, signed: true),
                      decoration: const InputDecoration(
                          labelText: "EOV X / Északi (m)")),
                  TextField(
                      controller: altCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true, signed: true),
                      decoration:
                          const InputDecoration(labelText: "Magasság (m)")),
                ],
                const Divider(height: 30),

                // Sablon mezők (ha vannak)
                if (template != null)
                  ...template.fields.map((field) {
                    return _buildFieldInput(
                      context: context,
                      label: _getLocalizedFieldLabel(field.labelKey),
                      type: field.type,
                      choices: field.optionKeys,
                      initialValue: editData[field.key],
                      onChanged: (val) =>
                          setDialogState(() => editData[field.key] = val),
                    );
                  }),

                // Réteg egyedi mezői
                if (service.activeLayer != null)
                  ...service.activeLayer!.fields.map((fDef) {
                    return _buildFieldInput(
                      context: context,
                      label: fDef.label,
                      type: fDef.type,
                      choices: fDef.choices,
                      initialValue: editData[fDef.key],
                      onChanged: (val) =>
                          setDialogState(() => editData[fDef.key] = val),
                    );
                  }),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: Text(l10n.cancel)),
            ElevatedButton(
                onPressed: () async {
                  final draft = GeoFeature(
                    id: feature.id,
                    name: nameCtrl.text,
                    description: descCtrl.text,
                    type: feature.type,
                    geometry: List<LatLng>.from(feature.geometry),
                    customData: Map<String, dynamic>.from(editData),
                  );
                  final layer = service.activeLayer;
                  final issues = const DataValidationService().validateFeature(
                    feature: draft,
                    fields: layer?.fields ?? const [],
                    crsInfo: layer?.crsInfo,
                  );
                  final errors = issues
                      .where(
                          (issue) => issue.severity == ValidationSeverity.error)
                      .toList();
                  if (errors.isNotEmpty) {
                    await showDialog<void>(
                      context: ctx,
                      builder: (dialogContext) => AlertDialog(
                        title: const Text('Az objektum nem menthető'),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: errors
                              .map((issue) => Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Text('• ${issue.message}'),
                                  ))
                              .toList(),
                        ),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(dialogContext),
                              child: const Text('Rendben'))
                        ],
                      ),
                    );
                    return;
                  }
                  if (feature.type == FeatureType.point &&
                      eovYCtrl != null &&
                      eovXCtrl != null &&
                      feature.geometry.isNotEmpty) {
                    final parsedY =
                        double.tryParse(eovYCtrl.text.replaceAll(',', '.'));
                    final parsedX =
                        double.tryParse(eovXCtrl.text.replaceAll(',', '.'));
                    final parsedAlt = double.tryParse(
                        altCtrl?.text.replaceAll(',', '.') ?? '');
                    if (parsedY != null && parsedX != null) {
                      final wgs = eovService.eovToWgs(parsedY, parsedX);
                      if (wgs[0].abs() <= 90 && wgs[1].abs() <= 180) {
                        feature.geometry[0] = LatLng(wgs[0], wgs[1]);
                        if (parsedAlt != null) {
                          if (feature.altitudes.isNotEmpty) {
                            feature.altitudes[0] = parsedAlt;
                          } else {
                            feature.altitudes.add(parsedAlt);
                          }
                        }
                      }
                    }
                  }
                  service.updateFeatureCustomData(feature.id, editData,
                      name: nameCtrl.text, description: descCtrl.text);
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: Text(l10n.save)),
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
        builder: (ctx) => StatefulBuilder(builder: (context, setDialogState) {
              final activeProject = service.activeProject;

              return AlertDialog(
                title: Row(
                  children: [
                    const Icon(Icons.layers, color: Colors.blue),
                    const SizedBox(width: 10),
                    Text(l10n.projectsLayers),
                  ],
                ),
                content: SizedBox(
                  width: double.maxFinite,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // --- NEW ELEMENT SECTION ---
                      Row(children: [
                        Expanded(
                            child: TextField(
                                controller: nameCtrl,
                                decoration: InputDecoration(
                                    hintText: "${l10n.name}...",
                                    isDense: true))),
                        IconButton(
                            icon: const Icon(Icons.add_circle,
                                color: Colors.blue),
                            onPressed: () {
                              if (nameCtrl.text.isEmpty) return;
                              if (activeProject == null) {
                                service.createProject(nameCtrl.text);
                                nameCtrl.clear();
                                setDialogState(() {});
                              } else {
                                showDialog(
                                    context: context,
                                    builder: (c) {
                                      LayerCrs selectedCrs = LayerCrs.wgs84;
                                      return StatefulBuilder(
                                        builder: (context, setCrsState) =>
                                            AlertDialog(
                                          title: Text(l10n.newElement),
                                          content: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                  "${l10n.createWhat}: '${nameCtrl.text}'?"),
                                              const SizedBox(height: 12),
                                              DropdownButtonFormField<LayerCrs>(
                                                value: selectedCrs,
                                                isExpanded: true,
                                                decoration:
                                                    const InputDecoration(
                                                  labelText:
                                                      'Réteg koordinátarendszere',
                                                  border:
                                                      OutlineInputBorder(),
                                                ),
                                                items: LayerCrs.values
                                                    .map((crs) =>
                                                        DropdownMenuItem(
                                                          value: crs,
                                                          child: Text(crs.label),
                                                        ))
                                                    .toList(),
                                                onChanged: (value) {
                                                  if (value != null) {
                                                    setCrsState(() =>
                                                        selectedCrs = value);
                                                  }
                                                },
                                              ),
                                              const SizedBox(height: 8),
                                              const Text(
                                                'A térképi megjelenítés WGS84-ben történik; exportnál a kiválasztott CRS lesz használva.',
                                                style: TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.grey),
                                              ),
                                            ],
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(c),
                                              child: Text(l10n.cancel),
                                            ),
                                            TextButton(
                                              onPressed: () {
                                                service.createProject(
                                                    nameCtrl.text);
                                                nameCtrl.clear();
                                                Navigator.pop(c);
                                                setDialogState(() {});
                                              },
                                              child: Text(l10n.newProject),
                                            ),
                                            ElevatedButton(
                                              onPressed: () {
                                                service.createLayer(
                                                  nameCtrl.text,
                                                  coordinateCrs: selectedCrs,
                                                );
                                                nameCtrl.clear();
                                                Navigator.pop(c);
                                                setDialogState(() {});
                                              },
                                              child: Text(l10n.newLayer),
                                            ),
                                          ],
                                        ),
                                      );
                                    });
                              }
                            })
                      ]),
                      const Divider(),

                      // --- LAYERS OF ACTIVE PROJECT ---
                      if (activeProject != null) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text("${l10n.activeProject}: ${activeProject.name}",
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blueGrey)),
                            TextButton(
                                onPressed: () => setDialogState(() => service
                                    .selectProject(service.projects.firstWhere(
                                        (p) => p.id != activeProject.id,
                                        orElse: () => activeProject))),
                                child: const Text("Switch Project",
                                    style: TextStyle(fontSize: 10)))
                          ],
                        ),
                        const SizedBox(height: 5),
                        Flexible(
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: activeProject.layers.length,
                            itemBuilder: (ctx, i) {
                              final l = activeProject.layers[i];
                              final isActive = l.id == service.activeLayer?.id;

                              return ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: IconButton(
                                  icon: Icon(
                                      l.isVisible
                                          ? Icons.visibility
                                          : Icons.visibility_off,
                                      color: l.isVisible
                                          ? Colors.blue
                                          : Colors.grey,
                                      size: 20),
                                  onPressed: () {
                                    service.toggleLayerVisibility(l);
                                    setDialogState(() {});
                                  },
                                ),
                                title: Text(l.name,
                                    style: TextStyle(
                                      fontWeight: isActive
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                      color:
                                          isActive ? Colors.blue : Colors.black,
                                    )),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                        "${l.features.length} features • ${l.sourceType.toUpperCase()}",
                                        style: const TextStyle(fontSize: 10)),
                                    if (l.crsInfo != null)
                                      Text(l.crsInfo!,
                                          style: const TextStyle(
                                              fontSize: 9, color: Colors.grey)),
                                    if (l.crsInfo == null)
                                      Text(l.coordinateCrs.label,
                                          style: const TextStyle(
                                              fontSize: 9, color: Colors.grey)),
                                  ],
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (isActive)
                                      const Icon(Icons.check_circle,
                                          color: Colors.green, size: 16),
                                    PopupMenuButton<String>(
                                      icon:
                                          const Icon(Icons.more_vert, size: 20),
                                      onSelected: (val) => _handleLayerAction(
                                          val, l, setDialogState),
                                      itemBuilder: (ctx) => [
                                        const PopupMenuItem(
                                            value: 'table',
                                            child: Row(children: [
                                              Icon(Icons.table_chart, size: 18),
                                              SizedBox(width: 8),
                                              Text("GIS Table")
                                            ])),
                                        const PopupMenuItem(
                                            value: 'summary',
                                            child: Row(children: [
                                              Icon(Icons.analytics, size: 18),
                                              SizedBox(width: 8),
                                              Text("Quality Summary")
                                            ])),
                                        const PopupMenuItem(
                                            value: 'active',
                                            child: Text("Set as Active")),
                                        const PopupMenuItem(
                                            value: 'rename',
                                            child: Text("Rename")),
                                        const PopupMenuItem(
                                            value: 'export',
                                            child: Text("Export Layer")),
                                        const PopupMenuItem(
                                            value: 'delete',
                                            child: Text("Delete Layer",
                                                style: TextStyle(
                                                    color: Colors.red))),
                                      ],
                                    ),
                                  ],
                                ),
                                onTap: () {
                                  service.selectLayer(l);
                                  setDialogState(() {});
                                },
                              );
                            },
                          ),
                        ),
                        const Divider(),
                      ],

                      // --- PROJECTS LIST (if needed or collapsed) ---
                      if (activeProject == null || service.projects.length > 1)
                        const Text("Other Projects",
                            style: TextStyle(fontSize: 10, color: Colors.grey)),

                      if (activeProject == null || service.projects.length > 1)
                        SizedBox(
                          height: 100,
                          child: ListView.builder(
                            itemCount: service.projects.length,
                            itemBuilder: (ctx, i) {
                              final p = service.projects[i];
                              if (p.id == activeProject?.id)
                                return const SizedBox.shrink();

                              return ListTile(
                                dense: true,
                                title: Text(p.name,
                                    style: const TextStyle(fontSize: 13)),
                                leading:
                                    const Icon(Icons.folder_outlined, size: 18),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete_outline,
                                      color: Colors.red, size: 18),
                                  onPressed: () {
                                    service.deleteProject(p.id);
                                    setDialogState(() {});
                                  },
                                ),
                                onTap: () {
                                  service.selectProject(p);
                                  setDialogState(() {});
                                },
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(l10n.close))
                ],
              );
            }));
  }

  void _handleLayerAction(
      String action, ProjectLayer layer, StateSetter setDialogState) {
    final service = context.read<ProjectService>();

    if (action == 'table') {
      Navigator.pop(context);
      Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => AttributeTableScreen(layer: layer)));
    } else if (action == 'summary') {
      showDialog(
          context: context, builder: (_) => SurveySummaryDialog(layer: layer));
    } else if (action == 'active') {
      service.selectLayer(layer);
      setDialogState(() {});
    } else if (action == 'rename') {
      _showRenameLayerDialog(layer, setDialogState);
    } else if (action == 'delete') {
      _showDeleteLayerConfirm(layer, setDialogState);
    } else if (action == 'export') {
      Navigator.pop(context);
      _showExportDialog(service, service.activeProject!, null,
          initialLayer: layer);
    }
  }

  void _showRenameLayerDialog(ProjectLayer layer, StateSetter parentSetState) {
    final ctrl = TextEditingController(text: layer.name);
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text("Rename Layer"),
              content: TextField(controller: ctrl, autofocus: true),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(l10n.cancel)),
                ElevatedButton(
                    onPressed: () {
                      context
                          .read<ProjectService>()
                          .renameLayer(layer, ctrl.text);
                      Navigator.pop(ctx);
                      parentSetState(() {});
                    },
                    child: Text(l10n.save)),
              ],
            ));
  }

  void _showDeleteLayerConfirm(ProjectLayer layer, StateSetter parentSetState) {
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text("Delete Layer?"),
              content: Text(
                  "Are you sure you want to delete '${layer.name}'? All features and attributes in this layer will be permanently removed."),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(l10n.cancel)),
                ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white),
                    onPressed: () {
                      context.read<ProjectService>().deleteLayer(layer);
                      Navigator.pop(ctx);
                      parentSetState(() {});
                    },
                    child: Text(l10n.delete)),
              ],
            ));
  }

  @override
  Widget build(BuildContext context) {
    final projectService = context.watch<ProjectService>();
    final geoidService = context.watch<GeoidCorrectionService>();
    final gnssService = context.watch<GnssInfoService>();
    final vectorService = context.watch<VectorMapService>();
    final eovService = context.read<EovService>();

    final liveEov = _currentLocation != null
        ? eovService.transformWgsToEov(
            _currentLocation!.latitude,
            _currentLocation!.longitude,
            sourceFrame: EovInputFrame.unknown,
          )
        : null;
    final eov = liveEov?.coordinates ?? [0.0, 0.0];
    final orthoHeight = _currentLocation != null
        ? geoidService.getOrthoHeight(
            _currentLocation!.latitude,
            _currentLocation!.longitude,
            _gpsAltitude,
            isEllipsoidal: true,
            referenceFrame: GeoidInputFrame.assumed,
          )
        : null;

    final topPadding = MediaQuery.of(context).padding.top;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    const bottomPanelMinHeight = 160.0;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          children: [
            Text(projectService.activeProject?.name ?? l10n.noProject,
                style: const TextStyle(fontSize: 16)),
            Text(projectService.activeLayer?.name ?? l10n.noLayer,
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
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
              final imported = await importService.importGisData(context);
              if (imported.isNotEmpty) {
                projectService.addImportedLayers(imported);
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
                            icon: const Icon(Icons.delete_forever,
                                color: Colors.red),
                            label: Text(l10n.deleteStorage,
                                style: const TextStyle(color: Colors.red)),
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
                      ));
            },
          ),
          IconButton(
            icon: const Icon(Icons.fact_check_outlined),
            tooltip: 'Alappont ellenőrzés',
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const ControlPointCheckScreen())),
          ),
          IconButton(
              onPressed: _showProjectManager,
              icon: const Icon(Icons.folder_open)),
        ],
      ),
      body: LayoutBuilder(builder: (context, constraints) {
        return Stack(
          children: [
            if (gnssService.isMfkRtkActive)
              Positioned(
                top: topPadding + 8,
                left: 8,
                right: 8,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (gnssService.rtcmAlert != null)
                      Card(
                        color: Colors.red.shade700,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          child: Row(
                            children: [
                              const Icon(Icons.warning_amber,
                                  color: Colors.white),
                              const SizedBox(width: 8),
                              Expanded(
                                  child: Text(gnssService.rtcmAlert!,
                                      style: const TextStyle(
                                          color: Colors.white))),
                              IconButton(
                                tooltip: 'Bezárás',
                                onPressed: gnssService.dismissRtcmAlert,
                                icon: const Icon(Icons.close,
                                    color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      ),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        child: Row(
                          children: [
                            Icon(
                              gnssService.mfkRtkMeasurementState ==
                                      MfkRtkMeasurementState.readyToMeasure
                                  ? Icons.check_circle
                                  : gnssService.mfkRtkMeasurementState ==
                                          MfkRtkMeasurementState.rtcmLost
                                      ? Icons.warning
                                      : Icons.hourglass_top,
                              color: gnssService.mfkRtkMeasurementState ==
                                      MfkRtkMeasurementState.readyToMeasure
                                  ? Colors.green
                                  : gnssService.mfkRtkMeasurementState ==
                                          MfkRtkMeasurementState.rtcmLost
                                      ? Colors.red
                                      : Colors.orange,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                  switch (gnssService.mfkRtkMeasurementState) {
                                    MfkRtkMeasurementState.readyToMeasure =>
                                      l10n.readyToMeasure,
                                    MfkRtkMeasurementState.waitingInsAlign =>
                                      l10n.waitingInsAlignMsg,
                                    MfkRtkMeasurementState.rtcmLost =>
                                      l10n.rtcmLost,
                                    MfkRtkMeasurementState.waitingRtk =>
                                      '${l10n.waitingRtkFix} (${gnssService.mfkRtkNavData?.posType ?? gnssService.mfkRtkStatus?.posType ?? '—'}).',
                                  },
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                            ),
                            Builder(
                              builder: (_) {
                                final batteryPct = (gnssService.mfkRtkStatus
                                                ?.batteryPercentage !=
                                            null &&
                                        gnssService.mfkRtkStatus!
                                                .batteryPercentage >
                                            0)
                                    ? gnssService
                                        .mfkRtkStatus!.batteryPercentage
                                    : (gnssService.mfkRtkNavData
                                                    ?.batteryPercentage !=
                                                null &&
                                            gnssService.mfkRtkNavData!
                                                    .batteryPercentage! >
                                                0)
                                        ? gnssService
                                            .mfkRtkNavData!.batteryPercentage
                                        : null;
                                if (batteryPct == null || batteryPct <= 0)
                                  return const SizedBox.shrink();
                                return Container(
                                  margin: const EdgeInsets.only(left: 8),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: batteryPct > 20
                                        ? Colors.green.shade50
                                        : Colors.red.shade50,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: batteryPct > 20
                                          ? Colors.green
                                          : Colors.red,
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        batteryPct > 50
                                            ? Icons.battery_full
                                            : batteryPct > 20
                                                ? Icons.battery_4_bar
                                                : Icons.battery_alert,
                                        size: 14,
                                        color: batteryPct > 20
                                            ? Colors.green.shade800
                                            : Colors.red.shade800,
                                      ),
                                      const SizedBox(width: 2),
                                      Text(
                                        "$batteryPct%",
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: batteryPct > 20
                                              ? Colors.green.shade900
                                              : Colors.red.shade900,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter:
                    _currentLocation ?? const LatLng(47.4979, 19.0402),
                initialZoom: 15.0,
                interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
                onTap: (tapPosition, point) {
                  if (!_manualDrawing) return;
                  final service = context.read<ProjectService>();
                  if (!service.isRecording) service.beginManualDrawing();
                  service.addManualVertex(point,
                      snap: _snapEnabled, orthogonal: _orthogonalEnabled);
                  if (service.activeTool == FeatureType.point)
                    _showSaveDialog(service);
                  setState(() {});
                },
                onPositionChanged: (pos, hasGesture) {
                  if (hasGesture) setState(() => _isTracking = false);
                },
                onMapReady: () {
                  setState(() => _mapReady = true);
                  if (_isTracking && _currentLocation != null) {
                    _safeMove(_currentLocation!, 15.0);
                  }
                },
              ),
              children: [
                if (!vectorService.isVectorEnabled ||
                    vectorService.mbtilesPath == null)
                  TileLayer(
                    urlTemplate: _getLayerUrl(_activeLayer),
                    userAgentPackageName: 'com.mfk.geomeasure',
                    tileProvider: CachedTileProvider(),
                  )
                else
                  vmt.VectorTileLayer(
                    tileProviders: vmt.TileProviders({
                      'openmaptiles': MbTilesVectorTileProvider(
                        mbtiles:
                            MbTiles(mbtilesPath: vectorService.mbtilesPath!),
                      ),
                    }),
                    theme: _getVectorTheme(),
                  ),
                PolygonLayer(polygons: [
                  ...projectService.visibleFeatures
                      .where((f) => f.type == FeatureType.polygon)
                      .map((f) {
                    final isSelected =
                        projectService.selectedFeatureIds.contains(f.id);
                    return Polygon(
                        points: f.geometry,
                        color: isSelected
                            ? Colors.blue.withValues(alpha: 0.5)
                            : Colors.blue.withValues(alpha: 0.3),
                        borderColor: isSelected ? Colors.yellow : Colors.blue,
                        borderStrokeWidth: isSelected ? 4 : 2,
                        label: f.name);
                  })
                ]),
                PolylineLayer(polylines: [
                  ...projectService.visibleFeatures
                      .where((f) => f.type == FeatureType.line)
                      .map((f) {
                    final isSelected =
                        projectService.selectedFeatureIds.contains(f.id);
                    return Polyline(
                        points: f.geometry,
                        color: isSelected ? Colors.blue : Colors.green,
                        strokeWidth: isSelected ? 5 : 3);
                  })
                ]),
                MarkerLayer(markers: [
                  ...projectService.visibleFeatures
                      .where((f) => f.type == FeatureType.point)
                      .map((f) {
                    final isSelected =
                        projectService.selectedFeatureIds.contains(f.id);
                    return Marker(
                        point: f.geometry.first,
                        width: isSelected ? 50 : 40,
                        height: isSelected ? 50 : 40,
                        child: GestureDetector(
                            onTap: () {
                              projectService.selectFeature(null, f.id);
                              _showFeatureDetails(f);
                            },
                            child: Icon(Icons.location_on,
                                color: isSelected ? Colors.blue : Colors.red,
                                size: isSelected ? 40 : 30)));
                  })
                ]),
                if (_manualDrawing &&
                    projectService.activeTool == FeatureType.polygon &&
                    projectService.currentGeometry.length >= 3)
                  PolygonLayer(polygons: [
                    Polygon(
                        points: projectService.currentGeometry,
                        color: Colors.orange.withValues(alpha: 0.18),
                        borderColor: Colors.deepOrange,
                        borderStrokeWidth: 2)
                  ]),
                if (projectService.isRecording &&
                    projectService.activeTool != FeatureType.point)
                  PolylineLayer(polylines: [
                    Polyline(
                        points: [
                          ...projectService.currentGeometry,
                          if (!_manualDrawing && _currentLocation != null)
                            _currentLocation!
                        ],
                        color: _manualDrawing ? Colors.deepOrange : Colors.red,
                        strokeWidth: 2,
                        isDotted: !_manualDrawing)
                  ]),
                if (_manualDrawing && projectService.currentGeometry.isNotEmpty)
                  MarkerLayer(
                      markers: projectService.currentGeometry
                          .asMap()
                          .entries
                          .map((entry) => Marker(
                                point: entry.value,
                                width: 28,
                                height: 28,
                                child: Container(
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                          color: Colors.deepOrange, width: 2)),
                                  child: Text('${entry.key + 1}',
                                      style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold)),
                                ),
                              ))
                          .toList()),
                if (_currentLocation != null)
                  MarkerLayer(markers: [
                    Marker(
                        point: _currentLocation!,
                        width: 60,
                        height: 60,
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.blue.withValues(alpha: 0.15),
                          ),
                          child: const Icon(Icons.my_location,
                              color: Colors.blue, size: 28),
                        ))
                  ]),
              ],
            ),

            // --- ÉLŐ MÉRÉSI HUD (ÉLŐ TÁVOLSÁG / IRÁNYSZÖG / TERÜLET) ---
            if (projectService.isRecording &&
                projectService.currentGeometry.isNotEmpty)
              _buildLiveMeasurementHUD(projectService),

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
                    boxShadow: const [
                      BoxShadow(color: Colors.black26, blurRadius: 8)
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Transform.rotate(
                            angle: (_bearingToTarget - _deviceHeading) *
                                (pi / 180),
                            child: const Icon(Icons.arrow_upward,
                                size: 50, color: Colors.orange),
                          ),
                          const SizedBox(width: 15),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("${l10n.target}: ${_stakeoutTarget!.name}",
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14)),
                                Text(
                                    _distanceToTarget < 1.0
                                        ? "${(_distanceToTarget * 100).toStringAsFixed(0)} cm"
                                        : "${_distanceToTarget.toStringAsFixed(2)} m",
                                    style: TextStyle(
                                        fontSize: 28,
                                        fontWeight: FontWeight.bold,
                                        color: _distanceToTarget < 0.1
                                            ? Colors.green
                                            : (_distanceToTarget < 1.0
                                                ? Colors.blue
                                                : Colors.black))),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close,
                                color: Colors.red, size: 30),
                            onPressed: () =>
                                setState(() => _stakeoutTarget = null),
                          )
                        ],
                      ),
                      if (_distanceToTarget < 2.0)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: ElevatedButton.icon(
                            onPressed: () =>
                                _startAveragingProcess(projectService),
                            icon: const Icon(Icons.verified),
                            label: Text(l10n.stakeoutCheck),
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                minimumSize: const Size(double.infinity, 36)),
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
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20)),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(l10n.measuringInProgress,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 18)),
                        const SizedBox(height: 10),
                        Text(l10n.keepStill,
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey)),
                        const SizedBox(height: 20),
                        const LibellaWidget(size: 150),
                        const SizedBox(height: 30),
                        LinearProgressIndicator(
                            value: projectService.averagingProgress),
                        const SizedBox(height: 10),
                        Text(
                            "${(projectService.averagingProgress * 100).toInt()}%",
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        if (projectService.currentBatchBestAccuracy !=
                            null) ...[
                          const Divider(height: 30),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(l10n.bestAcc,
                                  style: const TextStyle(fontSize: 11)),
                              Text(
                                  "±${projectService.currentBatchBestAccuracy!.toStringAsFixed(2)} m",
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green,
                                      fontSize: 13)),
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(l10n.avgAcc,
                                  style: const TextStyle(fontSize: 11)),
                              Text(
                                  "±${projectService.currentBatchAverageAccuracy!.toStringAsFixed(2)} m",
                                  style: const TextStyle(
                                      color: Colors.blue, fontSize: 13)),
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
                        _buildToolBtn(Icons.place, l10n.point,
                            FeatureType.point, projectService),
                        const SizedBox(height: 10),
                        _buildToolBtn(Icons.timeline, l10n.line,
                            FeatureType.line, projectService),
                        const SizedBox(height: 10),
                        _buildToolBtn(Icons.pentagon_outlined, l10n.polygon,
                            FeatureType.polygon, projectService),
                        const SizedBox(height: 10),
                        FloatingActionButton.small(
                          heroTag: 'manualDrawing',
                          tooltip: _manualDrawing
                              ? 'Kézi rajzolás kikapcsolása'
                              : 'Kézi rajzolás',
                          backgroundColor:
                              _manualDrawing ? Colors.deepOrange : Colors.white,
                          onPressed: () => setState(() {
                            _manualDrawing = !_manualDrawing;
                            if (_manualDrawing)
                              projectService.beginManualDrawing();
                          }),
                          child: Icon(Icons.edit_location_alt,
                              color: _manualDrawing
                                  ? Colors.white
                                  : Colors.black87),
                        ),
                        if (_manualDrawing) ...[
                          const SizedBox(height: 8),
                          FloatingActionButton.small(
                            heroTag: 'snapToggle',
                            tooltip: 'Végpont és vonal illesztése',
                            backgroundColor:
                                _snapEnabled ? Colors.lightBlue : Colors.white,
                            onPressed: () =>
                                setState(() => _snapEnabled = !_snapEnabled),
                            child: Icon(Icons.join_full,
                                color: _snapEnabled
                                    ? Colors.white
                                    : Colors.black87),
                          ),
                          const SizedBox(height: 8),
                          FloatingActionButton.small(
                            heroTag: 'orthoToggle',
                            tooltip: 'Ortogonális rajzolás',
                            backgroundColor: _orthogonalEnabled
                                ? Colors.lightBlue
                                : Colors.white,
                            onPressed: () => setState(
                                () => _orthogonalEnabled = !_orthogonalEnabled),
                            child: Icon(Icons.square_foot,
                                color: _orthogonalEnabled
                                    ? Colors.white
                                    : Colors.black87),
                          ),
                          const SizedBox(height: 8),
                          FloatingActionButton.small(
                            heroTag: 'geometryUndo',
                            tooltip: 'Visszavonás',
                            onPressed: projectService.canUndoGeometry
                                ? projectService.undoGeometry
                                : null,
                            child: const Icon(Icons.undo),
                          ),
                          const SizedBox(height: 8),
                          FloatingActionButton.small(
                            heroTag: 'geometryRedo',
                            tooltip: 'Újra',
                            onPressed: projectService.canRedoGeometry
                                ? projectService.redoGeometry
                                : null,
                            child: const Icon(Icons.redo),
                          ),
                        ],
                        FloatingActionButton.small(
                          heroTag: "levelingBtn",
                          backgroundColor: Colors.white,
                          child: const Icon(Icons.height, color: Colors.blue),
                          onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const LevelingScreen())),
                        ),
                        const SizedBox(height: 10),
                        FloatingActionButton.small(
                          heroTag: "distanceMeasureBtn",
                          tooltip: 'Két pont közötti távolságmérés',
                          backgroundColor: Colors.white,
                          onPressed: _showQuickDistanceDialog,
                          child:
                              const Icon(Icons.straighten, color: Colors.blue),
                        ),
                        const SizedBox(height: 20),
                        FloatingActionButton.small(
                          heroTag: "cogoBtn",
                          backgroundColor: Colors.white,
                          child:
                              const Icon(Icons.calculate, color: Colors.blue),
                          onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const CogoScreen())),
                        ),
                        const SizedBox(height: 10),
                        FloatingActionButton.small(
                            heroTag: "layersBtn",
                            backgroundColor: Colors.white,
                            child:
                                const Icon(Icons.layers, color: Colors.black),
                            onPressed: () {
                              showDialog(
                                  context: context,
                                  builder: (ctx) => SimpleDialog(
                                          title: Text(l10n.mapType),
                                          children: [
                                            _layerOption(
                                                ctx, l10n.osm, "OpenStreetMap"),
                                            _layerOption(ctx, l10n.satellite,
                                                "Satellite"),
                                            _layerOption(ctx, l10n.hiking,
                                                "Turistautak"),
                                            const Divider(),
                                            ListTile(
                                              leading: const Icon(Icons.map,
                                                  color: Colors.blue),
                                              title:
                                                  Text(l10n.loadVectorMbtiles),
                                              subtitle: Text(context
                                                      .watch<VectorMapService>()
                                                      .mbtilesPath
                                                      ?.split('/')
                                                      .last ??
                                                  l10n.notLoaded),
                                              onTap: () {
                                                Navigator.pop(ctx);
                                                context
                                                    .read<VectorMapService>()
                                                    .pickMbTiles();
                                              },
                                            ),
                                            if (context
                                                    .watch<VectorMapService>()
                                                    .mbtilesPath !=
                                                null)
                                              SwitchListTile(
                                                title: Text(l10n.vectorMode),
                                                value: context
                                                    .watch<VectorMapService>()
                                                    .isVectorEnabled,
                                                onChanged: (val) {
                                                  context
                                                      .read<VectorMapService>()
                                                      .toggleVector(val);
                                                  Navigator.pop(ctx);
                                                },
                                              )
                                          ]));
                            }),
                      ],
                    ),
                  ),
                )),
            Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: GestureDetector(
                  onTap: () {
                    if (_currentLocation != null) {
                      setState(() => _isTracking = true);
                      _safeMove(_currentLocation!, 17.0);
                    }
                  },
                  child: Container(
                    padding: EdgeInsets.only(
                        bottom: bottomPadding > 0 ? bottomPadding : 20),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.95),
                      boxShadow: const [
                        BoxShadow(
                            color: Colors.black12,
                            blurRadius: 5,
                            offset: Offset(0, -2))
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      child: _currentLocation != null
                          ? Column(mainAxisSize: MainAxisSize.min, children: [
                              Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text("EOV Y, X:",
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold)),
                                    Text(
                                        "${eov[0].toStringAsFixed(0)}, ${eov[1].toStringAsFixed(0)}",
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 18,
                                            color: Colors.blue))
                                  ]),
                              const Divider(height: 10),
                              Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                        "φ: ${_currentLocation!.latitude.toStringAsFixed(6)}\nλ: ${_currentLocation!.longitude.toStringAsFixed(6)}",
                                        style: const TextStyle(fontSize: 12)),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (context
                                                    .watch<RtcmService>()
                                                    .status !=
                                                NtripStatus.disconnected)
                                              GestureDetector(
                                                onTap: () =>
                                                    _showNtripQuickMenu(
                                                        context),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Container(
                                                      margin:
                                                          const EdgeInsets.only(
                                                              right: 4),
                                                      width: 12,
                                                      height: 12,
                                                      decoration: BoxDecoration(
                                                        shape: BoxShape.circle,
                                                        color: _getNtripColor(
                                                            context
                                                                .watch<
                                                                    RtcmService>()
                                                                .status),
                                                        border: Border.all(
                                                            color: Colors.white,
                                                            width: 2),
                                                      ),
                                                    ),
                                                    if (context
                                                            .watch<
                                                                RtcmService>()
                                                            .status ==
                                                        NtripStatus
                                                            .correctionDataActive)
                                                      Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .only(right: 4),
                                                        child: Text(
                                                          context
                                                              .watch<
                                                                  RtcmService>()
                                                              .diagnostics
                                                              .correctionAgeString,
                                                          style: TextStyle(
                                                            fontSize: 10,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                            color: _getNtripColor(
                                                                context
                                                                    .watch<
                                                                        RtcmService>()
                                                                    .status),
                                                          ),
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                              ),
                                            if (gnssService.lastFix?.fixType ==
                                                GnssFixType.rtk)
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 4,
                                                        vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: gnssService.lastFix
                                                              ?.rtkStatus ==
                                                          RtkStatus.fixed
                                                      ? Colors.green
                                                      : Colors.orange,
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  gnssService.lastFix
                                                              ?.rtkStatus ==
                                                          RtkStatus.fixed
                                                      ? "RTK FIX"
                                                      : "RTK FLOAT",
                                                  style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.bold),
                                                ),
                                              ),
                                            _buildInsStatusBadge(
                                                gnssService.lastFix),
                                            Builder(
                                              builder: (_) {
                                                final batteryPct = (gnssService
                                                                .mfkRtkStatus
                                                                ?.batteryPercentage !=
                                                            null &&
                                                        gnssService
                                                                .mfkRtkStatus!
                                                                .batteryPercentage >
                                                            0)
                                                    ? gnssService.mfkRtkStatus!
                                                        .batteryPercentage
                                                    : (gnssService.mfkRtkNavData
                                                                    ?.batteryPercentage !=
                                                                null &&
                                                            gnssService
                                                                    .mfkRtkNavData!
                                                                    .batteryPercentage! >
                                                                0)
                                                        ? gnssService
                                                            .mfkRtkNavData!
                                                            .batteryPercentage
                                                        : null;
                                                if (!gnssService
                                                        .isMfkRtkActive ||
                                                    batteryPct == null ||
                                                    batteryPct <= 0) {
                                                  return const SizedBox
                                                      .shrink();
                                                }
                                                return Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                          left: 4),
                                                  child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Icon(
                                                        batteryPct > 50
                                                            ? Icons.battery_full
                                                            : batteryPct > 20
                                                                ? Icons
                                                                    .battery_4_bar
                                                                : Icons
                                                                    .battery_alert,
                                                        size: 14,
                                                        color: batteryPct > 20
                                                            ? Colors
                                                                .green.shade700
                                                            : Colors
                                                                .red.shade700,
                                                      ),
                                                      Text(
                                                        "$batteryPct%",
                                                        style: TextStyle(
                                                          fontSize: 10,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color: batteryPct > 20
                                                              ? Colors.green
                                                                  .shade900
                                                              : Colors
                                                                  .red.shade900,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                              },
                                            ),
                                            const SizedBox(width: 8),
                                            GestureDetector(
                                              onTap: Platform.isAndroid
                                                  ? _showSkyplotDialog
                                                  : null,
                                              child: _buildQualityIndicator(
                                                  gnssService.currentStatus
                                                      .qualityScore),
                                            ),
                                            const SizedBox(width: 8),
                                            Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.end,
                                              children: [
                                                if (gnssService.currentStatus
                                                        .satellitesInView >
                                                    0)
                                                  Text(
                                                    "${l10n.satellites}: ${gnssService.currentStatus.satellitesUsedInFix}/${gnssService.currentStatus.satellitesInView}",
                                                    style: const TextStyle(
                                                        fontSize: 10,
                                                        color: Colors.blueGrey,
                                                        fontWeight:
                                                            FontWeight.bold),
                                                  ),
                                                Text(
                                                  "±${_currentAccuracy.toStringAsFixed(2)} m",
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    color: _getAccuracyColor(
                                                        _currentAccuracy,
                                                        projectService
                                                            .requiredAccuracy),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                        if (projectService.antennaHeight > 0)
                                          Text(
                                              "${l10n.ant}: ${projectService.antennaHeight}m",
                                              style: const TextStyle(
                                                  fontSize: 10,
                                                  color: Colors.grey)),
                                      ],
                                    )
                                  ]),
                              const SizedBox(height: 6),
                              Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    _buildHeightBox(
                                        "GPS h (Ell.)",
                                        "${_gpsAltitude.toStringAsFixed(2)} m",
                                        Colors.orange),
                                    const Icon(Icons.arrow_right_alt,
                                        color: Colors.grey),
                                    _buildHeightBox(
                                        "EOV H (Balti)",
                                        "${orthoHeight?.toStringAsFixed(2) ?? '--'} m",
                                        Colors.green[700]!)
                                  ]),
                            ])
                          : Center(
                              child: Text(l10n.searchingGps,
                                  style: const TextStyle(
                                      fontStyle: FontStyle.italic))),
                    ),
                  ),
                )),
          ],
        );
      }),
      floatingActionButton: Padding(
        padding:
            EdgeInsets.only(bottom: bottomPadding + bottomPanelMinHeight - 20),
        child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
          if (Platform.isAndroid) ...[
            FloatingActionButton.small(
              heroTag: "ppkBtn",
              onPressed: gnssService.rawLogger.isLogging
                  ? () => gnssService.rawLogger.stopSession()
                  : _showPpkDialog,
              backgroundColor: gnssService.rawLogger.isLogging
                  ? Colors.red
                  : Colors.blueGrey,
              child: Icon(
                  gnssService.rawLogger.isLogging
                      ? Icons.stop_circle
                      : Icons.sensors,
                  color: Colors.white),
            ),
            const SizedBox(height: 10),
          ],
          if (projectService.isRecording)
            FloatingActionButton.extended(
                heroTag: "saveBtn",
                onPressed: projectService.canFinishRecording
                    ? () => _showSaveDialog(projectService)
                    : null,
                backgroundColor: Colors.green,
                icon: const Icon(Icons.check),
                label: Text(l10n.done)),
          const SizedBox(height: 10),
          if (!_manualDrawing)
            FloatingActionButton(
                heroTag: "recBtn",
                onPressed: _handleRecordButton,
                backgroundColor:
                    projectService.isRecording ? Colors.orange : Colors.blue,
                child: Icon(
                    projectService.isRecording
                        ? Icons.add
                        : Icons.fiber_manual_record,
                    color: Colors.white)),
          const SizedBox(height: 10),
          FloatingActionButton.small(
              heroTag: "gpsBtn",
              onPressed: () {
                setState(() => _isTracking = true);
                if (_currentLocation != null) _safeMove(_currentLocation!, 17);
              },
              backgroundColor: Colors.white,
              child: Icon(Icons.my_location,
                  color: _isTracking ? Colors.blue : Colors.grey)),
        ]),
      ),
    );
  }

  vtr.Theme _getVectorTheme() {
    return vtr.ProvidedThemes.lightTheme();
  }

  Widget _layerOption(BuildContext ctx, String name, String id) {
    return SimpleDialogOption(
      onPressed: () {
        setState(() => _activeLayer = id);
        Navigator.pop(ctx);
      },
      child: Row(children: [
        Icon(
            _activeLayer == id
                ? Icons.radio_button_checked
                : Icons.radio_button_unchecked,
            color: Colors.blue),
        const SizedBox(width: 10),
        Text(name)
      ]),
    );
  }

  Widget _buildInsStatusBadge(GnssFix? fix) {
    if (fix?.insStatus == null) return const SizedBox.shrink();

    Color bgColor = Colors.blueGrey;
    String label = "GNSS Fallback";

    if (fix!.insStatus == 'INS_SOLUTION_GOOD') {
      bgColor = Colors.green;
      label = "INS GOOD";
    } else if (fix.insStatus == 'INS_ALIGNMENT_COMPLETE') {
      bgColor = Colors.blue;
      label = "INS READY";
    } else if (fix.insStatus != 'INS_INACTIVE') {
      bgColor = Colors.orange;
      label = "INS ALIGNING";
    }

    return Container(
      margin: const EdgeInsets.only(left: 4),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: const TextStyle(
            color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildHeightBox(String label, String value, Color color) {
    return Column(children: [
      Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
      Text(value,
          style: TextStyle(
              fontWeight: FontWeight.bold, color: color, fontSize: 15))
    ]);
  }

  Color _getAccuracyColor(double acc, double required) {
    if (acc <= required) return Colors.green;
    if (acc <= required * 2) return Colors.orange;
    return Colors.red;
  }

  Color _getNtripColor(NtripStatus s) {
    switch (s) {
      case NtripStatus.connected:
        return Colors.blue;
      case NtripStatus.correctionDataActive:
        return Colors.green;
      case NtripStatus.error:
        return Colors.red;
      case NtripStatus.connecting:
        return Colors.orange;
      case NtripStatus.notConfigured:
        return Colors.redAccent;
      default:
        return Colors.grey;
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
              leading:
                  Icon(Icons.link, color: _getNtripColor(rtcmService.status)),
              title: Text("NTRIP: ${rtcmService.status.name}"),
              subtitle: Text(activeProfile?.host ?? ""),
            ),
            if (rtcmService.status == NtripStatus.correctionDataActive)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                        "Correction Age: ${rtcmService.diagnostics.correctionAgeString}"),
                    Text(
                        "Bitrate: ${rtcmService.diagnostics.bitrateKbps.toStringAsFixed(1)} kbps"),
                  ],
                ),
              ),
            if (rtcmService.status == NtripStatus.disconnected ||
                rtcmService.status == NtripStatus.error ||
                rtcmService.status == NtripStatus.notConfigured)
              ListTile(
                leading: const Icon(Icons.play_arrow, color: Colors.green),
                title: const Text("Csatlakozás"),
                enabled: rtcmService.status != NtripStatus.notConfigured,
                onTap: () {
                  Navigator.pop(ctx);
                  gnssService.updateNtripSettings(gnssService.ntripSettings,
                      rtcmService: rtcmService);
                },
              ),
            if (rtcmService.status != NtripStatus.disconnected &&
                rtcmService.status != NtripStatus.notConfigured)
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
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const GnssSettingsScreen()));
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolBtn(
      IconData icon, String label, FeatureType type, ProjectService service) {
    return FloatingActionButton.small(
        heroTag: "tool_$label",
        backgroundColor:
            service.activeTool == type ? Colors.blue : Colors.white,
        onPressed: () => service.setTool(type),
        child: Icon(icon,
            color: service.activeTool == type ? Colors.white : Colors.black87));
  }
}
