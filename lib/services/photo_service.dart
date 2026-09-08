import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:native_exif/native_exif.dart';
import 'package:path_provider/path_provider.dart';
import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';

class PhotoService extends ChangeNotifier {
  
  /// Feldolgozza a rögzített fotót: elmenti a végleges helyére és geotaggeli.
  Future<String?> processCapturedPhoto({
    required XFile photo,
    required LatLng location,
    required double heading,
    required double altitude,
  }) async {
    try {
      // 1. Áthelyezzük egy állandó helyre az app storage-ben
      final directory = await getApplicationDocumentsDirectory();
      final photoDir = Directory('${directory.path}/photos');
      if (!await photoDir.exists()) {
        await photoDir.create(recursive: true);
      }

      final String fileName = 'IMG_${const Uuid().v4()}.jpg';
      final String filePath = '${photoDir.path}/$fileName';
      final File savedImage = await File(photo.path).copy(filePath);

      // 2. EXIF adatok írása (Visszakapcsolva az új kamerával)
      try {
        final exif = await Exif.fromPath(savedImage.path);
        await exif.writeAttributes({
          'GPSLatitude': location.latitude.abs().toString(),
          'GPSLatitudeRef': location.latitude >= 0 ? 'N' : 'S',
          'GPSLongitude': location.longitude.abs().toString(),
          'GPSLongitudeRef': location.longitude >= 0 ? 'E' : 'W',
          'GPSAltitude': altitude.abs().toString(),
          'GPSAltitudeRef': altitude >= 0 ? '0' : '1',
          'GPSImgDirection': heading.toString(),
          'GPSImgDirectionRef': 'T',
        });
        await exif.close();
        debugPrint("Photo processed and geotagged: $filePath");
      } catch (e) {
        debugPrint("Warning: Could not write EXIF metadata: $e");
      }

      return filePath;
    } catch (e) {
      debugPrint("Error processing photo: $e");
      return null;
    }
  }

  Future<void> deletePhoto(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint("Error deleting photo: $e");
    }
  }
}
