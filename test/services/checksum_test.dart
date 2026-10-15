import 'package:flutter/foundation.dart';

void main() {
  const sentence = '\$GPGGA,123456.00,,,,,0,00,0.0,,,,,,*41\r\n';
  int checksum = 0;
  for (int i = 1; i < sentence.lastIndexOf('*'); i++) {
    checksum ^= sentence.codeUnitAt(i);
  }
  debugPrint('\$GPGGA,123456.00,,,,,0,00,0.0,,,,,,*${checksum.toRadixString(16).toUpperCase().padLeft(2, '0')}\r\n');
}
