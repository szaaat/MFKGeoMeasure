import 'dart:math';
import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';

class QuadrantWidget extends StatelessWidget {
  final double bearing; // WCB fokban
  final double size;

  const QuadrantWidget({super.key, required this.bearing, this.size = 120});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final quadrantStr = _getQuadrantName(bearing);
    final label = l10n?.quadrantName(quadrantStr) ?? "$quadrantStr síknegyed";

    return Column(
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey[300]!),
            borderRadius: BorderRadius.circular(10),
          ),
          child: CustomPaint(
            painter: QuadrantPainter(bearing: bearing),
          ),
        ),
        const SizedBox(height: 5),
        Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
      ],
    );
  }

  String _getQuadrantName(double b) {
    if (b >= 0 && b < 90) return "I.";
    if (b >= 90 && b < 180) return "II.";
    if (b >= 180 && b < 270) return "III.";
    return "IV.";
  }
}

class QuadrantPainter extends CustomPainter {
  final double bearing;

  QuadrantPainter({required this.bearing});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.4;

    final gridPaint = Paint()
      ..color = Colors.grey[400]!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    // Tengelyek
    canvas.drawLine(Offset(0, center.dy), Offset(size.width, center.dy), gridPaint);
    canvas.drawLine(Offset(center.dx, 0), Offset(center.dx, size.height), gridPaint);

    // Vektor
    final vectorPaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    // Geodéziai irányszög (0 = North) -> Matematikai szög (0 = East, CCW)
    double mathAngle = (90 - bearing) * pi / 180;
    
    Offset endPoint = Offset(
      center.dx + radius * cos(mathAngle),
      center.dy - radius * sin(mathAngle),
    );

    canvas.drawLine(center, endPoint, vectorPaint);
    canvas.drawCircle(endPoint, 4, Paint()..color = Colors.red);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
