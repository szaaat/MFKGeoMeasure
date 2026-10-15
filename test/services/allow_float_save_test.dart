import 'package:flutter_test/flutter_test.dart';
import 'package:mfk_geomeasure/models/ntrip_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('allowFloatSave Settings Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({'allowFloatSave': true});
    });

    test('NtripSettings defaults allowFloatSave to true', () {
      final settings = NtripSettings();
      expect(settings.allowFloatSave, isTrue);
    });

    test('NtripSettings converts allowFloatSave to/from JSON correctly', () {
      final settings = NtripSettings(allowFloatSave: true);
      final json = settings.toJson();

      expect(json['allowFloatSave'], isTrue);

      final restored = NtripSettings.fromJson(json);
      expect(restored.allowFloatSave, isTrue);
    });

    test('SharedPreferences stores and retrieves allowFloatSave correctly', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('allowFloatSave', true);

      expect(prefs.getBool('allowFloatSave'), isTrue);

      await prefs.setBool('allowFloatSave', false);
      expect(prefs.getBool('allowFloatSave'), isFalse);
    });
  });
}
