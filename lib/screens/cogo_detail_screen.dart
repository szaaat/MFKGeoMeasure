import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import '../services/gnss_info_service.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../providers/cogo_provider.dart';
import '../models/cogo_session.dart';
import '../models/geo_feature.dart';
import '../services/project_service.dart';
import '../widgets/cogo/quadrant_widget.dart';

class CogoDetailScreen extends StatefulWidget {
  const CogoDetailScreen({super.key});

  @override
  State<CogoDetailScreen> createState() => _CogoDetailScreenState();
}

class _CogoDetailScreenState extends State<CogoDetailScreen> {
  final MapController _mapController = MapController();
  bool _showDerivation = false;
  String? _pickingFor; // Melyik ponthoz várunk térképi kattintást
  String _lastFingerprint = "";

  AppLocalizations get l10n => AppLocalizations.of(context)!;

  @override
  Widget build(BuildContext context) {
    final cogo = context.watch<CogoProvider>();
    final type = cogo.activeType;
    if (type == null) return Scaffold(body: Center(child: Text(l10n.noTypeSelected)));

    // Automatikus fókuszálás, ha változtak a pontok
    String currentFingerprint = cogo.pointsFingerprint;
    if (currentFingerprint != _lastFingerprint) {
      _lastFingerprint = currentFingerprint;
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitPointsOnMap(cogo));
    }

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        appBar: AppBar(
          title: Text(_getTypeTitle(type)),
          backgroundColor: _pickingFor != null ? Colors.orange[100] : null,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
          actions: [
            if (_pickingFor != null)
              Padding(
                padding: const EdgeInsets.only(right: 20),
                child: Center(child: Text(l10n.selectPointTarget(_pickingFor!), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange))),
              )
          ],
        ),
        body: Stack(
          children: [
            // 1. Térkép réteg (Felső rész)
            Positioned.fill(
              bottom: MediaQuery.of(context).size.height * 0.35,
              child: FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: const LatLng(47.4979, 19.0402),
                  initialZoom: 15.0,
                  onTap: (tapPos, latLng) {
                    if (_pickingFor != null) {
                      if (_pickingFor == "AREA_NEW") {
                        cogo.addAreaPoint(wgs: latLng, source: 'map');
                      } else {
                        cogo.updatePoint(_pickingFor!, wgs: latLng, source: 'map');
                      }
                      setState(() => _pickingFor = null);
                    } else {
                      FocusScope.of(context).unfocus();
                    }
                  },
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.mfk.geomeasure',
                  ),
                  _buildGeometryLayers(cogo),
                  _buildMarkerLayer(cogo),
                ],
              ),
            ),

            // 2. Alsó beviteli panel
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                height: MediaQuery.of(context).size.height * 0.45,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
                  boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10)],
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildInputForm(context, cogo),
                      const Divider(height: 30),
                      _buildResultArea(cogo),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getTypeTitle(CogoType type) {
    switch (type) {
      case CogoType.inverse: return l10n.inverse;
      case CogoType.angularIntersection: return l10n.angularIntersection;
      case CogoType.distanceIntersection: return l10n.distanceIntersection;
      case CogoType.resection: return l10n.resection;
      case CogoType.area: return l10n.area;
    }
  }

  String _getResultLabel(String key) {
    switch (key) {
      case 'distance': return l10n.distanceLabel;
      case 'bearing': return l10n.bearingLabel;
      case 'y': return l10n.resultY;
      case 'x': return l10n.resultX;
      case 'y1': return l10n.intersection1Y;
      case 'x1': return l10n.intersection1X;
      case 'y2': return l10n.intersection2Y;
      case 'x2': return l10n.intersection2X;
      case 'area_m2': return l10n.areaLabel;
      case 'area_ha': return l10n.areaLabel;
      default: return key;
    }
  }

  String _getUnit(String key) {
    switch (key) {
      case 'distance': return "m";
      case 'bearing': return "°";
      case 'y':
      case 'x':
      case 'y1':
      case 'x1':
      case 'y2':
      case 'x2': return "m";
      case 'area_m2': return "m²";
      case 'area_ha': return "ha";
      default: return "";
    }
  }

  Widget _buildInputForm(BuildContext context, CogoProvider cogo) {
    switch (cogo.activeType!) {
      case CogoType.inverse:
        return Column(children: [
          _buildPointInput(context, cogo, "P1"),
          const SizedBox(height: 10),
          _buildPointInput(context, cogo, "P2"),
        ]);
      case CogoType.distanceIntersection:
        return Column(children: [
          _buildPointInput(context, cogo, "P1"),
          _buildParamInput(cogo, "r1", l10n.radius1),
          const SizedBox(height: 15),
          _buildPointInput(context, cogo, "P2"),
          _buildParamInput(cogo, "r2", l10n.radius2),
        ]);
      case CogoType.angularIntersection:
        return Column(children: [
          _buildPointInput(context, cogo, "P1"),
          _buildParamInput(cogo, "b1", l10n.bearing1),
          const SizedBox(height: 15),
          _buildPointInput(context, cogo, "P2"),
          _buildParamInput(cogo, "b2", l10n.bearing2),
        ]);
      case CogoType.resection:
        return Column(children: [
          _buildPointInput(context, cogo, "P1"),
          _buildParamInput(cogo, "a1", l10n.measuredBearingP1),
          const SizedBox(height: 10),
          _buildPointInput(context, cogo, "P2"),
          _buildParamInput(cogo, "a2", l10n.measuredBearingP2),
          const SizedBox(height: 10),
          _buildPointInput(context, cogo, "P3"),
          _buildParamInput(cogo, "a3", l10n.measuredBearingP3),
        ]);
      case CogoType.area:
        return _buildAreaInput(context, cogo);
    }
  }

  Widget _buildAreaInput(BuildContext context, CogoProvider cogo) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(l10n.areaPoints, style: const TextStyle(fontWeight: FontWeight.bold)),
            ElevatedButton.icon(
              onPressed: () => _showPointSourceSelector(context, cogo, l10n.newPoint, isArea: true),
              icon: const Icon(Icons.add, size: 16),
              label: Text(l10n.add, style: const TextStyle(fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (cogo.areaPoints.isEmpty)
          Padding(
            padding: const EdgeInsets.all(20),
            child: Center(child: Text(l10n.noPointsAdded, style: const TextStyle(color: Colors.grey, fontSize: 12))),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: cogo.areaPoints.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (ctx, i) {
              final p = cogo.areaPoints[i];
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text("P${i + 1}: Y=${p.y?.toStringAsFixed(1)}, X=${p.x?.toStringAsFixed(1)}", style: const TextStyle(fontSize: 12)),
                subtitle: Text(l10n.sourceLabel(_getSourceLabel(p.source)), style: const TextStyle(fontSize: 9)),
                trailing: IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red, size: 18),
                  onPressed: () => cogo.removeAreaPoint(i),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildPointInput(BuildContext context, CogoProvider cogo, String label) {
    final point = cogo.points[label];
    final yCtrl = TextEditingController(text: point?.y?.toStringAsFixed(3) ?? "");
    final xCtrl = TextEditingController(text: point?.x?.toStringAsFixed(3) ?? "");

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
              ElevatedButton.icon(
                onPressed: () => _showPointSourceSelector(context, cogo, label),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                  minimumSize: const Size(0, 30),
                  backgroundColor: Colors.blue[50],
                  foregroundColor: Colors.blue[800],
                  elevation: 0,
                ),
                icon: const Icon(Icons.add_location_alt, size: 14),
                label: Text(l10n.selectBtn, style: const TextStyle(fontSize: 11)),
              )
            ],
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: yCtrl,
                  decoration: const InputDecoration(labelText: "EOV Y", isDense: true, labelStyle: TextStyle(fontSize: 10)),
                  style: const TextStyle(fontSize: 12),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (val) {
                    double? d = double.tryParse(val.replaceAll(',', '.'));
                    if (d != null) cogo.updatePoint(label, y: d, x: point?.x);
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: xCtrl,
                  decoration: const InputDecoration(labelText: "EOV X", isDense: true, labelStyle: TextStyle(fontSize: 10)),
                  style: const TextStyle(fontSize: 12),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (val) {
                    double? d = double.tryParse(val.replaceAll(',', '.'));
                    if (d != null) cogo.updatePoint(label, y: point?.y, x: d);
                  },
                ),
              ),
            ],
          ),
          if (point?.source != null && point!.source != 'manual')
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(l10n.sourceLabel(_getSourceLabel(point.source)), style: TextStyle(fontSize: 9, color: Colors.grey[600], fontStyle: FontStyle.italic)),
            ),
        ],
      ),
    );
  }

  String _getSourceLabel(String source) {
    switch (source) {
      case 'map': return l10n.sourceMap;
      case 'gnss': return l10n.sourceGnss;
      case 'project': return l10n.sourceProject;
      default: return source;
    }
  }

  void _showPointSourceSelector(BuildContext context, CogoProvider cogo, String label, {bool isArea = false}) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(15.0),
              child: Text(l10n.selectSourceFor(label), style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: const Icon(Icons.map, color: Colors.orange),
              title: Text(l10n.pickFromMap),
              subtitle: Text(l10n.pickFromMapDesc),
              onTap: () {
                Navigator.pop(ctx);
                if (isArea) {
                  setState(() => _pickingFor = "AREA_NEW");
                } else {
                  _pickPointFromMap(cogo, label);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.my_location, color: Colors.blue),
              title: Text(l10n.currentGnss),
              subtitle: Text(l10n.currentGnssDesc),
              onTap: () {
                Navigator.pop(ctx);
                _pickFromGnss(context, cogo, label, isArea: isArea);
              },
            ),
            ListTile(
              leading: const Icon(Icons.folder, color: Colors.green),
              title: Text(l10n.pickFromProject),
              subtitle: Text(l10n.pickFromProjectDesc),
              onTap: () {
                Navigator.pop(ctx);
                _pickFromProject(context, cogo, label, isArea: isArea);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _safeMove(LatLng dest, double zoom) {
    if (!dest.latitude.isFinite || !dest.longitude.isFinite || !zoom.isFinite) {
      debugPrint("REJECTED move to invalid location or zoom: $dest, $zoom");
      return;
    }
    _mapController.move(dest, zoom);
  }

  Future<void> _pickFromGnss(BuildContext context, CogoProvider cogo, String label, {bool isArea = false}) async {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.fetchingGps), duration: const Duration(seconds: 1)));
    try {
      final gnssService = context.read<GnssInfoService>();
      final fix = gnssService.lastFix;
      
      if (fix == null) {
        throw Exception(l10n.gpsErrorPerm);
      }
      
      if (!fix.latitude.isFinite || !fix.longitude.isFinite) {
        throw Exception("Érvénytelen GPS koordináták (NaN)");
      }

      LatLng wgs = LatLng(fix.latitude, fix.longitude);

      if (isArea) {
        cogo.addAreaPoint(wgs: wgs, source: 'gnss');
      } else {
        cogo.updatePoint(label, wgs: wgs, source: 'gnss');
      }
      
      _safeMove(wgs, 17.0);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("GPS hiba: $e"), backgroundColor: Colors.red));
      }
    }
  }

  void _pickFromProject(BuildContext context, CogoProvider cogo, String label, {bool isArea = false}) {
    final projectService = context.read<ProjectService>();
    final points = projectService.visibleFeatures.where((f) => f.type == FeatureType.point).toList();

    if (points.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.noPointsInActiveLayers)));
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.selectPointTitle),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: points.length,
            itemBuilder: (c, i) => ListTile(
              title: Text(points[i].name),
              subtitle: Text(points[i].description),
              onTap: () {
                final p = points[i].geometry.first;
                if (!p.latitude.isFinite || !p.longitude.isFinite) {
                   ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.invalidSavedCoord)));
                   return;
                }

                if (isArea) {
                  cogo.addAreaPoint(wgs: p, source: 'project');
                } else {
                  cogo.updatePoint(label, wgs: p, source: 'project');
                }
                _safeMove(p, 17.0);
                Navigator.pop(ctx);
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildParamInput(CogoProvider cogo, String key, String label) {
    return TextField(
      decoration: InputDecoration(labelText: label, isDense: true),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: TextInputAction.done,
      onChanged: (val) {
        double? d = double.tryParse(val.replaceAll(',', '.'));
        if (d != null) cogo.updateParameter(key, d);
      },
    );
  }

  Widget _buildResultArea(CogoProvider cogo) {
    if (cogo.report == null) return Center(child: Text(l10n.waitingForInput, style: const TextStyle(color: Colors.grey)));
    if (cogo.report!.hasError) {
      return Container(
        padding: const EdgeInsets.all(10),
        color: Colors.red[50],
        child: Text(cogo.report!.errorMessage!, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(l10n.result, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
            IconButton(
              icon: const Icon(Icons.keyboard_hide, color: Colors.grey),
              tooltip: l10n.hideKeyboard,
              onPressed: () => FocusScope.of(context).unfocus(),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        const SizedBox(height: 5),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...cogo.report!.results.entries.map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 4.0),
                    child: Text("${_getResultLabel(e.key)}: ${e.value is double ? e.value.toStringAsFixed(3) : e.value} ${_getUnit(e.key)}"),
                  )),
                ],
              ),
            ),
            if (cogo.activeType == CogoType.inverse && cogo.report!.results['bearing'] != null)
              QuadrantWidget(bearing: cogo.report!.results['bearing']),
          ],
        ),
        const SizedBox(height: 20),
        InkWell(
          onTap: () => setState(() => _showDerivation = !_showDerivation),
          child: Row(
            children: [
              Icon(_showDerivation ? Icons.expand_less : Icons.expand_more, color: Colors.grey),
              Text(" ${l10n.mathDerivation}", style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ],
          ),
        ),
        if (_showDerivation)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: Colors.grey[50],
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: cogo.report!.derivationSteps.map((s) => Text(s, style: const TextStyle(fontFamily: 'monospace', fontSize: 11))).toList(),
              ),
            ),
          )
      ],
    );
  }

  Widget _buildMarkerLayer(CogoProvider cogo) {
    List<Marker> markers = [];
    cogo.points.forEach((key, p) {
      if (p.wgs != null) {
        markers.add(Marker(
          point: p.wgs!,
          width: 40, height: 40,
          child: Column(children: [
            const Icon(Icons.location_on, color: Colors.blue),
            Text(key, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
          ]),
        ));
      }
    });

    if (cogo.activeType == CogoType.area) {
      for (int i = 0; i < cogo.areaPoints.length; i++) {
        final p = cogo.areaPoints[i];
        if (p.wgs != null) {
          markers.add(Marker(
            point: p.wgs!,
            width: 30, height: 30,
            child: Column(children: [
              const Icon(Icons.location_on, color: Colors.green, size: 18),
              Text("P${i+1}", style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold)),
            ]),
          ));
        }
      }
    }

    if (cogo.report?.resultPoints != null) {
      for (int i = 0; i < cogo.report!.resultPoints!.length; i++) {
        final p = cogo.report!.resultPoints![i];
        final w = context.read<CogoProvider>().eovService.eovToWgs(p[0], p[1]);
        markers.add(Marker(
          point: LatLng(w[0], w[1]),
          width: 60, height: 60,
          child: GestureDetector(
            onTap: () => cogo.selectResult(i),
            child: Column(children: [
              Icon(Icons.stars, color: cogo.selectedResultIndex == i ? Colors.green : Colors.orange),
              Text("M${i+1}", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
            ]),
          ),
        ));
      }
    }

    return MarkerLayer(markers: markers);
  }

  Widget _buildGeometryLayers(CogoProvider cogo) {
    if (cogo.activeType == CogoType.distanceIntersection) {
      List<CircleMarker> circles = [];
      if (cogo.points['P1']?.wgs != null && cogo.parameters['r1'] != null) {
        circles.add(CircleMarker(
          point: cogo.points['P1']!.wgs!,
          radius: cogo.parameters['r1']!,
          useRadiusInMeter: true,
          color: Colors.blue.withValues(alpha: 0.1),
          borderColor: Colors.blue,
          borderStrokeWidth: 2,
        ));
      }
      if (cogo.points['P2']?.wgs != null && cogo.parameters['r2'] != null) {
        circles.add(CircleMarker(
          point: cogo.points['P2']!.wgs!,
          radius: cogo.parameters['r2']!,
          useRadiusInMeter: true,
          color: Colors.orange.withValues(alpha: 0.1),
          borderColor: Colors.orange,
          borderStrokeWidth: 2,
        ));
      }
      return CircleLayer(circles: circles);
    }

    if (cogo.activeType == CogoType.angularIntersection) {
      List<Polyline> lines = [];
      if (cogo.points['P1']?.wgs != null && cogo.parameters['b1'] != null) {
        lines.add(_buildDirectionLine(cogo.points['P1']!.wgs!, cogo.parameters['b1']!, Colors.blue));
      }
      if (cogo.points['P2']?.wgs != null && cogo.parameters['b2'] != null) {
        lines.add(_buildDirectionLine(cogo.points['P2']!.wgs!, cogo.parameters['b2']!, Colors.orange));
      }
      return PolylineLayer(polylines: lines);
    }

    if (cogo.activeType == CogoType.area && cogo.areaPoints.length >= 3) {
      final points = cogo.areaPoints.where((p) => p.wgs != null).map((p) => p.wgs!).toList();
      if (points.length >= 3) {
        return PolygonLayer(polygons: [
          Polygon(
            points: points,
            color: Colors.green.withValues(alpha: 0.2),
            borderColor: Colors.green,
            borderStrokeWidth: 2,
          )
        ]);
      }
    }
    
    return const SizedBox.shrink();
  }

  Polyline _buildDirectionLine(LatLng start, double bearing, Color color) {
    const distance = 5000.0;
    double brngRad = (90 - bearing) * pi / 180;
    
    double lat2 = start.latitude + (distance / 111111.0) * sin(brngRad);
    double lon2 = start.longitude + (distance / (111111.0 * cos(start.latitude * pi / 180))) * cos(brngRad);
    
    return Polyline(
      points: [start, LatLng(lat2, lon2)],
      color: color.withValues(alpha: 0.5),
      strokeWidth: 2,
      isDotted: true,
    );
  }

  void _pickPointFromMap(CogoProvider cogo, String label) {
    setState(() => _pickingFor = label);
  }

  void _fitPointsOnMap(CogoProvider cogo) {
    List<LatLng> allPoints = [];
    for (var p in cogo.points.values) { 
      if (p.wgs != null && p.wgs!.latitude.isFinite && p.wgs!.longitude.isFinite) {
        allPoints.add(p.wgs!); 
      }
    }
    for (var p in cogo.areaPoints) { 
      if (p.wgs != null && p.wgs!.latitude.isFinite && p.wgs!.longitude.isFinite) {
        allPoints.add(p.wgs!); 
      }
    }
    
    if (cogo.report?.resultPoints != null) {
      for (var rp in cogo.report!.resultPoints!) {
        if (rp[0].isFinite && rp[1].isFinite) {
          final w = cogo.eovService.eovToWgs(rp[0], rp[1]);
          if (w[0].isFinite && w[1].isFinite) {
            allPoints.add(LatLng(w[0], w[1]));
          }
        }
      }
    }

    if (allPoints.isEmpty) return;

    if (allPoints.length == 1) {
      _safeMove(allPoints.first, 17.0);
      return;
    }

    try {
      final bounds = LatLngBounds.fromPoints(allPoints);
      
      if (!bounds.north.isFinite || !bounds.south.isFinite || !bounds.east.isFinite || !bounds.west.isFinite) {
        debugPrint("HIBA: Érvénytelen bounds (NaN) a fitCamera hívásnál.");
        return;
      }

      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds, 
          padding: const EdgeInsets.all(50),
          maxZoom: 18.0,
        ),
      );
    } catch (e) {
      debugPrint("Hiba a fitCamera hívásakor: $e");
    }
  }
}
