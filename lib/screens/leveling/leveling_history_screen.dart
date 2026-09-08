import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/leveling/leveling_service.dart';
import '../../services/leveling/leveling_export_service.dart';
import '../../services/project_service.dart';
import '../../models/leveling/leveling_project.dart';

class LevelingHistoryScreen extends StatelessWidget {
  const LevelingHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final levelingService = context.watch<LevelingService>();
    final history = levelingService.history;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Szintezési Napló'),
      ),
      body: history.isEmpty
          ? const Center(child: Text('Nincsenek mentett jegyzőkönyvek.'))
          : ListView.builder(
              itemCount: history.length,
              padding: const EdgeInsets.all(12),
              itemBuilder: (context, index) {
                final project = history[index];
                final stationsCount = project.stations.length;

                return Card(
                  elevation: 2,
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    title: Text(project.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text('Mód: ${project.isPrecision ? "Precíziós" : "Vonal"}'),
                        Text('Állomások: $stationsCount db'),
                        Text('Induló alappont: ${project.startPointId}'),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.picture_as_pdf, color: Colors.red),
                          tooltip: 'PDF Export',
                          onPressed: () {
                            LevelingExportService.generateAndSharePdf(project, context.read<ProjectService>());
                          },
                        ),
                        PopupMenuButton<String>(
                          onSelected: (value) {
                            if (value == 'resume') {
                              levelingService.resumeFromHistory(project);
                              Navigator.pop(context); // Vissza a mérésre
                            } else if (value == 'delete') {
                              _showDeleteConfirm(context, levelingService, project);
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(value: 'resume', child: Text('Szerkesztés/Folytatás')),
                            const PopupMenuItem(value: 'delete', child: Text('Törlés', style: TextStyle(color: Colors.red))),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  void _showDeleteConfirm(BuildContext context, LevelingService service, LevelingProject project) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Törlés megerősítése'),
        content: Text('Biztosan törlöd a "${project.name}" jegyzőkönyvet?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Mégse')),
          ElevatedButton(
            onPressed: () {
              service.deleteFromHistory(project.id);
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Törlés'),
          ),
        ],
      ),
    );
  }
}
