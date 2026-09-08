import 'dart:async';

abstract class GnssTransport {
  /// Adatfolyam a vevőtől (bájtok)
  Stream<List<int>> get dataStream;

  /// Kapcsolódás állapota
  Stream<bool> get connectionStatus;

  /// Kapcsolódás a hardverhez
  Future<void> connect();

  /// Kapcsolat bontása
  Future<void> disconnect();

  /// Adatküldés a vevőnek (pl. RTCM bájtok)
  Future<void> write(List<int> data);

  /// Erőforrások felszabadítása
  void dispose();
}
