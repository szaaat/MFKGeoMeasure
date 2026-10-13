import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mfk_geomeasure/main.dart';
import 'package:mfk_geomeasure/providers/language_provider.dart';
import 'package:mfk_geomeasure/services/geoid_service.dart';
import 'package:mfk_geomeasure/services/eov_service.dart';
import 'package:mfk_geomeasure/services/cogo_service.dart';
import 'package:mfk_geomeasure/services/project_service.dart';
import 'package:mfk_geomeasure/services/gnss_info_service.dart';
import 'package:mfk_geomeasure/services/photo_service.dart';
import 'package:mfk_geomeasure/services/template_service.dart';
import 'package:mfk_geomeasure/services/import_service.dart';
import 'package:mfk_geomeasure/services/vector_map_service.dart';
import 'package:mfk_geomeasure/services/learning_service.dart';
import 'package:mfk_geomeasure/services/leveling/leveling_calculation_service.dart';
import 'package:mfk_geomeasure/services/leveling/leveling_service.dart';
import 'package:mfk_geomeasure/services/gnss/rtcm_service.dart';
import 'package:mfk_geomeasure/providers/cogo_provider.dart';

void main() {
  testWidgets('MFK Geomeasure Smoke Test', (WidgetTester tester) async {
    // We mock or use simple instances of services for the smoke test
    final geoidService = GeoidCorrectionService();
    // In a real smoke test we might want to avoid loading the heavy geoid file, 
    // but GeoidCorrectionService is designed to handle missing data gracefully.

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => LanguageProvider()),
          Provider.value(value: geoidService),
          Provider(
              create: (_) => EovService(
                  null, false, EovInputFrame.unknown, EovTransformMode.legacy)),
          ProxyProvider<EovService, CogoService>(
            update: (_, eov, __) => CogoService(eov),
          ),
          ChangeNotifierProxyProvider2<CogoService, EovService, CogoProvider>(
            create: (ctx) => CogoProvider(ctx.read<CogoService>(), ctx.read<EovService>()),
            update: (_, cogoSvc, eov, cogoProv) => cogoProv ?? CogoProvider(cogoSvc, eov),
          ),
          ChangeNotifierProvider(create: (ctx) => GnssInfoService(geoidService)),
          ChangeNotifierProvider(create: (_) => RtcmService()),
          ChangeNotifierProvider(create: (_) => PhotoService()),
          ChangeNotifierProvider(create: (_) => TemplateService()),
          ChangeNotifierProxyProvider<EovService, ImportService>(
            create: (_) => ImportService(),
            update: (_, eov, importSvc) => importSvc!..updateEovService(eov),
          ),
          ChangeNotifierProvider(create: (_) => VectorMapService()),
          ProxyProvider<CogoService, LearningService>(
            update: (_, cogo, __) => LearningService(cogo),
          ),
          ChangeNotifierProxyProvider3<EovService, GeoidCorrectionService, GnssInfoService, ProjectService>(
            create: (_) => ProjectService(),
            update: (ctx, eov, geoid, gnss, projectSvc) {
              final rtcm = ctx.read<RtcmService>();
              return projectSvc!
                ..updateEovService(eov)
                ..updateGeoidService(geoid)
                ..updateGnssServices(gnss, rtcm);
            },
          ),
          Provider(create: (_) => LevelingCalculationService()),
          ChangeNotifierProxyProvider2<LevelingCalculationService, ProjectService, LevelingService>(
            create: (ctx) => LevelingService(ctx.read<LevelingCalculationService>()),
            update: (_, calc, projectSvc, levelingSvc) => levelingSvc!..updateProjectService(projectSvc),
          ),
        ],
        child: const MyApp(),
      ),
    );

    // Verify that the app initializes and renders something (HomeScreen slogan or title)
    // LanguageProvider defaults to EN or system locale.
    expect(find.byType(MaterialApp), findsOneWidget);
    
    // Check if HomeScreen is visible by looking for a known text from l10n
    // Since l10n is async/provided, we might need a small delay or just check for Scaffold
    expect(find.byType(Scaffold), findsAtLeast(1));
  });
}
