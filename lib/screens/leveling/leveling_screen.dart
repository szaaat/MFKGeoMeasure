import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../l10n/app_localizations.dart';
import '../../services/leveling/leveling_service.dart';
import '../../models/geo_feature.dart';
import '../../widgets/leveling/numeric_keypad.dart';
import 'precision_leveling_screen.dart';
import 'leveling_history_screen.dart';
import 'leveling_log_screen.dart';

class LevelingScreen extends StatefulWidget {
  const LevelingScreen({super.key});

  @override
  State<LevelingScreen> createState() => _LevelingScreenState();
}

class _LevelingScreenState extends State<LevelingScreen> {
  final TextEditingController _foresightNameController = TextEditingController();

  AppLocalizations get l10n => AppLocalizations.of(context)!;

  @override
  void dispose() {
    _foresightNameController.dispose();
    super.dispose();
  }

  void _showStartProjectDialog(LevelingService levelingService) {
    final nameController = TextEditingController(text: l10n.newLeveling);
    final pointNameController = TextEditingController();
    final heightController = TextEditingController();
    bool isPrecision = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(l10n.startLevelingLine),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(labelText: l10n.lineName),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: pointNameController,
                      decoration: InputDecoration(labelText: l10n.startPointName),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.map, color: Colors.blue),
                    onPressed: () {
                      _showPointSelector(levelingService, onSelected: (p) {
                        setDialogState(() {
                          if (p != null) {
                            pointNameController.text = p.name;
                            if (p.altitudes.isNotEmpty) {
                              heightController.text = p.altitudes.first.toStringAsFixed(3);
                            } else if (p.calculatedStats.containsKey('Balti magasság')) {
                              heightController.text = (p.calculatedStats['Balti magasság'] as num).toStringAsFixed(3);
                            } else if (p.calculatedStats.containsKey('Ellipszoidi magasság')) {
                              heightController.text = (p.calculatedStats['Ellipszoidi magasság'] as num).toStringAsFixed(3);
                            }
                          }
                        });
                      });
                    },
                  ),
                ],
              ),
              TextField(
                controller: heightController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                decoration: InputDecoration(
                  labelText: l10n.startHeightM,
                  hintText: '0.000',
                  helperText: 'Ismeretlen magasság esetén hagyhatja 0.000 m értéken',
                ),
              ),
              const SizedBox(height: 10),
              SwitchListTile(
                title: Text(l10n.precisionMode),
                subtitle: Text(l10n.precisionModeSub),
                value: isPrecision,
                onChanged: (val) => setDialogState(() => isPrecision = val),
              ),
            ],
          ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.cancel)),
            ElevatedButton(
              onPressed: () {
                final pointName = pointNameController.text.trim();
                final heightText = heightController.text.trim().replaceAll(',', '.');

                if (pointName.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Kérjük adja meg a kezdőpont nevét!'), backgroundColor: Colors.red),
                  );
                  return;
                }

                // Ismeretlen magasság esetén alapértelmezett a 0.000 m
                final double startHeight = heightText.isEmpty ? 0.0 : (double.tryParse(heightText) ?? 0.0);

                levelingService.startNewProject(
                  id: const Uuid().v4(),
                  name: nameController.text.trim().isNotEmpty ? nameController.text.trim() : l10n.newLeveling,
                  startPointId: pointName,
                  startHeight: startHeight,
                  isPrecision: isPrecision,
                );
                levelingService.addStation(pointName);
                Navigator.pop(ctx);
                setState(() {});

                if (isPrecision) {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const PrecisionLevelingScreen()),
                  );
                }
              },
              child: Text(l10n.startLevelingLine),
            ),
          ],
        ),
      ),
    );
  }

  void _showPointSelector(LevelingService levelingService, {Function(GeoFeature?)? onSelected}) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text('Válassz pontot a projektből', style: TextStyle(fontWeight: FontWeight.bold)),
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
                        onSelected(p);
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

  void _showAddIntermediateDialog(LevelingService service) {
    final nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Új közbenső pont'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Pont neve'),
                    autofocus: true,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.map, color: Colors.blue),
                  onPressed: () {
                    _showPointSelector(service, onSelected: (p) {
                      if (p != null) {
                        nameController.text = p.name;
                      }
                    });
                  },
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Mégse')),
          ElevatedButton(
            onPressed: () {
              if (nameController.text.isNotEmpty) {
                Navigator.pop(ctx);
                _openKeypad(service, 'KÖZBENSŐ: ${nameController.text}', (val) {
                  service.addIntermediateReading(nameController.text, val);
                });
              }
            },
            child: const Text('Tovább'),
          ),
        ],
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

  @override
  Widget build(BuildContext context) {
    final levelingService = context.watch<LevelingService>();
    final project = levelingService.activeProject;
    final station = levelingService.currentStation;

    if (project != null && project.isPrecision) {
      return const PrecisionLevelingScreen();
    }

    if (project == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Vonal szintezés'),
          actions: [
            IconButton(
              icon: const Icon(Icons.history),
              tooltip: l10n.levelingLogTitle,
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LevelingHistoryScreen())),
            )
          ],
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.height, size: 80, color: Colors.blueGrey),
              const SizedBox(height: 20),
              Text(l10n.noActiveLevelingLine),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => _showStartProjectDialog(levelingService),
                child: Text(l10n.startNewLine),
              ),
            ],
          ),
        ),
      );
    }

    final mh = levelingService.currentInstrumentHeight;
    final startH = levelingService.getPointHeight(station?.backsightPointId ?? '');
    
    double? fsHeight;
    if (mh != null && station?.foresight != null) {
      fsHeight = mh - station!.foresight!;
    }

    // Biztonságos szinkronizáció a vezérlő és az állapot között (kurzor megőrzésével)
    final targetName = station?.foresightPointId ?? '';
    if (_foresightNameController.text != targetName) {
      _foresightNameController.value = _foresightNameController.value.copyWith(
        text: targetName,
        selection: TextSelection.collapsed(offset: targetName.length),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(project.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: l10n.levelingLogTitle,
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
              PopupMenuItem(value: 'finish', child: Text(l10n.finishAndSave)),
              PopupMenuItem(value: 'discard', child: Text(l10n.discardMeasurement, style: const TextStyle(color: Colors.red))),
            ],
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LinearProgressIndicator(
              value: (station?.backsight != null ? 0.33 : 0.0) + (station?.foresight != null ? 0.33 : 0.0) + (station != null && station.intermediateReadings.isNotEmpty ? 0.34 : 0.0),
              backgroundColor: Colors.grey[200],
              color: Colors.blue,
            ),
            const SizedBox(height: 16),

            ElevatedButton.icon(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LevelingLogScreen())),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[50],
                foregroundColor: Colors.blue[800],
                elevation: 0,
                minimumSize: const Size(double.infinity, 45),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: Colors.blue.shade200)),
              ),
              icon: const Icon(Icons.menu_book),
              label: Text(l10n.reviewLog, style: const TextStyle(fontWeight: FontWeight.bold)),
            ),

            const SizedBox(height: 16),

            // HÁTRAPONT KÁRTYA
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Expanded(
                          child: Text('HÁTRAPONT',
                              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Állás #${station?.stationId ?? 1}',
                                style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
                                overflow: TextOverflow.ellipsis),
                            IconButton(
                              icon: const Icon(Icons.info_outline, size: 20, color: Colors.blueGrey),
                              onPressed: () => _showMetadataDialog(levelingService),
                              constraints: const BoxConstraints(),
                              padding: const EdgeInsets.only(left: 8),
                            )
                          ],
                        ),
                      ],
                    ),
                    if (station?.surveyor != null || station?.instrument != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Text(
                          '${station?.surveyor ?? ""} | ${station?.instrument ?? ""}',
                          style: const TextStyle(fontSize: 10, color: Colors.grey, fontStyle: FontStyle.italic),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Text(
                      station?.backsightPointId ?? 'Ismeretlen',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    Text('Alappont magassága: ${startH.toStringAsFixed(3)} m'),
                    const Divider(height: 24),
                    
                    _buildInputBox(
                      label: 'Hátra leolvasás (m)',
                      value: station?.backsight,
                      onTap: () => _openKeypad(levelingService, 'HÁTRAPONT: ${station?.backsightPointId}', (val) {
                        levelingService.updateBacksight(val);
                      }, initialValue: station?.backsight),
                    ),
                    
                    _buildValidationBanner(context, levelingService, station?.backsight),

                    if (mh != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.orange[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.orange)),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Expanded(
                              child: Text('Műszerhorizont (MH):',
                                  style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                            Text('${mh.toStringAsFixed(3)} m',
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.orange)),
                          ],
                        ),
                      ),
                    ]
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // KÖZBENSŐ PONTOK KÁRTYA
            if (mh != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('KÖZBENSŐ PONTOK', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline, color: Colors.blue),
                            onPressed: () => _showAddIntermediateDialog(levelingService),
                          )
                        ],
                      ),
                      if (station?.intermediateReadings.isEmpty ?? true)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Text('Nincs rögzített közbenső pont', style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.grey)),
                        )
                      else
                        ...station!.intermediateReadings.map((reading) {
                          final pName = reading.pointId;
                          final pHeight = mh - reading.value;
                          return ListTile(
                            dense: true,
                            title: Text(pName),
                            subtitle: Text('Leolvasás: ${reading.value.toStringAsFixed(3)} m'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('${pHeight.toStringAsFixed(3)} m',
                                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                                IconButton(
                                  icon: const Icon(Icons.save_outlined, size: 16),
                                  onPressed: () => _showConfirmSaveDialog(levelingService, reading.pointId, pHeight),
                                )
                              ],
                            ),
                          );
                        }),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 16),

            // ELŐREPONT KÁRTYA
            if (station?.backsight != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('ELŐREPONT', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _foresightNameController,
                              decoration: const InputDecoration(labelText: 'Előre pont neve', border: OutlineInputBorder()),
                              onChanged: (val) {
                                if (val.isNotEmpty) {
                                  levelingService.updateForesight(val, station?.foresight ?? 0.0);
                                }
                              },
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.map, color: Colors.blue),
                            onPressed: () {
                              _showPointSelector(levelingService, onSelected: (p) {
                                if (p != null) {
                                  levelingService.updateForesight(p.name, station?.foresight ?? 0.0);
                                  _foresightNameController.text = p.name;
                                }
                              });
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      
                      _buildInputBox(
                        label: 'Előre leolvasás (m)',
                        value: station?.foresight,
                        onTap: () {
                           if (station?.foresightPointId == null || station!.foresightPointId!.isEmpty) {
                             ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Előbb add meg az előre pont nevét!')));
                             return;
                           }
                           _openKeypad(levelingService, 'ELŐRE: ${station.foresightPointId}', (val) {
                             levelingService.updateForesight(station.foresightPointId!, val);
                           }, initialValue: station.foresight);
                        },
                      ),
                      
                      _buildValidationBanner(context, levelingService, station?.foresight),

                      const SizedBox(height: 16),
                      _buildInputBox(
                        label: 'Távolság (m - opcionális)',
                        value: station?.distance,
                        onTap: () => _openKeypad(levelingService, 'TÁVOLSÁG: ${station?.stationId}. állás', (val) {
                          levelingService.updateStationDistance(val);
                        }, initialValue: station?.distance),
                      ),

                      if (fsHeight != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: Colors.green[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.green)),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Expanded(
                                child: Text('Számított magasság:',
                                    style: TextStyle(fontWeight: FontWeight.bold)),
                              ),
                              Text('${fsHeight.toStringAsFixed(3)} m', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green)),
                            ],
                          ),
                        ),
                      ]
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 24),

            if (fsHeight != null)
              Column(
                children: [
                  ElevatedButton.icon(
                    onPressed: () => _showConfirmSaveDialog(levelingService, station!.foresightPointId!, fsHeight!),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 50)),
                    icon: const Icon(Icons.check_circle),
                    label: Text(l10n.saveHeightToPoint),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () {
                      if (station?.foresight == null) {
                         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.missingBacksightError)));
                         return;
                      }
                      final nextBacksightId = station!.foresightPointId!;
                      levelingService.addStation(nextBacksightId);
                      _foresightNameController.clear();
                    },
                    style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
                    icon: const Icon(Icons.redo),
                    label: const Text('NEXT STATION'),
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
                    label: Text(l10n.finishMeasurement),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBox({required String label, double? value, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[400]!),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: Colors.blueGrey)),
                  const SizedBox(height: 4),
                  Text(
                    value != null ? value.toStringAsFixed(3) : '---',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            const Icon(Icons.keyboard_alt_outlined, color: Colors.blue),
          ],
        ),
      ),
    );
  }

  Widget _buildValidationBanner(BuildContext context, LevelingService service, double? value) {
    if (value == null) return const SizedBox();
    
    if (value < 0) {
      return Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: Colors.red[50], borderRadius: BorderRadius.circular(5)),
        child: Row(
          children: [
            const Icon(Icons.error, color: Colors.red, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(l10n.negativeReadingError,
                  style: const TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    }
    if (value > 4.0) {
      return Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: Colors.amber[50], borderRadius: BorderRadius.circular(5)),
        child: const Row(
          children: [
            Icon(Icons.warning, color: Colors.orange, size: 16),
            SizedBox(width: 8),
            Expanded(
              child: Text('Warning: Unusually high reading (>4m)',
                  style: TextStyle(color: Colors.orange, fontSize: 12)),
            ),
          ],
        ),
      );
    }
    return const SizedBox();
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
        title: const Text('Station Information'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: surveyorCtrl, decoration: const InputDecoration(labelText: 'Surveyor')),
              TextField(controller: instrumentCtrl, decoration: const InputDecoration(labelText: 'Instrument Model')),
              TextField(controller: orderCtrl, decoration: InputDecoration(labelText: l10n.measurementOrder)),
              TextField(controller: notesCtrl, decoration: InputDecoration(labelText: l10n.description), maxLines: 3),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.cancel)),
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
            child: Text(l10n.save),
          ),
        ],
      ),
    );
  }

  void _showConfirmSaveDialog(LevelingService service, String pointId, double newHeight) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.updateHeight),
        content: Text('Save leveled height (${newHeight.toStringAsFixed(3)} m) for point $pointId?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.cancel)),
          ElevatedButton(
            onPressed: () {
              service.saveLeveledHeightToPoint(pointId, newHeight);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.heightSaved)));
            },
            child: Text(l10n.save),
          ),
        ],
      ),
    );
  }

  void _showDiscardConfirm(BuildContext context, LevelingService service) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.discardMeasurement),
        content: const Text('Are you sure you want to discard the current measurement? All unsaved data will be lost.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.cancel)),
          ElevatedButton(
            onPressed: () {
              service.discardActiveProject();
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
  }

  void _showFinishConfirm(BuildContext context, LevelingService service) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.finishMeasurement),
        content: const Text('Finish measurement and save protocol to log?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.cancel)),
          ElevatedButton(
            onPressed: () {
              service.finishProject();
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.measurementFinishedSaved)));
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey, foregroundColor: Colors.white),
            child: Text(l10n.done),
          ),
        ],
      ),
    );

  }
}
