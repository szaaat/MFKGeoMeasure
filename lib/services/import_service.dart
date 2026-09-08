import 'dart:io';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:dxf/dxf.dart';
import 'package:latlong2/latlong.dart';
import 'package:geoxml/geoxml.dart';
import 'package:archive/archive.dart';
import '../models/geo_feature.dart';
import 'eov_service.dart';

class ImportService extends ChangeNotifier {
  EovService? _eovService;

  void updateEovService(EovService service) {
    _eovService = service;
  }

  Future<List<GeoFeature>> importGisData() async {
    if (_eovService == null) return [];
    
    try {
      PlatformFile? result = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['dxf', 'kml', 'kmz', 'gpx'],
      );

      if (result == null || result.path == null) return [];

      final file = File(result.path!);
      final extension = result.extension?.toLowerCase();

      if (extension == 'dxf') {
        return _parseDxf(file);
      } else if (extension == 'kml') {
        final content = await file.readAsString();
        return _parseKml(content);
      } else if (extension == 'kmz') {
        return _parseKmz(file);
      } else if (extension == 'gpx') {
        final content = await file.readAsString();
        return _parseGpx(content);
      }

      return [];
    } catch (e) {
      debugPrint("Hiba a GIS importálásakor: $e");
      return [];
    }
  }

  Future<List<GeoFeature>> _parseDxf(File file) async {
    final dxfString = await file.readAsString();
    final dxf = DXF.fromString(dxfString);
    List<GeoFeature> features = [];

    for (var entity in dxf.entities) {
      if (entity is AcDbLine) {
        final startWgs = _eovService!.eovToWgs(entity.x, entity.y);
        final endWgs = _eovService!.eovToWgs(entity.x1, entity.y1);
        features.add(GeoFeature(
          name: "DXF Vonal",
          type: FeatureType.line,
          geometry: [LatLng(startWgs[0], startWgs[1]), LatLng(endWgs[0], endWgs[1])],
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

  Future<List<GeoFeature>> _parseKml(String content) async {
    final geoXml = await GeoXml.fromKmlString(content);
    return _convertGeoXmlToFeatures(geoXml, "KML");
  }

  Future<List<GeoFeature>> _parseKmz(File file) async {
    final bytes = await file.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    
    for (final file in archive) {
      if (file.isFile && file.name.toLowerCase().endsWith('.kml')) {
        final kmlString = utf8.decode(file.content as List<int>);
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
}
