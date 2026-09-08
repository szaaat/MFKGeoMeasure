import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../providers/cogo_provider.dart';
import '../models/cogo_session.dart';
import 'cogo_detail_screen.dart';

class CogoScreen extends StatelessWidget {
  const CogoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.whatToCalculate)),
      body: GridView.count(
        crossAxisCount: 2,
        padding: const EdgeInsets.all(20),
        mainAxisSpacing: 20,
        crossAxisSpacing: 20,
        children: [
          _buildCogoCard(context, l10n.inverse.toUpperCase(), l10n.inverseDesc, Icons.straighten, CogoType.inverse),
          _buildCogoCard(context, l10n.angularIntersection.toUpperCase(), l10n.angularDesc, Icons.explore, CogoType.angularIntersection),
          _buildCogoCard(context, l10n.distanceIntersection.toUpperCase(), l10n.distanceDesc, Icons.adjust, CogoType.distanceIntersection),
          _buildCogoCard(context, l10n.resection.toUpperCase(), l10n.resectionDesc, Icons.location_searching, CogoType.resection),
          _buildCogoCard(context, l10n.area.toUpperCase(), l10n.areaDesc, Icons.pentagon_outlined, CogoType.area),
        ],
      ),
    );
  }

  Widget _buildCogoCard(BuildContext context, String title, String subtitle, IconData icon, CogoType type) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: InkWell(
        onTap: () {
          context.read<CogoProvider>().setType(type);
          Navigator.push(context, MaterialPageRoute(builder: (_) => const CogoDetailScreen()));
        },
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 40, color: Colors.blue[800]),
              const SizedBox(height: 10),
              Text(title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 4),
              Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, color: Colors.grey)),
            ],
          ),
        ),
      ),
    );
  }
}
