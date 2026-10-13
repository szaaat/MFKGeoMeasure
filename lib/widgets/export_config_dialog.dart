import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/geo_feature.dart';
import '../services/project_service.dart';
import '../services/geoid_service.dart';
import '../services/data_validation_service.dart';
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
            Text(l10n.pointLayer.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
            DropdownButton<ProjectLayer>(
              isExpanded: true,
              value: selectedLayer,
              items: widget.project.layers.map((l) => DropdownMenuItem(value: l, child: Text(l.name))).toList(),
              onChanged: (val) => setState(() => selectedLayer = val),
            ),
            const SizedBox(height: 16),

            const Text("FORMAT", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(label: const Text("SHP"), selected: format == "shp", onSelected: (s) => setState(() => format = "shp")),
                ChoiceChip(label: const Text("GeoJSON"), selected: format == "geojson", onSelected: (s) => setState(() => format = "geojson")),
                ChoiceChip(label: const Text("CSV"), selected: format == "csv", onSelected: (s) => setState(() => format = "csv")),
                ChoiceChip(label: const Text("GML"), selected: format == "gml", onSelected: (s) => setState(() => format = "gml")),
                ChoiceChip(label: const Text("GeoPackage"), selected: format == "gpkg", onSelected: (s) => setState(() => format = "gpkg")),
              ],
            ),
            const SizedBox(height: 16),

            const Text("COORDINATE SYSTEM", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
            RadioGroup<bool>(
              groupValue: useEov,
              onChanged: (value) {
                if (value != null) setState(() => useEov = value);
              },
              child: const Column(
                children: [
                  RadioListTile<bool>(
                    title: Text("EOV (EPSG:23700)", style: TextStyle(fontSize: 13)),
                    subtitle: Text("Hungarian projection", style: TextStyle(fontSize: 10)),
                    value: true,
                    contentPadding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  ),
                  RadioListTile<bool>(
                    title: Text("WGS84 (EPSG:4326)", style: TextStyle(fontSize: 13)),
                    subtitle: Text("Global GPS coordinates", style: TextStyle(fontSize: 10)),
                    value: false,
                    contentPadding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            const Text("CONTENT", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
            CheckboxListTile(
              title: const Text("Only selected items", style: TextStyle(fontSize: 13)),
              subtitle: Text("${widget.initialSelection?.length ?? 0} items selected", style: const TextStyle(fontSize: 10)),
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
          label: Text(l10n.export.toUpperCase()),
          onPressed: selectedLayer == null ? null : () async {
            final layer = selectedLayer!;
            final geoidService = context.read<GeoidCorrectionService>();
            final List<GeoFeature>? selected = exportOnlySelected ? widget.initialSelection : null;
            final features = selected ?? layer.features;
            const validator = DataValidationService();
            final issues = features.expand((feature) => validator.validateFeature(
              feature: feature,
              fields: layer.fields,
              crsInfo: layer.crsInfo,
            )).toList();
            final errors = issues.where((issue) => issue.severity == ValidationSeverity.error).toList();
            final warnings = issues.where((issue) => issue.severity == ValidationSeverity.warning).toList();
            if (errors.isNotEmpty || warnings.isNotEmpty) {
              final proceed = await showDialog<bool>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: Text(errors.isEmpty ? 'Export Warnings' : 'Data Errors in Export'),
                  content: SizedBox(
                    width: 480,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (errors.isNotEmpty)
                            Text('Erroneous objects: ${errors.length}. Export may contain invalid geometry or attribute data.'),
                          if (warnings.isNotEmpty)
                            Text('Warnings: ${warnings.length}. Check CRS and data.'),
                          const SizedBox(height: 8),
                          ...issues.take(12).map((issue) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text('• ${issue.featureName ?? layer.name}: ${issue.message}'),
                          )),
                          if (issues.length > 12) Text('… and ${issues.length - 12} more indications.'),
                        ],
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, errors.isEmpty),
                      child: Text(errors.isEmpty ? l10n.cancel : 'OK'),
                    ),
                    if (errors.isEmpty)
                      FilledButton(
                        onPressed: () => Navigator.pop(dialogContext, true),
                        child: Text(l10n.saveAnyway),
                      ),
                  ],
                ),
              );
              if (proceed != true) return;
            }
            if (!context.mounted) return;
            Navigator.pop(context);
            await projectService.exportWithFormat(
              context,
              geoidService,
              widget.project,
              format: format,
              layer: layer,
              features: selected,
              sharePositionOrigin: widget.sharePositionOrigin,
              useEov: useEov,
            );
          },
        ),
      ],
    );
  }
}
