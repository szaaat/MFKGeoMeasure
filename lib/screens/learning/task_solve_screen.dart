import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../models/learning_task.dart';
import '../../models/cogo_session.dart';
import '../../services/learning_service.dart';

class TaskSolveScreen extends StatefulWidget {
  final CogoTask task;
  const TaskSolveScreen({super.key, required this.task});

  @override
  State<TaskSolveScreen> createState() => _TaskSolveScreenState();
}

class _TaskSolveScreenState extends State<TaskSolveScreen> {
  final Map<String, TextEditingController> _controllers = {};
  bool _showFullDerivation = false;

  AppLocalizations get l10n => AppLocalizations.of(context)!;

  @override
  void initState() {
    super.initState();
    for (var key in widget.task.groundTruth.keys) {
      _controllers[key] = TextEditingController();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        appBar: AppBar(title: Text(l10n.taskSolveTitle)),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 15),
              _buildDescription(),
              const SizedBox(height: 15),
              _buildGivenData(),
              const Divider(height: 40),
              _buildAnswerForm(),
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: _evaluateTask,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 55),
                  backgroundColor: Colors.blue[800],
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
                child: Text(l10n.check, style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDescription() {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: Colors.blue[50],
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.blue[200]!),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue[800], size: 20),
                  const SizedBox(width: 10),
                  Text(l10n.taskGoal, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                widget.task.description,
                style: TextStyle(fontSize: 13, color: Colors.blue[900], height: 1.4),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: Colors.green[50],
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.green[200]!),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.list_alt, color: Colors.green[800], size: 20),
                  const SizedBox(width: 10),
                  Text(l10n.taskSteps, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                ],
              ),
              const SizedBox(height: 8),
              ...widget.task.steps.map((step) => Padding(
                padding: const EdgeInsets.only(bottom: 5.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("• ", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green[800])),
                    Expanded(child: Text(step, style: TextStyle(fontSize: 12, color: Colors.green[900]))),
                  ],
                ),
              )),
              const Divider(height: 25),
              InkWell(
                onTap: () => setState(() => _showFullDerivation = !_showFullDerivation),
                child: Row(
                  children: [
                    Icon(_showFullDerivation ? Icons.visibility_off : Icons.visibility, color: Colors.green[800], size: 16),
                    const SizedBox(width: 5),
                    Text(
                      _showFullDerivation ? l10n.derivationHide : l10n.derivationShow,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green[800]),
                    ),
                  ],
                ),
              ),
              if (_showFullDerivation)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(5)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: widget.task.derivation.map((line) => Text(
                      line,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.black87),
                    )).toList(),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    String title = "";
    switch (widget.task.type) {
      case CogoType.inverse: title = l10n.inverse; break;
      case CogoType.angularIntersection: title = l10n.angularIntersection; break;
      case CogoType.distanceIntersection: title = l10n.distanceIntersection; break;
      case CogoType.resection: title = l10n.resection; break;
      case CogoType.area: title = l10n.area; break;
    }

    final campusStr = widget.task.campus == CampusLocation.miskolc ? l10n.campusMiskolc : l10n.campusSzekesfehervar;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        Text(l10n.locationLabel(campusStr), style: const TextStyle(color: Colors.grey)),
      ],
    );
  }

  Widget _buildGivenData() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: Colors.orange[50], borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.orange[200]!)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.givenData, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange, fontSize: 12)),
          const SizedBox(height: 10),
          ...widget.task.inputs.entries.map((e) {
            if (e.value is Map) {
              return Text("${e.key}: Y=${e.value['y'].toStringAsFixed(3)}, X=${e.value['x'].toStringAsFixed(3)}", 
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13));
            }
            return Text("${e.key}: ${e.value is double ? e.value.toStringAsFixed(3) : e.value}", 
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13));
          }),
        ],
      ),
    );
  }

  Widget _buildAnswerForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.calculatedResults, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
        const SizedBox(height: 15),
        ..._controllers.entries.map((e) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 15),
            child: TextField(
              controller: e.value,
              decoration: InputDecoration(
                labelText: _getLabelForKey(e.key),
                border: const OutlineInputBorder(),
                suffixText: _getUnitForKey(e.key),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.done,
            ),
          );
        }),
      ],
    );
  }

  String _getLabelForKey(String key) {
    switch (key) {
      case 'distance': return "${l10n.distanceLabel} (d)";
      case 'bearing': return l10n.bearingLabel;
      case 'y': return l10n.resultY;
      case 'x': return l10n.resultX;
      case 'y1': return l10n.intersection1Y;
      case 'x1': return l10n.intersection1X;
      case 'y2': return l10n.intersection2Y;
      case 'x2': return l10n.intersection2X;
      case 'area_m2': return "${l10n.areaLabel} (m²)";
      case 'area_ha': return "${l10n.areaLabel} (ha)";
      default: return key;
    }
  }

  String _getUnitForKey(String key) {
    if (key == 'bearing') return "°";
    if (key == 'area_ha') return "ha";
    if (key == 'area_m2') return "m²";
    return "m";
  }

  void _evaluateTask() {
    Map<String, double> results = {};
    bool anyEmpty = false;
    _controllers.forEach((key, ctrl) {
      if (ctrl.text.isEmpty) anyEmpty = true;
      results[key] = double.tryParse(ctrl.text.replaceAll(',', '.')) ?? 0.0;
    });

    if (anyEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.fillAllFields)));
      return;
    }

    final isEnglish = Localizations.localeOf(context).languageCode == 'en';
    final evaluation = context.read<LearningService>().evaluate(widget.task, results, isEnglish: isEnglish);
    _showResultDialog(evaluation);
  }

  void _showResultDialog(TaskEvaluation eval) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(eval.isSuccess ? Icons.check_circle : Icons.error, color: eval.isSuccess ? Colors.green : Colors.red),
            const SizedBox(width: 10),
            Text(eval.grade),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(eval.message, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            Text(l10n.differences, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ...eval.differences.entries.map((e) => Text(
              "${_getLabelForKey(e.key)}: ${e.value > 0 ? '+' : ''}${e.value.toStringAsFixed(4)} ${e.key == 'bearing' ? '°' : 'm'}",
              style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: e.value.abs() > widget.task.tolerance ? Colors.red : Colors.green),
            )),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.retry)),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            }, 
            child: Text(l10n.done)
          ),
        ],
      ),
    );
  }
}
