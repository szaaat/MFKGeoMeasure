import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

class VectorMapService extends ChangeNotifier {
  String? _mbtilesPath;
  bool _isVectorEnabled = false;

  String? get mbtilesPath => _mbtilesPath;
  bool get isVectorEnabled => _isVectorEnabled;

  Future<void> pickMbTiles() async {
    PlatformFile? result = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['mbtiles'],
    );

    if (result != null && result.path != null) {
      _mbtilesPath = result.path;
      _isVectorEnabled = true;
      notifyListeners();
    }
  }

  void toggleVector(bool value) {
    _isVectorEnabled = value;
    notifyListeners();
  }
}
