import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mfk_geomeasure/services/gnss/ntrip_client.dart';

void main() {
  group('NtripClient Tests', () {
    late int port;

    setUp(() async {
      // Mock TCP Server helyett HTTP server-t használunk, ami hasonlít az NTRIP-re
      // Valójában az NTRIP TCP alapú, de HTTP-szerű fejlécekkel kezdődik.
      // Egy egyszerű Socket alapú mock szerver jobb lenne.
    });

    test('NtripClient basic auth and connection', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      port = server.port;

      final client = NtripClient(
        host: '127.0.0.1',
        port: port,
        mountpoint: 'TEST',
        username: 'user',
        password: 'pwd',
      );

      final statusCompleter = Completer<NtripStatus>();
      client.statusStream.listen((s) {
        if (s == NtripStatus.connected) statusCompleter.complete(s);
      });

      server.listen((socket) {
        socket.listen((data) {
          final req = utf8.decode(data);
          if (req.contains('Authorization: Basic dXNlcjpwd2Q=')) { // user:pwd base64
            socket.write('ICY 200 OK\r\n\r\n');
            socket.add([0xD3, 0x00, 0x13, 0x3E, 0x4D, 0x00]); // Mock RTCM bájtok
          }
        });
      });

      final statuses = <NtripStatus>[];
      client.statusStream.listen((s) {
        statuses.add(s);
      });

      final rtcmCompleter = Completer<List<int>>();
      client.rtcmStream.listen((data) {
        if (!rtcmCompleter.isCompleted) rtcmCompleter.complete(data);
      });

      await client.connect();
      
      // Várjunk amíg megérkezik a kívánt állapot
      for (int i = 0; i < 50; i++) {
        if (statuses.contains(NtripStatus.connected) || statuses.contains(NtripStatus.correctionDataActive)) break;
        await Future.delayed(const Duration(milliseconds: 100));
      }

      expect(statuses, anyOf(contains(NtripStatus.connected), contains(NtripStatus.correctionDataActive)));
      
      final rtcmData = await rtcmCompleter.future.timeout(const Duration(seconds: 5));
      expect(rtcmData[0], 0xD3); // RTCM preamble
      
      client.disconnect();
      await server.close();
    });

    test('NtripClient failed auth', () async {
       final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
       final client = NtripClient(
        host: '127.0.0.1',
        port: server.port,
        mountpoint: 'TEST',
        username: 'wrong',
        password: 'pwd',
      );

      final errorCompleter = Completer<NtripStatus>();
      client.statusStream.listen((s) {
        if (s == NtripStatus.error) errorCompleter.complete(s);
      });

      server.listen((socket) {
        socket.write('HTTP/1.0 401 Unauthorized\r\n\r\n');
        // socket.destroy() helyett várjunk kicsit
      });

      try {
        await client.connect();
      } catch (_) {}
      
      final status = await errorCompleter.future.timeout(const Duration(seconds: 5));
      expect(status, NtripStatus.error);
      
      client.disconnect();
      await server.close();
    });
   group('GGA Feedback', () {
    test('NtripClient periodic GGA sending', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final client = NtripClient(
        host: '127.0.0.1',
        port: server.port,
        mountpoint: 'TEST',
        ggaInterval: 1, // 1 sec for fast test
      );

      final ggaCompleter = Completer<String>();
      server.listen((socket) {
        socket.listen((data) {
          final str = utf8.decode(data);
          if (str.contains('GET')) {
            socket.write('ICY 200 OK\r\n\r\n');
          } else if (str.contains('GPGGA')) {
            if (!ggaCompleter.isCompleted) ggaCompleter.complete(str);
          }
        });
      });

      await client.connect();
      client.updatePosition(r'$GPGGA,123519,4807.038,N,01131.000,E,1,08,0.9,545.4,M,46.9,M,,*47');
      
      final receivedGga = await ggaCompleter.future.timeout(const Duration(seconds: 5));
      expect(receivedGga, contains('GPGGA'));
      
      client.disconnect();
      await server.close();
    });
   });
  });
}
