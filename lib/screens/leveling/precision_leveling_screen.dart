import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/leveling/leveling_service.dart';
import '../../services/leveling/leveling_export_service.dart';
import '../../services/project_service.dart';
import '../../widgets/leveling/numeric_keypad.dart';
import 'leveling_history_screen.dart';
import 'leveling_log_screen.dart';

class PrecisionLevelingScreen extends StatefulWidget {
  const PrecisionLevelingScreen({super.key});

  @override
  State<PrecisionLevelingScreen> createState() => _PrecisionLevelingScreenState();
}

class _PrecisionLevelingScreenState extends State<PrecisionLevelingScreen> {
  final TextEditingController _foresightNameController = TextEditingController();

  @override
  void dispose() {
    _foresightNameController.dispose();
    super.dispose();
  }

  void _showPointSelector(LevelingService levelingService, {Function(String)? onSelected}) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text('Előre pont kiválasztása', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: levelingService.availablePoints.length,
                itemBuilder: (context, index) {
                  final p = levelingService.availablePoints[index];
                  return ListTile(
                    title: Text(p.name),
                    subtitle: Text(p.altitudes.isNotEmpty ? '${p.altitudes.first.toStringAsFixed(3)} m' : 'Nincs magasság'),
                    onTap: () {
                      if (onSelected != null) {
                        onSelected(p.name);
                      } else {
                        levelingService.updateForesight(p.name, 0.0);
                      }
                      Navigator.pop(ctx);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openKeypad(LevelingService service, String title, Function(double) onConfirm, {double? initialValue}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => NumericKeypad(
        title: title,
        initialValue: initialValue?.toString() ?? '',
        onConfirm: onConfirm,
      ),
    );
  }

  void _showMetadataDialog(LevelingService service) {
    final station = service.currentStation;
    if (station == null) return;

    final surveyorCtrl = TextEditingController(text: station.surveyor);
    final instrumentCtrl = TextEditingController(text: station.instrument);
    final orderCtrl = TextEditingController(text: station.measurementOrder);
    final notesCtrl = TextEditingController(text: station.notes);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Állás információk'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: surveyorCtrl, decoration: const InputDecoration(labelText: 'Mérő személy')),
              TextField(controller: instrumentCtrl, decoration: const InputDecoration(labelText: 'Műszer típusa')),
              TextField(controller: orderCtrl, decoration: const InputDecoration(labelText: 'Mérési sorrend (pl. BFFB)')),
              TextField(controller: notesCtrl, decoration: const InputDecoration(labelText: 'Megjegyzés'), maxLines: 3),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Mégse')),
          ElevatedButton(
            onPressed: () {
              service.updateStationMetadata(
                surveyor: surveyorCtrl.text,
                instrument: instrumentCtrl.text,
                measurementOrder: orderCtrl.text,
                notes: notesCtrl.text,
              );
              Navigator.pop(ctx);
            },
            child: const Text('Mentés'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final levelingService = context.watch<LevelingService>();
    final project = levelingService.activeProject;
    final station = levelingService.currentStation;

    if (project == null || station == null) return const Scaffold(body: Center(child: Text('Hiba: Nincs aktív projekt')));

    final deltaH1 = station.deltaH1;
    final deltaH2 = station.deltaH2;
    final diff = station.stationDiff;
    final isAccepted = station.isPrecisionAccepted;

    // Biztonságos szinkronizáció a vezérlő és az állapot között (kurzor megőrzésével)
    final targetName = station.foresightPointId ?? '';
    if (_foresightNameController.text != targetName) {
      _foresightNameController.value = _foresightNameController.value.copyWith(
        text: targetName,
        selection: TextSelection.collapsed(offset: targetName.length),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('${project.name} - Precíziós'),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf, color: Colors.red),
            tooltip: 'PDF Jegyzőkönyv',
            onPressed: () async {
              try {
                await LevelingExportService.generateAndSharePdf(
                  context,
                  project,
                  context.read<ProjectService>(),
                );
              } catch (error) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('PDF export sikertelen: $error')),
                );
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.analytics_outlined),
            tooltip: 'Statisztika',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LevelingLogScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Szintezési Napló',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LevelingHistoryScreen())),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'finish') {
                levelingService.finishProject();
              } else if (value == 'discard') {
                _showDiscardConfirm(context, levelingService);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'finish', child: Text('Mérés lezárása és Mentés')),
              const PopupMenuItem(value: 'discard', child: Text('Mérés elvetése', style: TextStyle(color: Colors.red))),
            ],
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              color: Colors.blue[50],
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text('Állás #${station.stationId}',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis),
                        ),
                        Flexible(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text('Hátra: ${station.backsightPointId}',
                                  overflow: TextOverflow.ellipsis),
                            ),
                            IconButton(
                              icon: const Icon(Icons.info_outline, size: 20, color: Colors.blueGrey),
                              onPressed: () => _showMetadataDialog(levelingService),
                              constraints: const BoxConstraints(),
                              padding: const EdgeInsets.only(left: 8),
                            )
                          ],
                          ),
                        ),
                      ],
                    ),
                    if (station.surveyor != null || station.instrument != null)
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          '${station.surveyor ?? ""} | ${station.instrument ?? ""} | ${station.measurementOrder ?? ""}',
                          style: const TextStyle(fontSize: 10, color: Colors.blueGrey, fontStyle: FontStyle.italic),
                        ),
                      )
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            _buildReadingCard(
              title: 'FEKETE SKÁLA',
              hLabel: 'Hátra (m)',
              hValue: station.h1,
              eLabel: 'Előre (m)',
              eValue: station.e1,
              deltaH: deltaH1,
              onHTap: () => _openKeypad(levelingService, 'HÁTRA – FEKETE SKÁLA', (val) => levelingService.updatePrecisionReading(h1: val), initialValue: station.h1),
              onETap: () => _openKeypad(levelingService, 'ELŐRE – FEKETE SKÁLA', (val) => levelingService.updatePrecisionReading(e1: val), initialValue: station.e1),
            ),

            const SizedBox(height: 12),

            _buildReadingCard(
              title: 'VÖRÖS SKÁLA',
              hLabel: 'Hátra (m)',
              hValue: station.h2,
              eLabel: 'Előre (m)',
              eValue: station.e2,
              deltaH: deltaH2,
              onHTap: () => _openKeypad(levelingService, 'HÁTRA – VÖRÖS SKÁLA', (val) => levelingService.updatePrecisionReading(h2: val), initialValue: station.h2),
              onETap: () => _openKeypad(levelingService, 'ELŐRE – VÖRÖS SKÁLA', (val) => levelingService.updatePrecisionReading(e2: val), initialValue: station.e2),
            ),

            const SizedBox(height: 16),

            if (diff != null)
              Card(
                color: isAccepted ? Colors.green[50] : Colors.red[50],
                shape: RoundedRectangleBorder(
                  side: BorderSide(color: isAccepted ? Colors.green : Colors.red, width: 2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Expanded(
                            child: Text('Eltérés (d):',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                          Text('${(diff * 1000).toStringAsFixed(2)} mm', 
                            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: isAccepted ? Colors.green : Colors.red)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(isAccepted ? 'ELFOGADVA (≤ 0.5 mm)' : 'TŰRÉSEN KÍVÜL (> 0.5 mm)', 
                        style: TextStyle(fontWeight: FontWeight.bold, color: isAccepted ? Colors.green[700] : Colors.red[700])),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 20),

            if (isAccepted)
              Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _foresightNameController,
                          decoration: const InputDecoration(labelText: 'Előre pont neve', border: OutlineInputBorder()),
                          onChanged: (val) {
                            if (val.isNotEmpty) {
                              levelingService.updateForesight(val, 0.0);
                            }
                          },
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.map, color: Colors.blue),
                        onPressed: () {
                          _showPointSelector(levelingService, onSelected: (name) {
                            levelingService.updateForesight(name, 0.0);
                            _foresightNameController.text = name;
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (station.foresightPointId != null)
                    ElevatedButton.icon(
                      onPressed: () {
                        final nextBacksightId = station.foresightPointId!;
                        levelingService.addStation(nextBacksightId);
                        _foresightNameController.clear();
                      },
                      icon: const Icon(Icons.redo),
                      label: const Text('KÖVETKEZŐ MŰSZERÁLLÁS'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blue[800], foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 50)),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: () => _showFinishConfirm(context, levelingService),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueGrey[800],
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 50),
                      ),
                      icon: const Icon(Icons.flag),
                      label: const Text('MÉRÉS BEFEJEZÉSE'),
                    ),
                ],
              )
            else if (diff != null)
              const Padding(
                padding: EdgeInsets.all(8.0),
                child: Text('A mérési sorozatot meg kell ismételni, mert az eltérés túl nagy.', 
                  textAlign: TextAlign.center, style: TextStyle(color: Colors.red, fontStyle: FontStyle.italic)),
              ),
          ],
        ),
      ),
    );
  }

  void _showDiscardConfirm(BuildContext context, LevelingService service) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mérés elvetése'),
        content: const Text('Biztosan elveted a jelenlegi mérést? Minden nem mentett adat elvész.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Mégse')),
          ElevatedButton(
            onPressed: () {
              service.discardActiveProject();
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Elvetés'),
          ),
        ],
      ),
    );
  }

  void _showFinishConfirm(BuildContext context, LevelingService service) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mérés befejezése'),
        content: const Text('Befejezed a mérést és elmented a jegyzőkönyvet a naplóba?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Mégse')),
          ElevatedButton(
            onPressed: () {
              service.finishProject();
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mérés lezárva és elmentve.')));
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey, foregroundColor: Colors.white),
            child: const Text('Befejezés'),
          ),
        ],
      ),
    );
  }

  Widget _buildReadingCard({
    required String title,
    required String hLabel,
    required double? hValue,
    required String eLabel,
    required double? eValue,
    required double? deltaH,
    required VoidCallback onHTap,
    required VoidCallback onETap,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _buildMiniInputBox(hLabel, hValue, onHTap)),
                const SizedBox(width: 12),
                Expanded(child: _buildMiniInputBox(eLabel, eValue, onETap)),
              ],
            ),
            if (deltaH != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Δh:'),
                    Text('${(deltaH * 1000).toStringAsFixed(1)} mm', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniInputBox(String label, double? value, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
            Text(value != null ? value.toStringAsFixed(3) : '---', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
