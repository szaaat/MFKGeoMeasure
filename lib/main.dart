import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

// Saját fájlok importálása
import 'l10n/app_localizations.dart';
import 'providers/language_provider.dart';
import 'services/geoid_service.dart';
import 'services/eov_service.dart';
import 'services/cogo_service.dart';
import 'services/project_service.dart';
import 'services/gnss_info_service.dart';
import 'services/photo_service.dart';
import 'services/template_service.dart';
import 'services/import_service.dart';
import 'services/vector_map_service.dart';
import 'services/learning_service.dart';
import 'services/leveling/leveling_calculation_service.dart';
import 'services/leveling/leveling_service.dart';
import 'services/gnss/rtcm_service.dart';
import 'providers/cogo_provider.dart';
import 'package:camera/camera.dart';
import 'screens/home_screen.dart';

List<CameraDescription> cameras = [];

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    cameras = await availableCameras();
  } catch (e) {
    debugPrint("Error fetching cameras: $e");
  }
  
  final geoidService = GeoidCorrectionService();
  await geoidService.loadGeoidFile();

  runApp(
    MultiProvider(
      providers: [
        // Nyelvi beállítások
        ChangeNotifierProvider(create: (_) => LanguageProvider()),

        // Geoid magasságkorrekció
        Provider.value(value: geoidService),

        // EOV Szolgáltatás (Globális vetületi motor)
        Provider(create: (_) => EovService()),

        // COGO Szolgáltatás
        ProxyProvider<EovService, CogoService>(
          update: (_, eov, __) => CogoService(eov),
        ),

        // COGO State Provider
        ChangeNotifierProxyProvider2<CogoService, EovService, CogoProvider>(
          create: (ctx) => CogoProvider(ctx.read<CogoService>(), ctx.read<EovService>()),
          update: (_, cogoSvc, eov, cogoProv) => cogoProv ?? CogoProvider(cogoSvc, eov),
        ),

        // GNSS diagnosztika (Műholdak száma stb.)
        ChangeNotifierProvider(create: (ctx) => GnssInfoService(ctx.read<GeoidCorrectionService>())),

        // RTK / NTRIP Szolgáltatás
        ChangeNotifierProvider(create: (_) => RtcmService()),

        // Fotó szolgáltatás
        ChangeNotifierProvider(create: (_) => PhotoService()),

        // Sablon szolgáltatás
        ChangeNotifierProvider(create: (_) => TemplateService()),

        // Import szolgáltatás
        ChangeNotifierProxyProvider<EovService, ImportService>(
          create: (_) => ImportService(),
          update: (_, eov, importSvc) => importSvc!..updateEovService(eov),
        ),

        // Vektoros térkép szolgáltatás
        ChangeNotifierProvider(create: (_) => VectorMapService()),

        // Tanulás szolgáltatás
        ProxyProvider<CogoService, LearningService>(
          update: (_, cogo, __) => LearningService(cogo),
        ),

        // Adatgyűjtés (pontok, vonalak) kezelője
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

        // Szintezés Szolgáltatás
        Provider(create: (_) => LevelingCalculationService()),
        ChangeNotifierProxyProvider2<LevelingCalculationService, ProjectService, LevelingService>(
          create: (ctx) => LevelingService(ctx.read<LevelingCalculationService>()),
          update: (_, calc, projectSvc, levelingSvc) => levelingSvc!..updateProjectService(projectSvc),
        ),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final languageProvider = Provider.of<LanguageProvider>(context);

    return MaterialApp(
      title: 'MFK GeoMeasure',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        // Modern Material 3 dizájn
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      // Nyelv beállítása
      locale: languageProvider.currentLocale,

      // Lokalizációs modulok
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],

      // Támogatott nyelvek
      supportedLocales: const [
        Locale('en'), // Angol
        Locale('hu'), // Magyar
      ],

      // Kezdőképernyő
      home: const HomeScreen(),
    );
  }
}
