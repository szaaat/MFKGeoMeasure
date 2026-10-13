import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../l10n/app_localizations.dart';
import '../models/geo_feature.dart';

class SurveySummaryDialog extends StatelessWidget {
  final ProjectLayer layer;

  const SurveySummaryDialog({super.key, required this.layer});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final features = layer.features;
    final total = features.length;

    // Stats calculation
    int rtkFix = 0;
    int rtkFloat = 0;
    int phone = 0;
    int imported = 0;
    int ntripYes = 0;
    int ntripNo = 0;
    
    double sumSats = 0;
    int countSats = 0;
    double sumHdop = 0;
    int countHdop = 0;
    
    DateTime? minTime;
    DateTime? maxTime;

    for (var f in features) {
      final stats = f.calculatedStats;
      final method = stats['Survey Method'];
      
      if (method == 'RTK') {
        final rtkStat = stats['RTK Status'];
        if (rtkStat == 'FIXED') {
          rtkFix++;
        } else {
          rtkFloat++;
        }
      } else if (method == 'PHONE') {
        phone++;
      } else if (method == 'IMPORTED') {
        imported++;
      }

      if (stats['NTRIP Active'] == 'YES') {
        ntripYes++;
      } else if (stats['Survey Method'] != 'IMPORTED') {
        ntripNo++;
      }

      final dynamic sats = stats['Sats Used'];
      if (sats is num) {
        sumSats += sats;
        countSats++;
      }

      final dynamic hdop = stats['HDOP'];
      if (hdop is num) {
        sumHdop += hdop;
        countHdop++;
      }

      if (minTime == null || f.createdAt.isBefore(minTime)) {
        minTime = f.createdAt;
      }
      if (maxTime == null || f.createdAt.isAfter(maxTime)) {
        maxTime = f.createdAt;
      }
    }

    final avgSats = countSats > 0 ? sumSats / countSats : 0.0;
    final avgHdop = countHdop > 0 ? sumHdop / countHdop : 0.0;
    final timeFormat = DateFormat('yyyy-MM-dd HH:mm');

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.analytics, color: Colors.blue),
          const SizedBox(width: 10),
          Expanded(child: Text("${layer.name} - QA/QC Summary")),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildStatCard("GENERAL", [
              _buildRow("Total items", total.toString()),
              _buildRow("Geometry types", layer.containedGeometryTypes.map((e) => e.name.toUpperCase()).join(', ')),
              _buildRow("Data source", layer.sourceType.toUpperCase()),
              if (layer.crsInfo != null) _buildRow("Projection (CRS)", layer.crsInfo!),
            ]),
            const SizedBox(height: 12),
            _buildStatCard("SURVEY STATS", [
              _buildRow("RTK FIX", rtkFix.toString(), color: Colors.green),
              _buildRow("RTK FLOAT", rtkFloat.toString(), color: Colors.orange),
              _buildRow("Internal GPS", phone.toString()),
              _buildRow("Imported", imported.toString(), color: Colors.blueGrey),
            ]),
            const SizedBox(height: 12),
            _buildStatCard("QUALITY METRICS", [
              _buildRow("NTRIP Correction", "$ntripYes ON / $ntripNo OFF"),
              _buildRow("Avg Satellites", avgSats.toStringAsFixed(1)),
              _buildRow("Avg HDOP", avgHdop.toStringAsFixed(2), color: avgHdop < 1.0 ? Colors.green : Colors.orange),
            ]),
            const SizedBox(height: 12),
            _buildStatCard("TIME RANGE", [
              _buildRow("Start", minTime != null ? timeFormat.format(minTime) : "-"),
              _buildRow("End", maxTime != null ? timeFormat.format(maxTime) : "-"),
            ]),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.close)),
      ],
    );
  }

  Widget _buildStatCard(String title, List<Widget> rows) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueGrey, letterSpacing: 1.1)),
          const Divider(height: 16),
          ...rows,
        ],
      ),
    );
  }

  Widget _buildRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.bold, color: color),
            ),
          ),
        ],
      ),
    );
  }
}
