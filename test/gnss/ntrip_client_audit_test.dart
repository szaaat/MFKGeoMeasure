import 'package:flutter_test/flutter_test.dart';
import 'package:mfk_geomeasure/services/gnss/ntrip_client.dart';

void main() {
  group('NtripClient Professional Audit', () {
    test('Validation - Not configured if missing host', () {
      final client = NtripClient(host: '', port: 2101, mountpoint: 'TEST');
      expect(client.status, NtripStatus.notConfigured);
    });

    test('Validation - Not configured if missing mountpoint', () {
      final client = NtripClient(host: 'caster.com', port: 2101, mountpoint: '');
      expect(client.status, NtripStatus.notConfigured);
    });

    test('Validation - Not configured if invalid port', () {
      final client = NtripClient(host: 'caster.com', port: 0, mountpoint: 'TEST');
      expect(client.status, NtripStatus.notConfigured);
    });

    test('Initial state is disconnected if valid config', () {
      final client = NtripClient(host: 'caster.com', port: 2101, mountpoint: 'TEST');
      expect(client.status, NtripStatus.disconnected);
    });
  });
}
