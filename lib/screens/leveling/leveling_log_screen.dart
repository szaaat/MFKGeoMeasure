import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/leveling/leveling_service.dart';
import '../../models/leveling/leveling_reading.dart';
import '../../models/leveling/leveling_station.dart';
import '../../models/leveling/leveling_project.dart';
import '../../widgets/leveling/numeric_keypad.dart';

class LevelingLogScreen extends StatefulWidget {
  const LevelingLogScreen({super.key});

  @override
  State<LevelingLogScreen> createState() => _LevelingLogScreenState();
}

class _LevelingLogScreenState extends State<LevelingLogScreen> {
  bool _isProtocolView = false;

  void _editReading(BuildContext context, LevelingService service, LevelingStation station, LevelingReading? reading, ReadingType type) {
    String title = '';
    double? initialValue;
    String? readingId;

    if (type == ReadingType.backsight) {
      title = 'HÁTRA: ${station.backsightPointId}';
      initialValue = station.backsight;
    } else if (type == ReadingType.foresight) {
      title = 'ELŐRE: ${station.foresightPointId}';
      initialValue = station.foresight;
    } else if (reading != null) {
      title = 'KÖZBENSŐ: ${reading.pointId}';
      initialValue = reading.value;
      readingId = reading.id;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => NumericKeypad(
        title: title,
        initialValue: initialValue?.toString() ?? '',
        onConfirm: (val) {
          service.updateReading(station.stationId, readingId, type, val);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<LevelingService>();
    final project = service.activeProject;

    if (project == null) return const Scaffold(body: Center(child: Text('Nincs aktív projekt.')));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mérési napló'),
        actions: [
          IconButton(
            icon: Icon(_isProtocolView ? Icons.view_agenda : Icons.table_chart),
            tooltip: _isProtocolView ? 'Kártya nézet' : 'Jegyzőkönyv nézet',
            onPressed: () => setState(() => _isProtocolView = !_isProtocolView),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSummaryHeader(service),
          Expanded(
            child: _isProtocolView ? _buildProtocolTable(service) : _buildStationList(project, service),
          ),
          if (service.closureError != null) _buildAdjustmentBar(service),
        ],
      ),
    );
  }

  Widget _buildSummaryHeader(LevelingService service) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      color: Colors.blue[50],
      child: Column(
        children: [
          Text(
            '${service.stationCount} műszerállás · ${service.totalPointCount} pont · '
            '${service.readingCount(ReadingType.backsight)} BS · '
            '${service.readingCount(ReadingType.intermediate)} IS · '
            '${service.readingCount(ReadingType.foresight)} FS',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem('ΣBS', service.sumBacksights),
              _buildStatItem('ΣFS', service.sumForesights),
              _buildStatItem('ΣΔH', service.calculatedHeightDifference, isBold: true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, double value, {bool isBold = false}) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        Text(
          '${value.toStringAsFixed(3)} m',
          style: TextStyle(
            fontSize: 16, 
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            color: isBold ? Colors.blue[800] : Colors.black,
          ),
        ),
      ],
    );
  }

  Widget _buildAdjustmentBar(LevelingService service) {
    final error = service.closureError!;
    final color = error.abs() < 0.01 ? Colors.green : Colors.red;
    final isAdjusted = service.activeProject?.adjustmentMethod != AdjustmentMethod.none;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, -2))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Záróhiba (fH):', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  Text('${(error * 1000).toStringAsFixed(1)} mm', 
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
                ],
              ),
              if (!isAdjusted)
                ElevatedButton(
                  onPressed: () => _showAdjustmentMenu(service),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blue[800], foregroundColor: Colors.white),
                  child: const Text('KIEGYENLÍTÉS'),
                )
              else
                OutlinedButton.icon(
                  onPressed: () => service.clearAdjustments(),
                  icon: const Icon(Icons.undo),
                  label: const Text('VISSZAVONÁS'),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _showAdjustmentMenu(LevelingService service) {
    bool hasDistances = service.activeProject?.stations.every((s) => s.distance != null && s.distance! > 0) ?? false;

    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('Válassz kiegyenlítési módot', style: TextStyle(fontWeight: FontWeight.bold))),
            ListTile(
              leading: const Icon(Icons.numbers),
              title: const Text('Állomásszám szerint'),
              subtitle: const Text('A hibát egyenlő arányban osztja szét az állomások között.'),
              onTap: () {
                service.performAdjustment(AdjustmentMethod.stationCount);
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: const Icon(Icons.straighten),
              enabled: hasDistances,
              title: const Text('Távolságarányos'),
              subtitle: Text(hasDistances 
                ? 'A hibát a szakaszhosszak arányában osztja szét.' 
                : 'Csak akkor érhető el, ha minden állomáshoz megadtál távolságot.'),
              onTap: () {
                service.performAdjustment(AdjustmentMethod.distance);
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStationList(LevelingProject project, LevelingService service) {
    final currentStationId = service.currentStation?.stationId;
    return ListView.builder(
      itemCount: project.stations.length,
      padding: const EdgeInsets.all(12),
      itemBuilder: (context, index) {
        final station = project.stations[index];
        return _buildStationCard(context, service, station, station.stationId == currentStationId);
      },
    );
  }

  Widget _buildStationCard(BuildContext context, LevelingService service, LevelingStation station, bool isCurrent) {
    final mh = service.getPointHeight(station.backsightPointId) + (station.backsight ?? 0.0);

    return Card(
      elevation: isCurrent ? 6 : 2,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isCurrent ? const BorderSide(color: Colors.blue, width: 2) : BorderSide.none,
      ),
      child: ExpansionTile(
        initiallyExpanded: isCurrent,
        backgroundColor: isCurrent ? Colors.blue.withValues(alpha: 0.05) : null,
        title: Row(
          children: [
            Text('${station.stationId}. MŰSZERÁLLÁS', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            if (isCurrent)
              Container(
                margin: const EdgeInsets.only(left: 10),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Colors.blue, borderRadius: BorderRadius.circular(4)),
                child: const Text('AKTÍV', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('MH = ${mh.toStringAsFixed(3)} m', style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 12)),
            if (station.distance != null)
               Text('Távolság: ${station.distance!.toStringAsFixed(1)} m', style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Table(
              columnWidths: const {
                0: FlexColumnWidth(2.5),
                1: FixedColumnWidth(40),
                2: FlexColumnWidth(2),
                3: FlexColumnWidth(2),
              },
              border: TableBorder(horizontalInside: BorderSide(color: Colors.grey[200]!)),
              children: [
                const TableRow(
                  children: [
                    Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Pont', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10))),
                    Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Típus', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10))),
                    Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Leolv. (m)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10), textAlign: TextAlign.right)),
                    Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Magasság (m)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10), textAlign: TextAlign.right)),
                  ],
                ),
                _buildReadingRow(context, service, station, null, ReadingType.backsight),
                ...station.intermediateReadings.map((r) => _buildReadingRow(context, service, station, r, ReadingType.intermediate)),
                if (station.foresightPointId != null || isCurrent)
                  _buildReadingRow(context, service, station, null, ReadingType.foresight),
              ],
            ),
          ),
        ],
      ),
    );
  }

  TableRow _buildReadingRow(BuildContext context, LevelingService service, LevelingStation station, LevelingReading? reading, ReadingType type) {
    String name = '';
    double value = 0.0;
    String typeLabel = '';
    Color typeColor = Colors.grey;
    double pointH = 0.0;
    bool isComplete = false;

    final mh = service.getPointHeight(station.backsightPointId) + (station.backsight ?? 0.0);

    if (type == ReadingType.backsight) {
      name = station.backsightPointId;
      value = station.backsight ?? 0.0;
      typeLabel = 'BS';
      typeColor = Colors.blue;
      pointH = service.getPointHeight(name);
      isComplete = station.backsight != null;
    } else if (type == ReadingType.foresight) {
      name = station.foresightPointId ?? '---';
      value = station.foresight ?? 0.0;
      typeLabel = 'FS';
      typeColor = Colors.red;
      pointH = mh - value;
      isComplete = station.foresight != null;
    } else if (reading != null) {
      name = reading.pointId;
      value = reading.value;
      typeLabel = 'IS';
      typeColor = Colors.orange;
      pointH = mh - value;
      isComplete = true;
    }

    final adjustedH = service.getAdjustedHeight(name);
    final hasCorrection = (adjustedH - pointH).abs() > 0.0001;

    return TableRow(
      children: [
        GestureDetector(
          onTap: () => _editReading(context, service, station, reading, type),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12), 
            child: Row(
              children: [
                Icon(
                  isComplete ? Icons.check_circle : Icons.pending,
                  size: 14, 
                  color: isComplete ? (service.isPointSaved(name, adjustedH) ? Colors.green : Colors.grey) : Colors.amber
                ),
                const SizedBox(width: 4),
                Expanded(child: Text(name, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
              ],
            )
          ),
        ),
        Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(typeLabel, style: TextStyle(fontSize: 10, color: typeColor, fontWeight: FontWeight.bold))),
        GestureDetector(
          onTap: () => _editReading(context, service, station, reading, type),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12), 
            child: Text(
              isComplete ? value.toStringAsFixed(3) : '---', 
              style: TextStyle(fontSize: 12, color: isComplete ? Colors.blueGrey : Colors.grey), 
              textAlign: TextAlign.right
            )
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12), 
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                isComplete ? pointH.toStringAsFixed(3) : '---', 
                style: TextStyle(fontSize: 12, color: isComplete ? (hasCorrection ? Colors.grey : Colors.black) : Colors.grey, decoration: hasCorrection ? TextDecoration.lineThrough : null), 
                textAlign: TextAlign.right
              ),
              if (hasCorrection)
                Text(
                  adjustedH.toStringAsFixed(3),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue),
                  textAlign: TextAlign.right,
                )
            ],
          )
        ),
      ],
    );
  }

  Widget _buildProtocolTable(LevelingService service) {
    final List<TableRow> rows = [];
    
    // Header
    rows.add(const TableRow(
      decoration: BoxDecoration(color: Colors.black12),
      children: [
        Padding(padding: EdgeInsets.all(8), child: Text('Pont', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10))),
        Padding(padding: EdgeInsets.all(8), child: Text('Hátra', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10), textAlign: TextAlign.right)),
        Padding(padding: EdgeInsets.all(8), child: Text('MH', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10), textAlign: TextAlign.right)),
        Padding(padding: EdgeInsets.all(8), child: Text('Közb/El.', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10), textAlign: TextAlign.right)),
        Padding(padding: EdgeInsets.all(8), child: Text('Magasság', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10), textAlign: TextAlign.right)),
      ],
    ));

    double currentH = service.activeProject!.startHeight;
    
    for (var s in service.activeProject!.stations) {
      final mh = currentH + (s.backsight ?? 0.0);
      
      // BS row
      rows.add(TableRow(children: [
        Padding(padding: const EdgeInsets.all(8), child: Text(s.backsightPointId, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold))),
        Padding(padding: const EdgeInsets.all(8), child: Text(s.backsight?.toStringAsFixed(3) ?? '-', style: const TextStyle(fontSize: 10), textAlign: TextAlign.right)),
        Padding(padding: const EdgeInsets.all(8), child: Text(mh.toStringAsFixed(3), style: const TextStyle(fontSize: 10, color: Colors.blue), textAlign: TextAlign.right)),
        const Padding(padding: EdgeInsets.all(8), child: Text('')),
        Padding(padding: const EdgeInsets.all(8), child: Text(currentH.toStringAsFixed(3), style: const TextStyle(fontSize: 10), textAlign: TextAlign.right)),
      ]));

      // IS rows
      for (var ir in s.intermediateReadings) {
        final pointH = mh - ir.value;
        rows.add(TableRow(children: [
          Padding(padding: const EdgeInsets.all(8), child: Text(ir.pointId, style: const TextStyle(fontSize: 10))),
          const Padding(padding: EdgeInsets.all(8), child: Text('')),
          const Padding(padding: EdgeInsets.all(8), child: Text('')),
          Padding(padding: const EdgeInsets.all(8), child: Text(ir.value.toStringAsFixed(3), style: const TextStyle(fontSize: 10), textAlign: TextAlign.right)),
          Padding(padding: const EdgeInsets.all(8), child: Text(pointH.toStringAsFixed(3), style: const TextStyle(fontSize: 10), textAlign: TextAlign.right)),
        ]));
      }

      // FS row
      if (s.foresightPointId != null) {
        final nextH = mh - (s.foresight ?? 0.0);
        rows.add(TableRow(children: [
          Padding(padding: const EdgeInsets.all(8), child: Text(s.foresightPointId!, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold))),
          const Padding(padding: EdgeInsets.all(8), child: Text('')),
          const Padding(padding: EdgeInsets.all(8), child: Text('')),
          Padding(padding: const EdgeInsets.all(8), child: Text(s.foresight?.toStringAsFixed(3) ?? '-', style: const TextStyle(fontSize: 10), textAlign: TextAlign.right)),
          Padding(padding: const EdgeInsets.all(8), child: Text(nextH.toStringAsFixed(3), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold), textAlign: TextAlign.right)),
        ]));
        currentH = nextH;
      }
    }

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Table(
          border: TableBorder.all(color: Colors.grey[300]!),
          columnWidths: const {
            0: FlexColumnWidth(1.5),
            1: FlexColumnWidth(1),
            2: FlexColumnWidth(1.2),
            3: FlexColumnWidth(1.2),
            4: FlexColumnWidth(1.2),
          },
          children: rows,
        ),
      ),
    );
  }
}
