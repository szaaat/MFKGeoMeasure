import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../models/learning_task.dart';
import '../../models/cogo_session.dart';
import '../../services/learning_service.dart';
import 'task_solve_screen.dart';

class LearningMenuScreen extends StatefulWidget {
  const LearningMenuScreen({super.key});

  @override
  State<LearningMenuScreen> createState() => _LearningMenuScreenState();
}

class _LearningMenuScreenState extends State<LearningMenuScreen> {
  CampusLocation _selectedCampus = CampusLocation.miskolc;

  AppLocalizations get l10n => AppLocalizations.of(context)!;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(l10n.startLearning)),
      body: Column(
        children: [
          _buildCampusSelector(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _buildTaskTile(
                  context,
                  l10n.inverse,
                  l10n.inverseDesc,
                  Icons.straighten,
                  CogoType.inverse,
                ),
                const SizedBox(height: 15),
                _buildTaskTile(
                  context,
                  l10n.distanceIntersection,
                  l10n.distanceDesc,
                  Icons.adjust,
                  CogoType.distanceIntersection,
                ),
                const SizedBox(height: 15),
                _buildTaskTile(
                  context,
                  l10n.angularIntersection,
                  l10n.angularDesc,
                  Icons.explore,
                  CogoType.angularIntersection,
                ),
                const SizedBox(height: 15),
                _buildTaskTile(
                  context,
                  l10n.resection,
                  l10n.resectionDesc,
                  Icons.location_searching,
                  CogoType.resection,
                ),
                const SizedBox(height: 15),
                _buildTaskTile(
                  context,
                  l10n.area,
                  l10n.areaDesc,
                  Icons.pentagon_outlined,
                  CogoType.area,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCampusSelector() {
    return Container(
      padding: const EdgeInsets.all(15),
      color: Colors.blue[50],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.selectLocation, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          const SizedBox(height: 10),
          Row(
            children: [
              _campusChip(l10n.campusMiskolc, CampusLocation.miskolc),
              const SizedBox(width: 10),
              _campusChip(l10n.campusSzekesfehervar, CampusLocation.szekesfehervar),
            ],
          ),
        ],
      ),
    );
  }

  Widget _campusChip(String label, CampusLocation campus) {
    bool isSelected = _selectedCampus == campus;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (val) => setState(() => _selectedCampus = campus),
      selectedColor: Colors.blue[200],
    );
  }

  Widget _buildTaskTile(BuildContext context, String title, String desc, IconData icon, CogoType type) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.all(15),
        leading: CircleAvatar(
          backgroundColor: Colors.blue[800],
          child: Icon(icon, color: Colors.white),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(desc, style: const TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.play_arrow, color: Colors.green),
        onTap: () {
          final isEnglish = Localizations.localeOf(context).languageCode == 'en';
          final task = context.read<LearningService>().generateTask(type, _selectedCampus, isEnglish: isEnglish);
          Navigator.push(context, MaterialPageRoute(builder: (_) => TaskSolveScreen(task: task)));
        },
      ),
    );
  }
}
