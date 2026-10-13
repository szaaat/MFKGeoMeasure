import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/geo_feature.dart';
import '../services/project_service.dart';
import '../services/geoid_service.dart';
import '../l10n/app_localizations.dart';

class ExportConfigDialog extends StatefulWidget {
  final Project project;
  final ProjectLayer? initialLayer;
  final List<GeoFeature>? initialSelection;
  final Rect? sharePositionOrigin;

  const ExportConfigDialog({
    super.key,
    required this.project,
    this.initialLayer,
    this.initialSelection,
    this.sharePositionOrigin,
  });

  @override
  State<ExportConfigDialog> createState() => _ExportConfigDialogState();
}

class _ExportConfigDialogState extends State<ExportConfigDialog> {
  String format = "shp";
  bool useEov = true;
  ProjectLayer? selectedLayer;
  bool exportOnlySelected = false;

  @override
  void initState() {
    super.initState();
    selectedLayer = widget.initialLayer ?? (widget.project.layers.isNotEmpty ? widget.project.layers.first : null);
    exportOnlySelected = (widget.initialSelection != null && widget.initialSelection!.isNotEmpty);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final projectService = context.read<ProjectService>();

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.download, color: Colors.blue),
          const SizedBox(width: 10),
          Text(l10n.export),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("RÉTEG", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
            DropdownButton<ProjectLayer>(
              isExpanded: true,
              value: selectedLayer,
              items: widget.project.layers.map((l) => DropdownMenuItem(value: l, child: Text(l.name))).toList(),
              onChanged: (val) => setState(() => selectedLayer = val),
            ),
            const SizedBox(height: 16),

            const Text("FORMÁTUM", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(label: const Text("SHP"), selected: format == "shp", onSelected: (s) => setState(() => format = "shp")),
                ChoiceChip(label: const Text("GeoJSON"), selected: format == "geojson", onSelected: (s) => setState(() => format = "geojson")),
                ChoiceChip(label: const Text("CSV"), selected: format == "csv", onSelected: (s) => setState(() => format = "csv")),
              ],
            ),
            const SizedBox(height: 16),

            const Text("KOORDINÁTA-RENDSZER", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
            RadioListTile<bool>(
              title: const Text("EOV (EPSG:23700)", style: TextStyle(fontSize: 13)),
              subtitle: const Text("Magyarországi vetület", style: TextStyle(fontSize: 10)),
              value: true, groupValue: useEov, onChanged: (v) => setState(() => useEov = v!),
              contentPadding: EdgeInsets.zero, visualDensity: VisualDensity.compact,
            ),
            RadioListTile<bool>(
              title: const Text("WGS84 (EPSG:4326)", style: TextStyle(fontSize: 13)),
              subtitle: const Text("Globális GPS koordináták", style: TextStyle(fontSize: 10)),
              value: false, groupValue: useEov, onChanged: (v) => setState(() => useEov = v!),
              contentPadding: EdgeInsets.zero, visualDensity: VisualDensity.compact,
            ),
            const SizedBox(height: 16),

            const Text("TARTALOM", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
            CheckboxListTile(
              title: const Text("Csak a kijelölt elemek", style: TextStyle(fontSize: 13)),
              subtitle: Text("${widget.initialSelection?.length ?? 0} elem kijelölve", style: const TextStyle(fontSize: 10)),
              value: exportOnlySelected,
              enabled: widget.initialSelection != null && widget.initialSelection!.isNotEmpty,
              onChanged: (val) => setState(() => exportOnlySelected = val!),
              contentPadding: EdgeInsets.zero, 
              controlAffinity: ListTileControlAffinity.trailing,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
        ElevatedButton.icon(
          icon: const Icon(Icons.check),
          label: const Text("EXPORTÁLÁS"),
          onPressed: selectedLayer == null ? null : () {
            Navigator.pop(context);
            
            final List<GeoFeature>? featuresToExport = exportOnlySelected 
                ? widget.initialSelection
                : null;

            projectService.exportWithFormat(
              context, 
              context.read<GeoidCorrectionService>(), 
              widget.project, 
              format: format, 
              layer: selectedLayer,
              features: featuresToExport,
              sharePositionOrigin: widget.sharePositionOrigin, 
              useEov: useEov,
            );
          },
        ),
      ],
    );
  }
}
