import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Importok
import '../l10n/app_localizations.dart';
import '../providers/language_provider.dart';
import '../services/geoid_service.dart';
import 'map_screen.dart';
import 'learning/learning_menu_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // Geoid fájl betöltése az app indulásakor (csak ha még nincs betöltve)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final service = context.read<GeoidCorrectionService>();
        if (!service.isLoaded) {
          service.loadGeoidFile();
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final langProvider = Provider.of<LanguageProvider>(context);
    final appTitle = l10n.appTitle;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(appTitle, style: const TextStyle(fontSize: 18)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              langProvider.changeLanguage(Locale(value));
            },
            icon: const Icon(Icons.language, color: Colors.black87),
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'hu', child: Text('Magyar')),
              const PopupMenuItem(value: 'en', child: Text('English')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10),
            child: Column(
              children: [
                const SizedBox(height: 40),
  
                // 1. LOGÓ KÉP (KÓDBÓL GENERÁLT GEODÉZIAI GÖMB)
                Container(
                  width: 180,
                  height: 180,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    // Szép kék gradiens háttér, mintha egy bolygó lenne
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Colors.blue.shade400, Colors.blue.shade900],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 15,
                        offset: const Offset(0, 8),
                      )
                    ],
                  ),
                  // A földgömb ikon a közepén
                  child: const Center(
                    child: Icon(
                      Icons.public, // Ez a földgömb ikon
                      size: 110,
                      color: Colors.white,
                    ),
                  ),
                ),
  
                const SizedBox(height: 30),
  
                // 2. SZLOGEN
                Text(
                  l10n.slogan,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    fontStyle: FontStyle.italic,
                    color: Colors.green, // Zöld szín
                    letterSpacing: 1.1,
                  ),
                ),
  
                const SizedBox(height: 50),
  
                // 3. INDÍTÁS GOMB
                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue[800],
                      foregroundColor: Colors.white,
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const MapScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.map_outlined, size: 26),
                    label: Text(
                        l10n.startMap.toUpperCase(),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.0)
                    ),
                  ),
                ),
  
                const SizedBox(height: 15),
  
                // 3b. TANULÁS GOMB
                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.blue[800]!, width: 2),
                      foregroundColor: Colors.blue[800],
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const LearningMenuScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.school_outlined, size: 26),
                    label: Text(
                        l10n.startLearning.toUpperCase(),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.0)
                    ),
                  ),
                ),
  
                const SizedBox(height: 60),
  
                // 4. FEJLESZTŐI INFÓ
                Column(
                  children: [
                    const Divider(indent: 50, endIndent: 50),
                    const SizedBox(height: 12),
                    Text(
                      l10n.uniName,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[850],
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      l10n.institute,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
