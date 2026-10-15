import 'package:flutter/foundation.dart';

void main() {
  const sentence = '\$GPGGA,123456.00,,,,,0,00,0.0,,,,,,*61\r\n';
  final parts = sentence.split('*')[0].split(',');
  debugPrint(parts.length.toString());
  debugPrint(parts.toString());
}
