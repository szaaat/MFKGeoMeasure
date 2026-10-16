import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:latlong2/latlong.dart';
import '../services/project_service.dart';
import '../services/eov_service.dart';
import '../models/geo_feature.dart';

class SearchDialog extends StatefulWidget {
  final Function(LatLng, double) onLocationFound;

  const SearchDialog({Key? key, required this.onLocationFound}) : super(key: key);

  @override
  State<SearchDialog> createState() => _SearchDialogState();
}

class _SearchDialogState extends State<SearchDialog> {
  final _searchController = TextEditingController();
  final _altitudeController = TextEditingController();
  bool _isEllipsoidal = false;

  @override
  void dispose() {
    _searchController.dispose();
    _altitudeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final projectService = context.read<ProjectService>();

    return AlertDialog(
      title: Text(l10n.searchCoord),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'Pl: 47.902, 20.373 vagy 723000, 283000',
                labelText: 'WGS84 (Lat, Lon) vagy EOV (Y, X)',
              ),
              keyboardType: TextInputType.text,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _altitudeController,
              decoration: const InputDecoration(
                hintText: 'Magasság (opcionális)',
                labelText: 'Magasság (m)',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Expanded(child: Text('Magasság típusa:')),
                DropdownButton<bool>(
                  value: _isEllipsoidal,
                  items: const [
                    DropdownMenuItem(value: false, child: Text('Ortometrikus/Tengerszint feletti')),
                    DropdownMenuItem(value: true, child: Text('Ellipszoidi (WGS84)')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _isEllipsoidal = val);
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        ElevatedButton(
          onPressed: () {
            String cleanInput = _searchController.text
                .replaceAll(', ', ' ')
                .replaceAll(',', '.')
                .replaceAll(';', ' ');

            final parts = cleanInput
                .split(RegExp(r'\s+'))
                .where((s) => s.isNotEmpty)
                .toList();

            if (parts.length >= 2) {
              double? val1 = double.tryParse(parts[0]);
              double? val2 = double.tryParse(parts[1]);

              if (val1 != null && val2 != null) {
                double lat, lon;

                if (val1 > 10000 && val2 > 10000) {
                  double eovY = val1 > val2 ? val1 : val2;
                  double eovX = val1 < val2 ? val1 : val2;

                  final wgs = context.read<EovService>().eovToWgs(eovY, eovX);
                  lat = wgs[0];
                  lon = wgs[1];
                } else {
                  lat = val1;
                  lon = val2;
                }

                LatLng newPoint = LatLng(lat, lon);

                // Extract altitude from text field or 3rd coordinate part
                double altitude = 0.0;
                if (_altitudeController.text.isNotEmpty) {
                  altitude = double.tryParse(_altitudeController.text.replaceAll(',', '.')) ?? 0.0;
                } else if (parts.length >= 3) {
                  altitude = double.tryParse(parts[2]) ?? 0.0;
                }

                projectService.setTool(FeatureType.point);
                projectService.addPointToGeometry(newPoint, altitude, isEllipsoidal: _isEllipsoidal);
                final saved = projectService.finishRecording(
                    "${l10n.searched}: ${lat.toStringAsFixed(4)}, ${lon.toStringAsFixed(4)}",
                    l10n.recordedFromSearch);
                if (!saved) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Az objektum adatellenőrzés miatt nem menthető.')),
                  );
                  return;
                }

                widget.onLocationFound(newPoint, 17.0);
                Navigator.pop(context);

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text(l10n.pointSaved),
                      backgroundColor: Colors.green),
                );
                return;
              }
            }
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l10n.invalidCoord)),
            );
          },
          child: Text(l10n.searchAndSave),
        ),
      ],
    );
  }
}
