import 'cogo_session.dart';

enum CampusLocation {
  miskolc,
  szekesfehervar
}

class CogoTask {
  final String id;
  final CogoType type;
  final CampusLocation campus;
  final String description;
  final List<String> steps;
  final List<String> derivation;
  final Map<String, dynamic> inputs; // Ismert pontok, mért értékek
  final Map<String, dynamic> groundTruth; // A pontos megoldás
  final double tolerance; // Elvárt pontosság méterben (pl. 0.01)

  CogoTask({
    required this.id,
    required this.type,
    required this.campus,
    required this.description,
    required this.steps,
    required this.derivation,
    required this.inputs,
    required this.groundTruth,
    this.tolerance = 0.01,
  });
}

class TaskEvaluation {
  final bool isSuccess;
  final Map<String, double> differences; // ΔY, ΔX, Δd stb.
  final String grade; // "Kiváló", "Jó", "Hiba"
  final String message;

  TaskEvaluation({
    required this.isSuccess,
    required this.differences,
    required this.grade,
    required this.message,
  });
}
