import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mfk_geomeasure/services/import_service.dart';
import 'package:mfk_geomeasure/services/eov_service.dart';
import 'package:path/path.dart' as p;

void main() {
  group('ImportService - Multi-file & ZIP Logic', () {
    late ImportService importService;
    late EovService eovService;

    setUp(() {
      eovService = EovService();
      importService = ImportService();
      importService.updateEovService(eovService);
    });

    test('File Grouping Logic (Sibling Discovery)', () {
      final files = [
        File('/tmp/roads.shp'),
        File('/tmp/roads.dbf'),
        File('/tmp/roads.shx'),
        File('/tmp/roads.prj'),
        File('/tmp/points.shp'),
        File('/tmp/points.dbf'),
        File('/tmp/notes.txt'),
      ];

      // Accessing private method for logic verification
      // ignore: invalid_use_of_protected_member
      final sets = importService.groupFilesToSetsForTest(files);

      expect(sets.length, 2);
      
      final roads = sets.firstWhere((s) => s.baseName == 'roads');
      expect(roads.shpFile.path, contains('roads.shp'));
      expect(roads.dbfFile, isNotNull);
      expect(roads.shxFile, isNotNull);
      expect(roads.prjFile, isNotNull);
      expect(roads.isComplete, isTrue);

      final points = sets.firstWhere((s) => s.baseName == 'points');
      expect(points.shpFile.path, contains('points.shp'));
      expect(points.shxFile, isNull); // Missing
      expect(points.isComplete, isFalse);
    });

    test('EOV to WGS84 Transformation Accuracy (Hungarian Standard)', () {
      // Test point in Miskolc, Hungary
      const double eovY = 741234.56;
      const double eovX = 301234.56;
      
      // ignore: invalid_use_of_protected_member
      final wgs = importService.toWgsForTest(eovY, eovX, "EOV");
      
      // Miskolc is approx 48.1 N, 20.7 E
      expect(wgs.latitude, closeTo(48.1, 0.5));
      expect(wgs.longitude, closeTo(20.7, 0.5));
    });
  });
}
