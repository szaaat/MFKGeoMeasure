import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../services/leveling/leveling_service.dart';
import '../../services/leveling/leveling_export_service.dart';
import '../../services/project_service.dart';
import '../../models/leveling/leveling_project.dart';

class LevelingHistoryScreen extends StatelessWidget {
  const LevelingHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final levelingService = context.watch<LevelingService>();
    final history = levelingService.history;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.levelingLogTitle),
      ),
      body: history.isEmpty
          ? Center(child: Text(l10n.noSavedProtocols))
          : ListView.builder(
              itemCount: history.length,
              padding: const EdgeInsets.all(12),
              itemBuilder: (context, index) {
                final project = history[index];
                final stationsCount = project.stations.length;
                final modeStr = project.isPrecision ? l10n.modePrecision : l10n.modeLine;

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
                        Text(l10n.modeLabel(modeStr)),
                        Text(l10n.stationsCount(stationsCount)),
                        Text(l10n.startingPoint(project.startPointId)),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.picture_as_pdf, color: Colors.red),
                          tooltip: 'PDF Export',
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
                                SnackBar(content: Text(l10n.pdfExportFailed(error.toString()))),
                              );
                            }
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
                            PopupMenuItem(value: 'resume', child: Text(l10n.editResume)),
                            PopupMenuItem(value: 'delete', child: Text(l10n.delete, style: const TextStyle(color: Colors.red))),
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
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.confirmDelete),
        content: Text(l10n.confirmDeleteBody(project.name)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.cancel)),
          ElevatedButton(
            onPressed: () {
              service.deleteFromHistory(project.id);
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
  }
}
