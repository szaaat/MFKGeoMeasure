import 'dart:math';
import 'package:flutter/material.dart';
import 'package:raw_gnss/gnss_status_model.dart';

class SkyplotWidget extends StatelessWidget {
  final List<Status> satellites;
  final double size;

  const SkyplotWidget({
    super.key,
    required this.satellites,
    this.size = 300,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.05),
        shape: BoxShape.circle,
      ),
      child: CustomPaint(
        painter: SkyplotPainter(satellites: satellites),
      ),
    );
  }
}

class SkyplotPainter extends CustomPainter {
  final List<Status> satellites;

  SkyplotPainter({required this.satellites});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    final gridPaint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    // 1. Koncentrikus körök (Eleváció: 0, 30, 60, 90)
    for (var i = 0; i <= 3; i++) {
      canvas.drawCircle(center, radius * (i / 3), gridPaint);
    }

    // 2. Égtájak vonalai
    for (var i = 0; i < 4; i++) {
      double angle = i * pi / 2;
      canvas.drawLine(
        center,
        Offset(center.dx + radius * cos(angle), center.dy + radius * sin(angle)),
        gridPaint,
      );
    }

    // 3. Égtájak feliratai
    _drawLabel(canvas, "N", Offset(center.dx, center.dy - radius - 10), Colors.red);
    _drawLabel(canvas, "S", Offset(center.dx, center.dy + radius + 10), Colors.black);
    _drawLabel(canvas, "E", Offset(center.dx + radius + 10, center.dy), Colors.black);
    _drawLabel(canvas, "W", Offset(center.dx - radius - 10, center.dy), Colors.black);

    // 4. Műholdak kirajzolása
    for (var sat in satellites) {
      if (sat.azimuthDegrees == null || sat.elevationDegrees == null) continue;

      // Geodéziai azimut (0 = North) -> Matematikai szög (0 = East, CCW)
      // mathAngle = 90 - azimuth
      double azimuthRad = (sat.azimuthDegrees! - 90) * pi / 180;
      
      // Eleváció: 90 = közép, 0 = szél
      double dist = radius * (1 - (sat.elevationDegrees! / 90));

      double x = center.dx + dist * cos(azimuthRad);
      double y = center.dy + dist * sin(azimuthRad);

      Color satColor = _getConstellationColor(sat.constellationType ?? 0);
      
      final satPaint = Paint()
        ..color = satColor
        ..style = sat.usedInFix == true ? PaintingStyle.fill : PaintingStyle.stroke
        ..strokeWidth = 2;

      canvas.drawCircle(Offset(x, y), 6, satPaint);
      
      // SVID (Műhold száma) kiírása a pötty mellé
      _drawSmallText(canvas, "${sat.svid}", Offset(x + 8, y - 8), satColor);
    }
  }

  void _drawLabel(Canvas canvas, String text, Offset offset, Color color) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, Offset(offset.dx - tp.width / 2, offset.dy - tp.height / 2));
  }

  void _drawSmallText(Canvas canvas, String text, Offset offset, Color color) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold)),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, offset);
  }

  Color _getConstellationColor(int type) {
    switch (type) {
      case 1: return Colors.blue;    // GPS
      case 3: return Colors.red;     // GLONASS
      case 5: return Colors.orange;  // BEIDOU
      case 6: return Colors.green;   // GALILEO
      default: return Colors.grey;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
