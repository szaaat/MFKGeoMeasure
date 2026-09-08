import 'dart:async';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

class LibellaWidget extends StatefulWidget {
  final double size;
  const LibellaWidget({super.key, this.size = 120});

  @override
  State<LibellaWidget> createState() => _LibellaWidgetState();
}

class _LibellaWidgetState extends State<LibellaWidget> {
  double x = 0;
  double y = 0;
  StreamSubscription<AccelerometerEvent>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = accelerometerEventStream().listen((AccelerometerEvent event) {
      if (!mounted) return;
      setState(() {
        // X és Y tengely menti dőlés. 
        // 9.8-as érték a maximum (teljes dőlés), ezt skálázzuk a widget méretére.
        // A buborékot ellentétes irányba mozgatjuk.
        x = (event.x / 9.8) * (widget.size / 2 - 10);
        y = (event.y / 9.8) * (widget.size / 2 - 10);
      });
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Ha a dőlés kicsi, zöldre váltunk (függőleges állapot)
    bool isLevel = x.abs() < 5 && y.abs() < 5;
    Color statusColor = isLevel ? Colors.green : Colors.red;

    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.black12,
        border: Border.all(color: statusColor.withValues(alpha: 0.5), width: 2),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Keresztvonalak
          Center(child: Container(width: widget.size, height: 1, color: Colors.white24)),
          Center(child: Container(width: 1, height: widget.size, color: Colors.white24)),
          
          // Célkör (közép)
          Center(
            child: Container(
              width: 20, height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white38),
              ),
            ),
          ),
          
          // A Buborék
          AnimatedPositioned(
            duration: const Duration(milliseconds: 50),
            left: (widget.size / 2 - 10) - x,
            top: (widget.size / 2 - 10) + y,
            child: Container(
              width: 20, height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: statusColor.withValues(alpha: 0.8),
                boxShadow: [
                  BoxShadow(color: statusColor.withValues(alpha: 0.4), blurRadius: 4),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
