import 'package:uuid/uuid.dart';

class NtripProfile {
  final String id;
  String name;
  String host;
  int port;
  String mountpoint;
  String username;
  int ggaInterval;

  // Note: password is NOT stored here, it's in FlutterSecureStorage keyed by ID

  NtripProfile({
    String? id,
    required this.name,
    this.host = '',
    this.port = 2101,
    this.mountpoint = '',
    this.username = '',
    this.ggaInterval = 10,
  }) : id = id ?? const Uuid().v4();

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'host': host,
    'port': port,
    'mountpoint': mountpoint,
    'username': username,
    'ggaInterval': ggaInterval,
  };

  factory NtripProfile.fromJson(Map<String, dynamic> json) => NtripProfile(
    id: json['id'],
    name: json['name'] ?? 'Unnamed Profile',
    host: json['host'] ?? '',
    port: json['port'] ?? 2101,
    mountpoint: json['mountpoint'] ?? '',
    username: json['username'] ?? '',
    ggaInterval: json['ggaInterval'] ?? 10,
  );

  @override
  String toString() => name;
}
