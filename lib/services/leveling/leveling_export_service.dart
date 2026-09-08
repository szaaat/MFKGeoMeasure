import 'dart:io';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/leveling/leveling_project.dart';
import '../project_service.dart';

class LevelingExportService {
  static Future<void> generateAndSharePdf(LevelingProject project, ProjectService projectService) async {
    final pdf = pw.Document();
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm');

    // Mivel a PDF standard fontok nem támogatják az összes magyar ékezetet, 
    // egy "tisztító" függvényt használunk a szövegekhez a hibamentes export érdekében.
    String clean(String text) {
      return text
        .replaceAll('ő', 'o').replaceAll('Ő', 'O')
        .replaceAll('ű', 'u').replaceAll('Ű', 'U')
        .replaceAll('á', 'a').replaceAll('Á', 'A')
        .replaceAll('é', 'e').replaceAll('É', 'E')
        .replaceAll('í', 'i').replaceAll('Í', 'I')
        .replaceAll('ó', 'o').replaceAll('Ó', 'O')
        .replaceAll('ö', 'o').replaceAll('Ö', 'O')
        .replaceAll('ú', 'u').replaceAll('Ú', 'U')
        .replaceAll('ü', 'u').replaceAll('Ü', 'U');
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        header: (context) => pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(bottom: 20),
          child: pw.Text('MFK GeoMeasure - Szintezesi Jegyzokonyv', style: pw.TextStyle(color: PdfColors.grey700, fontSize: 10)),
        ),
        build: (context) => [
          pw.Header(
            level: 0,
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('SZINTEZESI JEGYZOKONYV', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 18)),
                pw.Text(dateFormat.format(DateTime.now()), style: const pw.TextStyle(fontSize: 12)),
              ],
            ),
          ),
          pw.SizedBox(height: 10),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _buildInfoRow('Projekt neve:', clean(project.name)),
              _buildInfoRow('Meresi mod:', project.isPrecision ? 'Precizios (H1-E1-H2-E2)' : 'Vonal szintezes'),
              _buildInfoRow('Kezdo alappont:', clean(_getPointName(projectService, project.startPointId))),
              _buildInfoRow('Kezdo magassag:', '${project.startHeight.toStringAsFixed(3)} m'),
            ],
          ),
          pw.SizedBox(height: 20),
          _buildStationTable(project, projectService, clean),
          pw.SizedBox(height: 20),
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.black)),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('EREDMENYEK ES ELLENORZES', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 5),
                _buildInfoRow('Szamitott magassagkulonbseg (sum dH):', '${_calculateHeightDiff(project).toStringAsFixed(4)} m'),
                _buildInfoRow('Szamitott vegmagassag:', '${(project.startHeight + _calculateHeightDiff(project)).toStringAsFixed(4)} m'),
                if (project.knownEndHeight != null) ...[
                  _buildInfoRow('Ismert vegmagassag:', '${project.knownEndHeight!.toStringAsFixed(3)} m'),
                  _buildInfoRow('Zarohiba (fH):', '${((project.startHeight + _calculateHeightDiff(project) - project.knownEndHeight!) * 1000).toStringAsFixed(1)} mm'),
                ],
              ],
            ),
          ),
        ],
        footer: (context) => pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(top: 10),
          child: pw.Text('Oldal ${context.pageNumber} / ${context.pagesCount}', style: const pw.TextStyle(fontSize: 10)),
        ),
      ),
    );

    final output = await getTemporaryDirectory();
    final file = File("${output.path}/jegyzokonyv_${project.name.replaceAll(' ', '_')}.pdf");
    await file.writeAsBytes(await pdf.save());

    await Share.shareXFiles([XFile(file.path)], text: 'Szintezési Jegyzőkönyv: ${project.name}');
  }

  static pw.Widget _buildInfoRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        children: [
          pw.SizedBox(width: 150, child: pw.Text(label, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10))),
          pw.Text(value, style: const pw.TextStyle(fontSize: 10)),
        ],
      ),
    );
  }

  static pw.Widget _buildStationTable(LevelingProject project, ProjectService projectService, String Function(String) clean) {
    if (project.isPrecision) {
      return _buildPrecisionTable(project, projectService, clean);
    } else {
      return _buildSimpleTable(project, projectService, clean);
    }
  }

  static pw.Widget _buildSimpleTable(LevelingProject project, ProjectService projectService, String Function(String) clean) {
    final headers = ['Allas', 'Pont', 'Hatra (m)', 'MH (m)', 'Kozb/Elore (m)', 'Magassag (m)', 'Tav. (m)', 'Info'];
    final List<List<String>> data = [];

    double currentH = project.startHeight;

    for (var s in project.stations) {
      final info = [
        if (s.surveyor != null) 'Mero: ${clean(s.surveyor!)}',
        if (s.instrument != null) 'Muszer: ${clean(s.instrument!)}',
        if (s.notes != null) 'Megj: ${clean(s.notes!)}',
      ].join('\n');

      final mh = s.backsight != null ? currentH + s.backsight! : 0.0;
      final distStr = s.distance?.toStringAsFixed(1) ?? '-';

      // Backsight row
      data.add([
        '#${s.stationId}',
        clean(_getPointName(projectService, s.backsightPointId)),
        s.backsight?.toStringAsFixed(3) ?? '-',
        mh > 0 ? mh.toStringAsFixed(3) : '-',
        '',
        currentH.toStringAsFixed(3),
        distStr,
        info
      ]);

      // Intermediate readings
      for (var ir in s.intermediateReadings) {
        final pointH = mh - ir.value;
        final adjustedH = _getAdjusted(project, ir.pointId, pointH);
        data.add([
          '',
          clean(_getPointName(projectService, ir.pointId)),
          '',
          '',
          ir.value.toStringAsFixed(3),
          adjustedH != pointH 
            ? '${pointH.toStringAsFixed(3)} -> ${adjustedH.toStringAsFixed(3)}' 
            : pointH.toStringAsFixed(3),
          '',
          ''
        ]);
      }

      // Foresight row
      if (s.foresightPointId != null && s.foresight != null) {
        final nextH = mh - s.foresight!;
        final nextAdjustedH = _getAdjusted(project, s.foresightPointId!, nextH);
        data.add([
          '',
          clean(_getPointName(projectService, s.foresightPointId!)),
          '',
          '',
          s.foresight!.toStringAsFixed(3),
          nextAdjustedH != nextH 
            ? '${nextH.toStringAsFixed(3)} -> ${nextAdjustedH.toStringAsFixed(3)}' 
            : nextH.toStringAsFixed(3),
          '',
          ''
        ]);
        currentH = nextH;
      }
    }

    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: data,
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8),
      cellStyle: const pw.TextStyle(fontSize: 8),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
      cellAlignment: pw.Alignment.centerLeft,
    );
  }

  static pw.Widget _buildPrecisionTable(LevelingProject project, ProjectService projectService, String Function(String) clean) {
    final headers = ['Allas', 'Pontok', 'Sorozat 1', 'Sorozat 2', 'd (mm)', 'atl dH (m)', 'Info'];
    final List<List<String>> data = [];

    for (var s in project.stations) {
      final info = [
        if (s.surveyor != null) 'Mero: ${clean(s.surveyor!)}',
        if (s.instrument != null) 'Muszer: ${clean(s.instrument!)}',
        if (s.measurementOrder != null) 'Rend: ${clean(s.measurementOrder!)}',
        if (s.notes != null) 'Megj: ${clean(s.notes!)}',
      ].join('\n');

      data.add([
        '#${s.stationId}',
        'H: ${clean(_getPointName(projectService, s.backsightPointId))}\nE: ${clean(_getPointName(projectService, s.foresightPointId ?? ''))}',
        'H1: ${s.h1?.toStringAsFixed(1) ?? '-'}\nE1: ${s.e1?.toStringAsFixed(1) ?? '-'}',
        'H2: ${s.h2?.toStringAsFixed(1) ?? '-'}\nE2: ${s.e2?.toStringAsFixed(1) ?? '-'}',
        s.stationDiff != null ? (s.stationDiff! * 1000).toStringAsFixed(1) : '-',
        s.meanDeltaH != null ? (s.meanDeltaH! / 1000).toStringAsFixed(4) : '-',
        info
      ]);
    }

    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: data,
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8),
      cellStyle: const pw.TextStyle(fontSize: 8),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
      cellAlignment: pw.Alignment.centerLeft,
    );
  }

  static String _getPointName(ProjectService service, String id) {
    try {
      return service.visibleFeatures.firstWhere((f) => f.id == id).name;
    } catch (e) {
      return id.length > 8 ? id.substring(0, 8) : id;
    }
  }

  static double _calculateHeightDiff(LevelingProject project) {
    double total = 0;
    for (var s in project.stations) {
      if (project.isPrecision && s.meanDeltaH != null) {
        total += (s.meanDeltaH! / 1000);
      } else if (s.backsight != null && s.foresight != null) {
        total += (s.backsight! - s.foresight!);
      }
    }
    return total;
  }

  static double _getAdjusted(LevelingProject project, String pointId, double rawHeight) {
    for (var s in project.stations) {
      if (s.corrections.containsKey(pointId)) {
        return rawHeight + s.corrections[pointId]!;
      }
    }
    return rawHeight;
  }
}
