import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';
import 'package:mfk_geomeasure/services/gnss/mfkrtk_ota_service.dart';

void main() {
  group('MfkRtkOtaService Tests', () {
    late MfkRtkOtaService otaService;

    setUp(() {
      otaService = MfkRtkOtaService();
      otaService.reset();
    });

    test('Prepare firmware calculates size and SHA-256 correctly', () async {
      // Create a dummy .bin file
      final file = File('test_dummy.bin');
      final bytes = Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0x01, 0x02]);
      await file.writeAsBytes(bytes);

      await otaService.prepareFirmwareFromFile(file, '1.0.0');

      expect(otaService.firmwareSize, equals(7));
      expect(otaService.firmwareVersion, equals('1.0.0'));
      expect(otaService.sha256Hash, equals(sha256.convert(bytes).toString().toLowerCase()));
      expect(otaService.state, equals(OtaUpdateState.idle));

      await file.delete();
    });
  });
}
