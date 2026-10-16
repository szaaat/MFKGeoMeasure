import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'bme_grid_service.dart';

enum GeoidInputFrame { unknown, etrf2000, assumed }

class _GeoidGrid {
  final int width;
  final int height;
  final double originLon;
  final double originLat;
  final double pixelWidth;
  final double pixelHeight;
  final double noData;
  final List<double> values;

  const _GeoidGrid({
    required this.width,
    required this.height,
    required this.originLon,
    required this.originLat,
    required this.pixelWidth,
    required this.pixelHeight,
    required this.noData,
    required this.values,
  });

  double valueAt(int x, int y) => values[y * width + x];
}

class GeoidResult {
  final double value;
  final String gridName;
  GeoidResult(this.value, this.gridName);
}

class GeoidCorrectionService {
  final BmeGridService gridService;
  _GeoidGrid? _grid;
  bool _isLoading = false;
  bool get isLoaded => _grid != null;

  GeoidCorrectionService([BmeGridService? gridService])
      : gridService = gridService ?? BmeGridService();

  Future<void> loadBmeGrid() => gridService.load();

  Future<void> loadGeoidFile() async {
    if (isLoaded || _isLoading) return;
    _isLoading = true;
    try {
      final data = await rootBundle.load('assets/data/geoid_eht2014.tif');
      final bytes = Uint8List.sublistView(data);
      final decoded = await compute(_decodeGeoTiff, bytes);
      _grid = _GeoidGrid(
        width: decoded['width'] as int,
        height: decoded['height'] as int,
        originLon: decoded['originLon'] as double,
        originLat: decoded['originLat'] as double,
        pixelWidth: decoded['pixelWidth'] as double,
        pixelHeight: decoded['pixelHeight'] as double,
        noData: decoded['noData'] as double,
        values: (decoded['values'] as List<dynamic>).cast<double>(),
      );
      debugPrint('Geoid GeoTIFF loaded: ${_grid!.width}x${_grid!.height}');
    } catch (error) {
      debugPrint('Error loading geoid GeoTIFF: $error');
    } finally {
      _isLoading = false;
    }
  }

  GeoidResult? getUndulation(double lat, double lon,
      {GeoidInputFrame referenceFrame = GeoidInputFrame.unknown}) {
    final bmeValue = gridService.geoidUndulation(lon, lat);
    if (bmeValue != null) return GeoidResult(bmeValue, 'BME_geoid2014');
    
    final grid = _grid;
    if (grid == null || !lat.isFinite || !lon.isFinite) return null;
    final x = (lon - grid.originLon) / grid.pixelWidth;
    final y = (grid.originLat - lat) / grid.pixelHeight;
    if (x < 0 || x > grid.width - 1 || y < 0 || y > grid.height - 1) {
      return null;
    }

    final x0 = x.floor();
    final y0 = y.floor();
    final x1 = x.ceil().clamp(0, grid.width - 1);
    final y1 = y.ceil().clamp(0, grid.height - 1);
    final tx = x - x0;
    final ty = y - y0;
    final samples = [
      grid.valueAt(x0, y0),
      grid.valueAt(x1, y0),
      grid.valueAt(x0, y1),
      grid.valueAt(x1, y1),
    ];
    if (samples.any((value) => !value.isFinite || value == grid.noData)) {
      return null;
    }
    final top = samples[0] + (samples[1] - samples[0]) * tx;
    final bottom = samples[2] + (samples[3] - samples[2]) * tx;
    return GeoidResult(top + (bottom - top) * ty, 'GeoTIFF_EHT2014');
  }

  GeoidResult? getOrthoHeight(double lat, double lon, double gpsAlt,
      {required bool isEllipsoidal,
      GeoidInputFrame referenceFrame = GeoidInputFrame.unknown}) {
    if (!isEllipsoidal) return null; // We don't apply correction if already orthometric
    final result = getUndulation(lat, lon, referenceFrame: referenceFrame);
    if (result == null) return null;
    return GeoidResult(gpsAlt - result.value, result.gridName);
  }
}

Map<String, dynamic> _decodeGeoTiff(Uint8List bytes) {
  final view = ByteData.sublistView(bytes);
  final littleEndian = view.getUint16(0, Endian.big) == 0x4949;
  Endian order(int size) => littleEndian ? Endian.little : Endian.big;
  final endian = order(2);
  final ifdOffset = view.getUint32(4, endian);
  final count = view.getUint16(ifdOffset, endian);
  final tags = <int, List<int>>{};

  int typeSize(int type) =>
      const {1: 1, 2: 1, 3: 2, 4: 4, 5: 8, 11: 4, 12: 8}[type] ?? 0;
  for (var i = 0; i < count; i++) {
    final offset = ifdOffset + 2 + i * 12;
    final tag = view.getUint16(offset, endian);
    final type = view.getUint16(offset + 2, endian);
    final itemCount = view.getUint32(offset + 4, endian);
    final size = typeSize(type) * itemCount;
    final valueOffset =
        size <= 4 ? offset + 8 : view.getUint32(offset + 8, endian);
    tags[tag] = List<int>.generate(size, (j) => bytes[valueOffset + j]);
  }

  int uint(List<int> data) => data.length == 2
      ? ByteData.sublistView(Uint8List.fromList(data)).getUint16(0, endian)
      : ByteData.sublistView(Uint8List.fromList(data)).getUint32(0, endian);
  double real(List<int> data) {
    final b = ByteData.sublistView(Uint8List.fromList(data));
    return data.length == 4 ? b.getFloat32(0, endian) : b.getFloat64(0, endian);
  }

  List<double> reals(int tag) {
    final data = tags[tag]!;
    final size = data.length ~/ (data.length % 8 == 0 ? 8 : 4);
    return List<double>.generate(
        size,
        (i) => real(data.sublist(i * (data.length % 8 == 0 ? 8 : 4),
            (i + 1) * (data.length % 8 == 0 ? 8 : 4))));
  }

  final width = uint(tags[256]!);
  final height = uint(tags[257]!);
  final bits = uint(tags[258]!);
  final samplesPerPixel = uint(tags[277]!);
  final sampleFormat = tags[339] == null ? 1 : uint(tags[339]!);
  if (bits != 32 || samplesPerPixel != 1 || sampleFormat != 3) {
    throw const FormatException('Unsupported geoid TIFF raster format');
  }
  final scale = reals(33550);
  final tie = reals(33922);
  final stripOffsets = _uintArray(tags[273]!, endian);
  final stripByteCounts = _uintArray(tags[279]!, endian);
  final values = <double>[];
  for (var strip = 0; strip < stripOffsets.length; strip++) {
    for (var i = 0; i < stripByteCounts[strip]; i += 4) {
      values.add(view.getFloat32(stripOffsets[strip] + i, endian));
    }
  }
  if (values.length != width * height) {
    throw const FormatException('Invalid geoid TIFF raster size');
  }
  final noData = tags[42113] == null
      ? double.nan
      : double.tryParse(String.fromCharCodes(tags[42113]!)
              .replaceAll('\x00', '')
              .trim()) ??
          double.nan;
  return {
    'width': width,
    'height': height,
    'originLon': tie[3],
    'originLat': tie[4],
    'pixelWidth': scale[0],
    'pixelHeight': scale[1],
    'noData': noData,
    'values': values,
  };
}

List<int> _uintArray(List<int> bytes, Endian endian) {
  final view = ByteData.sublistView(Uint8List.fromList(bytes));
  final size = bytes.length ~/ 4;
  return List<int>.generate(size, (i) => view.getUint32(i * 4, endian));
}
