import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;

class GeoidCorrectionService {
  img.Image? _geoidGrid;

  // EHT2014 (EPSG:23700) hozzávetőleges határai WGS84-ben
  final double minLon = 16.1;
  final double maxLon = 22.9;
  final double minLat = 45.7;
  final double maxLat = 48.6;

  bool _isLoading = false;
  bool get isLoaded => _geoidGrid != null;

  Future<void> loadGeoidFile() async {
    if (isLoaded || _isLoading) return;
    _isLoading = true;

    try {
      final ByteData data = await rootBundle.load('assets/data/geoid_eht2014.tif');
      final Uint8List originalBytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);

      // A TIFF dekódolást kiszervezzük a háttérbe, hogy ne akassza meg a UI-t
      final image = await compute(_decodeGeoidImage, originalBytes);

      if (image != null) {
        _geoidGrid = image;
        debugPrint("Geoid file loaded successfully in background: ${_geoidGrid?.width}x${_geoidGrid?.height}");
      } else {
        debugPrint("Warning: Geoid file could not be decoded (null result).");
      }
    } catch (e) {
      debugPrint("Error loading geoid file: $e");
    } finally {
      _isLoading = false;
    }
  }

  // Ez a függvény fut le a külön szálon (Isolate)
  static img.Image? _decodeGeoidImage(Uint8List bytes) {
    try {
      // Itt is alkalmazunk egy kis pufferelést a biztonság kedvéért
      final List<int> bufferedList = List<int>.from(bytes);
      bufferedList.addAll(List<int>.filled(256 * 1024, 0));
      return img.decodeImage(Uint8List.fromList(bufferedList));
    } catch (e) {
      return null;
    }
  }

  /// Visszaadja a geoid undulációt (N) az adott ponton.
  double? getUndulation(double lat, double lon) {
    if (_geoidGrid == null || lat < minLat || lat > maxLat || lon < minLon || lon > maxLon) {
      return null;
    }
    try {
      double ratioX = (lon - minLon) / (maxLon - minLon);
      double ratioY = (maxLat - lat) / (maxLat - minLat);
      int pixelX = (ratioX * _geoidGrid!.width).round().clamp(0, _geoidGrid!.width - 1);
      int pixelY = (ratioY * _geoidGrid!.height).round().clamp(0, _geoidGrid!.height - 1);
      return _geoidGrid!.getPixel(pixelX, pixelY).r.toDouble();
    } catch (e) {
      return null;
    }
  }

  /// Kiszámolja a tengerszint feletti (ortometrikus) magasságot.
  /// Ha [isEllipsoidal] igaz, akkor ellipszoidi magasságot várunk és kivonjuk az undulációt.
  /// Ha [isEllipsoidal] hamis, akkor feltételezzük, hogy már MSL magasság (pl. iOS internal GPS).
  double? getOrthoHeight(double lat, double lon, double gpsAlt, {bool? isEllipsoidal}) {
    // Ha nincs megadva, megtartjuk a korábbi platformfüggő alapértelmezett viselkedést
    final bool effectiveIsEllipsoidal = isEllipsoidal ?? Platform.isAndroid;

    if (_geoidGrid == null) {
      // Ha nincs geoid rács, akkor nem tudunk korrigálni.
      // Ha már MSL (effectiveIsEllipsoidal == false), visszaadjuk az eredetit.
      return !effectiveIsEllipsoidal ? gpsAlt : null;
    }

    if (lat < minLat || lat > maxLat || lon < minLon || lon > maxLon) {
      return !effectiveIsEllipsoidal ? gpsAlt : null;
    }

    try {
      double? undulation = getUndulation(lat, lon);
      if (undulation == null) return !effectiveIsEllipsoidal ? gpsAlt : null;

      if (effectiveIsEllipsoidal) {
        // Ellipszoidi -> MSL (Balti)
        return gpsAlt - undulation;
      } else {
        // Már MSL (Balti)
        return gpsAlt;
      }
    } catch (e) {
      debugPrint("Error during height calculation: $e");
      return !effectiveIsEllipsoidal ? gpsAlt : null;
    }
  }
}
